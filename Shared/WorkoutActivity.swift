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
            case work, rest

            var label: String { self == .work ? "Work" : "Rest" }
        }

        var phase: Phase
        var round: Int
        var moveName: String
        /// When the current phase ends. The widget renders a live timer from
        /// this rather than from a number we push.
        var phaseEnds: Date
        /// When the phase began, so the widget can draw how far through it is
        /// without another update.
        var phaseBegan: Date
        var nextUp: String

        var duration: TimeInterval { phaseEnds.timeIntervalSince(phaseBegan) }

        /// How much of the phase is left, at the moment this is evaluated.
        var remainingFraction: Double {
            guard duration > 0 else { return 0 }
            let left = phaseEnds.timeIntervalSinceNow
            return min(1, max(0, left / duration))
        }
    }
}
