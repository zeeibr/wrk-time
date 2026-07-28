import SwiftUI

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
    @State private var liveActivity = LiveActivityController()
    @State private var audio = SessionAudio()
    /// Persisted, because `.playback` sounds through the silent switch and the
    /// way to stop that has to be findable twice, not once.
    @AppStorage("cueSoundEnabled") private var soundEnabled = true
    @State private var stage: Stage = .arriving
    /// Seconds left of the lead-in, shown in place of the count.
    @State private var leadIn = 3
    /// 0 while the ground is still down, 1 once it has risen.
    @State private var entryProgress: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    private let routine: IntervalRoutine
    private let onEnd: (Outcome) -> Void

    /// What a finished session tells whoever presented it. A session run to the
    /// end carries its real bounds so it can be written back to Health; one
    /// that was walked away from carries nothing, because it earns nothing.
    enum Outcome {
        /// `skipped` travels with the ending so Today can ask about it. It is
        /// carried on both cases: a session she bailed out of has just as much
        /// to say about which move drove her out.
        case completed(start: Date, end: Date, skipped: [String])
        case abandoned(skipped: [String])
    }

    /// Set when this screen is picking up a session the process died under.
    private let resuming: ActiveSession?
    /// The real beginning of the session, which a resumed one inherits rather
    /// than restarting — so what is written back to Health is when she actually
    /// started, not when the app came back.
    @State private var sessionStart: Date?

    init(routine: IntervalRoutine,
         resuming: ActiveSession? = nil,
         onEnd: @escaping (Outcome) -> Void = { _ in }) {
        self.routine = routine
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
        ActiveSessionStore.save(
            ActiveSession(routine: routine,
                          startedAt: sessionStart ?? .now,
                          elapsed: engine.elapsed,
                          running: engine.status == .running,
                          savedAt: .now)
        )
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
                content(foreground: Palette.ink, secondary: Palette.mute,
                        countOffset: countRide(in: fullHeight))

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
        .onAppear {
            // The phone spends the session on the floor, untouched. Without
            // this the display locks during the first round and takes the
            // field register, the count and the cues with it.
            UIApplication.shared.isIdleTimerDisabled = true
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
            if status == .finished {
                liveActivity.end()
                report()
            } else {
                persist()
                // Pausing and resuming are phase-silent, so the lock screen
                // would otherwise keep counting down a stopped workout.
                liveActivity.update(engine: engine)
            }
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
        case .work: "Work. \(seconds) seconds."
        case .rest: "Rest. \(seconds) seconds."
        }
        AccessibilityNotification.Announcement(words).post()
    }

    /// Report the ending exactly once, with its real bounds. Only a session
    /// run to the end has bounds worth writing back.
    private func report() {
        // Either way the session is over, so the stored copy goes — it exists
        // only to survive a crash, never to outlive an ending.
        ActiveSessionStore.clear()
        guard engine.endReason == .completed, let start = sessionStart ?? engine.startDate else {
            onEnd(.abandoned(skipped: engine.skippedMoves))
            return
        }
        onEnd(.completed(start: start, end: .now, skipped: engine.skippedMoves))
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
        let lowestCentre = total * 0.55
        return min(max(boundary, opticalCentre), lowestCentre) - opticalCentre
    }

    // MARK: - Content

    private func content(foreground: Color, secondary: Color,
                         countOffset: CGFloat) -> some View {
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

                Text(phaseCaption)
                    .almanacLabel(secondary)
            }
            .padding(.horizontal, 22)
            // Both layers take the same offset, so the two copies stay in the
            // pixel agreement the knockout depends on.
            .offset(y: countOffset)

            Spacer(minLength: 12)

            // Rest used to leave the middle of the screen empty and put the one
            // thing rest is for — knowing what to set up next — in a ten point
            // line at the very bottom. It gets the same billing as the current
            // move instead.
            if let phase = engine.currentPhase, let move = phase.move {
                moveBlock(move, eyebrow: phase.isFlow ? phaseWord : nil,
                          foreground: foreground, secondary: secondary)
            } else if let next = engine.nextPhase, let move = next.move {
                moveBlock(move, eyebrow: next.isFlow && engine.routine.roundCount > 0
                                          ? "Warm-up next" : "Next up",
                          foreground: foreground, secondary: secondary)
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

            Text("One mark on the season.")
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
                Text(move.cue)
                    .font(.almanacBody)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
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
            .accessibilityLabel(soundEnabled ? "Sound on" : "Sound off")
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
                FieldButton(systemName: "forward.end", label: "Skip this interval",
                            foreground: foreground) {
                    engine.skip()
                    Haptics.skipped()
                }
            }
        }
    }

    // MARK: - Copy

    /// How long a plate stays up at the start of a phase.
    static let plateSeconds: TimeInterval = 5

    /// The plate is a reminder of the shape, not something to watch.
    ///
    /// It retires after five seconds, for two reasons. By then she has looked
    /// at it and is moving, and — the reason she raised it — the field's
    /// boundary sweeping down through a stick figure for the rest of the
    /// interval made the dissolve look wrong. During rest it stays: the whole
    /// point of rest is knowing what to set up next, and the field holds still
    /// there so there is no boundary to fight.
    private var showsPlate: Bool {
        guard let phase = engine.currentPhase else { return false }
        guard !phase.isRest else { return true }
        return engine.elapsed - phase.start < Self.plateSeconds
    }

    /// The lead-in counts in whole seconds; the session counts in its own clock.
    private var countString: String {
        stage == .running ? engine.remainingInPhase.clockString : "\(leadIn)"
    }

    /// The work length is read from the phase, not assumed. The builder allows
    /// anything from ten seconds up to the ceiling, and a routine built at
    /// thirty used to announce "sixty" regardless.
    private var phaseCaption: String {
        guard stage == .running else { return "find your position" }
        guard let phase = engine.currentPhase else { return "Finished" }
        switch phase.kind {
        // Never "left of forty seconds". The practice is timed so the session
        // moves along, not so she races it, and the caption is the one place
        // the screen can say which of those it means.
        case .flow: return engine.routine.roundCount > 0 ? "warm-up — take your time"
                                                     : "the practice — take your time"
        case .rest: return "rest — walk it off"
        case .work: return "left of \(Int(phase.duration.rounded())) seconds"
        }
    }

    private var positionLine: String {
        guard let phase = engine.currentPhase else {
            return "Round \(engine.routine.roundCount) / \(engine.routine.roundCount)"
        }
        return phase.position(rounds: engine.routine.roundCount,
                              flowCount: engine.schedule.flowPhaseCount)
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
        if let move = phase.move {
            return "\(move.name) · \(phase.duration.clockString)"
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
