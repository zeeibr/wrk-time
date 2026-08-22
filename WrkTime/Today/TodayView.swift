import SwiftUI
import SwiftData
import UIKit

/// The document register.
///
/// Reading order is deliberate: what today is, what it asks of you, the control
/// that starts it, then the supporting figures.
struct TodayView: View {
    @Query(sort: \PlannedSession.scheduledFor) private var sessions: [PlannedSession]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query(sort: \LoggedSet.date, order: .reverse) private var loggedSets: [LoggedSet]
    /// Observed, not fetched — a run recorded by the timer must appear here the
    /// moment it lands, or the day's extra work reads as never recorded.
    @Query(sort: \RoutineRun.finishedAt, order: .reverse) private var routineRuns: [RoutineRun]
    @Query(sort: \Block.startDate, order: .reverse) private var blocks: [Block]

    @AppStorage(PlannerService.Memo.explanation) private var planExplanation = ""
    @AppStorage(PlannerService.Memo.failure) private var planFailure = ""

    /// What is on the timer, if anything.
    ///
    /// One value and one presentation. This was three separate `@State`
    /// optionals behind two `fullScreenCover` modifiers and a `sheet` on the
    /// same view — and the session's completion callback was not firing, so a
    /// finished session never got its `completedAt` and never became a mark.
    /// Stacking presentations on one view is a known way to lose exactly that.
    @State private var running: RunningWorkout?
    /// Whether today's finished session has been put on the clipboard.
    @State private var copiedForWhoop = false
    /// The finished session's move list, folded by default — it is history.
    @State private var showFinishedMoves = false
    /// Whether today's recovery guidance says to ease off. Read once per
    /// appearance; a test is never offered on a measured bad day.
    @State private var recoveryHolding = false
    /// Results she has applied from today's test, so a verdict becomes an
    /// acknowledgement rather than repeating its offer.
    @State private var appliedVerdicts: Set<String> = []

    enum RunningWorkout: Identifiable, Equatable {
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }

        /// A planned session, carrying the session so finishing it marks the
        /// right one — a rest day can offer a session from earlier in the week.
        case session(PlannedSession, IntervalRoutine)
        case practice(IntervalRoutine)
        /// A second workout for a day whose plan is already finished. Composed
        /// by `ExtraSession`, never written to the store as a planned session —
        /// it earns no mark.
        case extra(IntervalRoutine)
        /// One she built herself, started from Today rather than the Moves tab.
        case saved(SavedRoutine, IntervalRoutine)
        /// A past run done again, from the copy the run carries — its saved
        /// routine is gone or it was an extra composed on the spot. Recorded
        /// as her own workout, like anything run from a record of her own.
        case rerun(IntervalRoutine)
        /// One the process died under, picked up where it stopped.
        case resumed(ActiveSession)
        /// The baseline or the weekly check — an extra, scored afterwards.
        case test(IntervalRoutine)

        var id: String {
            switch self {
            case .session(let s, _): "session-\(s.id)"
            case .practice: "practice"
            case .extra: "extra"
            case .test: "test"
            case .saved(let r, _): "saved-\(r.id)"
            case .rerun(let r): "rerun-\(r.id)"
            case .resumed: "resumed"
            }
        }

        var isResumed: Bool { if case .resumed = self { return true }; return false }

        var routine: IntervalRoutine {
            switch self {
            case .session(_, let r): r
            case .practice(let r): r
            case .extra(let r): r
            case .saved(_, let r): r
            case .rerun(let r): r
            case .resumed(let a): a.routine
            case .test(let r): r
            }
        }

