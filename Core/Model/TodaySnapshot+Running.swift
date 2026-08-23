import Foundation

/// The running half of the complication's fact sheet.
///
/// `TodaySnapshot` itself lives in `Shared/`, which the two widget extensions
/// compile and which therefore cannot see `ActiveSession` — so the part that
/// reads a running session lives here, in `Core/`, where the watch app and the
/// phone both have it and where the tests can reach it.
extension TodaySnapshot {

    /// Fills the running fields from the in-flight session, or **clears** them
    /// when there is none.
    ///
    /// Clearing is the half that matters. A snapshot keeps whatever was last
    /// written into it, so a session that ended without this running would
    /// leave the complication counting down a phase that finished — the
    /// wrist's version of the app's oldest bug shape, a side effect on a path
    /// nobody exercised end to end. There is one writer, it runs on every
    /// refresh, and it writes nil as readily as it writes a date.
    mutating func setRunning(_ session: ActiveSession?, now: Date = .now) {
        runningTitle = nil
        runningPhase = nil
        runningPhaseEnds = nil
        runningEnds = nil

        guard let session else { return }
        let schedule = session.routine.schedule
        let elapsed = session.elapsedNow(now)
        guard let index = schedule.index(atElapsed: elapsed) else { return }

        runningTitle = session.routine.name
        runningPhase = Self.word(for: schedule.phases[index])
        // Dates, never a countdown: the system ticks a `Text(timerInterval:)`
        // and the complication is redrawn once a phase rather than once a
        // second. The same rule the Live Activity follows.
        runningEnds = now.addingTimeInterval(schedule.total - elapsed)
        // A paused session has no honest phase end, so it is given none — the
        // complication says which phase she is in and holds still, rather than
        // counting down a clock that is not moving.
        if session.running {
            runningPhaseEnds = now.addingTimeInterval(schedule.phases[index].end - elapsed)
        }
    }

    /// The word on the wrist for a phase. Three cases, matching `Phase.Kind`,
    /// because a complication has room for one word and "flow" is not one she
    /// would recognise on a watch face.
    private static func word(for phase: Phase) -> String {
        switch phase.kind {
        case .flow: "Warm-up"
        case .work: "Work"
        case .rest: "Rest"
        }
    }
}
