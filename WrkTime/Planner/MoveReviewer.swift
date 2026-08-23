import Foundation

/// Checks the moves she queued and writes their library entries, and suggests
/// new moves for a muscle she wants to target.
///
/// This is a model task on purpose, unlike the warm-up or the extra session:
/// writing a correct cue for a movement, judging whether it can be done with
/// her kit, and knowing what a "renegade row" actually is are not arithmetic
/// over a closed library. It follows `ClaudePlanner`'s shape — structured
/// output, `stop_reason` read before `content`, everything allowed to fail —
/// but nothing here falls back to an offline path: the queue simply keeps
/// until a review can run, because a library that grows is optional in a way
/// a week is not.
struct MoveReviewer: Sendable {
    static let model = ClaudePlanner.model
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let version = "2023-06-01"

    var session: URLSession = .shared

    /// The muscles the suggestion section offers. A closed list, so the prompt
    /// and the picker cannot drift apart.
    static let muscles = ["Shoulders", "Arms", "Chest", "Back", "Core", "Glutes", "Legs"]

    /// One reviewed or suggested move, exactly as the schema returns it.
    struct Entry: Codable, Sendable {
        var name: String
        var verdict: String
        /// "strength" or "flow" — the review's call, never hers to mark.
        var kind: String
        var equipment: String
        var loadPounds: Double
        var cue: String
        var sided: String
        var muscles: String
        var note: String
        /// The five form lines, required of an approval. Optional in the
        /// struct so a stored response from before they were asked decodes.
        var form: Form?
        /// `MovePattern.rawValue` and "standing" / "kneeling" / "floor".
        /// Optional so a stored response from before they were asked decodes.
        var pattern: String?
        var position: String?

        var movePattern: MovePattern? { pattern.flatMap(MovePattern.init(rawValue:)) }
        var movePosition: MovePosition? {
            switch position {
            case "standing": .standing
            case "kneeling": .kneeling
            case "floor": .floor
            default: nil
            }
        }

        struct Form: Codable, Sendable {
            var setUp: String
            var movement: String
            var feel: String
            var wrong: String
            var stopIf: String
        }

        var isApproved: Bool { verdict == "approved" }
        var isFlow: Bool { kind == MoveKind.flow.rawValue }
    }

    private struct Response: Codable {
        var moves: [Entry]
    }

    struct Result: Sendable {
        var entries: [Entry]
        var usage: ClaudePlanner.Usage
    }

    /// Reviews a batch of queued names against the kit and the existing
    /// library. Returns one entry per name — approved with a written cue, or
    /// rejected with the reason.
    func review(_ names: [String], existing: [String]) async throws -> Result {
        let prompt = """
        Review these moves she wants to add to her library: \(names.joined(separator: ", ")).

        For each, either approve it — with its equipment, load, cue, sided flag \
        and muscles — or reject it with one plain sentence she can read. Return \
        one entry per name, in the same order, keeping her name for the move \
        unless its spelling needs tidying.

        Already in the library (reject a duplicate and say which move it \
        duplicates): \(existing.joined(separator: ", ")).
        """
        return try await send(prompt: prompt, existing: existing)
    }

    /// Suggests new moves for a target muscle, written out in full so an
    /// accepted suggestion needs no second look.
    ///
    /// Ten are asked for so that five to ten survive. It asked for exactly
    /// four, and `validated` then demoted every near-duplicate — which is how
    /// a well-stocked muscle once came back with a single offer. The refusals
    /// ride along too: a suggestion she is on record as ruling out is not an
    /// offer, it is the app forgetting she said no.
    func suggest(muscle: String, existing: [String],
                 avoiding ruledOut: Set<String> = []) async throws -> Result {
        var prompt = """
        Suggest ten strength moves that target the \(muscle.lowercased()), \
        doable with her kit, that are not already in her library. Range across \
        the kit rather than giving ten variations on one pattern. Every entry \
        should be approved and written out in full — these are offers, and one \
        she takes joins the library as written.

        Already in the library (do not repeat any of these, or a light variant \
        of one): \(existing.joined(separator: ", ")).
        """
        if !ruledOut.isEmpty {
            prompt += "\n\nNever suggest these, or a close variant of one — she has ruled them out: \(ruledOut.sorted().joined(separator: ", "))."
        }
        let result = try await send(prompt: prompt, existing: existing)
        // The prompt asks; this enforces. Covered offers are dropped rather
        // than shown rejected — a list of moves she already said no to is not
        // information, and the rest of the ten fill the space.
        return Result(entries: result.entries.filter {
            !MovePreference.anyCovers(ruledOut, $0.name)
        }, usage: result.usage)
    }

    // MARK: - Request

