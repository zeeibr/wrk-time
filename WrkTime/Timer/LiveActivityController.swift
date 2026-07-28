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
        // ActivityKit is not Sendable-audited: `Activity` is a non-Sendable
        // class whose `update` and `end` are nonisolated and async, so awaiting
        // them from this main-actor controller reads as sending the object off
        // the actor. Nothing else ever holds it — every touch goes through this
        // class, on the main actor — so the hop is safe in fact if not in type.
        nonisolated(unsafe) let live = activity
        let content = ActivityContent(
            state: state,
            staleDate: state.phaseEnds.addingTimeInterval(60)
        )
        Task { await live.update(content) }
    }

    /// Ends immediately rather than lingering — a finished workout on the lock
    /// screen an hour later is clutter, not information.
    ///
    /// Ends **every** activity of this type, not just the one this controller
    /// happens to hold. An activity outlives the process that started it, so a
    /// force-quit, a crash, or a session whose view was torn down before it
    /// could tidy up all leave one stranded on the lock screen — and a
    /// controller created fresh for the next session has no reference to it and
    /// cannot clear it. Sweeping the type is the only thing that actually ends
    /// what the reader is looking at.
    func end() {
        activity = nil
        Self.endAll()
    }

    /// Clears anything left over from a previous run. Called at launch as well
    /// as at the end of a session, because the one that outlived its process is
    /// exactly the one nothing else will ever end.
    static func endAll() {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            // ActivityKit is not Sendable-audited: `Activity` is a non-Sendable
            // class whose `end` is nonisolated and async. Nothing else holds
            // these — they are being discarded — so the hop is safe in fact if
            // not in type.
            nonisolated(unsafe) let live = activity
            Task { await live.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func state(from engine: IntervalEngine) -> WorkoutActivityAttributes.ContentState? {
        guard let phase = engine.currentPhase else { return nil }

        // Derive the phase's wall-clock bounds from how far into it we are, so
        // the widget's countdown and the app's agree exactly.
        let intoPhase = engine.elapsed - phase.start
        let began = Date.now.addingTimeInterval(-intoPhase)
        let ends = began.addingTimeInterval(phase.duration)

        let kind: WorkoutActivityAttributes.ContentState.Phase = switch phase.kind {
        case .flow: .flow
        case .work: .work
        case .rest: .rest
        }

        return .init(
            phase: kind,
            round: phase.round,
            position: phase.position(rounds: engine.routine.rounds,
                                     flowCount: engine.schedule.flowPhaseCount),
            moveName: phase.move?.name ?? kind.label,
            phaseEnds: ends,
            phaseBegan: began,
            nextUp: nextDescription(engine.nextPhase),
            isPaused: engine.status == .paused,
            // Carried explicitly: once the clock is held, the phase's dates
            // keep advancing past it and can no longer say what is left.
            pausedRemaining: engine.status == .paused ? engine.remainingInPhase : nil
        )
    }

    private func nextDescription(_ phase: Phase?) -> String {
        guard let phase else { return "Finish" }
        if let move = phase.move {
            return "\(move.name), \(phase.duration.clockString)"
        }
        // A move-less work interval is a plain interval, not a rest.
        return "\(phase.isRest ? "Rest" : "Work") \(phase.duration.clockString)"
    }
}
