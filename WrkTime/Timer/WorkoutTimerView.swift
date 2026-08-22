import SwiftUI
import SwiftData
import UIKit

/// The field register.
///
/// The screen is oat, and a dark field rises from the bottom to the height of
/// the time remaining in the phase. The count is drawn twice in identical
/// layout — ink on oat, then oat on field, the second masked to the field —
/// so the boundary cuts straight through the digits and the numeral stays one
/// continuous form rather than two stacked halves.
struct WorkoutTimerView: View {
    /// Where the session is in its own arrival.
    private enum Stage { case arriving, leadIn, running, ended }

    @State private var engine: IntervalEngine
    /// Where the count's digits end and the move block begins, in the
    /// field's own coordinate space, measured rather than assumed. The ride
    /// used to stop at a fixed fraction of the screen, which was fine until
    /// the block under it grew — a longer cue, the Form button, a sided
    /// eyebrow — and the digits rode straight into it.
    @State private var countRestBottom: CGFloat?
    @State private var blockTop: CGFloat?
    /// The move whose form notes are open over the timer. The engine runs on
    /// wall-clock time, so reading them costs nothing but the rest she
    /// chooses to spend on it.
    @State private var formFor: Move?
    /// Seconds left of the "get set" after the form notes close, or nil.
    /// Her ask: reading the form pauses the clock, and closing it gives five
    /// seconds to get back into position before it runs again.
    @State private var readyIn: Int?
    /// Whether the clock was running when the form notes opened, so closing
    /// them resumes only what was running.
    @State private var pausedForForm = false
    @State private var liveActivity = LiveActivityController()
    @State private var audio = SessionAudio()
    /// Persisted, because `.playback` sounds through the silent switch and the
    /// way to stop that has to be findable twice, not once.
    @AppStorage("cueSoundEnabled") private var soundEnabled = true
    @State private var stage: Stage = .arriving
    /// Whether the finished session has been put on the clipboard for Whoop.
    @State private var copiedForWhoop = false
    /// Reps she counted, by set — the work interval's ordinal in the schedule.
    /// Sparse on purpose: a set she did not count stays uncounted rather than
    /// being filled in with a plausible number.
    @State private var reps: [Int: Int] = [:]
    /// Seconds left of the lead-in, shown in place of the count.
    @State private var leadIn = 3
    /// 0 while the ground is still down, 1 once it has risen.
    @State private var entryProgress: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    /// Needed because this screen records a finished routine itself — see
    /// `report()`. Both presenters have a context to inherit.
    @Environment(\.modelContext) private var context

    private let routine: IntervalRoutine
    private let onEnd: (Outcome) -> Void

    /// What a finished session tells whoever presented it. A session run to the
    /// end carries its real bounds so it can be written back to Health; one
    /// that was walked away from carries nothing, because it earns nothing.
    enum Outcome {
        /// `skipped` travels with the ending so Today can ask about it. It is
        /// carried on both cases: a session she bailed out of has just as much
        /// to say about which move drove her out.
        case completed(start: Date, end: Date, skipped: [String], reps: [Int])
        case abandoned(skipped: [String])
    }

    /// Set when this screen is picking up a session the process died under.
    private let resuming: ActiveSession?
    /// The real beginning of the session, which a resumed one inherits rather
    /// than restarting — so what is written back to Health is when she actually
    /// started, not when the app came back.
    @State private var sessionStart: Date?
    /// One ending per session, however many places notice it.
    @State private var reported = false

    /// What this run is, so an interruption can be resumed as the same thing.
    /// A resumed run inherits the subject it was saved with.
    private let subject: ActiveSession.Subject

    init(routine: IntervalRoutine,
         subject: ActiveSession.Subject = .unknown,
         resuming: ActiveSession? = nil,
         onEnd: @escaping (Outcome) -> Void = { _ in }) {
        self.routine = routine
        self.subject = resuming?.subject ?? subject
        self.resuming = resuming
        self.onEnd = onEnd
        _engine = State(initialValue: IntervalEngine(routine: routine))
    }

    var body: some View {
        Group {
            if hasCompleted {
                // The field recedes and the document register returns. This is
                // the only place in the app the register comes back, and it
                // should feel like coming up for air.
                completion
                    .transition(.opacity)
            } else {
                field
            }
        }
        .animation(.easeInOut(duration: 0.42), value: hasCompleted)
    }

    /// A session run to the end. Ending early dismisses instead — there is
    /// nothing to celebrate and nothing was earned.
    private var hasCompleted: Bool {
        engine.status == .finished && engine.endReason == .completed
    }

