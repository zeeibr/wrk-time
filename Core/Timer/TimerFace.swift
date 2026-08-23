import Foundation

/// What the timer says, on either wrist or floor.
///
/// The three questions every timer screen asks of the engine — where are we,
/// what is the number, and what does the prominent control do — answered in
/// one place with no view attached. The phone and the watch are the same
/// session read on two devices, and the one thing they must never do is
/// disagree about it: "Set 2 / 12" on the phone and "Round 2 / 12" on the
/// wrist would be two apps.
///
/// Foundation only, deliberately. It takes the engine's state as plain
/// pieces rather than the engine itself, so a test can put it at any point of
/// any schedule without a clock, and so a mirrored session — a phase and an
/// elapsed that arrived over the wire — reads exactly as a local one.
///
/// `WorkoutTimerView` still spells these out for itself; the formats here are
/// pinned to its by `WatchScheduleTests`. Folding the phone into this is a
/// separate change, and doing it in the same breath as writing the watch
/// would have meant changing the screen that works to serve the one that did
/// not exist yet.
struct TimerFace: Equatable, Sendable {
    let routine: IntervalRoutine
    let schedule: RoutineSchedule
    /// The phase the session is in, or nil once it is over.
    let phase: Phase?
    /// Seconds from the start of the routine.
    let elapsed: TimeInterval

    init(routine: IntervalRoutine,
         schedule: RoutineSchedule? = nil,
         phase: Phase?,
         elapsed: TimeInterval) {
        self.routine = routine
        self.schedule = schedule ?? routine.schedule
        self.phase = phase
        self.elapsed = elapsed
    }

    /// "Round 3 / 8", "Set 2 / 12", "Minute 4 / 10", "Warm-up 2 / 4".
    ///
    /// The word comes from the mode and the count from `roundCount`, never
    /// from `rounds` — a sequence and a sided rotation both hold more work
    /// intervals than the routine's `rounds` says.
    var positionLine: String {
        guard let phase else {
            // Over. It ended on the last one rather than on nothing.
            return "\(routine.roundWord) \(routine.roundCount) / \(routine.roundCount)"
        }
        return phase.position(rounds: routine.roundCount,
                              flowCount: schedule.flowPhaseCount,
                              word: routine.roundWord)
    }

    /// The number, in the routine's own clock.
    ///
    /// An open set counts **up**: the figure is how long she has been
    /// lifting, which is the tempo check. Everything else counts down.
    var countString: String {
        guard let phase else { return TimeInterval(0).clockString }
        if phase.openEnded { return max(0, elapsed - phase.start).clockString }
        return max(0, phase.end - elapsed).clockString
    }

    /// What the prominent transport control is.
    enum Control: Equatable, Sendable {
        /// A set she ends herself. Not a skip — the set she ended is a set
        /// she did, and the engine records its real length.
        case done
        /// Move through time.
        case skip
    }

    var control: Control { (phase?.openEnded ?? false) ? .done : .skip }

    /// True while the prominent control ends a set rather than skipping one.
    var isOpenSet: Bool { control == .done }

    /// What the phase is, in a word — the accessibility label for the count
    /// and the eyebrow over a flow movement.
    var phaseWord: String {
        switch phase?.kind {
        case .flow: routine.roundCount > 0 ? "Warm-up" : "Movement"
        case .rest: "Rest"
        case .work, nil: "Work"
        }
    }
}

extension TimerFace {
    /// The face of a live engine.
    @MainActor
    init(engine: IntervalEngine) {
        self.init(routine: engine.routine,
                  schedule: engine.schedule,
                  phase: engine.currentPhase,
                  elapsed: engine.elapsed)
    }
}
