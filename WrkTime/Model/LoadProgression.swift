import Foundation
import SwiftData

/// When a load has stopped being work, by her own counts.
///
/// Double progression, `docs/COACH-BRIEF.md` §10, run locally because it is
/// arithmetic: hold the load and build the reps across the range; when every
/// set of a move reaches the top of the range in two consecutive sessions,
/// the next load up is **offered**. The model is not asked — the planner is
/// told the conclusion — and the tap that changes the load is hers
/// (`MoveOverride`), the same as it always was.
///
/// This replaced a pace rule (eighteen reps a minute) on 22 August 2026.
/// Pace measured how fast she moved, and with a 2 lb dumbbell fast is easy:
/// it promoted loads that were already too light and said nothing about how
/// near failure a set was. It also could not fire on rep sets, where she is
/// supposed to be slow.
///
/// "When appropriate" is deliberately conservative, because the cost of a
/// wrong "go heavier" lands on a beginner's joints:
/// - Only **rep-mode** sessions count. An interval is conditioning; a count
///   made against a clock is not a count made two reps short of failure.
/// - Only sessions at the **current** load count. Sets on the 5 lb ring say
///   nothing about whether the 8 is ready to become a 10.
/// - Every counted set in the session must reach the top of the range — one
///   strong set in a fading session is a strong set, not a verdict.
/// - A row counted loosely — without the seconds each set ran — cannot
///   qualify. The number was not made carefully enough to move a weight on.
/// - It takes `sessionsNeeded` such sessions in a row.
enum LoadProgression {
    /// The top of the working range. Eight to twelve, stopping two short of
    /// failure; twelve on every set, twice, means the load has stopped
    /// enforcing the range.
    static let repTarget = 12
    static let sessionsNeeded = 2
    /// A jump larger than this is bridged before it is taken: "same load,
    /// harder" is offered first, the next load second.
    static let bigJumpFraction = 0.3

    struct Suggestion: Equatable {
        var move: Move
        var currentPounds: Double
        var nextPounds: Double

        /// Whether the step is large enough that the coach bridges it.
        var isBigJump: Bool {
            (nextPounds - currentPounds) / currentPounds > LoadProgression.bigJumpFraction
        }

        /// "Kettlebell deadlift has outgrown the 18 lb kettlebell — the 35 lb
        /// kettlebell is ready when you are."
        var line: String {
            "\(move.name) has outgrown the \(move.equipment.label(forLoad: currentPounds).lowercasedFirst) — the \(move.equipment.label(forLoad: nextPounds).lowercasedFirst) is ready when you are."
        }

        /// The bridge for a large jump, brief §10: one intensifier per move
        /// per block, the next load second. Nil when the step is small enough
        /// to take directly.
        var bridge: String? {
            guard isBigJump else { return nil }
            let jump = Int(((nextPounds - currentPounds) / currentPounds * 100).rounded())
            return "That is a \(jump) percent jump, so harder-at-this-load comes first: a pause at the hard point, a four-second lower, or one-and-a-half reps — pick one and keep it for the block. Take the new load when twelve comes easily again, and if you cannot reach eight on it, two sets of five with a pause is the bridge, not a retreat."
        }
    }

    /// The next load up on this move's own equipment, if it has one.
    static func nextLoad(for move: Move) -> Double? {
        guard let current = move.loadPounds else { return nil }
        return Equipment.loads(for: move).sorted().first { $0 > current }
    }

    /// The pure rule, over history rows for this move. `history` is oldest
    /// first, exactly as `SetLogs.history` returns it.
    static func ready(move: Move, history: [SetLog]) -> Bool {
        guard nextLoad(for: move) != nil else { return false }
        // Only what she counted, in rep mode, at the weight she is on now.
        let qualifying = history.filter {
            $0.loadPounds == move.loadPounds && !$0.reps.isEmpty && $0.mode == .reps
        }
        guard qualifying.count >= sessionsNeeded else { return false }
        return qualifying.suffix(sessionsNeeded).allSatisfy(reachesTarget)
    }

    /// Every counted set at or above the target, and every set counted with
    /// its length — a row without its seconds was counted loosely.
    private static func reachesTarget(_ log: SetLog) -> Bool {
        guard let seconds = log.setSeconds, seconds.count == log.reps.count else { return false }
        return log.reps.allSatisfy { $0 >= repTarget }
    }

    @MainActor
    static func suggestion(for move: Move, in context: ModelContext) -> Suggestion? {
        guard let current = move.loadPounds,
              let next = nextLoad(for: move),
              ready(move: move, history: SetLogs.history(for: move, in: context))
        else { return nil }
        return Suggestion(move: move, currentPounds: current, nextPounds: next)
    }

    /// Every move in the working library that is ready, for the planner's
    /// context. The library is passed in with her load overrides already
    /// applied, so "current" means what she actually lifts.
    @MainActor
    static func all(in library: [Move], context: ModelContext) -> [Suggestion] {
        library.filter { $0.kind == .strength }
            .compactMap { suggestion(for: $0, in: context) }
    }
}

private extension String {
    var lowercasedFirst: String {
        guard let first = first else { return self }
        return first.lowercased() + dropFirst()
    }
}