    private func send(prompt: String, existing: [String]) async throws -> Result {
        guard let key = KeychainStore.read(.claudeAPIKey) else { throw PlannerError.noKey }

        // The system prompt lists the kit as a fixed fact, so anything she has
        // switched off has to be said out loud here or the two disagree.
        var prompt = prompt
        let missing = Equipment.switchable.filter { !$0.isOwned }
        if !missing.isEmpty {
            prompt += "\n\nShe does not currently have: \(missing.map { $0.label.lowercased() }.joined(separator: ", ")). Reject anything that needs one of those, however good the move."
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        // Same model, same effort, same exposure: shared so the two cannot
        // drift into disagreeing about how long thinking is allowed to take.
        request.timeoutInterval = ClaudePlanner.timeout

        let body: [String: Any] = [
            "model": Self.model,
            // A ceiling, not a spend — same lesson as the planner's. Ten
            // written-out suggestions under adaptive thinking at high effort
            // need headroom, and a `max_tokens` stop throws the answer away.
            "max_tokens": 16_000,
            "system": Self.systemPrompt,
            "thinking": ["type": "adaptive"],
            "output_config": [
                "effort": "high",
                "format": ["type": "json_schema", "schema": Self.schema]
            ],
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        do {
            (data, _) = try await sendChecked(request)
        } catch { throw error }

        let usage = ClaudePlanner.Usage.read(data)
        let entries = try Self.decode(data)
        return Result(entries: Self.validated(entries, existing: existing), usage: usage)
    }

    private func sendChecked(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PlannerError.transport(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw PlannerError.http(status, ClaudePlanner.reason(from: data))
        }
        return (data, response)
    }

    static func decode(_ data: Data) throws -> [Entry] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlannerError.malformed
        }
        switch object["stop_reason"] as? String {
        case "refusal": throw PlannerError.refused("unstated")
        case "max_tokens": throw PlannerError.truncated
        default: break
        }
        let blocks = object["content"] as? [[String: Any]] ?? []
        guard let json = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let response = try? JSONDecoder().decode(Response.self, from: Data(json.utf8))
        else { throw PlannerError.malformed }
        return response.moves
    }

    /// The checks the schema cannot express, applied after the fact — the same
    /// division of labour `PlanValidator` draws. An approval that names a load
    /// the equipment cannot be set to, or a name the working library already
    /// holds, is demoted to a rejection rather than let through: a wrong entry
    /// in the library outlives any one week.
    ///
    /// `existing` is the caller's working library — built-ins *and* her
    /// approved additions. Checking only `MoveLibrary.all` here let a second
    /// "Hammer curl" through, and duplicate names become duplicate values in
    /// the planner's schema enum. Within one answer, a repeated name keeps its
    /// first entry and the rest are demoted for the same reason.
    static func validated(_ entries: [Entry], existing: [String]) -> [Entry] {
        let taken = Set((MoveLibrary.all.map(\.name) + existing).map { MovePreference.key($0) })
        var seen: Set<String> = []
        return entries.map { entry in
            var entry = entry
            guard entry.isApproved else { return entry }

            guard let equipment = Equipment(rawValue: entry.equipment),
                  equipment != .walkingPad, equipment.isOwned else {
                entry.verdict = "rejected"
                entry.note = "That needs equipment outside the kit."
                return entry
            }
            let legal = equipment.availableLoadsPounds
            if entry.loadPounds > 0, !legal.contains(entry.loadPounds) {
                entry.verdict = "rejected"
                entry.note = "It asks for \(Int(entry.loadPounds)) lb, and the \(equipment.shortLabel.lowercased()) cannot be set to that."
                return entry
            }
            let key = MovePreference.key(entry.name)
            if taken.contains(key) || !seen.insert(key).inserted {
                entry.verdict = "rejected"
                entry.note = "Already in the library."
            }
            return entry
        }
    }

    // MARK: - Contract