        /// What finishing this should record. A resumed run carries its own,
        /// saved when it started, rather than being guessed at the end.
        var subject: ActiveSession.Subject {
            switch self {
            case .session(let s, _): .session(s.id)
            case .practice: .practice
            case .extra: .extra
            case .saved, .rerun: .routine
            case .resumed(let a): a.subject
            case .test: .test
            }
        }
    }
    @Query private var practices: [MorningPractice]
    /// A session the process died under, offered back rather than lost.
    @State private var resumable: ActiveSession?
    @State private var resuming: ActiveSession?
    /// Moves skipped in the session that just ended, awaiting a reason.
    @State private var skippedToReview: [String] = []
    /// Skipped moves waiting for the timer to close before they are asked about.
    @State private var pendingSkips: [String] = []
    @State private var showingSettings = false
    /// The move whose plate is open. Tapping a row shows the shape; the
    /// long-press menu is still there for an opinion.
    @State private var inspecting: Move?
    @State private var loggingSet = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.modelContext) private var context
    @Environment(PlannerActivity.self) private var plannerActivity

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                masthead

                if let note = plannerActivity.note { planningNote(note) }

                if let resumable { resumeNote(resumable) }

                practiceSection

                if let session = todaysSession, let routine = session.routine {
                    IndexedSection(number: "02", label: "Session") {
                        SectionHead(title: session.title,
                                    note: routine.totalDuration.durationString)
                            .padding(.bottom, 10)

                        planNote

                        counters(for: routine)
                            .padding(.bottom, 12)

                        // The practice that opens the session, listed before
                        // the rotation because that is the order she does it
                        // in. It is additive: it never replaces a round.
                        if !routine.warmUp.isEmpty {
                            Text("Warm-up · \(Int(routine.warmUpSeconds))s each")
                                .almanacLabel(Palette.mute, small: true)
                                .padding(.bottom, 2)
                            ForEach(Array(routine.warmUp.enumerated()), id: \.element.id) { index, move in
                                BlockRow(
                                    index: index + 1,
                                    symbol: move.symbol,
                                    name: move.name,
                                    equipment: move.equipmentLabel,
                                    measure: "\(Int(routine.warmUpSeconds))s"
                                )
                                .onTapGesture { inspecting = move }
                            }
                            Rule()
                            Text("In rotation")
                                .almanacLabel(Palette.mute, small: true)
                                .padding(.top, 12)
                                .padding(.bottom, 2)
                        }

                        ForEach(Array(routine.moves.enumerated()), id: \.element.id) { index, move in
                            BlockRow(
                                index: index + 1,
                                symbol: move.symbol,
                                name: move.name,
                                equipment: move.equipmentLabel,
                                measure: rotationMeasure(for: move, in: routine)
                            )
                            // Tap the move to see it and to say what you think
                            // of it.
                            //
                            // This used to carry a context menu with the same
                            // four options alongside the tap. Two gestures on
                            // one row is one too many — the tap could swallow
                            // the menu's action, so "never program it" recorded
                            // nothing and the session went on asking for the
                            // move. One way in, and it reports what it did.
                            .onTapGesture { inspecting = move }
                        }
                        Rule()

                        PrimaryButton(title: "Begin session",
                                      subtitle: routine.shapeLine) {
                            running = .session(session, routine)
                        }
                        .padding(.top, 14)
                    }
                } else if let done = finishedToday {
                    finishedNote(done)
                } else {
                    restDayNote
                }

                IndexedSection(number: "03", label: "Kept") {
                    SectionHead(title: "Loose work", note: keptNote)
                        .padding(.bottom, keptToday.isEmpty && runsToday.isEmpty ? 10 : 4)

                    // Whole workouts she took beyond the plan today, listed with
                    // the loose sets because this section is already the day's
                    // off-plan record. Volume, never a mark — and a way back
                    // in: tapping a run reopens its routine to do again. Rows
                    // from before runs carried their routine stay plain.
                    ForEach(runsToday) { run in
                        let reopen = RoutineRuns.reopen(run, in: context)
                        let row = VStack(spacing: 0) {
                            Rule()
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(run.name)
                                    .font(.almanacBody)
                                    .foregroundStyle(Palette.ink)
                                Spacer(minLength: 8)
                                Text("\(run.seconds.durationString) · \(run.finishedAt.formatted(date: .omitted, time: .shortened))")
                                    .almanacLabel(Palette.mute, small: true)
                                    .tabular()
                                if reopen != nil {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Palette.mute)
                                }
                            }
                            .padding(.vertical, 9)
                        }

                        // A plain row when there is nothing to reopen — a
                        // disabled button dims its label, and an old ledger
                        // line is a fact, not a failure.
                        if let reopen {
                            Button {
                                running = reopen.saved.map { .saved($0, reopen.routine) }
                                    ?? .rerun(reopen.routine)
                            } label: {
                                row.contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Runs this routine again")
                        } else {
                            row.accessibilityElement(children: .combine)
                        }
                    }

                    ForEach(keptToday) { set in
                        VStack(spacing: 0) {
                            Rule()
                            HStack(alignment: .firstTextBaseline) {
                                Text(set.summary)
                                    .font(.almanacBody)
                                    .foregroundStyle(Palette.ink)
                                Spacer(minLength: 8)
                                Text(set.date.formatted(date: .omitted, time: .shortened))
                                    .almanacLabel(Palette.mute, small: true)
                                    .tabular()
                            }
                            .padding(.vertical, 9)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    Button { loggingSet = true } label: {
                        HStack {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Keep a set")
                                .font(.almanacBody)
                            Spacer()
                        }
                        .foregroundStyle(Palette.moss)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Records reps you did off the plan")
                    Rule()
                }

                IndexedSection(number: "04", label: "Season") {
                    SectionHead(title: "The season so far", note: seasonNote)
                        .padding(.bottom, 12)
                    // The mockup's composition: a thumbnail beside the figures,
                    // not a hero. As a full-width hero it ate the fold to say
                    // nothing, and on day one it was a large empty circle where
                    // three short lines would have told you where you stand.
                    HStack(alignment: .top, spacing: 16) {
                        GrowthForm(marksByWeek: marksByWeek, weeks: weekCount,
                                   currentWeek: currentWeek,
                                   minorsByWeek: minorsByWeek,
                                   sessionsPerWeek: marksPerWeek,
                                   blockSeed: blocks.first?.formSeed ?? 0,
                                   livedWeeksOnly: true,
                                   dayOfWeek: dayOfBlockWeek)
                            .frame(width: 84, height: 84)
                        VStack(alignment: .leading, spacing: 7) {
                            seasonLine("Marks earned", "\(completedCount) / \(marksInBlock)")
                            seasonLine("This week", "\(marksThisWeek) / \(marksPerWeek)")
                            seasonLine("Week", "\(currentWeek) of \(weekCount)")
                            // The weight rides here as a fourth line rather
                            // than holding a section of its own — a lone
                            // ledger row restating Signals' headline was a
                            // whole section spent saying one number twice.
                            seasonLine(weeklyRateString ?? "Weight · 7-day mean",
                                       latestWeightString == "—" ? "—" : "\(latestWeightString) lb")
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.oat.ignoresSafeArea())
        // One cover for everything the timer runs. What finished is decided by
        // the value that opened it, so a session marks itself and a practice
        // records a day — and neither depends on looking today up afterwards.
        .fullScreenCover(item: $running) { workout in
            WorkoutTimerView(routine: workout.routine,
                             subject: workout.subject,
                             resuming: workout.isResumed ? resuming : nil) { outcome in
                finish(workout, outcome)
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(item: $inspecting) { MoveSheet(move: $0) }
        .sheet(isPresented: $loggingSet) { LogSetView() }
        // Asked after the field register has closed, never inside it.
        .sheet(isPresented: Binding(get: { !skippedToReview.isEmpty },
                                    set: { if !$0 { skippedToReview = [] } })) {
            SkipReviewView(skipped: skippedToReview) { skippedToReview = [] }
        }
        .task {
            resumable = ActiveSessionStore.load()
            let health = HealthKitService()
            await HealthSync(health: health, context: context).importWeights()
            // A test is never offered on a day the numbers say to ease off.
            // `.hold` is the neutral state — the plan as written — and
            // missing data lands there too; only a measured bad day withholds.
            recoveryHolding = await health.recoverySnapshot().guidance == .ease
        }
        // Cleared once the cover closes, so a second run does not silently
        // resume the session that was just finished or abandoned.
        .onChange(of: running) { _, value in
            guard value == nil else { return }
            resuming = nil
            // Cleared too: the card is offered from a `@State` copy that
            // `report()` has no way to reach, so it went on offering a session
            // whose stored copy no longer existed. Tapping it started a
            // phantom workout.
            resumable = nil
            // Asked now the field has closed, never inside it.
            skippedToReview = pendingSkips
            pendingSkips = []
        }
    }

    // MARK: - Pieces

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 10) {
            Masthead(context: mastheadLabel) { showingSettings = true }
            Text(greeting)
                .font(.almanacTitle)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 4)
    }

    private func counters(for routine: IntervalRoutine) -> some View {
        HStack(spacing: 0) {
            // Whole minutes, and labelled honestly. This read "13:15" under the
            // word MINUTES, which is m:ss — and the full length is already on
            // the section head and the button, so it was the third time on one
            // screen besides.
            counter("\(Int((routine.totalDuration / 60).rounded()))", "Minutes")
            divider
            switch routine.mode {
            case .reps:
                counter("\(routine.setsPerMove)", "Sets per move")
                divider
                counter("8–12", "Reps, 2 in reserve")
            case .emom:
                counter("\(routine.rounds)", "Minutes")
                divider
                counter("\(Int(IntervalRoutine.emomWorkSeconds))/\(Int(IntervalRoutine.emomMinute - IntervalRoutine.emomWorkSeconds))", "Work / rest")
            case .intervals:
                counter("\(routine.roundCount)", "Rounds")
                divider
                counter("\(Int(routine.clampedWork))/\(Int(routine.rest))", "Work / rest")
            }
        }
        // Padding first, then the rules — so the rules sit outside the breathing
        // room rather than flush against the type. Applied the other way round
        // the figures were pinched between two hairlines.
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rule() }
        .overlay(alignment: .bottom) { Rule() }
    }

    private func counter(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(Face.ui(26))
                .tabular()
                .foregroundStyle(Palette.ink)
            Text(label).almanacLabel(small: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(Palette.rule).frame(width: 1 / displayScale, height: 40)
    }

    /// A session that was running when the app stopped.
    ///
    /// It sits above everything because it is the only thing on this screen
    /// with a clock still attached to it. The wording states what was lost and
    /// what is left, and offers a way out as well as a way back — being handed
    /// an unfinished workout with no way to put it down would be worse than
    /// losing it silently.
    private func resumeNote(_ session: ActiveSession) -> some View {
        IndexedSection(number: "00", label: "Open") {
            SectionHead(title: "Session left open", note: "Interrupted")
                .padding(.bottom, 10)

            Text("\(session.routine.name) — \(session.summary()). The clock kept running while the app was closed.")
                .font(.almanacBody)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            // Only offered when there is something left to run. A session the
            // clock outran is over: tapping "Pick it back up" would open the
            // timer, hit the run-out guard, clear the session and dismiss with
            // no mark and no explanation — a button that cannot do what it
            // says. It earns nothing either way, and saying so is kinder than
            // a control that quietly fails.
            if !session.ranOut(), !session.isStale() {
                PrimaryButton(title: "Pick it back up", subtitle: nil) {
                    resuming = session
                    running = .resumed(session)
                    resumable = nil
                }
                .padding(.top, 14)
            }

            Button("Let it go") {
                ActiveSessionStore.clear()
                resumable = nil
            }
            .font(.almanacButton)
            .foregroundStyle(Palette.mute)
            .padding(.vertical, 12)
            Rule()
        }
    }

    /// Says the app is working rather than broken.
    ///
    /// Writing a week can take the better part of a minute on a slow
    /// connection. Before this, both moments it happens — finishing setup, and
    /// the first launch of a new week — were completely silent.
    private func planningNote(_ note: String) -> some View {
        IndexedSection(number: "00", label: "Plan") {
            SectionHead(title: "Writing the week", note: "Working")
                .padding(.bottom, 10)
            Text(note)
                .font(.almanacBody)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// One sentence on what this week changed and why.
    ///
    /// HANDOFF §8.6 requires the plan to explain itself, and this is the only
    /// place it does. It sits above the numbers rather than below them because
    /// the reason a session looks the way it does should be read before the
    /// session is, not offered afterwards as a footnote.
    @ViewBuilder
    private var planNote: some View {
        if !planExplanation.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(planExplanation)
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.mute)
                    .fixedSize(horizontal: false, vertical: true)

                // Only shown when a key is set and the call still failed —
                // otherwise the offline planner is the plan, not a fallback.
                if !planFailure.isEmpty {
                    Text(planFailure)
                        .font(.almanacBodySmall)
                        .foregroundStyle(Palette.saffronInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 14)
        }
    }

    /// The morning practice, above everything the plan asks for.
    ///
    /// It sits first because it happens first and because it happens every day —
    /// a rest day still has one. Section 01 is the only section on this screen
    /// that is never absent.
    @ViewBuilder
    private var practiceSection: some View {
        let done = MorningPractices.done(in: context)
        let routine = Practice.routine(on: .now, avoiding: refusedFlow,
                                       library: MoveLibrary.flow + CustomMoves.flow(in: context))

        IndexedSection(number: "01", label: "Morning") {
            SectionHead(title: "The practice",
                        note: done ? "Done" : routine.totalDuration.durationString)
                .padding(.bottom, 10)

            Text(practiceNote(done: done))
                .font(.almanacBody)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, done ? 0 : 12)

            // Once it is done, the section folds to its sentence. The eight
            // movement rows are for this morning's doing, and this screen is
            // about the next thirteen minutes — a finished practice keeping
            // the fold all afternoon was the day's tallest piece of history.
            if !done {
                ForEach(Array(routine.warmUp.enumerated()), id: \.element.id) { index, move in
                    BlockRow(index: index + 1, symbol: move.symbol, name: move.name,
                             equipment: move.equipmentLabel,
                             measure: "\(Int(Practice.seconds))s")
                        .onTapGesture { inspecting = move }
                }
                Rule()

                PrimaryButton(title: "Begin the practice",
                              subtitle: "\(routine.warmUp.count) movements · \(routine.totalDuration.durationString)") {
                    running = .practice(routine)
                }
                .padding(.top, 14)
            }
        }
    }

    /// Says where the practice stands. Never scolds: a run of days is stated as
    /// a fact when there is one, and a day that was missed is simply not
    /// mentioned — the app does not keep a ledger of absences.
    private func practiceNote(done: Bool) -> String {
        let run = MorningPractices.run(in: context)
        if done {
            return run > 1
                ? "Done today. That is \(run) days in a row."
                : "Done today."
        }
        return run > 0
            ? "\(Practice.count) movements, \(Int(Tuning.practiceDuration / 60)) minutes, starting with the rebounding. \(run) days behind it."
            : "\(Practice.count) movements, \(Int(Tuning.practiceDuration / 60)) minutes, starting with the rebounding. This one happens every day."
    }

    /// Flow movements she has asked not to see, in the form the practice wants.
    private var refusedFlow: Set<String> {
        let lists = MovePreferences.lists(in: context)
        return Set((lists.avoided + lists.disliked).map { MovePreference.key($0) })
    }

    /// Today's session, once it is done.
    ///
    /// Without this the section simply disappeared when a session was finished
    /// and the rest-day copy took its place — so the reward for completing a
    /// session was the app saying "nothing scheduled". It states what happened
    /// and stops: the mark on the season is the reward and it is already earned.
    private func finishedNote(_ session: PlannedSession) -> some View {
        IndexedSection(number: "02", label: "Session") {
            SectionHead(title: session.title, note: "Done")
                .padding(.bottom, 10)
            Text(finishedLine(session))
                .font(.almanacBody)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)

            if let routine = session.routine {
                // The moves fold away once the session is history — what stays
                // in view is what she still does something with: the Whoop
                // copy and what else today offers. The list is one tap back
                // for checking a load or opening a move's history.
                Button {
                    showFinishedMoves.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text("The moves")
                            .almanacLabel(Palette.mute, small: true)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.mute)
                            .rotationEffect(.degrees(showFinishedMoves ? 0 : -90))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showFinishedMoves ? "Expanded" : "Collapsed")

                if showFinishedMoves {
                    ForEach(Array(routine.moves.enumerated()), id: \.element.id) { index, move in
                        BlockRow(index: index + 1, symbol: move.symbol, name: move.name,
                                 equipment: move.equipmentLabel,
                                 measure: routine.mode == .reps ? "\(routine.setsPerMove) sets" : "\(Int(routine.clampedWork))s")
                            .onTapGesture { inspecting = move }
                    }
                }
                Rule()

                // The same list the finish screen offers, still here after it
                // has been dismissed — logging into Whoop is a thing she does
                // when she gets to it, not in the minute she stops moving.
                if !routine.moves.isEmpty {
                    copyForWhoop(routine, finishedAt: session.completedAt ?? .now,
                                 reps: session.repCounts ?? [])
                }
            }

            moreToday
        }
    }

    /// Whoop's API only reads, so Muscular Load has to be told by her. This
    /// hands over the session as text she can paste into Whoop's assistant.
    private func copyForWhoop(_ routine: IntervalRoutine, finishedAt: Date,
                              reps: [Int]) -> some View {
        Button {
            UIPasteboard.general.string = WhoopSummary.text(for: routine,
                                                           finishedAt: finishedAt,
                                                           reps: reps)
            Haptics.transport()
            // Acknowledges, then goes back to being an offer. This row lives
            // on a screen she returns to all day; a "Copied" that never
            // reverts stops telling her anything and hides the action.
            copiedForWhoop = true
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                copiedForWhoop = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: copiedForWhoop ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                Text(copiedForWhoop ? "Copied — paste it into Whoop"
                                    : "Copy the moves for Whoop")
                    .font(.almanacBody)
                Spacer()
            }
            .foregroundStyle(Palette.moss)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Copies this session's moves and loads to the clipboard")
    }

    /// Says which session this was when it is not the one today was written
    /// for — a session pulled forward on a rest day is the plan working, and
    /// the line should read as that rather than as a day that got confused.
    private func finishedLine(_ session: PlannedSession) -> String {
        guard let at = session.completedAt else { return "Finished." }
        let time = at.formatted(date: .omitted, time: .shortened)
        let marks = "\(marksThisWeek.marksPhrase) on the season this week."

        guard !Calendar.current.isDateInToday(session.scheduledFor) else {
            return "Finished at \(time). \(marks)"
        }
        let day = session.scheduledFor.formatted(.dateTime.weekday(.wide))
        return session.scheduledFor > at
            ? "\(day)'s session, done early at \(time). \(marks)"
            : "\(day)'s session, picked up at \(time). \(marks)"
    }

    /// A session scheduled for today that has been finished.
    /// A session she finished **today**, whatever day it was written for.
    ///
    /// This used to ask which session was *scheduled* today and complete, so a
    /// rest day she filled by pulling tomorrow's session forward — which the
    /// rest-day copy offers her, in as many words — showed the rest-day text
    /// afterwards and nothing else. The work was done, the mark was earned,
    /// and Today said nothing about it: no record of it on the day, and no way
    /// to copy the moves for Whoop, which is the surface that made it visible.
    ///
    /// Today's own session wins when there is one, so a day with both reads as
    /// the day the plan describes.
    private var finishedToday: PlannedSession? {
        FinishedSessions.today(sessions)
    }

    // MARK: - More today

    /// What else is available once the day's plan is done.
    ///
    /// Her ask: *"i want to be able to do multiple sessions in a day with the
    /// option to have a second set of workouts to do."* The finished branch of
    /// section 02 had no button at all, so a day the plan scheduled something
    /// ended when she did it, whether or not she wanted more.
    ///
    /// Ordered most-earned first, and offered rather than urged — the same rule
    /// the rest-day offer already follows. Nothing here implies the day was
    /// insufficient:
    ///
    /// 1. A session the plan already wrote — one missed earlier this week, or
    ///    the next one early. That earns a mark, because it is the plan.
    /// 2. Otherwise an extra session composed from the kit, and her own saved
    ///    routines. Neither earns a mark; both are recorded as volume and both
    ///    reach the planner. That split was her call when asked.
    @ViewBuilder
    private var moreToday: some View {
        whereYouAre
        if let offer = offeredSession, let routine = offer.session.routine {
            Spacer(minLength: 16)
            SectionHead(title: "More today", note: "Still on the plan")
                .padding(.bottom, 8)
            Text(offer.note)
                .font(.almanacBody)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: offer.action,
                          subtitle: routine.shapeLine) {
                running = .session(offer.session, routine)
            }
            .padding(.top, 14)

            repeatOffer
                .padding(.top, 10)
        } else {
            Spacer(minLength: 16)
            SectionHead(title: "More today", note: "No mark")
                .padding(.bottom, 8)
            Text("The week's sessions are all done or already claimed. Anything below is extra — it is kept and the planner sees it, but a mark on the season stays one finished session from the plan.")
                .font(.almanacBodySmall)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            repeatOffer

            let extra = extraSession
            Button { running = .extra(extra) } label: {
                offerRow(title: extra.name,
                         detail: extra.shapeLine,
                         note: extra.moves.map(\.name).joined(separator: ", "))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Starts an extra session")

            ForEach(savedRoutines) { item in
                if let routine = item.routine {
                    Button { running = .saved(item, routine) } label: {
                        offerRow(title: routine.name,
                                 detail: "\(RoutineListView.shapeNote(routine)) · \(routine.totalDuration.durationString)",
                                 note: RoutineListView.rotationNote(routine))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Starts your own routine")
                }
            }
        }
    }

    /// The session she finished today, offered once more. Her ask: repeat the
    /// day's session — whichever it was, today's own or the next one done
    /// early, which is exactly what `finishedToday` already answers.
    ///
    /// Run as an extra, deliberately: the mark was earned by the first pass
    /// and `mark` froze that session's routine, so the repeat runs the
    /// routine as it was actually done — her loads, her warm-up — and lands
    /// as a `RoutineRun`, which is how the planner hears about the volume.
    @ViewBuilder
    private var repeatOffer: some View {
        if let done = finishedToday, let routine = done.routine {
            Button { running = .extra(routine) } label: {
                offerRow(title: "\(routine.name) · again",
                         detail: routine.shapeLine,
                         note: "The session you finished today, one more time. No mark — the first pass earned it.")
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Repeats the session you finished today")
        }
    }

    /// A real `Button`, not a tap gesture on a stack — the lesson the saved-
    /// routine list already carries: without the trait VoiceOver reads a row as
    /// static text and Switch Control will not scan it.
    private func offerRow(title: String, detail: String, note: String) -> some View {
        VStack(spacing: 0) {
            Rule()
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.almanacMoveName).foregroundStyle(Palette.ink)
                    Text(note).almanacLabel(Palette.mute, small: true)
                }
                Spacer(minLength: 8)
                Text(detail)
                    .almanacLabel(Palette.mute, small: true)
                    .tabular()
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(note), \(detail)")
    }

    // MARK: - Where you are

    /// The baseline and the weekly check, `docs/COACH-BRIEF.md` §11 and
    /// `Baseline`. Offered after the day's session or on a rest day, never
    /// on a day the recovery guidance holds, and never as a session: it is
    /// an extra, and she said so.
    ///
    /// After a test, its results sit here as sentences with a button where
    /// a verdict is a load change — through `MoveOverrides`, so it behaves
    /// like any load change and reaches the sessions already written.
    @ViewBuilder
    private var whereYouAre: some View {
        let todaysTest = routineRuns.first {
            $0.source == .test && Calendar.current.isDateInToday($0.finishedAt)
        }
        let offer = Baseline.offer(runs: routineRuns, sessionDoneOrRestDay: true,
                                   recoveryHolding: recoveryHolding)
        if todaysTest != nil || offer != nil {
            Spacer(minLength: 16)
            SectionHead(title: "Where you are", note: "Extra · no mark")
                .padding(.bottom, 8)

            if let run = todaysTest {
                let results = Baseline.results(for: run, in: context)
                if results.isEmpty {
                    Text("\(run.name) done. Nothing was counted, so there is nothing to read from it — next time, the number on the rest is the whole point.")
                        .font(.almanacBodySmall)
                        .foregroundStyle(Palette.mute)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(results) { result in
                        resultRow(result)
                    }
                }
            } else if let offer {
                switch offer {
                case .baseline:
                    Text("Six moves, one set each, to two reps short of failure, after the warm-up. It gives every pattern a working load. About twenty minutes; it counts as an extra, not a session.")
                        .font(.almanacBody)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    let routine = Baseline.routine(warmUp: testWarmUp)
                    PrimaryButton(title: "Take the baseline", subtitle: routine.shapeLine) {
                        running = .test(routine)
                    }
                    .padding(.top, 14)
                case .check(let turn):
                    let routine = Baseline.check(turn: turn, warmUp: testWarmUp)
                    Text("Two of the six, one set each, to two reps short of failure. Every pattern gets a fresh number every three weeks this way, and it never costs a session.")
                        .font(.almanacBody)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "This week's check",
                                  subtitle: routine.moves.map(\.name).joined(separator: " · ")) {
                        running = .test(routine)
                    }
                    .padding(.top, 14)
                }
            }
        }
    }

    private var testWarmUp: [Move] {
        let refused = MovePreferences.lists(in: context)
        let ruledOut = Set((refused.avoided + refused.disliked).map { MovePreference.key($0) })
        return WarmUp.afterPractice(on: .now, avoiding: ruledOut,
                                    library: MoveLibrary.flow + CustomMoves.flow(in: context))
    }

    private func resultRow(_ result: Baseline.Result) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(result.line)
                .font(.almanacBody)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
            if let move = result.station.move, result.verdict.isChange,
               case let to? = newLoad(result.verdict) {
                if appliedVerdicts.contains(result.id) {
                    Text("\(move.name) now asks for \(Int(to)) lb — everywhere, including sessions already written.")
                        .font(.almanacBodySmall)
                        .foregroundStyle(Palette.saffronInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 10)
                } else {
                    Button("Move \(move.name) to \(Int(to)) lb") {
                        MoveOverrides.set(to, for: move, in: context)
                        appliedVerdicts.insert(result.id)
                        Haptics.transport()
                    }
                    .font(.almanacBody)
                    .foregroundStyle(Palette.moss)
                    .padding(.bottom, 10)
                }
            }
            Rule()
        }
    }

    private func newLoad(_ verdict: Baseline.Verdict) -> Double? {
        switch verdict {
        case .hold: nil
        case .down(let to): to
        case .up(let to): to
        }
    }

    /// Composed once per day rather than per redraw, so the offer does not
    /// change its moves under her while she reads it.
    private var extraSession: IntervalRoutine {
        let refused = MovePreferences.lists(in: context)
        let ruledOut = Set((refused.avoided + refused.disliked).map { MovePreference.key($0) })
        let doneToday = sessions
            .filter { Calendar.current.isDateInToday($0.scheduledFor) && $0.isComplete }
            .flatMap { $0.routine?.moves.map(\.name) ?? [] }
        let block = blocks.first
        return ExtraSession.build(week: block?.currentWeek ?? 1,
                                  pace: block?.pace ?? .building,
                                  avoiding: ruledOut,
                                  notRepeating: doneToday,
                                  including: CustomMoves.strength(in: context),
                                  flowExtras: CustomMoves.flow(in: context),
                                  loads: MoveOverrides.table(in: context))
    }

    private var savedRoutines: [SavedRoutine] {
        (try? context.fetch(FetchDescriptor<SavedRoutine>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    /// A rest day, and what is still available on it.
    ///
    /// The plan's intent comes first and is never softened — a rest day is part
    /// of the programming, not a gap. But it is not a locked door: a session
    /// that went undone earlier in the week is still there to be picked up, and
    /// if nothing was missed the next one can be pulled forward. Both are
    /// offered, neither is urged.
    @ViewBuilder
    private var restDayNote: some View {
        IndexedSection(number: "02", label: "Session") {
            SectionHead(title: "Nothing scheduled", note: "Rest")
                .padding(.bottom, 10)
            Text("A rest day is part of the plan, not a gap in it. If you want to move anyway, a walk on the pad is free.")
                .font(.almanacBody)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)

            if let offer = offeredSession, let routine = offer.session.routine {
                Rule().padding(.top, 14)
                Text(offer.note)
                    .font(.almanacBody)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                ForEach(Array(routine.moves.enumerated()), id: \.element.id) { index, move in
                    BlockRow(index: index + 1, symbol: move.symbol, name: move.name,
                             equipment: move.equipmentLabel,
                             measure: "\(Int(routine.clampedWork))s")
                        .onTapGesture { inspecting = move }
                }
                Rule()

                PrimaryButton(title: offer.action,
                              subtitle: routine.shapeLine) {
                    running = .session(offer.session, routine)
                }
                .padding(.top, 14)
            } else {
                // Nothing of the plan left to offer, so the same extras a
                // finished day gets. A rest day is still not a locked door.
                moreToday
            }
        }
    }

    /// Records what just finished.
    ///
    /// Written here, synchronously, rather than inside a `Task` that races the
    /// sheet's dismissal: the mark is the whole point of finishing and it must
    /// land before anything else can go wrong. Health is a nicety and can be
    /// awaited afterwards.
    private func finish(_ workout: RunningWorkout, _ outcome: WorkoutTimerView.Outcome) {
        guard case .completed(let start, let end, let skipped, _) = outcome else {
            // Walked away from: no mark, but it has just as much to say about
            // which move drove her out.
            if case .abandoned(let skipped) = outcome { skippedToReview = skipped }
            return
        }

        // Decided by what the run *was*, which it now carries, rather than by
        // what happens to be scheduled when it ends. Resuming used to fall
        // through to "today's session", so an interrupted morning practice
        // marked a session she had never started and recorded no practice —
        // and a resumed session finished after midnight marked the wrong day's.
        switch workout.subject {
        case .session(let id):
            guard let session = sessions.first(where: { $0.id == id }) else { break }
            // Reps are not written here. The timer owns them start to finish —
            // it is the only screen that knows them, and the last set is
            // counted after this has already run. Two writers for one field is
            // how they end up disagreeing.
            mark(session, ran: workout.routine, start: start, end: end)
        case .practice:
            MorningPractices.record(workout.routine.warmUp, in: context)
            try? context.save()
        case .routine, .extra:
            // The `RoutineRun` itself is written by `WorkoutTimerView.report`,
            // because a run started from the Timer tab never reaches this
            // function — it has its own `onEnd`. Recording it here as well
            // would double-count exactly the weeks she does most in.
            //
            // What is left is presenter-specific: only Today knows which saved
            // routine was tapped, so only Today can date it.
            if case .saved(let record, _) = workout {
                record.lastRunAt = end
                try? context.save()
            }
        case .test:
            // Recorded by `report()` like any extra; the scoring reads the
            // rows it wrote and is shown on Today from the run itself, so
            // there is nothing to write here and nothing that can be missed.
            break
        case .unknown:
            // Written by a build before a run said what it was. Today's
            // session is the old behaviour and the only guess available; it is
            // at least never a practice, so it cannot invent a mark from one.
            if let session = todaysSession {
                mark(session, ran: workout.routine, start: start, end: end)
            }
        }
        // Held rather than presented. `report()` now fires from the engine at
        // the moment the session ends, which on the completed path is while
        // the cover is still showing the completion screen — asking a sheet to
        // present over a live full-screen cover either drops the presentation
        // or invokes its binding's setter with `false`, which clears the array
        // and destroys the only record of what drove her out of the session.
        // The abandoned path always worked because it dismisses the cover in
        // the same update; the completed path is the one nobody exercised.
        pendingSkips = skipped
    }

    /// Writes the mark, then tells Health.
    ///
    /// Synchronously, and before anything is awaited. This used to happen
    /// inside a `Task` that raced the cover's dismissal, and a finished session
    /// could end up with no `completedAt` at all — the work simply vanished.
    /// The mark is the point of finishing; Health is a nicety.
    private func mark(_ session: PlannedSession, ran: IntervalRoutine,
                      start: Date, end: Date) {
        // Frozen at the moment it becomes a record: `ran` is the routine the
        // timer actually counted her through, her load overrides included.
        // Without this the row kept the library's defaults and re-read every
        // later change, so stepping the halo up to the 8 lb ring would rewrite
        // what a finished session claims she lifted.
        session.routineData = (try? JSONEncoder().encode(ran)) ?? session.routineData
        session.completedAt = end
        try? context.save()
        let sync = HealthSync(health: HealthKitService(), context: context)
        Task { await sync.record(session: session, start: start, end: end) }
    }

    private struct Offer { let session: PlannedSession; let note: String; let action: String }

    /// What a rest day can still offer: something missed earlier this week
    /// first, then the next one early.
    ///
    /// Missed comes first deliberately. Pulling tomorrow's forward on a day she
    /// already skipped one would leave the skipped session sitting there and
    /// quietly shorten the week.
    private var offeredSession: Offer? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let block = blocks.first else { return nil }
        let weekStart = PlannerService.weekStart(block.currentWeek, of: block)

        // Most recent first, so "the day before" is what gets offered.
        if let missed = sessions
            .filter({ !$0.isComplete && $0.scheduledFor < today && $0.scheduledFor >= weekStart })
            .max(by: { $0.scheduledFor < $1.scheduledFor }) {
            let day = missed.scheduledFor.formatted(.dateTime.weekday(.wide))
            return Offer(session: missed,
                         note: "\(day)'s session is still here if you want it.",
                         action: "Do \(day)'s session")
        }

        if let next = sessions
            .filter({ !$0.isComplete && $0.scheduledFor > today })
            .min(by: { $0.scheduledFor < $1.scheduledFor }) {
            let day = next.scheduledFor.formatted(.dateTime.weekday(.wide))
            return Offer(session: next,
                         note: "\(day)'s session is written already, if you would rather move today.",
                         action: "Do it early")
        }
        return nil
    }

    // MARK: - Derived copy

    private var todaysSession: PlannedSession? {
        sessions.first { Calendar.current.isDateInToday($0.scheduledFor) && !$0.isComplete }
    }

    /// Marks in **this** block, which is what the figures beside it count.
    ///
    /// This was every finished session ever stored, shown over
    /// `marksPerWeek * weekCount` — a denominator for one block. So the first
    /// day of a fresh twelve-week block read "47 / 60" while Season, which sums
    /// the same block's weeks, read "Not yet drawn" on the same afternoon. Two
    /// screens describing one number, disagreeing.
    private var completedCount: Int { marksByWeek.reduce(0, +) }

    private var keptToday: [LoggedSet] {
        loggedSets.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var runsToday: [RoutineRun] {
        routineRuns.filter { Calendar.current.isDateInToday($0.finishedAt) }
    }

    /// "40s ×3", or "40s ×3 each side" when the move runs once per side — the
    /// row says up front that this one takes two intervals a turn.
    private func rotationMeasure(for move: Move, in routine: IntervalRoutine) -> String {
        routine.rowMeasure(for: move)
    }

    /// States the count, and says plainly that it is not a mark — so the number
    /// here and the number on the season can differ without looking like a bug.
    private var keptNote: String {
        var parts: [String] = []
        if !runsToday.isEmpty {
            parts.append(runsToday.count == 1 ? "1 workout" : "\(runsToday.count) workouts")
        }
        let reps = keptToday.reduce(0) { $0 + $1.reps }
        if reps > 0 { parts.append("\(reps) reps") }
        guard !parts.isEmpty else { return "Off the plan" }
        return parts.joined(separator: " · ") + " · no mark"
    }

    /// Which day of the block's week today is, 0–6 — the same start-of-day
    /// arithmetic the week bins use, so the highlighted segment and the
    /// binned marks cannot disagree about where the week is.
    private var dayOfBlockWeek: Int? {
        guard let start = blocks.first?.startDate else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: .now)).day ?? 0
        return days >= 0 ? days % 7 : nil
    }

    /// Read from the block, so the week Today draws and the week the planner
    /// writes cannot drift apart.
    private var currentWeek: Int { blocks.first?.currentWeek ?? 1 }
    private var weekCount: Int { blocks.first?.weekCount ?? 12 }

    /// Finished sessions binned by the week they were actually finished in.
    private var marksByWeek: [Int] {
        var counts = Array(repeating: 0, count: weekCount)
        guard let start = blocks.first?.startDate else { return counts }
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: start)
        for session in sessions {
            guard let done = session.completedAt else { continue }
            let days = calendar.dateComponents([.day], from: first,
                                               to: calendar.startOfDay(for: done)).day ?? 0
            // Integer division truncates toward zero, so the six days *before*
            // a block began all mapped to week 0 — and nothing prunes a
            // previous block's sessions from the query. A new block therefore
            // opened with the last week of the old one already drawn on it.
            guard days >= 0 else { continue }
            let week = days / 7
            if counts.indices.contains(week) { counts[week] += 1 }
        }
        return counts
    }

    private var marksThisWeek: Int {
        marksByWeek.indices.contains(currentWeek - 1) ? marksByWeek[currentWeek - 1] : 0
    }

    /// Her own substantial workouts as tick positions — binned by the same
    /// start-of-day arithmetic marks use, then placed by `tickPositions` so
    /// each tick follows the session it was performed after, same-day extras
    /// clustered close. Her spec, and the drawing just draws it.
    private var minorsByWeek: [[Double]] {
        var sessionTimes = Array(repeating: [Date](), count: weekCount)
        var extraTimes = Array(repeating: [Date](), count: weekCount)
        guard let start = blocks.first?.startDate else {
            return Array(repeating: [], count: weekCount)
        }
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: start)
        func week(of date: Date) -> Int? {
            let days = calendar.dateComponents([.day], from: first,
                                               to: calendar.startOfDay(for: date)).day ?? 0
            guard days >= 0 else { return nil }
            let bin = days / 7
            return bin < weekCount ? bin : nil
        }
        for session in sessions {
            guard let done = session.completedAt, let bin = week(of: done) else { continue }
            sessionTimes[bin].append(done)
        }
        for run in routineRuns where run.isSubstantial {
            guard let bin = week(of: run.finishedAt) else { continue }
            extraTimes[bin].append(run.finishedAt)
        }
        return (0..<weekCount).map {
            GrowthForm.tickPositions(sessions: sessionTimes[$0], extras: extraTimes[$0])
        }
    }

    /// The denominators follow the pace she chose rather than a fixed six.
    /// Hard-coding them meant a block set to four sessions a week still counted
    /// toward six, so a week she completed in full read as two short.
    private var marksPerWeek: Int { blocks.first?.pace.sessionsPerWeek ?? Pace.building.sessionsPerWeek }
    private var marksInBlock: Int { marksPerWeek * weekCount }

    /// "0 marks" under "Day one. Start small." is true and needlessly bleak.
    private var seasonNote: String {
        switch completedCount {
        case 0: "Not yet drawn"
        case 1: "1 mark"
        default: completedCount.marksPhrase
        }
    }

    private func seasonLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // The label holds its line; the leader gives up the width instead.
            Text(label)
                .almanacLabel(Palette.mute, small: true)
                .lineLimit(1)
                .fixedSize()
            Rectangle()
                .fill(Palette.rule)
                .frame(height: 1 / displayScale)
            Text(value)
                .font(Face.ui(14))
                .tabular()
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private var mastheadLabel: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()
    }

    /// Warm, specific, and never exclamatory — the voice this lane inherited
    /// from Season.
    /// The first line she reads, and it has to be true of the day she is having.
    ///
    /// It used to ask `todaysSession == nil`, which is the *unfinished* session
    /// today — so the moment she finished one, the headline turned into "Rest
    /// day. That counts too." on a day she had just trained, above a section
    /// reading DONE. The app telling her she rested is the sort of small
    /// untruth the whole voice exists to avoid.
    ///
    /// It also asserted "Today is a steady one" regardless of what today
    /// actually held. The session names itself two lines further down; the
    /// headline does not need to characterise it, and cannot honestly.
    private var greeting: String {
        let marks = completedCount
        if finishedToday != nil {
            // Not "Done for today" — there is more on offer two sections down,
            // and a headline that closes the day above a section opening it
            // would be the screen disagreeing with itself.
            return marks == 1
                ? "That is one.\nFirst of the season."
                : "That is today's.\n\(marks.marksPhrase) this season."
        }
        if marks == 0 { return "Day one. Start small." }
        if todaysSession == nil { return "Rest day. That counts too." }
        return marks == 1 ? "One session in.\nHere is the next." : "\(marks) sessions in.\nHere is the next."
    }

    private var trend: WeightTrend { WeightTrend(entries: weights) }

    /// The seven-day mean, because a single morning's reading is mostly water.
    private var latestWeightString: String {
        guard let mean = trend.sevenDayMean ?? weights.first?.pounds else { return "—" }
        return String(format: "%.1f", mean)
    }

    private var weeklyRateString: String? {
        guard let rate = trend.weeklyRate else { return nil }
        return String(format: "%+.1f lb this week", rate)
    }
}

/// Which session a day should show as finished.
///
/// Out of the view because the rule has a wrinkle worth stating once and
/// testing: it is decided by **when she finished**, not by the day the session
/// was written for. A rest day filled by pulling the next session forward —
/// which the rest-day copy offers her in as many words — was showing the
/// rest-day text afterwards and nothing else, because the question being asked
/// was "which session scheduled today is complete". The work was done and the
/// mark was earned; the day said nothing about it.
enum FinishedSessions {
    static func today(_ sessions: [PlannedSession], now: Date = .now,
                      calendar: Calendar = .current) -> PlannedSession? {
        let done = sessions.filter {
            guard let at = $0.completedAt else { return false }
            return calendar.isDate(at, inSameDayAs: now)
        }
        // The session today was written for wins, so a day holding both reads
        // as the day the plan describes rather than as whatever finished last.
        return done.first { calendar.isDate($0.scheduledFor, inSameDayAs: now) }
            ?? done.max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }
}
