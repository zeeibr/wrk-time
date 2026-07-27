import ActivityKit
import Foundation

/// Keeps a Live Activity in step with the engine.
///
/// One update per phase change, not one per second. The widget is handed the
/// phase's start and end dates and renders a live countdown from them, so the
/// clock keeps ticking on the lock screen while the app is suspended and we
/// never spend a background wake on something the system can do itself.
@MainActor
final class LiveActivityController {
    private var activity: Activity<WorkoutActivityAttributes>?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(routine: IntervalRoutine, engine: IntervalEngine) {
        guard isSupported, activity == nil, let state = state(from: engine) else { return }

        let attributes = WorkoutActivityAttributes(
            routineName: routine.name,
            totalRounds: routine.rounds
        )

        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: state.phaseEnds.addingTimeInterval(60)),
            pushType: nil
        )
    }

    func update(engine: IntervalEngine) {
        guard let activity, let state = state(from: engine) else { return }
        Task {
            await activity.update(
                .init(state: state, staleDate: state.phaseEnds.addingTimeInterval(60))
            )
        }
    }

    /// Ends immediately rather than lingering — a finished workout on the lock
    /// screen an hour later is clutter, not information.
    func end() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func state(from engine: IntervalEngine) -> WorkoutActivityAttributes.ContentState? {
        guard let phase = engine.currentPhase else { return nil }

        // Derive the phase's wall-clock bounds from how far into it we are, so
        // the widget's countdown and the app's agree exactly.
        let intoPhase = engine.elapsed - phase.start
        let began = Date.now.addingTimeInterval(-intoPhase)
        let ends = began.addingTimeInterval(phase.duration)

        return .init(
            phase: phase.isWork ? .work : .rest,
            round: phase.round,
            moveName: phase.move?.name ?? (phase.isWork ? "Work" : "Rest"),
            phaseEnds: ends,
            phaseBegan: began,
            nextUp: nextDescription(engine.nextPhase)
        )
    }

    private func nextDescription(_ phase: Phase?) -> String {
        guard let phase else { return "Finish" }
        if phase.isWork, let move = phase.move {
            return "\(move.name), \(phase.duration.clockString)"
        }
        return "Rest \(phase.duration.clockString)"
    }
}
