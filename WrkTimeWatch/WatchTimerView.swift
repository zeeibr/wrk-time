import SwiftUI
import SwiftData

/// The field register at watch size.
///
/// Phase 0 stub carrying the final interface so the rest of the watch app
/// can build against it; Phase 1 replaces the body. The recording rules it
/// must keep are the phone's: `engine.onEnded` is the one place an ending
/// is detected, `report()` writes the `RoutineRun` and `SetLog` rows for a
/// subject with a `recordedSource`, and the presenter is told the outcome —
/// a planned session's mark and the practice's row are the presenter's,
/// because only it has the rows.
struct WatchTimerView: View {
    /// What a finished session tells whoever presented it. The same shape as
    /// the phone's `WorkoutTimerView.Outcome`, deliberately.
    enum Outcome {
        case completed(start: Date, end: Date, skipped: [String], reps: [Int])
        case abandoned(skipped: [String])
    }

    private let routine: IntervalRoutine
    private let subject: ActiveSession.Subject
    private let resuming: ActiveSession?
    private let onEnd: (Outcome) -> Void

    init(routine: IntervalRoutine,
         subject: ActiveSession.Subject = .unknown,
         resuming: ActiveSession? = nil,
         onEnd: @escaping (Outcome) -> Void = { _ in }) {
        self.routine = routine
        self.subject = resuming?.subject ?? subject
        self.resuming = resuming
        self.onEnd = onEnd
    }

    var body: some View {
        Text(routine.name)
            .font(.almanacBody)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.oat.ignoresSafeArea())
    }
}
