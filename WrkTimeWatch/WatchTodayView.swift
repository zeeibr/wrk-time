import SwiftUI
import SwiftData

/// The day, on the wrist.
///
/// The same reads the phone's Today makes, in the same order, with the words
/// cut to what a 46mm face holds: what today asks, what is left of the week,
/// the practice, and the extras. Everything it offers, it offers — a rest day
/// states the plan's intent and then says what is available, and nothing here
/// implies the day was insufficient.
///
/// It starts sessions. A session started here is **watch-owned**: this device
/// called `engine.start()`, so this device writes the record, and the phone
/// writes none for it. That rule is the whole defence against two writers,
/// and it is why `record` below does what `TodayView.finish` does and no more.
struct WatchTodayView: View {
    @Query(sort: \PlannedSession.scheduledFor) private var sessions: [PlannedSession]
    @Query(sort: \Block.startDate, order: .reverse) private var blocks: [Block]
    @Query(sort: \SavedRoutine.createdAt, order: .reverse) private var saved: [SavedRoutine]
    /// Observed rather than fetched: the test offer reads the runs, and a run
    /// the timer just wrote must change the offer the moment it lands.
    @Query(sort: \RoutineRun.finishedAt, order: .reverse) private var runs: [RoutineRun]

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    /// What is on the timer, if anything. One value and one presentation —
    /// the phone learned that the hard way, and stacking covers is how a
    /// finished session loses its completion callback.
    @State private var running: WatchRun?
    /// A session this process died under, offered back rather than lost.
    @State private var resumable: ActiveSession?
    @State private var resuming: ActiveSession?
    /// A session the *phone* owns, mirrored here. Phase 2 owns the live link;
    /// until then this is read from the stored session and only when it is
    /// phone-owned. See `phoneRow`.
    @State private var mirrored: ActiveSession?
    /// Whether the mirror screen is up over this one.
    @State private var showMirror = false
    /// The wire to the phone. Shared — see `SessionLink.shared`.
    @State private var link = SessionLink.shared
    /// Whether the Health authorization sheet has been offered. One-shot by
    /// stored flag rather than by authorization state, because an
    /// undetermined state re-asks forever.
    @AppStorage("watchAskedHealth") private var askedForHealth = false

    // MARK: - What can be running

    /// What the timer is running, so finishing it records the right thing.
    /// The phone's `RunningWorkout`, minus the cases the wrist has no screen
    /// for: there is no skip review here, and no rerun-from-a-record.
    enum WatchRun: Identifiable, Equatable {
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }

        case session(PlannedSession, IntervalRoutine)
        case practice(IntervalRoutine)
        case extra(IntervalRoutine)
        case saved(SavedRoutine, IntervalRoutine)
        case test(IntervalRoutine)
        case resumed(ActiveSession)

        var id: String {
            switch self {
            case .session(let s, _): "session-\(s.id)"
            case .practice: "practice"
            case .extra: "extra"
            case .saved(let r, _): "saved-\(r.id)"
            case .test: "test"
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
            case .test(let r): r
            case .resumed(let a): a.routine
            }
        }

