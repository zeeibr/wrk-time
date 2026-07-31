import Foundation

enum PlannerError: LocalizedError {
    case noKey
    case refused(String)
    case http(Int, String)
    case truncated
    case malformed
    case rejected(String)
    case transport(Error)

    /// Written for the reader, not the log. Every one of these ends up under a
    /// plan that was generated offline instead, so none of them is a dead end.
    var errorDescription: String? {
        switch self {
        case .noKey:
            "No API key is set, so this week was drawn from the plan's own rules."
        case .refused:
            "Claude declined to answer that. This week was drawn from the plan's own rules."
        case .http(let code, _) where code == 401:
            "That API key was not accepted. This week was drawn from the plan's own rules."
        case .http(let code, _) where code == 429:
            "Claude is rate limiting the key just now. This week was drawn from the plan's own rules."
        // The code and Claude's own sentence, not a shrug. "Could not be
        // reached" on its own is unfalsifiable: it reads the same whether the
        // service is down, the request is malformed, or the key is out of
        // credit, and there is no log on a phone to go and check. A 400 is a
        // bug in this app; a 529 is Claude being busy. She should be able to
        // tell those apart, and so should anyone fixing it.
        case .http(let code, let detail):
            "Claude answered \(code)\(detail.isEmpty ? "" : ": \(detail)"). This week was drawn from the plan's own rules."
        case .truncated, .malformed:
            "Claude's answer came back unusable. This week was drawn from the plan's own rules."
        case .rejected(let why):
            "Claude's week did not hold up: \(why) This week was drawn from the plan's own rules."
        case .transport:
            "No connection to Claude. This week was drawn from the plan's own rules."
        }
    }
}

/// Calls Claude directly from the device with the user's own key.
///
/// Swift has no official Anthropic SDK, so this is the documented raw-HTTP path
/// against `POST /v1/messages`. Three choices are worth stating:
///
/// **Structured outputs, not tool use.** The planner returns one object and
/// makes no decisions the app has to execute, so `output_config.format` with a
/// JSON schema is the whole mechanism — no tool loop, no second round trip.
///
/// **`stop_reason` is read before `content`.** Claude Opus 5 runs safety
/// classifiers that can decline a request with a perfectly successful HTTP 200
/// and an empty `content` array. Indexing `content[0]` without checking first
/// is the standard way to crash on a refusal.
///
/// **The whole thing is allowed to fail.** Every path out of here is caught by
/// `PlannerService`, which falls back to the offline planner. A week is never
/// blocked on a network.
struct ClaudePlanner: Sendable {
    /// Opus over Sonnet deliberately: this runs once a week, the input is small,
    /// and the quality of a twelve-week progression is worth more than the few
    /// cents saved. Never a dated suffix — the id is complete as written.
    static let model = "claude-opus-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let version = "2023-06-01"
    // No `fallbacks` parameter, deliberately, and this cost a while to find.
    //
    // Server-side refusal fallback is the documented default for Opus 5, and it
    // was set here. With it on, every request came back schema-valid and empty:
    // zeroed integers, empty strings, `moves: []` — once with a real
    // explanation attached to a week that had one hollow session in it.
    // Removing `fallbacks: "default"` and its beta header, changing nothing
    // else, produced a full and correct week on the next call.
    //
    // A fitness planner is not going to trip a safety classifier, so the
    // protection was buying nothing here and breaking the thing it rode along
    // with. If it is ever restored, re-test the structured output first.

    var session: URLSession = .shared

    /// A week, and what asking for it actually cost.
    ///
    /// Returned rather than left in a static. `lastUsage` was a
    /// `nonisolated(unsafe)` written from a URLSession continuation and read on
    /// the main actor with nothing serialising them — a real race, not merely a
    /// wrong number — and it also lost a request: `plan` may send twice, each
    /// send overwriting the other, while the caller read once. The weeks that
    /// cost the most were the ones counted at half price.
    struct Result {
        var draft: PlanDraft
        var usage: Usage
    }