    /// The way in.
    ///
    /// Inevitability is a function of anticipation. The register change is the
    /// whole thesis of the lane, and it used to be performed by UIKit's stock
    /// modal slide-up with the field already at full height on arrival — so
    /// there was nothing to see, and the first heavy cue landed before you had
    /// put the phone down.
    ///
    /// Instead: the ground rises through a document that does not move,
    /// inverting the numeral as it passes — one unhurried demonstration of the
    /// entire design language — and then three seconds to get into position,
    /// counted in the same ticks that will later mark the end of a round. The
    /// motif is the point: dry ascending clicks always mean *a boundary is
    /// three seconds away*.
    private func beginSession() async {
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: reduceMotion ? 0 : 0.52)) {
            entryProgress = 1
        }
        audio.isEnabled = soundEnabled
        audio.begin()
        Haptics.prepare()
        if !reduceMotion {
            try? await Task.sleep(for: .milliseconds(520))
        }

        // A resumed session skips the lead-in. Three seconds to get into
        // position is for the start of a workout; she is already mid-round and
        // counting her in again would be theatre.
        if let resuming {
            // Re-checked here, not only where the card was built. `load()` runs
            // once in Today's `.task`, and a running session's clock keeps
            // moving while the card sits on screen — so a session with three
            // minutes left when the app opened could be tapped forty minutes
            // later, at which point `restore` fell through to `start()` and ran
            // the *entire* routine again from round one, still carrying the
            // original start date. Finishing that replay earned a mark and
            // wrote an hour-long workout to Health. A session with nothing left
            // to run is discarded, which is what recovery has always promised.
            guard !resuming.ranOut(), !resuming.isStale() else {
                stage = .ended
                ActiveSessionStore.clear()
                dismiss()
                return
            }
            sessionStart = resuming.startedAt
            stage = .running
            SessionCues(audio: audio).bind(to: engine)
            engine.restore(to: resuming.elapsedNow(), running: resuming.running)
            liveActivity.start(routine: routine, engine: engine)
            return
        }

        stage = .leadIn
        for count in stride(from: 3, through: 1, by: -1) {
            guard stage == .leadIn else { return }   // dismissed mid-lead-in
            leadIn = count
            Haptics.countdownTick()
            try? await Task.sleep(for: .seconds(1))
        }
        guard stage == .leadIn else { return }

        stage = .running
        sessionStart = .now
        SessionCues(audio: audio).bind(to: engine)
        engine.start()
        liveActivity.start(routine: routine, engine: engine)
        persist()
    }

    /// Write down where the session is, so it survives the process dying.
    ///
    /// Cheap enough to do often: a routine and two dates. It is called at every
    /// phase boundary, every transport change, and on the way to the background
    /// — plus on a slow timer, because a force-quit from the app switcher gives
    /// no warning at all.
    private func persist() {
        guard stage == .running, engine.status != .finished else { return }
        var session = ActiveSession(routine: routine,
                                    startedAt: sessionStart ?? .now,
                                    elapsed: engine.elapsed,
                                    running: engine.status == .running,
                                    savedAt: .now)
        session.setSubject(subject)
        ActiveSessionStore.save(session)
    }

    private var field: some View {
        GeometryReader { proxy in
            // The field rises from the physical bottom of the display, not from
            // the top of the home indicator — a band of oat under it would read
            // as the field falling short. `proxy` is inset by the safe area, so
            // the bottom inset has to be added back to reach the glass.
            let bottomInset = proxy.safeAreaInsets.bottom
            let fullHeight = proxy.size.height + bottomInset

            ZStack(alignment: .bottom) {
                Palette.oat.ignoresSafeArea()

                // Base layer: everything as it reads on oat.
                // The base layer is the one that measures itself: the field
                // layer is an identical copy shifted by the inset, and two
                // readings of one layout would disagree by exactly that.
                content(foreground: Palette.ink, secondary: Palette.mute,
                        countOffset: countRide(in: fullHeight), measures: true)
                    .coordinateSpace(name: "field")

                // Field layer: the same content, inverted, clipped to the
                // draining block. Identical layout is what makes the knockout
                // work — the two layers must agree to the pixel. This one hangs
                // below the safe area, so its content is padded back up by the
                // same inset to land exactly on top of the base layer.
                ZStack(alignment: .bottom) {
                    Palette.field
                    content(foreground: Palette.oat, secondary: Palette.sage,
                            countOffset: countRide(in: fullHeight))
                        .padding(.bottom, bottomInset)
                }
                .frame(height: fullHeight)
                .mask(alignment: .bottom) {
                    Rectangle()
                        .frame(height: fieldHeight(in: fullHeight))
                }
                .padding(.bottom, -bottomInset)
                .animation(.linear(duration: 0.05), value: engine.elapsed)
                // Purely a visual duplicate of the layer beneath. `mask` clips
                // pixels but does not prune the accessibility tree, so without
                // this VoiceOver reads the whole screen twice — two counts, two
                // Pause buttons — and Switch Control scans six transport
                // controls instead of three.
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.light)
        .onChange(of: formFor) { _, move in
            formOpened(move != nil)
        }
        .sheet(item: $formFor) { move in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(move.name)
                            .font(.almanacTitle)
                            .foregroundStyle(Palette.ink)
                        Text(move.equipmentLabel)
                            .almanacLabel(Palette.mute, small: true)
                            .padding(.top, 6)
                        if let form = MoveForm.notes(for: move.name) {
                            FormCard(form: form).padding(.top, 18)
                        } else {
                            Text(move.cue)
                                .font(.almanacBody)
                                .foregroundStyle(Palette.ink)
                                .padding(.top, 18)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 30)
                }
                .background(Palette.oat.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { formFor = nil }.foregroundStyle(Palette.ink)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            // The phone spends the session on the floor, untouched. Without
            // this the display locks during the first round and takes the
            // field register, the count and the cues with it.
            UIApplication.shared.isIdleTimerDisabled = true
            // Set before anything can start, and read from the engine rather
            // than from a view modifier: finishing removes this view in the
            // same update that ends the session, so a handler living on it
            // never runs. See `IntervalEngine.onEnded`.
            engine.onEnded = { _ in report() }
            guard stage == .arriving else { return }
            Task { await beginSession() }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            // Also ends the lead-in: its loop checks the stage between ticks.
            stage = .ended
            engine.pause()
            liveActivity.end()
            audio.end()
        }
        // One Live Activity update per phase, not per second — the widget
        // renders its own countdown from the phase bounds.
        .animation(.easeInOut(duration: 0.35), value: showsPlate)
        .onChange(of: engine.currentPhase) { _, phase in
            liveActivity.update(engine: engine)
            announce(phase)
            persist()
        }
        // A force-quit gives no lifecycle warning, so the boundaries alone are
        // not enough — a round is forty seconds and losing all of it is the
        // difference between resuming and starting over.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                persist()
            }
        }
        // The iOS convention for a running timer, and the only way to stop one
        // from anywhere on screen without hunting for a 66pt target.
        .accessibilityAction(.magicTap) { engine.toggle() }
        // Returning from the background recomputes from the clock rather than
        // resuming a stale count.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { engine.refresh() } else { persist() }
        }
        .onChange(of: engine.status) { _, status in
            // A paused session must not hold the screen awake indefinitely.
            UIApplication.shared.isIdleTimerDisabled = (status == .running)
            // Deliberately no longer the place the ending is reported from.
            // This handler only runs while the field is on screen, which a
            // finished session is not — `engine.onEnded` carries the ending.
            guard status != .finished else { return }
            persist()
            // Pausing and resuming are phase-silent, so the lock screen would
            // otherwise keep counting down a stopped workout.
            liveActivity.update(engine: engine)
        }
    }

    /// Tell VoiceOver at the boundary — never every second. A count that
    /// announces itself continuously is unusable; one that never announces
    /// leaves a blind user unable to know the round changed at all, which is
    /// the same problem the countdown haptic solves for everyone else.
    private func announce(_ phase: Phase?) {
        guard let phase else { return }
        let seconds = Int(phase.duration.rounded())
        let words = switch phase.kind {
        case .flow: "\(phase.move?.name ?? "Flow"). \(seconds) seconds. No rush."
        case .work: "Work\(phase.side.map { ", \($0.lowercased())" } ?? ""). \(seconds) seconds."
        case .rest: "Rest. \(seconds) seconds."
        }
        AccessibilityNotification.Announcement(words).post()
    }

    /// Report the ending exactly once, with its real bounds. Only a session
    /// run to the end has bounds worth writing back.
    private func report() {
        // Called from the engine, which can only end once — but a guard costs
        // nothing and a double mark would be a lie about the day.
        guard !reported else { return }
        reported = true
        // Either way the session is over, so the stored copy goes — it exists
        // only to survive a crash, never to outlive an ending.
        ActiveSessionStore.clear()
        liveActivity.end()
        guard engine.endReason == .completed, let start = sessionStart ?? engine.startDate else {
            onEnd(.abandoned(skipped: engine.skippedMoves))
            return
        }
        // Capped at the routine's own length rather than reported as `.now`.
        //
        // Two ways wall-clock lied. Pause for a phone call and resume half an
        // hour later, and a thirteen-minute routine wrote a forty-three-minute
        // workout to Health — every one of those minutes counting toward the
        // Exercise ring. And because the engine only discovers it has finished
        // when something calls `refresh()`, a session left running while the
        // app was suspended was stamped at the moment she came back, which
        // could be an hour after the last round ended.
        //
        // The floor is the same guard from the other direction: skipping to the
        // end is a real ending, and the elapsed clock is the honest length of
        // it, so the cap only ever removes time nobody was working.
        let ceiling = start.addingTimeInterval(engine.schedule.total)
        let end = min(.now, ceiling)

        // Recorded here, by the screen that knows the workout finished, rather
        // than by whoever presented it.
        //
        // This was in `TodayView.finish` alone, so a routine started from the
        // Timer tab — which has its own `onEnd` closure and never touches
        // `finish` — left no record at all. That is the sixth instance of the
        // shape named in CLAUDE.md: an effect placed on one of two paths, the
        // wired path verified, the other never exercised. A presenter must not
        // get to decide whether a finished workout is written down.
        //
        // A planned session is not recorded here: it earns a mark, which needs
        // the session row, which only the presenter has.
        if let source = subject.recordedSource {
            recordedRun = RoutineRuns.record(routine, source: source,
                                             seconds: end.timeIntervalSince(start),
                                             reps: countedReps, in: context)
        }

        onEnd(.completed(start: start, end: end, skipped: engine.skippedMoves,
                         reps: countedReps))
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The field fills from the bottom in proportion to time left in the phase.
    /// During rest it is deliberately still — resting is not a countdown you
    /// should feel chased by, so it holds at full height and only the digits
    /// move.
    private func fieldHeight(in total: CGFloat) -> CGFloat {
        // Rising, or held full through the lead-in while you get set.
        guard stage == .running else { return total * entryProgress }
        guard let phase = engine.currentPhase else { return total }
        guard phase.isWork else { return total }
        // A rep set is open until she ends it. The field holds still, as it
        // does through rest: a boundary sweeping toward a ninety-second net
        // would be a clock that means nothing, chasing her through a set
        // that is supposed to be slow.
        guard !phase.openEnded else { return total }
        // Under Reduce Motion the field holds still through work, exactly as it
        // already does through rest. A full-height hard edge sweeping the whole
        // screen for sixty seconds at a stretch is a textbook vestibular
        // trigger, and the count carries the timing without it. The composition
        // — the knockout, the two registers — survives untouched; only the
        // sweep is dropped.
        guard !reduceMotion else { return total }
        return total * CGFloat(engine.phaseRemainingFraction)
    }

    /// How far the count has ridden down with the boundary.
    ///
    /// The knockout is the whole claim of this lane, and it only happens where
    /// the boundary crosses something. With the numeral parked under the header
    /// the boundary swept the other nine tenths of the screen crossing nothing,
    /// so the signature was on screen for about five seconds of every sixty and
    /// the rest of the interval was a dark rectangle with a number in the
    /// corner.
    ///
    /// Tying the numeral to the same fraction that drives the field keeps the
    /// boundary cutting the digits for most of the interval, and makes the
    /// count's *height* a second reading of how far through you are — legible
    /// across a room without resolving a single digit. It holds still during
    /// rest, and under Reduce Motion, which is also what tells the two phases
    /// apart at a glance.
    private func countRide(in total: CGFloat) -> CGFloat {
        guard stage == .running else { return 0 }
        guard let phase = engine.currentPhase, phase.isWork, !reduceMotion else { return 0 }
        let boundary = total * (1 - CGFloat(engine.phaseRemainingFraction))
        // Where the digits' *optical* centre already sits, and the lowest it
        // may ride before it would start crowding the move block below.
        //
        // This is the optical centre, not the centre of the text's line box:
        // the slab's cap height sits high in its box, so measuring the box put
        // the boundary about sixty points low and it sliced the caption instead
        // of the digits. Tuned against the rendered glyph.
        let opticalCentre: CGFloat = 88
        var lowestCentre = total * 0.55
        // Never into the block below: the digits' resting bottom plus the
        // ride must stay a clear margin above wherever the block starts.
        if let countRestBottom, let blockTop {
            let room = blockTop - 14 - countRestBottom
            lowestCentre = min(lowestCentre, opticalCentre + max(room, 0))
        }
        return min(max(boundary, opticalCentre), lowestCentre) - opticalCentre
    }

    // MARK: - Content

    private func content(foreground: Color, secondary: Color,
                         countOffset: CGFloat, measures: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(foreground: foreground, secondary: secondary)

            VStack(alignment: .leading, spacing: 0) {
                Text(countString)
                    // 96, not 112: the slab sets considerably wider than the
                    // grotesk it replaced, and the mockup's figure is 96.
                    .font(.almanacCount(96))
                    .tracking(-3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(foreground)
                    .padding(.top, 6)
                    .accessibilityLabel(phaseWord)
                    .accessibilityValue(accessibilityCount)
                    .accessibilityAddTraits(.updatesFrequently)

                HStack(spacing: 8) {
                    // Saffron means live, and a running work interval is the
                    // one live thing on this screen — the mockup's Work pill,
                    // reduced to its mark.
                    if engine.currentPhase?.isWork == true, engine.status == .running {
                        Rectangle()
                            .fill(Palette.saffron)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                    Text(phaseCaption)
                        .almanacLabel(secondary)
                }
            }
            .padding(.horizontal, 22)
            .background {
                if measures {
                    GeometryReader { proxy in
                        // The reader sits inside the offset, so what it sees
                        // has already ridden; subtracting the ride gives the
                        // resting position, which is the one the floor needs.
                        let bottom = proxy.frame(in: .named("field")).maxY - countOffset
                        Color.clear.onChange(of: bottom, initial: true) { _, value in
                            if abs((countRestBottom ?? -1) - value) > 0.5 { countRestBottom = value }
                        }
                    }
                }
            }
            // Both layers take the same offset, so the two copies stay in the
            // pixel agreement the knockout depends on. Measured above the
            // offset, so the reading is where the digits rest, not where
            // they have ridden to.
            .offset(y: countOffset)

            Spacer(minLength: 12)

            // Rest used to leave the middle of the screen empty and put the one
            // thing rest is for — knowing what to set up next — in a ten point
            // line at the very bottom. It gets the same billing as the current
            // move instead.
            Group {
                if let phase = engine.currentPhase, let move = phase.move {
                    // The set is already in the header and the caption; the
                    // eyebrow keeps to the side, the one thing that has to
                    // be readable at a glance mid-set.
                    moveBlock(move, eyebrow: phase.isFlow ? phaseWord : phase.side,
                              foreground: foreground, secondary: secondary)
                } else if let next = engine.nextPhase, let move = next.move {
                    moveBlock(move, eyebrow: next.isFlow && engine.routine.roundCount > 0
                                              ? "Warm-up next"
                                              : next.side.map { "Next up · \($0.lowercased())" } ?? "Next up",
                              foreground: foreground, secondary: secondary)
                }
            }
            .background {
                if measures {
                    GeometryReader { proxy in
                        let top = proxy.frame(in: .named("field")).minY
                        Color.clear.onChange(of: top, initial: true) { _, value in
                            if abs((blockTop ?? -1) - value) > 0.5 { blockTop = value }
                        }
                    }
                }
            }

            // Counting the set she has just finished, during the rest that
            // follows it — the one moment she is standing still and it is
            // still fresh. Steppers rather than a keyboard: a number pad in
            // the field register, on a forty-second rest, with the hands this
            // has just been done with, is a way of not recording anything.
            if let set = restingAfterSet {
                repCounter(for: set, foreground: foreground, secondary: secondary)
                    .padding(.top, 16)
                    .padding(.horizontal, 22)
            }

            upNext(foreground: foreground, secondary: secondary)
                .padding(.top, 16)
                .padding(.horizontal, 22)

            transport(foreground: foreground)
                .padding(.top, 18)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Completion

    /// What a finished session looks like.
    ///
    /// It states what happened and stops. No congratulation, no score, no
    /// prompt to go again — the mark on the growth form is the reward, and it
    /// has already been earned by the time this appears.
    private var completion: some View {
        VStack(alignment: .leading, spacing: 0) {
            Masthead(context: routine.name)
                .padding(.top, 8)

            Spacer(minLength: 24)

            Text(completionHeadline)
                .font(.almanacTitle)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            // A mark is a finished *session*. The practice keeps its own record
            // and deliberately earns none, so claiming one here would be the
            // screen contradicting the season it points at — and so would
            // claiming one for a routine or an extra, which are recorded as
            // her own work. The subject knows which this was; the round count
            // does not.
            Text(completionRecordNote)
                .font(.almanacBody)
                .foregroundStyle(Palette.mute)
                .padding(.top, 8)

            HStack(spacing: 0) {
                completionFigure("\(engine.routine.roundCount)", "Rounds")
                completionFigure(engine.schedule.total.durationString, "Elapsed")
            }
            .padding(.top, 26)
            .overlay(alignment: .top) { Rule() }
            .overlay(alignment: .bottom) { Rule() }
            .padding(.bottom, 2)

            // The last set has no rest after it, so it is the one set that
            // could not be counted while she was working. Asked for here, once,
            // rather than left as the gap in every list she pastes.
            if let set = lastSet, let phase = lastWorkPhase, let move = phase.move {
                VStack(alignment: .leading, spacing: 0) {
                    Rule()
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text([("Last set"), move.name, phase.side]
                                .compactMap { $0 }.joined(separator: " · "))
                                .almanacLabel(Palette.mute, small: true)
                            Text(reps[set].map(String.init) ?? "—")
                                .font(Face.slab(26))
                                .tabular()
                                .foregroundStyle(Palette.ink)
                        }
                        Spacer(minLength: 8)
                        FieldButton(systemName: "minus", label: "One fewer rep",
                                    foreground: Palette.ink) {
                            reps[set] = max((reps[set] ?? 0) - 1, 0)
                            applyReps()
                            Haptics.transport()
                        }
                        FieldButton(systemName: "plus", label: "One more rep",
                                    foreground: Palette.ink) {
                            reps[set] = (reps[set] ?? 7) + 1
                            applyReps()
                            Haptics.transport()
                        }
                    }
                    .padding(.vertical, 10)
                    Rule()
                }
                .padding(.top, 18)
                .accessibilityElement(children: .contain)
            }

            // Whoop computes Muscular Load from what it is told, and its API
            // only reads — nothing can be written in. So the session goes to
            // the clipboard in her words instead, ready to paste into Whoop's
            // own assistant rather than typed again from memory.
            if !engine.routine.moves.isEmpty {
                Button {
                    UIPasteboard.general.string = WhoopSummary.text(
                        for: engine.routine,
                        seconds: engine.schedule.total,
                        reps: countedReps,
                        durations: engine.setDurations)
                    Haptics.transport()
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
                .padding(.top, 12)
                .accessibilityHint("Copies this session's moves and loads to the clipboard")
            }

            Spacer()

            PrimaryButton(title: "Done", subtitle: nil) { dismiss() }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Palette.oat.ignoresSafeArea())
    }

    private func completionFigure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(Face.slab(30)).tabular().foregroundStyle(Palette.ink)
            Text(label).almanacLabel(Palette.mute, small: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// Spelled out, because this line is read once and read properly — the
    /// mono labels take digits, a slab sentence does not.
    private var completionHeadline: String {
        let spell = NumberFormatter()
        spell.numberStyle = .spellOut
        func word(_ n: Int) -> String {
            (spell.string(from: NSNumber(value: n)) ?? "\(n)")
        }
        func sentence(_ n: Int, _ singular: String, _ plural: String) -> String {
            "\(word(n).capitalized) \(n == 1 ? singular : plural)."
        }

        let rounds = engine.routine.roundCount
        let minutes = Int((engine.schedule.total / 60).rounded())
        // A routine can be shorter than a minute, and "Zero minutes" is not a
        // thing to tell someone who just finished one.
        guard minutes >= 1 else {
            let seconds = Int(engine.schedule.total.rounded())
            return sentence(rounds, "round", "rounds") + " "
                 + sentence(seconds, "second", "seconds")
        }
        return sentence(rounds, "round", "rounds") + " "
             + sentence(minutes, "minute", "minutes")
    }

    /// The move: its plate, then its name and cue at full width.
    ///
    /// The strip sits above the type rather than beside it. Sharing the row
    /// meant the name wrapped to two lines at thirty point and the panels were
    /// squeezed to a third of the width — both halves losing, so that neither
    /// could be read across a room. Stacked, the strip gets the whole measure
    /// and the sentence underneath gets it too.
    ///
    /// It is drawn in the register's own colours rather than in ink, so it
    /// inverts with everything else as the boundary passes over it. Both layers
    /// of the knockout render the same `Canvas` at the same size, so they agree
    /// to the pixel the way the type does.
    private func moveBlock(_ move: Move, eyebrow: String?,
                           foreground: Color, secondary: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow {
                Text(eyebrow).almanacLabel(secondary)
            }

            if MoveStrip.exists(for: move), showsPlate {
                MoveStrip(move: move, style: .strip,
                          line: foreground, rule: secondary.opacity(0.45),
                          label: secondary)
                    .frame(height: 124)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(move.name)
                    .font(Face.slab(30))
                    .foregroundStyle(foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                // What to pick up, on the one screen where she is picking it
                // up. Every other surface — Today, the library, the move
                // sheet, the builder — has carried `equipmentLabel` all along
                // and this one never did, which was survivable only while the
                // moves she saw most were the ring ones, whose cues name the
                // weight in prose. Fifty-five of the seventy-five loaded moves
                // do not, so most of the library reached the field register
                // with the load nowhere on screen.
                //
                // It cannot live in the cue instead. `MoveOverride` lets her
                // change a load, and a sentence that has been rewritten around
                // a number is a worse place to keep that number than a line
                // that simply reads it.
                Text(move.equipmentLabel)
                    .almanacLabel(secondary)
                Text(move.cue)
                    .font(.almanacBody)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // The form notes, one tap away and never in the way: the cue
                // is what she reads mid-set, the notes are what she reads
                // before the first one. Her ask — she is new to this and
                // has not been shown.
                if MoveForm.notes(for: move.name) != nil {
                    Button { formFor = move } label: {
                        Text("Form")
                            .almanacLabel(foreground, small: true)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .overlay(Rectangle().strokeBorder(secondary.opacity(0.6), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .accessibilityLabel("Form notes for \(move.name)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
    }

    /// Opening the form notes pauses the clock; closing them counts her back
    /// in. The pause is the engine's own, so a session that was already
    /// paused stays paused, and the count-in is skipped if she ends the
    /// session or opens the notes again before it finishes.
    private func formOpened(_ open: Bool) {
        if open {
            readyIn = nil
            pausedForForm = stage == .running && engine.status == .running
            if pausedForForm { engine.pause() }
            return
        }
        guard pausedForForm else { return }
        pausedForForm = false
        Task {
            for count in stride(from: 5, through: 1, by: -1) {
                guard stage == .running, formFor == nil, engine.status == .paused else {
                    readyIn = nil; return
                }
                readyIn = count
                Haptics.countdownTick()
                try? await Task.sleep(for: .seconds(1))
            }
            guard stage == .running, formFor == nil, engine.status == .paused else {
                readyIn = nil; return
            }
            readyIn = nil
            engine.resume()
            Haptics.resumed()
        }
    }

    /// The row `report()` wrote, so a count made after the ending lands on it
    /// rather than on a second record.
    @State private var recordedRun: RoutineRun?

    /// Files her counts against whatever this workout was recorded as.
    ///
    /// Called once at the ending and again whenever the last set is counted on
    /// the finish screen — the one set with no rest after it, and so the one
    /// set with nowhere to be counted during the workout.
    ///
    /// Deliberately *not* the thing that records the workout: that stays in
    /// `report()`, where the ending is detected, because a screen she dismisses
    /// quickly must never be what decides whether the session was written down.
    /// This only revisits a field on a row that already exists, so it is
    /// additive and safe to never run.
    private func applyReps() {
        let counts = countedReps
        guard counts.contains(where: { $0 > 0 }) else { return }
        var source: UUID?
        switch subject {
        case .session(let id):
            let wanted = FetchDescriptor<PlannedSession>(
                predicate: #Predicate { $0.id == id })
            (try? context.fetch(wanted))?.first?.repCounts = counts
            source = id
        default:
            recordedRun?.repCounts = counts
            source = recordedRun?.id
        }
        try? context.save()
        // And per move, which is the shape the history is read in. Rewritten
        // rather than appended, so counting the last set corrects this
        // session's rows instead of adding a second set of them.
        SetLogs.record(routine, reps: counts, durations: engine.setDurations,
                       sourceID: source, in: context)
    }

    /// Her counts laid out by set, zero where a set went uncounted — the shape
    /// `WhoopSummary` and the stored record both read.
    private var countedReps: [Int] {
        guard !reps.isEmpty else { return [] }
        return (0..<engine.schedule.workPhaseCount).map { reps[$0] ?? 0 }
    }

    /// The final set of the session, when there is one to count.
    private var lastSet: Int? {
        let count = engine.schedule.workPhaseCount
        guard count > 0, !engine.routine.moves.isEmpty else { return nil }
        return count - 1
    }

    private var lastWorkPhase: Phase? {
        engine.schedule.phases.last(where: \.isWork)
    }

    /// The set this rest follows, when the screen is resting after real work.
    /// Nil through the warm-up, through a set itself, and at the very end.
    private var restingAfterSet: Int? {
        guard let index = engine.currentIndex,
              engine.currentPhase?.isRest == true,
              let set = engine.schedule.setEnding(before: index)
        else { return nil }
        return set
    }

    /// What she just did, in her own number. Counting is hers — the app times
    /// the work and cannot see the reps — and Whoop wants sets and reps rather
    /// than intervals, which is what this is for.
    ///
    /// Named after the move it files to. The rest screen leads with the *next*
    /// move — its plate, its name, its cue — and an unlabelled stepper sitting
    /// under that block read as counting the move above it, when it counts the
    /// one she just put down. The finish screen's "Last set · Bicep curl"
    /// already solved this; same pattern here.
    private func repCounter(for set: Int, foreground: Color, secondary: Color) -> some View {
        let counted = reps[set] ?? 0
        let workPhases = engine.schedule.phases.filter(\.isWork)
        let phase = workPhases.indices.contains(set) ? workPhases[set] : nil
        let label = [phase?.move?.name, phase?.side, "reps just done"]
            .compactMap(\.self).joined(separator: " · ")
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).almanacLabel(secondary)
                Text(counted > 0 ? "\(counted)" : "—")
                    .font(Face.slab(30))
                    .tabular()
                    .foregroundStyle(foreground)
            }
            Spacer(minLength: 8)
            FieldButton(systemName: "minus", label: "One fewer rep",
                        foreground: foreground) {
                reps[set] = max((reps[set] ?? 0) - 1, 0)
                Haptics.transport()
            }
            FieldButton(systemName: "plus", label: "One more rep",
                        foreground: foreground) {
                // Opens at eight rather than one: a first press means "I did a
                // set", not "I did one rep", and eight is the middle of what
                // forty seconds of these moves comes to.
                reps[set] = (reps[set] ?? 7) + 1
                Haptics.transport()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reps just done")
        .accessibilityValue(counted > 0 ? "\(counted)" : "Not counted")
    }

    private func header(foreground: Color, secondary: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(positionLine)
                .almanacLabel(secondary)
                .tabular()
            Spacer()
            Text(engine.remainingInRoutine.durationString + " left")
                .almanacLabel(secondary)
                .tabular()
            // Cues sound through the silent switch, so the way to stop them has
            // to be here, during a session, and not only in settings.
            Button {
                soundEnabled.toggle()
                audio.isEnabled = soundEnabled
            } label: {
                Image(systemName: soundEnabled ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
            // "Sound on, button" reads as "this turns sound on". A label
        // names the control; a value names its state.
        .accessibilityLabel("Interval cues")
        .accessibilityValue(soundEnabled ? "On" : "Off")
            .accessibilityHint("Turns the interval cues on or off")
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    private func upNext(foreground: Color, secondary: Color) -> some View {
        Group {
            if let next = engine.nextPhase {
                VStack(spacing: 6) {
                    Rectangle()
                        .fill(secondary.opacity(0.35))
                        .frame(height: 1 / displayScale)
                    HStack {
                        Text("Next").almanacLabel(secondary)
                        Spacer()
                        Text(nextDescription(next))
                            .almanacLabel(secondary)
                            .tabular()
                    }
                }
            }
        }
    }

    private func transport(foreground: Color) -> some View {
        HStack(spacing: 22) {
            FieldButton(systemName: "stop", label: "End session", foreground: foreground) {
                engine.end(reason: .abandoned)
                dismiss()
            }
            // Nothing to pause or skip until the session is actually running —
            // and tapping pause during the lead-in would start the engine early,
            // out of step with the count on screen.
            if stage == .running {
                FieldButton(
                    systemName: engine.status == .running ? "pause.fill" : "play.fill",
                    prominent: true,
                    label: engine.status == .running ? "Pause" : "Resume",
                    foreground: foreground
                ) {
                    let wasRunning = engine.status == .running
                    engine.toggle()
                    wasRunning ? Haptics.paused() : Haptics.resumed()
                }
                if engine.currentPhase?.openEnded == true {
                    // Ending a set is the one thing she does during a rep
                    // session, so it is the prominent control while a set
                    // is open. Not a skip: the set she ended is a set she did.
                    FieldButton(systemName: "checkmark", prominent: true,
                                label: "Set done", foreground: foreground) {
                        engine.endSet()
                        Haptics.transport()
                    }
                } else {
                    FieldButton(systemName: "forward.end", label: "Skip this interval",
                                foreground: foreground) {
                        engine.skip()
                        Haptics.skipped()
                    }
                }
            }
        }
    }

    // MARK: - Copy

    /// The plate is a reminder of the shape, not something to watch.
    ///
    /// It retires partway through the interval for the reason she raised: the
    /// field's boundary sweeping down through a stick figure for the rest of
    /// the interval made the dissolve look wrong. How long it stays is hers
    /// now — `Tuning.plateSeconds`, ten by default. During rest it stays
    /// regardless: the whole point of rest is knowing what to set up next, and
    /// the field holds still there so there is no boundary to fight.
    private var showsPlate: Bool {
        guard let phase = engine.currentPhase else { return false }
        guard !phase.isRest else { return true }
        return engine.elapsed - phase.start < Double(Tuning.plateSeconds)
    }

    /// The lead-in counts in whole seconds; the session counts in its own clock.
    private var countString: String {
        if let readyIn { return "\(readyIn)" }
        guard stage == .running else { return "\(leadIn)" }
        // An open set counts up: the number is how long she has been
        // lifting, which is the tempo check, not how long until something
        // happens to her.
        if let phase = engine.currentPhase, phase.openEnded {
            return (engine.elapsed - phase.start).clockString
        }
        return engine.remainingInPhase.clockString
    }

    /// The work length is read from the phase, not assumed. The builder allows
    /// anything from ten seconds up to the ceiling, and a routine built at
    /// thirty used to announce "sixty" regardless.
    private var phaseCaption: String {
        if readyIn != nil { return "get set" }
        guard stage == .running else { return "find your position" }
        guard let phase = engine.currentPhase else { return "Finished" }
        switch phase.kind {
        // Never "left of forty seconds". The practice is timed so the session
        // moves along, not so she races it, and the caption is the one place
        // the screen can say which of those it means.
        case .flow: return engine.routine.roundCount > 0 ? "warm-up — take your time"
                                                     : "the practice — take your time"
        case .rest: return "rest — walk it off"
        case .work:
            if phase.openEnded {
                // One set of a move is a test: the count is the point, so
                // the instruction is the range's ceiling, not the range.
                return engine.routine.setsPerMove == 1
                    ? "one set — as many as you can, two short of failure"
                    : "\(phase.setLabel?.lowercased() ?? "set") — eight to twelve, two short of failure"
            }
            if engine.routine.mode == .emom {
                return "up to eight reps, then rest"
            }
            return "left of \(Int(phase.duration.rounded())) seconds"
        }
    }

    /// What this ending was recorded as, read from the subject rather than
    /// guessed from the shape. "One mark on the season" over a Timer-tab
    /// routine was the screen promising a mark the store rightly never wrote.
    private var completionRecordNote: String {
        if subject.recordedSource != nil { return "Kept with your own workouts." }
        return engine.routine.roundCount > 0
            ? "One mark on the season."
            : "Kept in the practice's own record."
    }

    private var positionLine: String {
        guard let phase = engine.currentPhase else {
            return "\(engine.routine.roundWord) \(engine.routine.roundCount) / \(engine.routine.roundCount)"
        }
        return phase.position(rounds: engine.routine.roundCount,
                              flowCount: engine.schedule.flowPhaseCount,
                              word: engine.routine.roundWord)
    }

    private var phaseWord: String {
        switch engine.currentPhase?.kind {
        case .flow: engine.routine.roundCount > 0 ? "Warm-up" : "Movement"
        case .rest: "Rest"
        case .work, nil: "Work"
        }
    }

    private var accessibilityCount: String {
        guard engine.currentPhase != nil else { return "Session complete" }
        let seconds = Int(engine.remainingInPhase.rounded(.up))
        return "\(phaseWord), \(seconds) seconds remaining"
    }

    /// A move-less work phase is a plain interval, not a rest — a timer-only
    /// routine used to announce every one of its work intervals as "Rest".
    private func nextDescription(_ phase: Phase) -> String {
        // A rest that knows what follows it is still a rest: naming the move
        // against the rest's length reads as a ninety-second set.
        if let move = phase.move, !phase.isRest {
            let side = phase.side.map { " · \($0.lowercased())" } ?? ""
            // An open set has no length to promise.
            if phase.openEnded { return "\(move.name)\(side) · \(phase.setLabel?.lowercased() ?? "set")" }
            return "\(move.name)\(side) · \(phase.duration.clockString)"
        }
        return phase.isRest ? "Rest \(phase.duration.clockString)"
                            : "Work \(phase.duration.clockString)"
    }
}

#Preview {
    WorkoutTimerView(routine: IntervalRoutine(
        name: "Beam & rings, steady",
        work: 60,
        rest: 45,
        rounds: 8,
        moves: [
            MoveLibrary.all[0],
            MoveLibrary.all[4],
            MoveLibrary.all[6]
        ]
    ))
}
