import Foundation

/// A finished session written out as plain lines, for pasting into Whoop.
///
/// Whoop's developer API is read-only — recovery, sleep and strain come *out*
/// of it, and nothing can be written in — so Muscular Load has to be told what
/// she lifted by her, in their app. This turns the session the app already
/// holds into something she can paste in one go instead of re-entering six
/// moves from memory.
///
/// Built from the **schedule**, not from `rounds`, so a sided move reports the
/// turns she actually did rather than the expansion: three turns on a split
/// squat is "3 × 40s each side", not six intervals.
enum WhoopSummary {

    static func text(for routine: IntervalRoutine,
                     finishedAt: Date = .now,
                     seconds: TimeInterval? = nil,
                     reps: [Int] = [],
                     durations: [Int: TimeInterval] = [:]) -> String {
        let length = seconds ?? routine.schedule.total
        var lines = [
            "\(routine.name) · \(finishedAt.formatted(.dateTime.day().month(.abbreviated))) · \(Int((length / 60).rounded())) min"
        ]

        for entry in entries(for: routine, reps: reps, durations: durations) {
            lines.append("\(entry.name) — \(entry.equipment), \(entry.measure)")
        }

        if !routine.warmUp.isEmpty {
            let count = routine.warmUp.count
            lines.append("Warm-up: \(count) mobility \(count == 1 ? "movement" : "movements"), \(Int(routine.warmUpSeconds))s each")
        }
        return lines.joined(separator: "\n")
    }

    struct Entry: Equatable {
        var name: String
        var equipment: String
        var measure: String
    }

    /// One entry per move in the rotation, in the order it is first worked.
    ///
    /// `reps` is counted per set in the order the sets were worked — the same
    /// order `RoutineSchedule.setOrdinal` files them under. A zero is a set
    /// she did not count, and is left out rather than reported as none.
    static func entries(for routine: IntervalRoutine, reps: [Int] = [],
                        durations: [Int: TimeInterval] = [:]) -> [Entry] {
        grouped(for: routine, reps: reps, durations: durations).map { held in
            Entry(name: held.move.name,
                  equipment: held.move.equipmentLabel,
                  measure: measure(for: held.move,
                                   durations: held.sets.map(\.seconds),
                                   reps: held.sets.compactMap(\.reps),
                                   asSets: routine.mode == .reps))
        }
    }

    /// The moves she actually counted, with their counts and how long each
    /// counted set ran — what the rep history is written from. The seconds
    /// travel with the reps because she lifts to time: nine reps means one
    /// thing in a forty-second interval and another in sixty, and the
    /// progression rule reads the pace, not the raw count.
    static func counted(for routine: IntervalRoutine, reps: [Int],
                        durations: [Int: TimeInterval] = [:])
    -> [(move: Move, reps: [Int], seconds: [TimeInterval])] {
        grouped(for: routine, reps: reps, durations: durations).compactMap { held in
            let done = held.sets.compactMap { set -> (Int, TimeInterval)? in
                guard let reps = set.reps else { return nil }
                return (reps, set.seconds)
            }
            guard !done.isEmpty else { return nil }
            return (held.move, done.map(\.0), done.map(\.1))
        }
    }

    /// The rotation gathered per move, in the order each is first worked, one
    /// entry per work interval with its length and any count against it. One
    /// walk of the schedule, because the summary and the history must agree
    /// about which set belonged to which move.
    /// `durations` overrides a set's scheduled length with the seconds it
    /// actually ran — a rep set is open-ended and its schedule is only a net.
    private static func grouped(for routine: IntervalRoutine, reps: [Int],
                                durations: [Int: TimeInterval] = [:])
    -> [(move: Move, sets: [(seconds: TimeInterval, reps: Int?)])] {
        let work = routine.schedule.phases.filter(\.isWork)
        var order: [String] = []
        var byName: [String: (move: Move, sets: [(seconds: TimeInterval, reps: Int?)])] = [:]

        for (set, phase) in work.enumerated() {
            guard let move = phase.move else { continue }
            if byName[move.name] == nil {
                order.append(move.name)
                byName[move.name] = (move, [])
            }
            let counted = set < reps.count && reps[set] > 0 ? reps[set] : nil
            byName[move.name]?.sets.append((durations[set] ?? phase.duration, counted))
        }
        return order.compactMap { byName[$0] }
    }

    /// Reps where she counted them, time where she did not.
    ///
    /// Whoop asks for sets and reps — that is what Muscular Load is computed
    /// from — so a counted move reports "3 sets × 12 reps" and only falls back
    /// to "3 × 40s" for a move that was worked to the clock alone. Sets whose
    /// counts differ are listed rather than averaged: 12, 10 and 8 is the shape
    /// of the set going, and flattening it to "10" describes a session she did
    /// not do.
    private static func measure(for move: Move,
                                durations: [TimeInterval],
                                reps: [Int],
                                asSets: Bool = false) -> String {
        var count = durations.count
        var suffix = ""
        if let sided = move.sided {
            // The schedule holds one interval per side; she did half as many
            // turns, on both sides.
            count = max(count / 2, 1)
            suffix = sided == .directions ? " each way" : " each side"
        }

        // A rep set she did not count is a set, not an interval: its length
        // was whatever she took, and reporting it by the clock would describe
        // a session she did not do.
        if asSets, reps.isEmpty {
            return "\(count) \(count == 1 ? "set" : "sets"), reps not counted\(suffix)"
        }

        if !reps.isEmpty {
            let sets = move.sided != nil ? max(reps.count / 2, 1) : reps.count
            let counted = Set(reps)
            if counted.count == 1, let each = counted.first {
                return "\(sets) \(sets == 1 ? "set" : "sets") × \(each) reps\(suffix)"
            }
            let listed = reps.map(String.init).joined(separator: ", ")
            return "\(listed) reps\(suffix)"
        }

        let lengths = Set(durations.map { Int($0.rounded()) })
        guard lengths.count == 1, let seconds = lengths.first else {
            let total = durations.reduce(0, +)
            return "\(count) intervals, \(total.durationString) in all\(suffix)"
        }
        return "\(count) × \(seconds)s\(suffix)"
    }
}
