import ActivityKit
import Foundation

/// The contract between the app and the Live Activity.
///
/// Deliberately small. The widget is given a phase end *date* rather than a
/// countdown value, so the system can tick the clock itself — the app does not
/// have to push an update every second, which is both impossible in the
/// background and unnecessary.
struct WorkoutActivityAttributes: ActivityAttributes {
    /// Fixed for the life of the session.
    let routineName: String
    let totalRounds: Int

    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case flow, work, rest

            var label: String {
                switch self {
                case .flow: "Warm-up"
                case .work: "Work"
                case .rest: "Rest"
                }
            }
        }

        var phase: Phase
        var round: Int
        /// "Round 3 / 8" or "Warm-up 2 / 4", formatted app-side.
        ///
        /// Pushed rather than rebuilt here so the widget cannot drift from the
        /// screen: during the opening practice the round number is a position
        /// in the flow, and a lock screen counting it against the session's
        /// rounds would be quietly wrong for the first three minutes.
        var position: String = ""
        var moveName: String
        /// When the current phase ends. The widget renders a live timer from
        /// this rather than from a number we push.
        var phaseEnds: Date
        /// When the phase began, so the widget can draw how far through it is
        /// without another update.
        var phaseBegan: Date
        var nextUp: String
        /// Set while the session is paused. Without it the lock screen keeps
        /// counting down to zero on a workout that has stopped.
        var isPaused: Bool = false
        /// What was left when the pause began, since the dates can no longer
        /// tell the truth once the clock is held.
        var pausedRemaining: TimeInterval?

        var duration: TimeInterval { phaseEnds.timeIntervalSince(phaseBegan) }
    }
}