    /// One entry per move, approved or not. Equipment and sidedness are enums
    /// for the same reason the planner's move names are: a bad answer should
    /// be unrepresentable, not merely caught.
    static var schema: [String: Any] {[
        "type": "object",
        "additionalProperties": false,
        "required": ["moves"],
        "$defs": [
            "move": [
                "type": "object",
                "additionalProperties": false,
                "required": ["name", "verdict", "kind", "equipment", "loadPounds",
                             "cue", "sided", "muscles", "note", "form", "pattern", "position"],
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "The move's name, in the library's style: 'Beam front squat', 'Ring halo'. Keep her name unless the spelling needs tidying."
                    ],
                    "verdict": ["type": "string", "enum": ["approved", "rejected"]],
                    "kind": [
                        "type": "string",
                        "enum": [MoveKind.strength.rawValue, MoveKind.flow.rawValue],
                        "description": "'strength' for a lift or hold done as a timed set; 'flow' for qi gong, mobility or lymphatic movement — continuous, unhurried, never counted down at. Flow joins her daily practice pool, strength joins the session rotations."
                    ],
                    "equipment": [
                        "type": "string",
                        // Her kit as it stands, minus the pad, which carries no
                        // moves. A review that approves a band move she cannot
                        // do puts it in the library and then into rotations.
                        "enum": Equipment.owned
                            .filter { $0 != .walkingPad }
                            .map(\.rawValue)
                    ],
                    "loadPounds": [
                        "type": "number",
                        "enum": ClaudePlanner.legalLoads,
                        "description": "The load the move is written for. Zero for bodyweight."
                    ],
                    "cue": [
                        "type": "string",
                        "description": "One line of form in plain words, shown under the name while she works. Never exclaims."
                    ],
                    "sided": [
                        "type": "string",
                        "enum": ["none", "sides", "directions"],
                        "description": "'sides' when it is done one leg or arm at a time, 'directions' when one way and then the other. Each side then gets its own full work interval."
                    ],
                    "muscles": [
                        "type": "string",
                        "description": "What it works, lowercase, comma separated, drawn from: shoulders, arms, chest, back, core, glutes, legs."
                    ],
                    "note": [
                        "type": "string",
                        "description": "For a rejection, one plain sentence saying why. For an approval, empty."
                    ],
                    "pattern": [
                        "type": "string",
                        "enum": MovePattern.allCases.map(\.rawValue),
                        "description": "The movement pattern a strength move trains: squat, hinge, lunge, pushHorizontal, pushVertical, pullHorizontal, pullVertical, carry, coreAntiRotation, coreFlexion, coreExtension, or accessory for single-joint work. For flow, accessory."
                    ],
                    "position": [
                        "type": "string",
                        "enum": ["standing", "kneeling", "floor"],
                        "description": "Where the body is: standing; kneeling (tall or half, legs taken out so the trunk holds her up); floor for anything on the mat, seated or on all fours."
                    ],
                    "form": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["setUp", "movement", "feel", "wrong", "stopIf"],
                        "description": "Five one-sentence form notes for a beginner who has never been shown. Empty strings on a rejection.",
                        "properties": [
                            "setUp": ["type": "string", "description": "Where the feet, hands and implement are before anything moves."],
                            "movement": ["type": "string", "description": "What moves, in what order, how fast."],
                            "feel": ["type": "string", "description": "Where the work should land."],
                            "wrong": ["type": "string", "description": "The mistake a beginner makes, and what to do instead."],
                            "stopIf": ["type": "string", "description": "The signal that means stop — pain named by place, never effort."]
                        ]
                    ]
                ]
            ]
        ],
        "properties": [
            "moves": ["type": "array", "items": ["$ref": "#/$defs/move"]]
        ]
    ]}

    /// The coach brief, then what only code can say: the kit with its loads
    /// (from the enum) and what a library move is. One coach for the planner
    /// and the reviewer, so a move the reviewer approves is one the planner
    /// would have written.
    static var systemPrompt: String {
        """
        You curate the move library of a home training app called Almanac, for \
        its one user. You are the coach described below; the brief's rules — \
        what a move must name to be accepted, what is never proposed — are \
        yours here.

        ===== THE COACH BRIEF =====
        \(CoachBrief.text)
        ===== END OF THE BRIEF =====

        \(ClaudePlanner.kitSection)

        WHAT A LIBRARY MOVE IS
        Two kinds, and classifying is your job, never hers:
        - 'strength': a lift or hold done for sets or for time, with one piece \
        of the kit and one load that equipment can actually be set to. It joins \
        the session rotations.
        - 'flow': qi gong, mobility or lymphatic movement — continuous, \
        unhurried, never counted down at. It joins her daily morning practice \
        and the warm-ups. Almost always bodyweight with no load.
        Approve only what a careful beginner can do alone on a mat at home. \
        Reject anything that is really cardio, anything that needs a coach's \
        eye to be safe (heavy hinges at speed, anything overhead and behind the \
        neck, the kettlebell swing), and any duplicate of a move the library \
        already holds — say which one.

        Mark a move 'sides' when it is done one leg or arm at a time, and \
        'directions' when it runs one way and then the other, like a halo. The \
        timer then gives each side its own full work interval.

        PATTERN AND POSITION
        Every move names its pattern and its position. Kneeling means the legs \
        are taken out so the trunk has to hold her up; a move on the mat, \
        seated, or on all fours is floor.

        FORM
        Every approval carries five form lines for someone who has never been \
        shown: set up, the movement, what to feel, what goes wrong, stop if. \
        One sentence each, in the brief's voice. Effort is never the stop \
        signal; pain named by place is.

        VOICE — every cue, note and form line
        Plain, warm, specific. Name the real equipment and the real load. One \
        sentence. Never exclaim, never imply she failed, no emoji. In register: \
        "The 10 lb ring between the feet. Hinge, don't squat."
        """
    }
}
