import Foundation

/// A second workout for a day whose plan is already finished.
///
/// Her ask: *"i want to be able to do multiple sessions in a day with the option
/// to have a second set of workouts to do."* Today used to dead-end — the
/// finished branch of section 02 had no button at all, so on a day the plan
/// scheduled something, doing it was the end of the day whether or not she
/// wanted more.
///
/// Composed here rather than asked of Claude, for the same reason the warm-up
/// and the morning practice are: this is arithmetic over a closed library, it
/// costs nothing, and it works with no network. Asking the model for a second
/// workout would spend a request on a question the app can answer.
///
/// Three things it is deliberately **not**:
///
/// **Not a `PlannedSession`.** It is not part of the plan, so it earns no mark —
/// which was her call when asked. Writing one would also collide with
/// `PlanValidator.duplicateDay` and with `PlannerService.write`'s set of days
/// already trained. It returns a routine and nothing else; finishing it records
/// a `RoutineRun`.
///
/// **Not a repeat.** It excludes the moves from what she has already done today,
/// so the extra is different work rather than the same session twice.
///
/// **Not as long.** It is extra. Roughly half the rounds of a planned session,
/// because the honest offer is "there is more here if you want it", not "here is
/// another full workout".
@MainActor
enum ExtraSession {

    /// Rounds relative to a planned session's, floored so the offer is never
    /// trivial.
    static let roundFraction = 0.5
    static let minimumRounds = 4

    /// How many moves the rotation carries. Fewer than a planned session's,
    /// deliberately: a shorter workout cycling five moves would reach each of
    /// them once, which is a warm-up with extra steps rather than a set.
    static let moves = 3

    static func build(week: Int,
                      pace: Pace,
                      avoiding ruledOut: Set<String>,
                      notRepeating done: [String] = [],
                      on date: Date = .now) -> IntervalRoutine {
        // The current week's shape, so the extra feels like the plan rather than
        // a different app. Taken from the same arithmetic `OfflinePlanner` uses
        // so the two cannot drift.
        let shape = OfflinePlanner.shape(week: week, pace: pace)
        let rounds = max(minimumRounds, Int((Double(shape.rounds) * roundFraction).rounded()))

        var rotation = MoveLibrary.rotation(
            of: moves,
            avoiding: ruledOut,
            excluding: Set(done.map { MovePreference.key($0) }))

        // If everything is either ruled out or already done today, repeating is
        // better than handing back an empty rotation — that would be a plain
        // interval timer presented as a session. Refusals still hold; only the
        // done-today exclusion is relaxed.
        if rotation.isEmpty {
            rotation = MoveLibrary.rotation(of: moves, avoiding: ruledOut)
        }

        return IntervalRoutine(name: title(for: rotation),
                               work: shape.work,
                               rest: shape.rest,
                               rounds: rounds,
                               moves: rotation)
            // Opens with flow, like every other session in the app, drawn from
            // what the morning practice did not use today so nothing repeats
            // within a day.
            .warmingUp(with: WarmUp.afterPractice(on: date, avoiding: ruledOut))
    }

    /// "Extra · beam" — named after the kit so she can see what it needs before
    /// starting, and marked as extra so it is never mistaken for the plan.
    static func title(for rotation: [Move]) -> String {
        guard let kit = rotation.first?.equipment else { return "Extra · timer" }
        let single = rotation.allSatisfy { $0.equipment == kit }
        return single ? "Extra · \(kit.shortLabel)" : "Extra · mixed"
    }
}