    /// Asks for a week, and asks again if the first answer is not usable.
    ///
    /// The repair pass exists because of what the first real call returned: a
    /// well-written explanation describing four sessions, sitting next to a
    /// `sessions` array holding one session with no moves in it. Structured
    /// outputs guarantee the *shape* of an answer and nothing about its
    /// substance — JSON Schema's `minItems` is not supported, so nothing in the
    /// contract can require a session to contain any moves at all.
    ///
    /// Handing the model its own rejected answer and the reason is far more
    /// effective than re-asking blind, and one extra request is cheap next to
    /// a week that falls back to the offline planner.
    func plan(_ context: PlanContext) async throws -> Result {
        guard let key = KeychainStore.read(.claudeAPIKey) else { throw PlannerError.noKey }

        var messages: [[String: Any]] = [["role": "user", "content": context.prompt]]
        var lastReason = ""
        // Read once. Asking, checking and repairing all have to mean the same
        // number, and `Tuning` is a `UserDefaults` read she could change from
        // Settings while a request is in flight.
        let moveCount = Tuning.movesPerSession

        // Every request this call makes, including the ones that come back
        // unusable — a refusal and a truncation are both billed.
        var usage = Usage()

        for attempt in 0..<Self.attempts {
            let (draft, raw) = try await send(messages: messages, key: key,
                                              sessionCount: context.pace.sessionsPerWeek,
                                              moveCount: moveCount,
                                              usage: &usage)

            do {
                _ = try PlanValidator.routines(from: draft)
                guard draft.sessions.count == context.pace.sessionsPerWeek else {
                    throw PlanValidator.Failure.nonsenseTiming(
                        "The week has \(draft.sessions.count) sessions; it needs \(context.pace.sessionsPerWeek).")
                }
                // Counted because it went uncounted for weeks. The schema
                // requires a slot per move, so a short rotation means either
                // the model ignored a required property or the decoder dropped
                // one — and the second of those actually happened, silently,
                // on every paid week. `PlanValidator` checks a rotation is not
                // empty; it has no way to know how many were asked for.
                if let short = draft.sessions.first(where: { $0.moves.count != moveCount }) {
                    throw PlanValidator.Failure.nonsenseTiming(
                        "\"\(short.title)\" came back with \(short.moves.count) moves; it needs \(moveCount).")
                }
                return Result(draft: draft, usage: usage)
            } catch {
                lastReason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                guard attempt < Self.attempts - 1 else { break }

                // A normal assistant turn followed by a user turn — not a
                // prefill, which Opus 5 rejects. The last message is the user's.
                messages.append(["role": "assistant", "content": raw])
                messages.append(["role": "user", "content": """
                That week was rejected and not used. \(lastReason)

                Write it again in full, with exactly \(context.pace.sessionsPerWeek) sessions of \(Tuning.movesPerSession) moves each.
                """])
            }
        }

        throw PlannerError.rejected(lastReason)
    }

    /// How many times to ask before giving the week to the offline planner.
    static let attempts = 2

    // MARK: - Request

    private func send(messages: [[String: Any]], key: String,
                      sessionCount: Int, moveCount: Int,
                      usage: inout Usage) async throws -> (PlanDraft, String) {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        // A week is a small answer, but the model is generating on a phone that
        // may be on a slow connection.
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "model": Self.model,
            // Thinking is on by default on Opus 5 and `max_tokens` caps thinking
            // and text together, so this is sized for both rather than for the
            // few hundred tokens of JSON that come out the far end.
            //
            // Back to 16k after briefly being 8k as a saving, which it was not.
            // **`max_tokens` is a ceiling, not a spend** — output is billed as
            // it is generated, so lowering a cap the response never reached
            // saved nothing. What it did do was leave no room above an adaptive
            // thinking budget at `high` effort, and the only two ways that
            // shows up are an HTTP 400 or a `max_tokens` stop, both of which
            // spend the request and hand the week to the offline planner.
            //
            // Generous on purpose, then. The real economy is upstream, in
            // `PlanTrigger` deciding not to ask at all.
            "max_tokens": 16_000,
            "system": Self.systemPrompt,
            "thinking": ["type": "adaptive"],
            "output_config": [
                // `high` is the documented floor for intelligence-sensitive
                // work on Opus 5. `medium` was a false economy: it returned a
                // week with one empty session, so the request was spent and
                // the plan still came from the offline planner.
                "effort": "high",
                "format": ["type": "json_schema",
                           "schema": Self.schema(sessions: sessionCount, moves: moveCount)]
            ],
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PlannerError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw PlannerError.http(status, Self.reason(from: data))
        }

