import Foundation

/// The guardrail that makes the `Equipment` enum mean something.
///
/// A closed enum only constrains anything if something checks against it. This
/// runs over every generated week before a single session is written to the
/// store, and it rejects the **whole week** rather than dropping bad moves —
/// a session missing half its rotation is a worse artefact than no session, and
/// a planner that silently had its output edited never learns it was wrong.
enum PlanValidator {
    enum Failure: LocalizedError, Equatable {
        case noSessions
        case dayOutOfWeek(Int)
        case emptyRotation(String)
        case unknownEquipment(String)
        case unknownMove(String)
        case impossibleLoad(move: String, equipment: Equipment, pounds: Double)
        case workOverCeiling(seconds: Int)
        case nonsenseTiming(String)
        case duplicateDay(Int)
        case stubbed
        /// Three implements in one session is a planning error, brief §8:
        /// one by default, two at most, the second set out before she starts.
        case tooManyImplements(String, Int)

        var errorDescription: String? {
            switch self {
            case .noSessions: "The week came back with no sessions."
            case .dayOutOfWeek(let day): "A session was scheduled on day \(day)."
            case .tooManyImplements(let title, let count): "\"\(title)\" asks for \(count) implements; two is the most a session may need."
            case .emptyRotation(let title): "\"\(title)\" has no moves."
            case .unknownEquipment(let raw): "\"\(raw)\" is not equipment that exists."
            case .unknownMove(let raw): "\"\(raw)\" is not a move in the library."
            case .impossibleLoad(let move, let equipment, let pounds):
                "\"\(move)\" asks for \(Int(pounds)) lb, and the \(equipment.shortLabel.lowercased()) cannot be set to that."
            case .workOverCeiling(let seconds):
                "A work interval of \(seconds)s is over the 60-second ceiling."
            case .nonsenseTiming(let detail): detail
            case .duplicateDay(let day):
                "Two sessions were both put on day \(day)."
            case .stubbed:
                "A session came back as a placeholder rather than real moves."
            }
        }
    }

    /// The most rounds a thirteen-minute session can sensibly hold. Not a
    /// safety limit — a sanity one, so a stray zero cannot produce a routine
    /// that runs for an hour.
    static let roundCeiling = 20

    /// Walking is programmed toward the goal, so it is the one number with a
    /// real safety bound rather than a sanity one. Above five hours a week
    /// adherence collapses and it stops being a plan she can keep.
    static let walkFloor = 0
    static let walkCeiling = 300

    /// Validates and converts. Throws on the first thing that is wrong.
    /// `extras` are her own approved additions — the one way the working
    /// library is larger than the built-in one.
    static func routines(from draft: PlanDraft,
                         extras: [Move] = []) throws -> [(dayOffset: Int, routine: IntervalRoutine)] {
        guard !draft.sessions.isEmpty else { throw Failure.noSessions }

        // Two sessions on one day is the signature of a half-written week: the
        // model fills the slots it has something to say about and stubs the
        // rest onto whatever day it used first. Caught here rather than in the
        // store, where it would show up as a day with two sessions and a day
        // with none.
        let days = draft.sessions.map(\.dayOffset)
        if let repeated = days.first(where: { day in days.filter { $0 == day }.count > 1 }) {
            throw Failure.duplicateDay(repeated)
        }

        // A stub carries the word through from the schema rather than a move
        // name. It is a weak signal on its own, which is why it is checked
        // alongside the duplicate day rather than instead of it.
        if draft.sessions.contains(where: { $0.moves.contains { $0.name.lowercased().contains("placeholder") } }) {
            throw Failure.stubbed
        }

        guard (walkFloor...walkCeiling).contains(draft.walkMinutes) else {
            throw Failure.nonsenseTiming(
                "A walking target of \(draft.walkMinutes) minutes is outside \(walkFloor)–\(walkCeiling).")
        }

        return try draft.sessions.map { session in
            guard (0...6).contains(session.dayOffset) else {
                throw Failure.dayOutOfWeek(session.dayOffset)
            }
            guard !session.moves.isEmpty else {
                throw Failure.emptyRotation(session.title)
            }
            guard session.work > 0 else {
                throw Failure.nonsenseTiming("\"\(session.title)\" has a work interval of \(session.work)s.")
            }
            guard Double(session.work) <= IntervalRoutine.workCeiling else {
                throw Failure.workOverCeiling(seconds: session.work)
            }
            guard session.rest >= 0 else {
                throw Failure.nonsenseTiming("\"\(session.title)\" has a negative rest.")
            }
            guard (1...roundCeiling).contains(session.rounds) else {
                throw Failure.nonsenseTiming("\"\(session.title)\" asks for \(session.rounds) rounds.")
            }

            // Ordered, never trimmed: whatever the model or the offline
            // planner wrote, the session runs standing first and the floor
            // last, so a week never opens on the mat, stands up for the
            // beam and lies back down. Coverage is the writer's job; order
            // is the app's.
            let moves = MoveLibrary.ordered(
                try session.moves.map { try move(from: $0, extras: extras) })
            // Brief §8: one implement by default, two at most. A third is
            // fetching mid-session, which is the complaint this exists for.
            let implements = MoveLibrary.implements(in: moves).count
            guard implements <= 2 else {
                throw Failure.tooManyImplements(session.title, implements)
            }
            return (session.dayOffset,
                    IntervalRoutine(name: session.title,
                                    work: TimeInterval(session.work),
                                    rest: TimeInterval(session.rest),
                                    rounds: session.rounds,
                                    moves: moves)
                        .inMode(session.sessionMode))
        }
    }

