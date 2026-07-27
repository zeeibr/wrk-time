import Foundation

/// A movement the user can actually do with the kit they own.
struct Move: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var equipment: Equipment
    /// One line of form, in plain words. Shown under the name while working.
    var cue: String

    var symbol: String { equipment.symbol }
    var equipmentLabel: String { equipment.label }
}

/// A self-guided interval routine: fixed work and rest, a rotation of moves,
/// and a number of rounds. This is also the shape the planner emits, so a
/// generated session and a hand-built one run through the same engine.
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

    /// The ceiling the user asked for. Enforced at the model layer rather than
    /// in the UI, so nothing downstream can exceed it.
    static let workCeiling: TimeInterval = 60

    var clampedWork: TimeInterval { min(work, Self.workCeiling) }

    var totalDuration: TimeInterval {
        schedule.total
    }

    var schedule: RoutineSchedule { RoutineSchedule(routine: self) }
}

// MARK: - Schedule

/// One stretch of the routine — a work interval or the rest after it.
struct Phase: Equatable {
    enum Kind: Equatable { case work, rest }

    let kind: Kind
    /// 1-based, for display.
    let round: Int
    let move: Move?
    let duration: TimeInterval
    /// Seconds from routine start at which this phase begins and ends.
    let start: TimeInterval
    let end: TimeInterval

    var isWork: Bool { kind == .work }
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

        for round in 1...max(routine.rounds, 1) {
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
}