        var subject: ActiveSession.Subject {
            switch self {
            case .session(let s, _): .session(s.id)
            case .practice: .practice
            case .extra: .extra
            case .saved: .routine
            case .test: .test
            case .resumed(let a): a.subject
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                masthead

                // `ranOut` re-checked at every redraw: the row's copy keeps
                // its own clock, and a phone that stopped announcing — ended
                // while nothing here was listening — must not leave a session
                // on offer that no longer exists.
                if let mirrored, !mirrored.ranOut(), !mirrored.isStale() {
                    phoneRow(mirrored)
                }
                if let resumable { resumeRow(resumable) }

                sessionSection
                practiceSection
                extrasSection
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
        .background(Palette.oat.ignoresSafeArea())
        .fullScreenCover(item: $running) { run in
            WatchTimerView(routine: run.routine,
                           subject: run.subject,
                           resuming: run.isResumed ? resuming : nil) { outcome in
                record(run, outcome)
            }
        }
        .fullScreenCover(isPresented: $showMirror) {
            if let mirrored {
                WatchMirrorView(session: mirrored)
            }
        }
        .task {
            readActiveSession()
            listen()
            WatchSnapshots.refresh(in: context)
            // The one place the watch asks for Health. Asked here, on a
            // screen she is reading, so the sheet never lands mid-session —
            // and asked once: on a device the answer makes later calls
            // no-ops anyway, and on the simulator, where the sheet never
            // draws, re-asking on every open would take the screen with it.
            if !askedForHealth {
                askedForHealth = true
                _ = await WatchWorkout.requestAuthorization()
            }
        }
        .onChange(of: running) { _, value in
            guard value == nil else { return }
            resuming = nil
            // Cleared for the phone's reason: the card is offered from a
            // `@State` copy the timer cannot reach, so it went on offering a
            // session whose stored copy no longer existed.
            resumable = nil
            readActiveSession()
            // Every ending refreshes, whatever the ending was — abandoned as
            // readily as completed, because the complication must stop
            // counting down either way.
            WatchSnapshots.refresh(in: context)
            relisten()
        }
        .onChange(of: showMirror) { _, up in
            guard !up else { return }
            // The mirror closing usually means the session ended, and the
            // `.ended` that closed it landed while the cover held the link's
            // handler — this screen never heard it. Drop the row rather than
            // trust a frozen copy; if the session is in fact still running,
            // the owner answers the `whatIsRunning` below within a message
            // and the row comes straight back.
            mirrored = nil
            relisten()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            WatchSnapshots.refresh(in: context)
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Date.now.formatted(.dateTime.weekday(.wide)))
                .almanacLabel(Palette.mute, small: true)
            Spacer(minLength: 4)
            Text("\(marksThisWeek) / \(marksTarget)")
                .almanacLabel(Palette.moss, small: true)
                .tabular()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Marks this week")
        .accessibilityValue("\(marksThisWeek) of \(marksTarget)")
    }

    // MARK: - The session

    @ViewBuilder
    private var sessionSection: some View {
        if let session = todaysSession, let routine = session.routine {
            section("Session") {
                startRow(title: session.title,
                         detail: routine.shapeLine) { running = .session(session, routine) }
            }
        } else if let done = finishedToday {
            section("Session") {
                Text(finishedLine(done))
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.mute)
                    .fixedSize(horizontal: false, vertical: true)
                offerRow
            }
        } else {
            section("Rest") {
                Text("Nothing scheduled. A rest day is part of the plan, not a gap in it.")
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.mute)
                    .fixedSize(horizontal: false, vertical: true)
                offerRow
            }
        }
    }

    /// What the week still has, offered and never urged.
    @ViewBuilder
    private var offerRow: some View {
        if let offer = plannedOffer, let routine = offer.session.routine {
            startRow(title: offer.kind == .missed
                        ? "\(offer.day)'s session"
                        : "\(offer.day), early",
                     detail: routine.shapeLine,
                     note: offer.kind == .missed
                        ? "Still here if you want it"
                        : "Written already") {
                running = .session(offer.session, routine)
            }
        }
    }

    // MARK: - The practice

    /// The morning practice, which happens every day and earns no mark.
    /// Folded to one line once it is done — this screen is about the next
    /// thirteen minutes.
    @ViewBuilder
    private var practiceSection: some View {
        if MorningPractices.done(in: context) {
            section("Morning") {
                Text(practiceRun > 1 ? "Practice done. \(practiceRun) days in a row."
                                     : "Practice done today.")
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            let routine = practiceRoutine
            section("Morning") {
                startRow(title: "The practice",
                         detail: "\(routine.warmUp.count) movements · \(routine.totalDuration.durationString)") {
                    running = .practice(routine)
                }
            }
        }
    }

    // MARK: - Extras

    /// The test, her own routines, and the composed extra. None of it earns a
    /// mark, and the label says so once rather than on every row.
    ///
    /// The composed extra waits for the plan. On the phone it lives inside
    /// "More today", which appears only once the day's session is done or the
    /// day is a rest day — an extra offered *beside* an unstarted session is
    /// the app competing with its own plan. `Baseline.offer` gates itself the
    /// same way, so the test needs no guard here.
    ///
    /// Her own routines are the exception, and deliberately: on the phone they
    /// are always one tap away on Moves, and the watch has no Moves tab.
    /// Holding them back until the plan was done would put them out of reach
    /// on exactly the days she trains.
    @ViewBuilder
    private var extrasSection: some View {
        let planDone = todaysSession == nil
        let test = testOffer
        let mine = saved.filter { $0.routine != nil }
        if test != nil || planDone || !mine.isEmpty {
            section("More · no mark") {
                if let test {
                    switch test {
                    case .baseline:
                        let routine = Baseline.routine(warmUp: testWarmUp)
                        startRow(title: "Baseline",
                                 detail: routine.shapeLine,
                                 note: "Six moves, one set each") { running = .test(routine) }
                    case .check(let turn):
                        let routine = Baseline.check(turn: turn, warmUp: testWarmUp)
                        startRow(title: "This week's check",
                                 detail: routine.shapeLine,
                                 note: routine.moves.map(\.name).joined(separator: " · ")) {
                            running = .test(routine)
                        }
                    }
                }

                ForEach(mine) { item in
                    if let routine = item.routine {
                        startRow(title: routine.name, detail: routine.shapeLine) {
                            running = .saved(item, routine)
                        }
                    }
                }

                if planDone {
                    let extra = extraSession
                    startRow(title: extra.name,
                             detail: extra.shapeLine,
                             note: extra.moves.map(\.name).joined(separator: ", ")) {
                        running = .extra(extra)
                    }
                }
            }
        }
    }

    // MARK: - The two sessions that are already going

    /// A session the phone is running, mirrored here.
    ///
    /// Live from the link: the phone's `.running(_, owner: .phone)`
    /// announcements replace whatever the stored session said, and `.ended`
    /// takes the row down. Tapping opens `WatchMirrorView` — a read-only
    /// mirror that records nothing, because the phone started this session
    /// and the phone will write it down.
    private func phoneRow(_ session: ActiveSession) -> some View {
        section("On your phone") {
            Button {
                showMirror = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.routine.name)
                        .font(Self.slab(16))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(session.summary())
                        .almanacLabel(Palette.mute, small: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// A session this watch died under, picked up where it stopped.
    private func resumeRow(_ session: ActiveSession) -> some View {
        section("Unfinished") {
            startRow(title: "Pick it back up",
                     detail: session.summary(),
                     note: session.routine.name) {
                resuming = session
                running = .resumed(session)
            }
        }
    }

    /// Reads what is stored, and sorts it by who owns it.
    ///
    /// One read, two answers: a watch-owned session is hers to resume, and a
    /// phone-owned one is hers to watch. Written as one function so the two
    /// can never be offered at once — resuming a session the phone owns is
    /// exactly the second writer the ownership rule exists to prevent.
    private func readActiveSession() {
        let stored = ActiveSessionStore.load()
        resumable = stored?.owner == .watch ? stored : nil
        mirrored = stored?.owner == .phone ? stored : nil
    }

    /// Hear the phone while this screen is the one on top.
    ///
    /// The timer and the mirror each take the link's one handler when they
    /// are presented and clear it when they go; this screen listens the rest
    /// of the time, and asks outright, so a session started on the phone
    /// shows up here within a message rather than on the next launch.
    private func listen() {
        link.onMessage = { message in
            switch message {
            case .running(let session, owner: .phone):
                guard !session.isStale(), !session.ranOut() else { return }
                mirrored = session
            case .ended:
                mirrored = nil
                showMirror = false
            case .running, .reps, .transport, .whatIsRunning:
                // Not this screen's to answer. A watch-owned .running is the
                // timer's own announcement leaking back; counts and transport
                // belong to whichever screen owns a session.
                break
            }
        }
        link.send(.whatIsRunning)
    }

    /// Take the handler back after a cover goes down — a tick later, so the
    /// cover's own `onDisappear` (which clears the handler) has run first
    /// and cannot run after this and leave the screen deaf.
    private func relisten() {
        Task { @MainActor in listen() }
    }

    // MARK: - Recording

    /// The presenter's half of recording a finished run.
    ///
    /// `WatchTimerView.report` owns the other half and writes the `RoutineRun`
    /// and the `SetLog` rows — an extra, a saved routine and a test are all
    /// recorded there, by the screen that saw the ending, never by whoever
    /// presented it. What is left here is only what a presenter alone knows:
    /// which planned session was tapped, and which saved routine.
    ///
    /// **Health is deliberately not written here.** On the phone `mark` calls
    /// `HealthSync.record`; on the watch the workout is written by the live
    /// `HKLiveWorkoutBuilder` (`WATCH-PLAN` §2.6, Phase 3), and the owner
    /// writes Health exactly once. Adding a `HealthSync` call here would put a
    /// second workout in Health for every session started on the wrist.
    private func record(_ run: WatchRun, _ outcome: WatchTimerView.Outcome) {
        guard case .completed(_, let end, _, _) = outcome else {
            // Walked away from. No mark, and no skip review: the phone asks
            // about a move that drove her out, because that is a question
            // with a sentence for an answer.
            return
        }

        switch run.subject {
        case .session(let id):
            guard let session = sessions.first(where: { $0.id == id }) else { break }
            // Frozen at the moment it becomes a record: the routine the timer
            // actually counted her through, her loads as they were today.
            // Without this the row keeps tracking the library and a later
            // load change rewrites what a finished session claims she lifted.
            session.routineData = (try? JSONEncoder().encode(run.routine)) ?? session.routineData
            session.completedAt = end
            try? context.save()
        case .practice:
            MorningPractices.record(run.routine.warmUp, in: context)
            try? context.save()
        case .routine, .extra:
            // Only the presenter knows which saved routine was tapped, so
            // only the presenter can date it. The run itself is already
            // written by the timer.
            if case .saved(let item, _) = run {
                item.lastRunAt = end
                try? context.save()
            }
        case .test, .unknown:
            // A test is recorded by the timer like any extra, and scored on
            // the phone from the rows it wrote. `.unknown` cannot arise from
            // this screen — every case above sets a subject — and guessing
            // at a mark is the one thing recovery must never do.
            break
        }
    }

    // MARK: - Reads

    private var todaysSession: PlannedSession? {
        sessions.first { Calendar.current.isDateInToday($0.scheduledFor) && !$0.isComplete }
    }

    private var finishedToday: PlannedSession? { DayOffer.finishedToday(sessions) }

    private var plannedOffer: DayOffer.Offer? {
        guard let block = blocks.first else { return nil }
        return DayOffer.next(from: sessions,
                             weekStart: DayOffer.weekStart(block.currentWeek, of: block),
                             today: Calendar.current.startOfDay(for: .now))
    }

    private func finishedLine(_ session: PlannedSession) -> String {
        guard let at = session.completedAt else { return "Finished." }
        let time = at.formatted(date: .omitted, time: .shortened)
        return "Done at \(time). \(marksThisWeek) of \(marksTarget) this week."
    }

    /// Flow movements she has asked not to see, in the form the practice wants.
    private var refusedFlow: Set<String> {
        let lists = MovePreferences.lists(in: context)
        return Set((lists.avoided + lists.disliked).map { MovePreference.key($0) })
    }

    private var practiceRoutine: IntervalRoutine {
        Practice.routine(on: .now, avoiding: refusedFlow,
                         library: MoveLibrary.flow + CustomMoves.flow(in: context))
    }

    private var practiceRun: Int { MorningPractices.run(in: context) }

    private var testWarmUp: [Move] {
        WarmUp.afterPractice(on: .now, avoiding: refusedFlow,
                             library: MoveLibrary.flow + CustomMoves.flow(in: context))
    }

    /// The baseline or the weekly check, on the same gating the phone uses.
    ///
    /// `recoveryHolding` is read from `RecoveryLog` rather than from a live
    /// HealthKit call: the watch's HealthKit is Phase 3's, and a reading taken
    /// here would be a second opinion about a day the phone already judged.
    /// An ease streak of one is exactly "today read ease", which is what the
    /// phone passes. With no readings stored the streak is zero and the plan
    /// stands as written — missing data never counts against her.
    private var testOffer: Baseline.Offer? {
        Baseline.offer(runs: runs,
                       sessionDone: finishedToday != nil,
                       restDay: todaysSession == nil,
                       recoveryHolding: RecoveryLog.easeStreak() >= 1)
    }

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

    private var marksTarget: Int {
        blocks.first?.pace.sessionsPerWeek ?? Pace.building.sessionsPerWeek
    }

    private var marksThisWeek: Int {
        guard let block = blocks.first else { return 0 }
        let start = DayOffer.weekStart(block.currentWeek, of: block)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        return sessions.filter {
            guard let done = $0.completedAt else { return false }
            return done >= start && done < end
        }.count
    }

    // MARK: - Pieces

    /// A titled block in the document register. The rule and the mono label
    /// are the whole of the phone's `IndexedSection` that survives at this
    /// size — an index number beside a two-word label is two labels.
    @ViewBuilder
    private func section(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Palette.ruleFirm).frame(height: 1)
            Text(label)
                .almanacLabel(Palette.mute, small: true)
            content()
        }
    }

    /// The slab, on a face that does not have one.
    ///
    /// watchOS ships no Superclarendon, and `Font.custom` falls back to SF
    /// without saying so — which is how the wrist quietly lost the register
    /// the whole lane is built on. New York is the serif watchOS *does* have,
    /// and a serif that is present beats a slab that is not. `Face.slab` is
    /// still right on the phone; this is the one substitution, in one place.
    private static func slab(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// A row that starts something. A real `Button`, not a tap gesture on a
    /// stack: without the trait VoiceOver reads a row as static text and the
    /// crown will not scan it.
    private func startRow(title: String,
                          detail: String,
                          note: String? = nil,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Self.slab(16))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail.uppercased())
                    // The label vocabulary at wrist width. `almanacLabel` is
                    // 10pt tracked 1.5, and "1 set × 6 moves · 23:20" wrapped
                    // to two lines inside the row at that size — a shape line
                    // that breaks mid-phrase says the shape twice as slowly.
                    .font(Face.mono(9, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Palette.mute)
                    .multilineTextAlignment(.leading)
                    .accessibilityShowsLargeContentViewer()
                if let note {
                    Text(note)
                        .font(.almanacBodySmall)
                        .foregroundStyle(Palette.mute)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.oat)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.ruleFirm, lineWidth: 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(note.map { "\($0), \(detail)" } ?? detail)
        .accessibilityAddTraits(.isButton)
    }
}
