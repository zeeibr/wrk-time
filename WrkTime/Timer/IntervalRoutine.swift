import Foundation

/// What sort of movement this is.
///
/// Strength work and flow work want opposite things from a timer. A split squat
/// is a set: forty seconds of effort against a rest. A spinal wave or a round
/// of arm swings is a *practice* — continuous, unhurried, and ruined by being
/// counted down at. Without this distinction the planner would happily drop a
/// lymphatic bounce into a work interval and cue it like a deadlift.
enum MoveKind: String, Codable, Sendable, CaseIterable {
    case strength
    case flow

    var label: String {
        switch self {
        case .strength: "Strength"
        case .flow: "Flow"
        }
    }
}

/// A movement the user can actually do with the kit they own.
struct Move: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var equipment: Equipment
    /// One line of form, in plain words. Shown under the name while working.
    var cue: String
    /// The load this move is written for, where the equipment offers a choice.
    ///
    /// The rings are three different weights, so "the 8 lb ring" in a cue has
    /// to be a fact the app knows rather than a sentence it happens to print —
    /// otherwise logging that move would offer the wrong weight by default.
    var loadPounds: Double?

    /// Optional on purpose. Routines are stored as JSON in `PlannedSession`,
    /// `SavedRoutine` and `ActiveSession`, and Swift's synthesized decoder
    /// *throws* on a missing non-optional key rather than using its default —
    /// so adding this as non-optional would have made every routine already on
    /// disk undecodable. Optional decodes as nil and reads as `.strength`.
    var kindRaw: MoveKind?

    var kind: MoveKind { kindRaw ?? .strength }

    init(id: UUID = UUID(), name: String, equipment: Equipment, kind: MoveKind = .strength,
         cue: String, loadPounds: Double? = nil) {
        self.id = id
        self.name = name
        self.equipment = equipment
        self.cue = cue
        self.loadPounds = loadPounds
        self.kindRaw = kind
    }

    var symbol: String { equipment.symbol }
    /// Names the one thing this move needs, not the whole drawer. A move using
    /// the 10 lb ring says so; it does not list all three rings.
    var equipmentLabel: String { equipment.label(forLoad: loadPounds) }
}

/// One stretch of a hand-built sequence.
///
/// A routine can be a fixed shape — so many rounds of so much work against so
/// much rest — or a written-out sequence where every interval is its own
/// length. The second is what "30 on, 30 rest, 20 on, 15 rest, 10 on, 10 on,
/// 10 on, 30 rest" needs, and note that it has three work intervals in a row:
/// a step says what it is, so nothing here assumes work and rest alternate.
struct IntervalStep: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var isWork: Bool
    var seconds: TimeInterval

    static func work(_ seconds: TimeInterval) -> IntervalStep {
        IntervalStep(isWork: true, seconds: seconds)
    }
    static func rest(_ seconds: TimeInterval) -> IntervalStep {
        IntervalStep(isWork: false, seconds: seconds)
    }

    /// The same ceiling the fixed shape has, enforced here so a sequence cannot
    /// route around it.
    var clamped: TimeInterval {
        isWork ? min(seconds, IntervalRoutine.workCeiling) : max(seconds, 0)
    }
}