    /// The check the whole brief hangs on: the rings are three *different*
    /// weights, so a load is only legal if it is one the kit can actually be
    /// set to. Validated against `availableLoadsPounds`, never against prose.
    /// The library move the name refers to, taken whole.
    ///
    /// It used to cross-check the model's equipment against the library's and
    /// its load against `availableLoadsPounds`. Those checks are gone because
    /// what they guarded is now unrepresentable: the schema asks only for a
    /// name, and a legal name determines the equipment, the cue and the load.
    /// "Ring halo" *is* the 5 lb ring. A week can no longer name a move with a
    /// load its kit cannot be set to, because the load is not the model's to
    /// state — which is stricter than checking it after the fact.
    ///
    /// It also removed three fields from a definition paid for once per move
    /// slot per session, which is what put the compiled grammar over the size
    /// limit and returned 400 "schema too complex".
    static func move(from draft: DraftMove, extras: [Move] = []) throws -> Move {
        // The library is closed, so a name outside it is a week that would draw
        // the wrong shape or none at all. Rejected here rather than papered
        // over by a matcher further down. Her approved additions count as the
        // library here — they went through their own review to earn it.
        guard let known = (MoveLibrary.all + extras).first(where: {
            MovePreference.key($0.name) == MovePreference.key(draft.name)
        }) else {
            throw Failure.unknownMove(draft.name)
        }
        // `MoveLibrary.names` — the schema's enum — is strength only, but this
        // lookup runs against the whole library, so the second gate has to say
        // so too. A flow movement in a rotation becomes a work interval and
        // gets counted down at like a set.
        guard known.kind == .strength else {
            throw Failure.unknownMove(draft.name)
        }
        // And the kit has to be in the house. The schema's name enum is built
        // from what she owns, so this should be unreachable from a generated
        // week — but the validator guards the offline planner too, and it is
        // the last thing between a plan and the store. A week asking for a
        // band she does not have is a week she cannot do.
        guard known.equipment.isOwned else {
            throw Failure.unknownMove(draft.name)
        }
        return known
    }

    /// Recognises a flow movement by name.
    ///
    /// The draft schema carries no kind — adding one would be another required
    /// field for the model to fill and get wrong. Matching against the flow
    /// library instead means a generated "cat cow" is tagged as the practice it
    /// is rather than cued like a deadlift.
    static func kind(of name: String) -> MoveKind {
        let candidate = MovePreference.key(name)
        let isFlow = MoveLibrary.flow.contains { known in
            let key = MovePreference.key(known.name)
            return candidate == key || candidate.contains(key)
        }
        return isFlow ? .flow : .strength
    }
}
