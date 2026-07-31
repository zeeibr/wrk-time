import Foundation

/// What the planner is told before it writes a week.
///
/// Everything here is a fact the app already holds. Nothing is inferred, and
/// nothing about her body or her goals appears that she did not type in
/// herself — see the brief's closing rule.
struct PlanContext: Sendable {
    var weekNumber: Int
    var pace: Pace
    /// Sessions finished in the last fortnight, most recent first, as
    /// "Tue · Lower · finished" lines. Attendance is the strongest signal the
    /// planner has, and the only one it should ever program down from.
    var recent: [String]
    /// Loose sets logged off-plan. Real volume the planner should know about.
    var loggedSets: [String]
    /// The trailing weight mean and the projection, when she has set a goal.
    var weightNote: String?
    /// Eating window, if one is recorded.
    var eatingWindow: String?
    /// Walking minutes recorded in the last seven days, from Health.
    var recentWalkMinutes: Int?
    /// Pounds still to go, when she has set a goal. The only number the walking
    /// target is allowed to be programmed against.
    var poundsToGoal: Double?
    /// Moves she has said hurt. Absolute — the planner must not use these.
    var avoidedMoves: [String] = []
    /// Moves she does not enjoy. Allowed rarely, never twice in a week.
    var dislikedMoves: [String] = []
    /// Moves she found too hard. Keep, but scale.
    var hardMoves: [String] = []
    /// What the last generated week said, so this week reads as a continuation
    /// rather than a fresh start every time.
    var lastExplanation: String?

    /// How much she actually did in the last seven days.
    ///
    /// Her ask, in her words: *"sometimes i do a lot of them in a day and i want
    /// that to be considered."* Before this the planner was told a binary
    /// finished/not-done per planned session and up to ten **undated**
    /// off-plan set summaries. So a week where she did four planned sessions
    /// and five of her own routines looked identical to a week of four
    /// sessions and nothing else — the extra work was not merely unweighted,
    /// it was absent.
    ///
    /// An aggregate rather than another list, deliberately. The existing lists
    /// are truncated at ten and carry no dates, so a busy fortnight silently
    /// loses its tail; a count cannot.
    var workload: Workload?

    struct Workload: Sendable, Equatable {
        var sessionsDone = 0
        var sessionsPlanned = 0
        var routineRuns = 0
        var practices = 0
        var loggedSets = 0

        /// Workouts beyond what the plan asked for. Practices are excluded —
        /// they happen every day by design and are not extra.
        var beyondThePlan: Int { routineRuns }

        /// Whether the week carried appreciably more than it was written for.
        /// Used as a planning trigger, so the threshold is "worth adapting to"
        /// rather than "any extra at all": one bonus workout is a good day, not
        /// a signal the plan is wrong.
        static let notableExtra = 2
        var carriedNotableExtra: Bool { beyondThePlan >= Self.notableExtra }

        var line: String {
            var parts = ["\(sessionsDone) of \(sessionsPlanned) planned sessions finished"]
            if routineRuns > 0 {
                parts.append(routineRuns == 1
                             ? "1 extra workout of her own"
                             : "\(routineRuns) extra workouts of her own")
            }
            if practices > 0 { parts.append("\(practices) morning practices") }
            if loggedSets > 0 { parts.append("\(loggedSets) loose sets") }
            return parts.joined(separator: ", ") + "."
        }
    }

