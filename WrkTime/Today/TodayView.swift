import SwiftUI
import SwiftData

/// The document register.
///
/// Reading order is deliberate: what today is, what it asks of you, the control
/// that starts it, then the supporting figures. Fasting appears once, as a cell
/// beside weight — it is an input to the plan, not the point of the app.
struct TodayView: View {
    @Query(sort: \PlannedSession.scheduledFor) private var sessions: [PlannedSession]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query private var fastWindows: [FastWindow]
    @Query(sort: \LoggedSet.date, order: .reverse) private var loggedSets: [LoggedSet]
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

    enum RunningWorkout: Identifiable, Equatable {
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }

        /// A planned session, carrying the session so finishing it marks the
        /// right one — a rest day can offer a session from earlier in the week.
        case session(PlannedSession, IntervalRoutine)
        case practice(IntervalRoutine)
        /// One the process died under, picked up where it stopped.
        case resumed(ActiveSession)

        var id: String {
            switch self {
            case .session(let s, _): "session-\(s.id)"
            case .practice: "practice"
            case .resumed: "resumed"
            }
        }

        var isResumed: Bool { if case .resumed = self { return true }; return false }

        var routine: IntervalRoutine {
            switch self {
            case .session(_, let r): r
            case .practice(let r): r
            case .resumed(let a): a.routine
            }
        }