        // Counted before decoding, so a refusal or a truncation — both of
        // which throw on the next line — still counts against the bill.
        usage += Usage.read(data)
        return try Self.decode(data)
    }

    // MARK: - Response

    /// One sentence out of an error body, and nothing else out of it.
    ///
    /// An error response is `{"error": {"type": ..., "message": ...}}`, and only
    /// `message` is taken. The rest of a failed request's body can echo fields
    /// that were sent, which is not something to put on a screen or into a
    /// screenshot — the key itself is a header rather than a field, so it is
    /// never in here, but that is a reason not to be casual rather than a
    /// reason to relax. Trimmed, because some of these run long.
    static func reason(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String, !message.isEmpty
        else { return "" }
        return message.count > 160 ? String(message.prefix(160)) + "…" : message
    }

    /// What a request actually cost, from the response rather than from a
    /// guess. Thinking bills as output, which is where nearly all of it goes.
    struct Usage: Equatable {
        var inputTokens = 0
        var outputTokens = 0

        /// Opus 5: $5 per million in, $25 per million out.
        static let inputPerMillion = 5.0
        static let outputPerMillion = 25.0

        var dollars: Double {
            Double(inputTokens) / 1_000_000 * Self.inputPerMillion
                + Double(outputTokens) / 1_000_000 * Self.outputPerMillion
        }

        static func read(_ object: [String: Any]) -> Usage {
            guard let usage = object["usage"] as? [String: Any] else { return Usage() }
            return Usage(inputTokens: usage["input_tokens"] as? Int ?? 0,
                         outputTokens: usage["output_tokens"] as? Int ?? 0)
        }

        /// Straight off the wire, for the one caller that has the bytes rather
        /// than the parsed object.
        static func read(_ data: Data) -> Usage {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return Usage() }
            return read(object)
        }

        static func += (total: inout Usage, next: Usage) {
            total.inputTokens += next.inputTokens
            total.outputTokens += next.outputTokens
        }
    }


    static func decode(_ data: Data) throws -> (PlanDraft, String) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlannerError.malformed
        }
        switch object["stop_reason"] as? String {
        case "refusal":
            let details = object["stop_details"] as? [String: Any]
            throw PlannerError.refused(details?["category"] as? String ?? "unstated")
        case "max_tokens":
            // Structured output truncated mid-object; the JSON will not parse
            // and a partial week is worse than none.
            throw PlannerError.truncated
        default:
            break
        }

        // With thinking on, a thinking block precedes the text — and with
        // `display` at its default that block's text is empty. A fallback
        // block can also appear ahead of it. Take the first genuine text block
        // rather than assuming an index.
        let blocks = object["content"] as? [[String: Any]] ?? []
        guard let json = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let draft = try? JSONDecoder().decode(PlanDraft.self, from: Data(json.utf8))
        else { throw PlannerError.malformed }

        // The raw text goes back with the draft so a rejected week can be
        // handed to the model verbatim for repair.
        return (draft, json)
    }

    // MARK: - Contract

    // MARK: Legal values
    //
    // Structured outputs support `enum` but **not** `minimum`/`maximum`. That
    // is the whole reason these lists exist: a bound cannot be expressed, but a
    // set of legal values can, and enumerating them makes the bad answer
    // unrepresentable rather than merely rejected.
    //
    // This is the same move as the required named slots above, applied to
    // numbers. It was earned the same way: the first live week after the
    // warm-up shipped came back with a session asking for **0 rounds**, which
    // the validator threw out whole — a correct outcome that still cost her the
    // personalised week. `rounds` was also the one field in this schema with no
    // description at all.
    //
    // Four of `PlanValidator`'s failure modes become impossible here rather
    // than merely caught: zero or absurd rounds, work over the ceiling,
    // negative rest, and a day outside the week. The validator keeps checking
    // all of them — it also guards the offline planner, and a schema is a
    // contract with one caller, not a guarantee about the store.

    /// Work intervals, in seconds. The 60-second ceiling is a hard constraint of
    /// the app, so the schema stops at it rather than trusting prose.
    static let workSeconds = [20, 25, 30, 35, 40, 45, 50, 55, 60]
    /// Three-second granularity, not five, because the offline planner shortens
    /// rest by three seconds a step. A schema that could not express 42 seconds
    /// would forbid Claude from writing a week the app's own floor writes every
    /// day — and the repair turn would then be arguing against the house.
    /// Five-second steps, not three.
    ///
    /// Structured outputs compile the schema into a grammar with a size limit,
    /// and exceeding it is a 400 — "schema too complex" — before the model sees
    /// anything. The cost is combinatorial: at the hard pace a week is five
    /// sessions, each carrying work × rest × rounds, and each holding
    /// `Tuning.movesPerSession` move slots with their own name and load enums.
    ///
    /// Rest was much the largest list at twenty-six values, and three-second
    /// granularity bought nothing — nobody rests 48 seconds rather than 50.
    /// Sixteen values now, over the same 15–90 range.
    static let restSeconds = Array(stride(from: 15, through: 90, by: 5))
    /// Rounds a thirteen-minute session can sensibly hold. Well inside
    /// `PlanValidator.roundCeiling`, and starting nowhere near zero.
    static let roundCounts = Array(6...16)
    static let dayOffsets = Array(0...6)
    /// Every load the kit can be set to, plus zero for bodyweight and the pad.
    /// Which load goes with which equipment is still the validator's job — the
    /// schema can say "5 lb is a real weight", not "5 lb is a ring".
    static var legalLoads: [Double] {
        ([0] + Equipment.allCases.flatMap(\.availableLoadsPounds)).sorted()
    }

    /// The response shape, enforced by the API rather than hoped for.
    ///
    /// The ceilings that cannot be expressed as a set — a load matching its
    /// own equipment, two sessions not sharing a day — are checked in
    /// `PlanValidator` after this returns. This schema guarantees the shape and
    /// the legal values; the validator guarantees the sense.
    ///
    /// Built on each call rather than stored: a `[String: Any]` is not
    /// `Sendable`, and this runs once a week — there is nothing to cache.
    /// One move. Repeated three times per session, as named slots.
    static var moveSchema: [String: Any] {[
        "type": "object",
        "additionalProperties": false,
        // Only the name. Equipment, cue and load were all facts the closed
        // library already holds — "Ring halo" *is* the 5 lb ring — and every
        // one of them was paid for once per move slot per session, which at the
        // hard pace is twenty-five times over. That redundancy is what put the
        // compiled grammar past its size limit and returned 400, "schema too
        // complex". Coarsening the rest list first was aiming at the wrong
        // thing entirely.
        //
        // Stricter, not looser: a week naming a move with a load its kit cannot
        // be set to is now unrepresentable rather than caught afterwards.
        "required": ["name"],
        "properties": [
            // The library, closed. Move names were the last free-text field in
            // this schema and every fuzzy-matching problem downstream came from
            // that: the planner would invent "Beam goblet squat", the app would
            // try to guess which of thirty-seven drawings it meant, and
            // sometimes guess wrong. Enumerated, every move in every plan has a
            // plate by construction rather than by resemblance.
            //
            // Nothing is lost. Progression here comes from tempo, range,
            // density and volume — the kit tops out at 15 lb — so the planner's
            // job is which moves and in what order, not inventing a
            // thirty-eighth for a drawer with four things in it.
            "name": ["type": "string", "enum": MoveLibrary.names]
        ]
    ]}

    /// Ordinal slot names, so a fixed number of sessions can be *required*.
    static let slots = ["one", "two", "three", "four", "five"]
    /// The same trick for the rotation. `minItems` is not supported, so "five
    /// moves" has to be five required properties or it is not a requirement.
    static let moveSlots = ["first", "second", "third", "fourth", "fifth", "sixth"]

    /// The schema for a week of exactly `sessions` sessions.
    ///
    /// Session count and rotation size are both pinned by *required properties*
    /// rather than by array bounds, because JSON Schema's `minItems` is not
    /// supported by structured outputs — asking in prose for four sessions of
    /// three moves produced two sessions, then one with an empty rotation.
    ///
    /// The move and session shapes live in `$defs` and are referenced. Inlining
    /// them instead put twelve copies of the move object in one grammar and the
    /// API rejected it outright: "The compiled grammar is too large."
    static func schema(sessions: Int, moves: Int = Tuning.movesPerSession) -> [String: Any] {
        let names = Array(slots.prefix(max(sessions, 1)))
        var slotProperties: [String: Any] = [:]
        for name in names { slotProperties[name] = ["$ref": "#/$defs/session"] }

        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["explanation", "sessions", "walkMinutes"],
            "$defs": [
                "move": moveSchema,
                "session": sessionSchema(moves: moves)
            ],
            "properties": [
                "explanation": [
                    "type": "string",
                    "description": "One sentence in the app's voice: what changed this week and why. Never exclaims, never implies she failed."
                ],
                "walkMinutes": [
                    "type": "integer",
                    "description": "Total minutes on the walking pad this week, spread across the days however she likes. Between \(PlanValidator.walkFloor) and \(PlanValidator.walkCeiling)."
                ],
                "sessions": [
                    "type": "object",
                    "additionalProperties": false,
                    "description": "The \(names.count) sessions for this week, in day order.",
                    "required": names,
                    "properties": slotProperties
                ]
            ]
        ]
    }

    private static func sessionSchema(moves: Int) -> [String: Any] {
        let names = Array(moveSlots.prefix(min(max(moves, 1), moveSlots.count)))
        var slotProperties: [String: Any] = [:]
        for name in names { slotProperties[name] = ["$ref": "#/$defs/move"] }
        return [
        "type": "object",
        "additionalProperties": false,
        "required": ["dayOffset", "title", "work", "rest", "rounds", "moves"],
        "properties": [
            "dayOffset": [
                "type": "integer",
                "enum": dayOffsets,
                "description": "Days from the start of the week. Every session in the week takes a different day."
            ],
            "title": ["type": "string", "description": "Two or three words, e.g. 'Lower · beam'."],
            "work": [
                "type": "integer",
                "enum": workSeconds,
                // Every other number here now states what normal looks like, and
                // this one did not. The first live week to pass validation chose
                // the shortest interval on offer for all four sessions — a
                // defensible week-one call, but one made against no anchor at
                // all. The floor stays available; it is no longer the only value
                // with nothing said about it.
                "description": "Work interval in seconds. Forty is the standing default for someone new to lifting; go shorter only for a pattern she is still learning, and longer as time under tension becomes the progression."
            ],
            "rest": [
                "type": "integer",
                "enum": restSeconds,
                "description": "Rest in seconds between rounds. 45 is the standing default; shortening it is a progression lever."
            ],
            "rounds": [
                "type": "integer",
                "enum": roundCounts,
                "description": "How many times the rotation runs. Eight is a normal week-one session; the whole thing should come to roughly thirteen minutes."
            ],
            // An array, not five named slots.
            //
            // The slots existed because `minItems` is unsupported by structured
            // outputs, so an array could come back empty — and once did, on the
            // first live call. That is no longer the only defence: `plan` counts
            // the moves in every session and hands a short week back to the
            // model with the reason, then falls to the offline planner if the
            // repair turn does not fix it.
            //
            // And the slots were expensive. Five *required properties* per
            // session, each pulling in the whole move definition, across five
            // sessions at the hard pace — twenty-five instances of a
            // thirty-five-way name enum. Asking for a name and nothing else was
            // not enough on its own: it compiled at four sessions and still
            // failed at five, which is the difference between the simulator I
            // tested on and her phone.
            "moves": [
                "type": "array",
                "description": "The \(names.count) moves this session rotates through, in order. Exactly \(names.count) of them — a session with fewer is rejected and the week is thrown away.",
                "items": ["$ref": "#/$defs/move"]
            ]
        ]
    ]
    }

    /// Lifted from `docs/PLANNER-BRIEF.md`, which was written to be pasted here.
    /// If the two ever disagree, the document is the source and this is stale.
    static let systemPrompt = """
    You program a twelve-week training block for one person, inside an app called \
    Almanac. You write one week at a time.

    WHO THIS IS FOR
    A 34-year-old woman, new to fitness. She is the only user. Three things follow.

    Progression cannot come from load. The kit tops out at 15 lb. Progress comes \
    from tempo (slower eccentrics), range, density (shorter rests), volume (more \
    rounds), and unilateral variants. Reaching for "add weight" has nowhere to go \
    and will stall by week three.

    Resistance work is the point and must not drift to cardio. Loading matters for \
    bone density and lean mass from the mid-thirties onward. The walking pad is for \
    zone 2 and recovery, never for filling a session you could not figure out how \
    to program.

    She is new to this. Movement quality and finishing sessions beat intensity. A \
    week she completes is worth more than a week she abandons.

    THE KIT — nothing else exists
    - Two 2 lb Peloton dumbbells
    - One 15 lb Bala Beam
    - Bala Power Rings at 5, 8 and 10 lb. Three DIFFERENT weights, not a matched \
      set. "One in each hand" is only true for a pair she chooses, and any move \
      that assumes a uniform ring load is wrong.
    - A walking pad
    - Bodyweight

    HARD CONSTRAINTS
    - A work interval is never longer than 60 seconds.
    - Every move uses equipment from the list above and a load that equipment \
      actually offers. A generated week that breaks this is discarded whole.
    - A rest day is part of the plan. Spread the rest days; do not stack them at \
      the end of the week.

    PROGRAMMING
    - Heaviest implement to the biggest muscles: the beam for squat, hinge and hip \
      thrust; the rings for deadlift and row patterns. The three rings are used \
      one at a time unless a move genuinely calls for two — name the one you mean.
    - She has said she likes the 2 lb dumbbells. Use them freely for shoulder and \
      arm work, where a long lever held slowly makes two pounds a real load: \
      raises in every direction, presses, curls, kickbacks, flys. They stay close \
      to pointless for lower body — do not program them there just to use them.
    - Push and pull want balancing across the week, and this kit is push-heavy. \
      Hinge patterns and ring rows carry the pull side.
    - Rest is programmed, not leftover. 45 seconds is the standing default; \
      shortening it is a progression lever, so spend it deliberately.
    - Do not assume anything about her goals beyond what you are told. Nothing you \
      write should imply an aesthetic target she has not stated.

    FLOW WORK
    She does a round of qi gong and lymphatic movement most mornings — bounces,
    arm swings, spinal waves, tapping, shaking, cat cow, standing twists. That
    is her own practice and it is not yours to program. You may use one such
    movement on an easy or recovery day if it genuinely fits, and never as a
    strength interval: they are continuous and unhurried, and counting one down
    like a deadlift misreads what it is for.

    WHAT SHE HAS TOLD YOU ABOUT MOVES
    If a move is listed as one she said hurt, it is out. Not scaled, not
    substituted with a near-identical variant under another name — out, along
    with anything that is obviously the same movement. This overrides every
    other consideration in this prompt, including balance across the week.
    A move she simply dislikes may appear rarely, never twice in one week, and
    never in consecutive weeks. Do not argue with her about any of this in the
    explanation, and do not draw attention to the omission.

    WALKING — the one thing programmed toward the goal weight
    The sessions are thirteen minutes and cannot move energy balance; they exist \
    to build and keep muscle, and they are written the same whether or not she \
    has a goal. Walking is different. It is the only training lever that \
    meaningfully affects the scale, so `walkMinutes` is the one number you may \
    set with her goal in mind.
    - Build from what she is already doing. If she walked 90 minutes last week, \
      ask for a little more, not double. Raise it by roughly ten to twenty per \
      cent a week, and never by more than 40 minutes in one step.
    - Stay between 60 and 300 minutes a week. Above that is not a plan, it is a \
      second job, and adherence collapses.
    - With no goal set, hold it steady at whatever she is already doing.
    - Never present walking as making up for a missed session, and never imply \
      that eating or fasting is something you are programming. You are not.

    VOICE — applies to every string you emit
    Plain, warm, specific. Name real numbers and real equipment. Never exclaim. \
    Never imply she failed. State the change, then the reason, in one sentence. \
    Educational, never medical advice: say what a signal is and what the plan does \
    with it, never what it means for her health. No emoji.

    In register:
      "Sleep and heart rate are both off your usual. Today drops a round — that is \
    the plan working, not you failing."
      "Two pounds is enough when you go slowly."

    Never: "Crush it", "Great job", "You've got this", or any sentence where the \
    subject of a negative verb is "you".
    """
}