    /// The prompt body. Deliberately plain lines rather than JSON — the model
    /// reads this better, and there is nothing here that needs escaping.
    var prompt: String {
        var lines: [String] = [
            "Write week \(weekNumber) of the block.",
            "Pace: \(pace.label.lowercased()) — \(pace.note)",
            "Schedule exactly \(pace.sessionsPerWeek) sessions across the seven days, with the rest days spread rather than stacked at the end.",
            // Spelled out because the schema cannot say it: JSON Schema's
            // `minItems` is unsupported by structured outputs, so an empty
            // rotation satisfies the contract and produces a session with
            // nothing in it. The first live call did exactly that.
            // Named from `Tuning` rather than written out, because this line
            // said "two or three" for weeks after the schema had moved to five.
            // The schema is what is enforced; a prompt that disagrees with it
            // only spends thinking on resolving the contradiction.
            "Every session must fill all \(Tuning.movesPerSession) move slots. A session with an empty move list is discarded and the whole week is thrown away."
        ]
        if let weightNote { lines.append("Weight: \(weightNote)") }
        if let eatingWindow { lines.append("Eating window: \(eatingWindow)") }
        if let recentWalkMinutes {
            lines.append("Walking in the last seven days: \(recentWalkMinutes) minutes.")
        } else {
            lines.append("No walking recorded in the last seven days — either she did not walk or nothing wrote it to Health. Do not read it as zero effort.")
        }
        if let poundsToGoal, poundsToGoal > 0 {
            lines.append("She is \(Int(poundsToGoal.rounded())) lb above a goal she set. Set the walking target with that in mind; leave the sessions alone.")
        }

        if recent.isEmpty {
            lines.append("\nThis is the first week. There is no history yet — start conservatively and leave room to progress.")
        } else {
            lines.append("\nLast fortnight:")
            lines.append(contentsOf: recent.map { "- \($0)" })
        }
        if let workload {
            lines.append("\nLast seven days: \(workload.line)")
            // The instruction, not just the number. `Logged off-plan:` sat
            // under a bare heading with no guidance anywhere in this prompt or
            // the system prompt, which is why extra work had never changed a
            // week: the model was handed data and told nothing about it.
            //
            // Both directions matter, and the second is the one that protects
            // her: extra work next to missed sessions is not a licence to
            // program more.
            if workload.beyondThePlan > 0 {
                lines.append("Those extra workouts are hers, not yours to program — but they are real volume. If she is consistently doing more than the plan asks, there is room to progress faster than the default step.")
                if workload.sessionsDone < workload.sessionsPlanned {
                    lines.append("She is also missing planned sessions while adding her own. Read that as the plan's shape not fitting her week — try different days or shorter sessions — not as a reason to add work.")
                }
            }
        }
        if !loggedSets.isEmpty {
            lines.append("\nLoose sets logged off-plan, newest first:")
            lines.append(contentsOf: loggedSets.map { "- \($0)" })
        }
        if !avoidedMoves.isEmpty {
            lines.append("\nNever program these — she said they hurt: \(avoidedMoves.joined(separator: ", ")). This includes close variants of them.")
        }
        if !dislikedMoves.isEmpty {
            lines.append("She does not enjoy these, so use them rarely and never more than once in a week: \(dislikedMoves.joined(separator: ", ")). Variants of them count.")
        }
        if !hardMoves.isEmpty {
            lines.append("These were too hard. Keep them, but scale them down — an easier variant, fewer rounds, or a lighter ring: \(hardMoves.joined(separator: ", ")).")
        }
        if let lastExplanation {
            lines.append("\nWhat you said about last week: \(lastExplanation)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - The shape that comes back

/// A week, as the planner writes it. Not yet trusted — `PlanValidator` decides
/// whether any of this is allowed to become a session.
struct PlanDraft: Codable, Sendable, Equatable {
    /// One sentence, in the app's voice, saying what changed and why.
    var explanation: String
    var sessions: [DraftSession]

    /// Minutes on the walking pad this week.
    ///
    /// Separate from `sessions` because it is a different kind of thing: a
    /// session is thirteen minutes of intervals, and walking is volume spread
    /// across a week. Faking it as a session would have made the growth form
    /// count a walk as a mark, which it is not.
    ///
    /// This is also the only part of the plan that is programmed *toward* the
    /// goal weight, and the reason is arithmetic rather than philosophy: the
    /// resistance work builds and keeps muscle but barely moves energy balance,
    /// and walking is the one training lever that does.
    var walkMinutes: Int

    init(explanation: String, sessions: [DraftSession], walkMinutes: Int = 0) {
        self.explanation = explanation
        self.sessions = sessions
        self.walkMinutes = walkMinutes
    }

    private enum Key: String, CodingKey { case explanation, sessions, walkMinutes }

    /// The named slots the schema requires, in order. Same trick as the move
    /// rotation: a required property pins the count, an array cannot.
    private struct Slots: Codable {
        var one: DraftSession?
        var two: DraftSession?
        var three: DraftSession?
        var four: DraftSession?
        var five: DraftSession?

        var ordered: [DraftSession] { [one, two, three, four, five].compactMap { $0 } }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        explanation = try container.decode(String.self, forKey: .explanation)
        walkMinutes = (try? container.decode(Int.self, forKey: .walkMinutes)) ?? 0

        if let slots = try? container.decode(Slots.self, forKey: .sessions), !slots.ordered.isEmpty {
            sessions = slots.ordered
        } else {
            sessions = try container.decode([DraftSession].self, forKey: .sessions)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(explanation, forKey: .explanation)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(walkMinutes, forKey: .walkMinutes)
    }
}

struct DraftSession: Codable, Sendable, Equatable {
    /// Days from the start of the week, 0–6.
    var dayOffset: Int
    var title: String
    /// Seconds. Validated against `IntervalRoutine.workCeiling`.
    var work: Int
    var rest: Int
    var rounds: Int
    var moves: [DraftMove]

    init(dayOffset: Int, title: String, work: Int, rest: Int, rounds: Int, moves: [DraftMove]) {
        self.dayOffset = dayOffset
        self.title = title
        self.work = work
        self.rest = rest
        self.rounds = rounds
        self.moves = moves
    }

    private enum Key: String, CodingKey {
        case dayOffset, title, work, rest, rounds, moves
    }

    /// Named slots rather than a list.
    ///
    /// This exists because of a failure the prompt could not fix. JSON Schema's
    /// `minItems` is not supported by structured outputs, so `moves: []`
    /// satisfies an array contract perfectly — and the model kept returning
    /// exactly that for one session per week, even when handed its own
    /// rejected answer and told the rule in plain words. *Required* properties
    /// are enforceable where a minimum length is not, so the empty rotation
    /// stops being expressible at all.
    ///
    /// The slot names are `ClaudePlanner.moveSlots`, and how many of them are
    /// required is `Tuning.movesPerSession`. That is why this reads them by
    /// name at runtime instead of declaring a struct: the struct used to name
    /// `first`, `second` and `third` while the schema had already moved to
    /// five, so five moves were asked for, billed for, returned — and two of
    /// them silently dropped on the way in. Nothing caught it, because
    /// `PlanValidator` counted sessions and never counted moves. And at a
    /// setting of two the struct failed to decode at all, which threw outside
    /// the repair loop and sent every week of the block to the offline planner
    /// after paying for it.
    private struct SlotKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        dayOffset = try container.decode(Int.self, forKey: .dayOffset)
        title = try container.decode(String.self, forKey: .title)
        work = try container.decode(Int.self, forKey: .work)
        rest = try container.decode(Int.self, forKey: .rest)
        rounds = try container.decode(Int.self, forKey: .rounds)

        // The object form is what the schema asks for; the array form is still
        // accepted so a hand-written fixture or an older stored draft decodes.
        if let slots = try? container.nestedContainer(keyedBy: SlotKey.self, forKey: .moves) {
            // In slot order, and every slot present is taken. Reading the
            // container's own keys instead would put the rotation in whatever
            // order JSON happened to serialise.
            moves = ClaudePlanner.moveSlots
                .compactMap { SlotKey(stringValue: $0) }
                .compactMap { try? slots.decode(DraftMove.self, forKey: $0) }
            guard !moves.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .moves, in: container,
                    debugDescription: "A rotation object with no recognised slots.")
            }
        } else {
            moves = try container.decode([DraftMove].self, forKey: .moves)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(dayOffset, forKey: .dayOffset)
        try container.encode(title, forKey: .title)
        try container.encode(work, forKey: .work)
        try container.encode(rest, forKey: .rest)
        try container.encode(rounds, forKey: .rounds)
        try container.encode(moves, forKey: .moves)
    }
}

struct DraftMove: Codable, Sendable, Equatable {
    var name: String
    /// Must decode to a case of `Equipment`; anything else is rejected.
    var equipment: String = ""
    var cue: String = ""
    /// Pounds. Zero means the move carries no load — bodyweight.
    var loadPounds: Double = 0

    init(name: String, equipment: String = "", cue: String = "", loadPounds: Double = 0) {
        self.name = name
        self.equipment = equipment
        self.cue = cue
        self.loadPounds = loadPounds
    }

    /// Only `name` is required.
    ///
    /// The schema asks Claude for the name and nothing else, because the
    /// library is closed and therefore already holds the equipment, the cue and
    /// the load for every legal name — "Ring halo" *is* the 5 lb ring. Making
    /// the model restate them was asking it to repeat three facts the app
    /// owns, and each one multiplied across every move slot in the week, which
    /// is what put the compiled grammar over the size limit.
    ///
    /// The other three stay on the struct because `OfflinePlanner` builds
    /// complete drafts by hand and the archive's fixtures carry them.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        equipment = try container.decodeIfPresent(String.self, forKey: .equipment) ?? ""
        cue = try container.decodeIfPresent(String.self, forKey: .cue) ?? ""
        loadPounds = try container.decodeIfPresent(Double.self, forKey: .loadPounds) ?? 0
    }
}