/// A self-guided interval routine: fixed work and rest, a rotation of moves,
/// and a number of rounds. This is also the shape the planner emits, so a
/// generated session and a hand-built one run through the same engine.
///
/// A routine may have **no moves at all**. That is not an unfinished routine —
/// it is a plain interval timer, which is sometimes the only thing wanted, and
/// the schedule handles it by leaving the move on each phase nil.
struct IntervalRoutine: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var work: TimeInterval
    var rest: TimeInterval
    var rounds: Int
    var moves: [Move]
    /// The rest after the final round is pointless — you've finished. Dropping
    /// it is the default because it makes the stated total honest.
    var dropsFinalRest: Bool = true

    /// The flow practice that opens the session, before round one.
    ///
    /// Optional for the same reason `Move.kindRaw` is: routines are already on
    /// disk as JSON without these keys, and Swift's synthesized decoder throws
    /// on a missing non-optional key rather than falling back to the property's
    /// default. A non-optional array here would have made every stored routine
    /// undecodable at a stroke.
    var warmUpMoves: [Move]?
    var warmUpSecondsRaw: TimeInterval?

    /// A written-out sequence, when the routine is not a fixed shape.
    ///
    /// Optional for the same reason the warm-up is: routines are on disk as
    /// JSON without this key, and the synthesized decoder throws on a missing
    /// non-optional one. Empty and nil both mean "use work, rest and rounds".
    var steps: [IntervalStep]?

    /// How many times the written-out cadence runs.
    ///
    /// Her ask: *"i want to be able to say repeat this cadence for x rounds
    /// without having to set 6 things x more times."* Writing 30/30, 20/20,
    /// 10/10 and then wanting it four times over meant twenty-four steppers.
    ///
    /// Optional for the reason every field added to a stored routine is: these
    /// are JSON on disk and the synthesized decoder *throws* on a missing
    /// non-optional key, so a non-optional here would make every routine
    /// already saved undecodable. Nil reads as one pass.
    var sequenceRepeatsRaw: Int?

    var sequence: [IntervalStep] { steps ?? [] }
    var isSequence: Bool { !sequence.isEmpty }
    /// At least one, however the stored value got there.
    var sequenceRepeats: Int { max(sequenceRepeatsRaw ?? 1, 1) }

    /// How many work intervals this routine holds, however it is shaped. The
    /// header counts against this, so "Round 3 / 7" is true of a sequence too.
    var roundCount: Int {
        isSequence ? sequence.filter(\.isWork).count * sequenceRepeats : rounds
    }

    var warmUp: [Move] { warmUpMoves ?? [] }
    /// How long each flow movement runs. Longer than a work interval on
    /// purpose: this is a practice, and forty seconds of arm swings is barely
    /// enough to stop rushing them.
    var warmUpSeconds: TimeInterval { warmUpSecondsRaw ?? WarmUp.seconds }

    /// The ceiling the user asked for. Enforced at the model layer rather than
    /// in the UI, so nothing downstream can exceed it.
    static let workCeiling: TimeInterval = 60

    var clampedWork: TimeInterval { min(work, Self.workCeiling) }

    /// The same routine as a written-out sequence, optionally repeated.
    func following(_ steps: [IntervalStep], repeats: Int = 1) -> IntervalRoutine {
        var copy = self
        copy.steps = steps.isEmpty ? nil : steps
        copy.sequenceRepeatsRaw = steps.isEmpty ? nil : max(repeats, 1)
        return copy
    }

    /// The same routine with a flow practice on the front.
    func warmingUp(with moves: [Move], seconds: TimeInterval = WarmUp.seconds) -> IntervalRoutine {
        var copy = self
        copy.warmUpMoves = moves.isEmpty ? nil : moves
        copy.warmUpSecondsRaw = moves.isEmpty ? nil : seconds
        return copy
    }

    var totalDuration: TimeInterval {
        schedule.total
    }

    var schedule: RoutineSchedule { RoutineSchedule(routine: self) }
}

// MARK: - Schedule

/// One stretch of the routine — a flow movement, a work interval, or the rest
/// after it.
struct Phase: Equatable {
    /// `flow` is a third kind rather than a work interval with a flag, because
    /// almost everything the app does at a boundary asks this question: the
    /// field holds still through flow, no countdown is cued into it, and it is
    /// not a round. A boolean would have had to be checked in all of those
    /// places and would have been forgotten in one.
    enum Kind: Equatable { case flow, work, rest }

    let kind: Kind
    /// 1-based, for display. Counts rounds for work and rest; counts position
    /// in the practice for flow.
    let round: Int
    let move: Move?
    let duration: TimeInterval
    /// Seconds from routine start at which this phase begins and ends.
    let start: TimeInterval
    let end: TimeInterval

    var isWork: Bool { kind == .work }
    var isFlow: Bool { kind == .flow }
    var isRest: Bool { kind == .rest }