        /// What finishing this should record. A resumed run carries its own,
        /// saved when it started, rather than being guessed at the end.
        var subject: ActiveSession.Subject {
            switch self {
            case .session(let s, _): .session(s.id)
            case .practice: .practice
            case .resumed(let a): a.subject
            }
        }
    }
    @Query private var practices: [MorningPractice]
    /// A session the process died under, offered back rather than lost.
    @State private var resumable: ActiveSession?
    @State private var resuming: ActiveSession?
    /// Moves skipped in the session that just ended, awaiting a reason.
    @State private var skippedToReview: [String] = []
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
                                measure: "\(Int(routine.clampedWork))s ×\(routine.rounds / max(routine.moves.count, 1))"
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
                                      subtitle: "\(routine.rounds) rounds · \(routine.totalDuration.durationString)") {
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
                        .padding(.bottom, keptToday.isEmpty ? 10 : 4)

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
                                   sessionsPerWeek: marksPerWeek,
                                   blockSeed: blocks.first?.formSeed ?? 0)
                            .frame(width: 84, height: 84)
                        VStack(alignment: .leading, spacing: 7) {
                            seasonLine("Marks earned", "\(completedCount) / \(marksInBlock)")
                            seasonLine("This week", "\(marksThisWeek) / \(marksPerWeek)")
                            seasonLine("Week", "\(currentWeek) of \(weekCount)")
                        }
                    }
                    .padding(.bottom, 4)
                }

                IndexedSection(number: "04", label: "Signals") {
                    Rule(firm: true)
                    HStack(alignment: .top, spacing: 14) {
                        StatCell(label: weeklyRateString ?? "Weight · 7-day mean",
                                 value: latestWeightString,
                                 unit: "lb")
                        StatCell(label: "Fasting",
                                 value: fastingString,
                                 emphasis: Palette.moss)
                    }
                    .padding(.top, 12)

                    Text(fastingFootnote)
                        .font(.almanacBodySmall)
                        .foregroundStyle(Palette.mute)
                        .padding(.top, 10)
                        .fixedSize(horizontal: false, vertical: true)
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
            await HealthSync(health: HealthKitService(), context: context).importWeights()
        }
        // Cleared once the cover closes, so a second run does not silently
        // resume the session that was just finished or abandoned.
        .onChange(of: running) { _, value in
            if value == nil { resuming = nil }
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
            counter("\(routine.rounds)", "Rounds")
            divider
            counter("\(Int(routine.clampedWork))/\(Int(routine.rest))", "Work / rest")
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

            PrimaryButton(title: "Pick it back up", subtitle: nil) {
                resuming = session
                running = .resumed(session)
                resumable = nil
            }
            .padding(.top, 14)

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
        let routine = Practice.routine(on: .now, avoiding: refusedFlow)

        IndexedSection(number: "01", label: "Morning") {
            SectionHead(title: "The practice",
                        note: done ? "Done" : routine.totalDuration.durationString)
                .padding(.bottom, 10)

            Text(practiceNote(done: done))
                .font(.almanacBody)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            ForEach(Array(routine.warmUp.enumerated()), id: \.element.id) { index, move in
                BlockRow(index: index + 1, symbol: move.symbol, name: move.name,
                         equipment: move.equipmentLabel,
                         measure: "\(Int(Practice.seconds))s")
                    .onTapGesture { inspecting = move }
            }
            Rule()

            if !done {
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
            ? "Eight movements, eight minutes, starting with the rebounding. \(run) days behind it."
            : "Eight movements, eight minutes, starting with the rebounding. This one happens every day."
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
                ForEach(Array(routine.moves.enumerated()), id: \.element.id) { index, move in
                    BlockRow(index: index + 1, symbol: move.symbol, name: move.name,
                             equipment: move.equipmentLabel,
                             measure: "\(Int(routine.clampedWork))s")
                        .onTapGesture { inspecting = move }
                }
                Rule()
            }
        }
    }

    private func finishedLine(_ session: PlannedSession) -> String {
        guard let at = session.completedAt else { return "Finished." }
        let time = at.formatted(date: .omitted, time: .shortened)
        return marksThisWeek == 1
            ? "Finished at \(time). One mark on the season this week."
            : "Finished at \(time). \(marksThisWeek) marks on the season this week."
    }

    /// A session scheduled for today that has been finished.
    private var finishedToday: PlannedSession? {
        sessions.first { Calendar.current.isDateInToday($0.scheduledFor) && $0.isComplete }
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
                              subtitle: "\(routine.rounds) rounds · \(routine.totalDuration.durationString)") {
                    running = .session(offer.session, routine)
                }
                .padding(.top, 14)
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
        guard case .completed(let start, let end, let skipped) = outcome else {
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
            mark(session, start: start, end: end)
        case .practice:
            MorningPractices.record(workout.routine.warmUp, in: context)
            try? context.save()
        case .routine:
            // A saved timer routine earns no mark and no practice row. It is
            // recorded where it belongs, against the routine that was run.
            break
        case .unknown:
            // Written by a build before a run said what it was. Today's
            // session is the old behaviour and the only guess available; it is
            // at least never a practice, so it cannot invent a mark from one.
            if let session = todaysSession { mark(session, start: start, end: end) }
        }
        skippedToReview = skipped
    }

    /// Writes the mark, then tells Health.
    ///
    /// Synchronously, and before anything is awaited. This used to happen
    /// inside a `Task` that raced the cover's dismissal, and a finished session
    /// could end up with no `completedAt` at all — the work simply vanished.
    /// The mark is the point of finishing; Health is a nicety.
    private func mark(_ session: PlannedSession, start: Date, end: Date) {
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

    private var completedCount: Int { sessions.filter(\.isComplete).count }

    private var keptToday: [LoggedSet] {
        loggedSets.filter { Calendar.current.isDateInToday($0.date) }
    }

    /// States the count, and says plainly that it is not a mark — so the number
    /// here and the number on the season can differ without looking like a bug.
    private var keptNote: String {
        let reps = keptToday.reduce(0) { $0 + $1.reps }
        guard !keptToday.isEmpty else { return "Off the plan" }
        return "\(reps) reps · no mark"
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
            let week = days / 7
            if counts.indices.contains(week) { counts[week] += 1 }
        }
        return counts
    }

    private var marksThisWeek: Int {
        marksByWeek.indices.contains(currentWeek - 1) ? marksByWeek[currentWeek - 1] : 0
    }

    /// The denominators follow the pace she chose rather than a fixed six.
    /// Hard-coding them meant a block set to four sessions a week still counted
    /// toward six, so a week she completed in full read as two short.
    private var marksPerWeek: Int { blocks.first?.pace.sessionsPerWeek ?? Pace.building.sessionsPerWeek }
    private var marksInBlock: Int { marksPerWeek * weekCount }

    /// "0 marks" under "Day one. Start small." is true and needlessly bleak.
    private var seasonNote: String {
        completedCount == 0 ? "Not yet drawn" : "\(completedCount) marks"
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
    private var greeting: String {
        let streak = completedCount
        if streak == 0 { return "Day one. Start small." }
        if todaysSession == nil { return "Rest day. That counts too." }
        return "\(streak) sessions in.\nToday is a steady one."
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

    private var fastingString: String {
        fastWindows.first?.summaryLine ?? "Not tracking"
    }

    private var fastingFootnote: String {
        "Your eating window is one of three inputs to the projected rate, alongside session volume and sleep."
    }
}
