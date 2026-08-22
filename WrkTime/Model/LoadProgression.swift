import Foundation
import SwiftData

/// When a load has stopped being work, by her own counts.
///
/// Classic double progression, run locally because it is arithmetic: hold the
/// load and build reps; when the reps have outgrown the load across
/// consecutive sessions, the next weight up is offered. The model is not asked
/// — the planner is told the conclusion, and the tap that changes the load is
/// hers (`MoveOverride`), the same as it always was.
///
/// "When appropriate" is deliberately conservative, because the cost of a
/// wrong "go heavier" lands on a beginner's joints:
/// - Only sessions at the **current** load count. Sets on the 5 lb ring say
///   nothing about whether the 8 is ready to become a 10.
/// - Every counted set in a session must clear the ceiling — one strong set in
///   a fading session is a strong set, not a verdict.
/// - It takes `sessionsNeeded` such sessions in a row, so one good day cannot
///   move the weight.
enum LoadProgression {
    /// The threshold is a **pace**, not a count, because she lifts to time and
    /// records reps after: twelve reps in a forty-second interval and twelve
    /// in sixty are different facts, and a fixed number would read the long
    /// intervals as strong and the short ones as weak. Eighteen a minute is
    /// twelve in forty seconds — the pace at which the load has stopped
    /// enforcing the tempo the cues ask for, which is this app's own
    /// definition of "too light": the fix is weight, not speed.
    static let repsPerMinuteCeiling: Double = 18
    static let sessionsNeeded = 2

    /// A set's pace, reps per minute of work.
    static func pace(reps: Int, seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(reps) * 60 / seconds
    }

    struct Suggestion: Equatable {
        var move: Move
        var currentPounds: Double
        var nextPounds: Double

        /// "Ring halo has outgrown the 5 lb ring — the 8 is ready when you are."
        var line: String {
            "\(move.name) has outgrown \(label(currentPounds)) — \(label(nextPounds)) is ready when you are."
        }

        private func label(_ pounds: Double) -> String {
            "the \(Int(pounds)) lb \(move.equipment == .rings ? "ring" : "pair")"
        }
    }

    /// The next load up on this move's own equipment, if it has one.
    static func nextLoad(for move: Move) -> Double? {
        guard let current = move.loadPounds else { return nil }
        return move.equipment.availableLoadsPounds.sorted().first { $0 > current }
    }

    /// The pure rule, over history rows for this move. `history` is oldest
    /// first, exactly as `SetLogs.history` returns it.
    static func ready(move: Move, history: [SetLog]) -> Bool {
        guard nextLoad(for: move) != nil else { return false }
        // Only what she counted at the weight she is on now.
        let atCurrent = history.filter { $0.loadPounds == move.loadPounds && !$0.reps.isEmpty }
        guard atCurrent.count >= sessionsNeeded else { return false }
        return atCurrent.suffix(sessionsNeeded).allSatisfy(clearsCeiling)
    }

    /// Every counted set in the session at or above the pace ceiling. A row
    /// without its interval lengths — written before they were kept — cannot
    /// qualify: the pace cannot be known, and a guessed forty seconds could
    /// send a beginner up a weight on arithmetic that never happened.
    private static func clearsCeiling(_ log: SetLog) -> Bool {
        guard let seconds = log.setSeconds, seconds.count == log.reps.count else { return false }
        return zip(log.reps, seconds).allSatisfy {
            pace(reps: $0, seconds: $1) >= repsPerMinuteCeiling
        }
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