    /// "Round 3 / 8", or "Warm-up 2 / 4" during the practice.
    ///
    /// Lives on the phase rather than in each view because the screen and the
    /// lock screen must never be able to disagree about where the session is —
    /// they are the same session read in two places.
    func position(rounds: Int, flowCount: Int) -> String {
        guard isFlow else { return "Round \(round) / \(rounds)" }
        // A routine with no rounds is the morning practice, not a warm-up for
        // something else. Calling it a warm-up would name it after work that is
        // not coming.
        let label = rounds > 0 ? "Warm-up" : "Movement"
        return "\(label) \(round) / \(max(flowCount, round))"
    }
}

/// The routine flattened into an ordered list of phases with absolute offsets.
///
/// Everything about progress is derived from elapsed time against these
/// offsets rather than by accumulating per-tick decrements, so the clock cannot
/// drift no matter how irregular the ticks are.
struct RoutineSchedule: Equatable {
    let phases: [Phase]
    let total: TimeInterval

    init(routine: IntervalRoutine) {
        var built: [Phase] = []
        var cursor: TimeInterval = 0
        let work = routine.clampedWork
        let moves = routine.moves

        // The practice comes first, and it runs continuously — no rest between
        // one movement and the next. A rest interval inside a flow would be the
        // countdown logic reasserting itself over something that is meant to be
        // unhurried.
        let flowLength = routine.warmUpSeconds
        for (position, move) in routine.warmUp.enumerated() where flowLength > 0 {
            built.append(Phase(kind: .flow, round: position + 1, move: move,
                               duration: flowLength, start: cursor, end: cursor + flowLength))
            cursor += flowLength
        }

        // A written-out sequence: every interval its own length, in the order
        // she wrote them, with no assumption that work and rest alternate.
        // Moves are taken from the rotation in turn as work intervals arrive,
        // exactly as rounds do.
        if routine.isSequence {
            var round = 0
            // The cadence, however many times she asked for it. Rounds keep
            // counting across passes rather than restarting, so "Round 7 / 12"
            // is true of a three-work cadence run four times.
            for _ in 0..<routine.sequenceRepeats {
                for step in routine.sequence {
                    let length = step.clamped
                    guard length > 0 else { continue }
                    if step.isWork {
                        round += 1
                        let move = moves.isEmpty ? nil : moves[(round - 1) % moves.count]
                        built.append(Phase(kind: .work, round: round, move: move,
                                           duration: length, start: cursor, end: cursor + length))
                    } else {
                        built.append(Phase(kind: .rest, round: max(round, 1), move: nil,
                                           duration: length, start: cursor, end: cursor + length))
                    }
                    cursor += length
                }
            }
            phases = built
            total = cursor
            return
        }

        // A routine may be nothing but its practice — that is the morning
        // ritual, eight flow movements and no rounds at all. Without this the
        // schedule would invent a work interval to satisfy `max(rounds, 1)`.
        guard routine.rounds > 0 else {
            phases = built
            total = cursor
            return
        }

        for round in 1...routine.rounds {
            let move = moves.isEmpty ? nil : moves[(round - 1) % moves.count]

            built.append(Phase(kind: .work, round: round, move: move,
                               duration: work, start: cursor, end: cursor + work))
            cursor += work

            let isLast = round == routine.rounds
            if !(isLast && routine.dropsFinalRest), routine.rest > 0 {
                built.append(Phase(kind: .rest, round: round, move: nil,
                                   duration: routine.rest, start: cursor, end: cursor + routine.rest))
                cursor += routine.rest
            }
        }

        phases = built
        total = cursor
    }

    /// The phase containing `elapsed`, or nil once the routine is over.
    func index(atElapsed elapsed: TimeInterval) -> Int? {
        guard elapsed >= 0, elapsed < total else { return nil }
        // Phases are short and few; a linear scan is faster than a binary
        // search here and far easier to reason about.
        return phases.firstIndex { elapsed < $0.end }
    }

    /// Offset at which a given phase begins — used when skipping.
    func start(of index: Int) -> TimeInterval {
        guard phases.indices.contains(index) else { return total }
        return phases[index].start
    }

    var workPhaseCount: Int { phases.filter(\.isWork).count }
    var flowPhaseCount: Int { phases.filter(\.isFlow).count }

    /// Where round one starts. The header reads "Warm-up 2 / 4" before this and
    /// "Round 3 / 8" after it.
    var workBegins: TimeInterval { phases.first(where: \.isWork)?.start ?? 0 }
}
