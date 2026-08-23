import SwiftUI
import SwiftData
import WatchKit

/// The field register, at watch size.
///
/// The same engine, the same schedule, the same two layers: the screen is oat,
/// a dark field rises from the bottom to the height of the time remaining in
/// the phase, and the count is drawn twice in identical layout — ink on oat,
/// then oat on field, the second masked to the field — so the boundary cuts
/// straight through the digits rather than stacking two halves of a numeral.
///
/// What the wrist drops is prose. There is no cue sentence, no plate, no Form
/// button and no sound: mid-set she reads the count, the move, the load and
/// what the big control does, and reading a sentence on a watch during a set
/// is a thing nobody does. What the wrist gains is the Digital Crown on the
/// rep stepper, which is the one input a watch has and a phone does not.
struct WatchTimerView: View {
    /// Where the session is in its own arrival.
    private enum Stage { case arriving, leadIn, running, ended }

    @State private var engine: IntervalEngine
    @State private var stage: Stage = .arriving
    /// Seconds left of the lead-in, shown in place of the count.
    @State private var leadIn = 3
    /// 0 while the ground is still down, 1 once it has risen.
    @State private var entryProgress: CGFloat = 0
    /// Reps she counted, by set — the work interval's ordinal in the schedule.
    /// Sparse on purpose: a set she did not count stays uncounted rather than
    /// being filled in with a plausible number.
    @State private var reps: [Int: Int] = [:]
    /// What the crown is turning. Mirrored into `reps` rather than bound
    /// straight to it: the crown is a Double, the record is a count, and the
    /// dictionary is sparse where the crown is not.
    @State private var crown: Double = 0
    /// The real beginning of the session, which a resumed one inherits.
    @State private var sessionStart: Date?
    /// One ending per session, however many places notice it.
    @State private var reported = false
    /// The row `report()` wrote, so a count made after the ending lands on it
    /// rather than on a second record.
    @State private var recordedRun: RoutineRun?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Always-on: the screen is dimmed and the watch is asleep on her wrist.
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    /// Needed because this screen records a finished routine itself — see
    /// `report()`.
    @Environment(\.modelContext) private var context

    private let routine: IntervalRoutine
    private let onEnd: (Outcome) -> Void
    /// Set when this screen is picking up a session the process died under.
    private let resuming: ActiveSession?
    /// What this run is, so an interruption can be resumed as the same thing.
    private let subject: ActiveSession.Subject

    /// What a finished session tells whoever presented it. A session run to
    /// the end carries its real bounds so it can be written back to Health;
    /// one that was walked away from carries nothing, because it earns
    /// nothing.
    enum Outcome {
        /// `skipped` travels with the ending so Today can ask about it.
        case completed(start: Date, end: Date, skipped: [String], reps: [Int])
        case abandoned(skipped: [String])
    }

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
                completion.transition(.opacity)
            } else {
                field
            }
        }
        .animation(.easeInOut(duration: 0.35), value: hasCompleted)
    }

    /// A session run to the end. Ending early dismisses instead — there is
    /// nothing to celebrate and nothing was earned.
    private var hasCompleted: Bool {
        engine.status == .finished && engine.endReason == .completed
    }

    /// What the screen says, from the one place both devices read it.
    private var face: TimerFace { TimerFace(engine: engine) }

    // MARK: - The field

    private var field: some View {
        GeometryReader { proxy in
            // The field rises from the physical bottom of the display and can
            // reach the physical top. `proxy` is inset by the safe area, so
            // both insets are added back to reach the glass; the field layer's
            // own content is padded by the same amounts so the two layers land
            // on top of each other to the pixel, which is what makes the
            // knockout a knockout rather than two drawings.
            let top = proxy.safeAreaInsets.top
            let bottom = proxy.safeAreaInsets.bottom
            let fullHeight = proxy.size.height + top + bottom

            ZStack(alignment: .bottom) {
                Palette.oat.ignoresSafeArea()

                // Base layer: everything as it reads on oat.
                content(foreground: Palette.ink, secondary: Palette.mute)

                if luminanceReduced {
                    // Always-on. A full dark field at half a frame a second is
                    // both wrong for the display and wrong for the room she is
                    // in; the boundary is the information, so the boundary is
                    // all that is drawn. The engine keeps time regardless —
                    // it derives everything from the wall clock.
                    Rectangle()
                        .fill(Palette.ink)
                        .frame(height: 1.5)
                        .offset(y: -(fieldHeight(in: fullHeight) - bottom))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else {
                    // Field layer: the same content, inverted, clipped to the
                    // draining block.
                    ZStack(alignment: .bottom) {
                        Palette.field
                        content(foreground: Palette.oat, secondary: Palette.sage)
                            .padding(.top, top)
                            .padding(.bottom, bottom)
                    }
                    .frame(height: fullHeight)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: fieldHeight(in: fullHeight))
                    }
                    // No implicit animation on this layer. The phone smooths
                    // the boundary with a fifty-millisecond linear animation,
                    // and on the wrist that animated the *count* too: the
                    // masked copy cross-faded from 0:04 to 0:03 while the copy
                    // beneath it changed at once, so the knockout showed two
                    // digits at the same time. The engine already refreshes at
                    // 20 Hz, which is a smooth enough boundary without it.
                    //
                    // Both insets are taken back out of the *layout*, so this
                    // layer asks the stack for exactly the height the screen
                    // has and the base content is not pushed off the bottom by
                    // its own inverted copy. It still draws to both edges: the
                    // bottom padding places it, the bottom alignment holds it
                    // there, and the top simply overhangs.
                    .padding(.bottom, -bottom)
                    .padding(.top, -top)
                    // Purely a visual duplicate of the layer beneath. `mask`
                    // clips pixels but does not prune the accessibility tree,
                    // so without this VoiceOver reads the whole screen twice.
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
        }
        // The crown counts the set she has just finished. Focus is claimed
        // only while there is a set to count, so it is not competing with the
        // scroll of anything else for the rest of the session.
        .focusable(restingAfterSet != nil)
        .digitalCrownRotation($crown, from: 0, through: 99, by: 1,
                              sensitivity: .low, isContinuous: false,
                              isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, turned in
            guard let set = restingAfterSet else { return }
            let counted = max(0, Int(turned.rounded()))
            guard counted != (reps[set] ?? 0) else { return }
            reps[set] = counted
        }
        // A new rest is a new set to count, and the crown starts where that
        // set already stands rather than where the last one was left.
        .onChange(of: restingAfterSet) { _, set in
            crown = Double(set.flatMap { reps[$0] } ?? 0)
        }
        .onAppear {
            // Set before anything can start, and read from the engine rather
            // than from a view modifier: finishing removes this view in the
            // same update that ends the session, so a handler living on it
            // never runs. See `IntervalEngine.onEnded`, and the bug shape in
            // CLAUDE.md that it exists to close.
            engine.onEnded = { _ in report() }
            guard stage == .arriving else { return }
            Task { await beginSession() }
        }
        .onDisappear {
            // Also ends the lead-in: its loop checks the stage between ticks.
            stage = .ended
            engine.pause()
        }
        .onChange(of: engine.currentPhase) { _, _ in persist() }
        .onChange(of: engine.status) { _, status in
            // Deliberately not the place the ending is reported from. This
            // handler only runs while the field is on screen, which a finished
            // session is not — `engine.onEnded` carries the ending.
            guard status != .finished else { return }
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
        // Coming back from the wrist-down state recomputes from the clock
        // rather than resuming a stale count.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { engine.refresh() } else { persist() }
        }
    }

    /// The field fills from the bottom in proportion to time left in the
    /// phase. During rest it is deliberately still — resting is not a
    /// countdown you should feel chased by, so it holds at full height and
    /// only the digits move. The same policy as `WorkoutTimerView.fieldHeight`,
    /// clause for clause, because the two devices are one session.
    private func fieldHeight(in total: CGFloat) -> CGFloat {
        // Rising, or held full through the lead-in while she gets set.
        guard stage == .running else { return total * entryProgress }
        guard let phase = engine.currentPhase else { return total }
        guard phase.isWork else { return total }
        // A rep set is open until she ends it. A boundary sweeping toward a
        // ninety-second net would be a clock that means nothing.
        guard !phase.openEnded else { return total }
        // Under Reduce Motion the field holds still through work, exactly as
        // it already does through rest.
        guard !reduceMotion else { return total }
        return total * CGFloat(engine.phaseRemainingFraction)
    }

    // MARK: - Content

    private func content(foreground: Color, secondary: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(foreground: foreground, secondary: secondary)

            // The count and the move sit between the header and the
            // transport rather than stacked against the top. Two reasons, and
            // the second is the lane's: a 46mm face is 248 points tall, so the
            // boundary crosses the whole screen in one interval — parked under
            // the header, the digits were cut in the first ten seconds and the
            // remaining thirty were a dark rectangle with a number in the
            // corner. Centred, the knockout happens around the middle of the
            // interval, which is when she actually looks.
            Spacer(minLength: 0)

            Text(countString)
                .font(.almanacCount(countSize))
                .tracking(-1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(face.phaseWord)
                .accessibilityValue(accessibilityCount)
                .accessibilityAddTraits(.updatesFrequently)

            moveBlock(foreground: foreground, secondary: secondary)

            Spacer(minLength: 0)

            // Counting the set she has just finished, during the rest that
            // follows it — the one moment she is standing still and it is
            // still fresh.
            if let set = restingAfterSet {
                repCounter(for: set, foreground: foreground, secondary: secondary)
                    .padding(.bottom, 4)
            }

            transport(foreground: foreground)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private func header(foreground: Color, secondary: Color) -> some View {
        HStack(spacing: 5) {
            // Saffron means live, and a running work interval is the one live
            // thing on this screen.
            if engine.currentPhase?.isWork == true, engine.status == .running,
               stage == .running {
                Rectangle()
                    .fill(Palette.saffron)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(positionLine)
                .almanacLabel(secondary, small: true)
                .tabular()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    /// The move, or on a rest the one thing rest is for: what to set up next.
    @ViewBuilder
    private func moveBlock(foreground: Color, secondary: Color) -> some View {
        if let phase = engine.currentPhase, let move = phase.move, !phase.isRest {
            VStack(alignment: .leading, spacing: 1) {
                if let eyebrow = phase.isFlow ? face.phaseWord : phase.side {
                    Text(eyebrow).almanacLabel(secondary, small: true).lineLimit(1)
                }
                Text(move.name)
                    .font(Face.slab(15))
                    .foregroundStyle(foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                // What to pick up, on the one screen where she is picking it
                // up. The load is a fact the app knows, not a sentence it
                // happens to print, so it is read rather than quoted.
                Text(move.equipmentLabel)
                    .almanacLabel(secondary, small: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let next = engine.nextPhase, let move = next.move {
            VStack(alignment: .leading, spacing: 1) {
                Text(next.isFlow && engine.routine.roundCount > 0
                     ? "Warm-up next"
                     : next.side.map { "Next up · \($0.lowercased())" } ?? "Next up")
                    .almanacLabel(secondary, small: true)
                    .lineLimit(1)
                Text(move.name)
                    .font(Face.slab(15))
                    .foregroundStyle(foreground)
                    .lineLimit(restingAfterSet == nil ? 2 : 1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What she just did, in her own number. Named after the move it files to,
    /// because the block above it names the *next* move and an unlabelled
    /// stepper under that reads as counting the wrong one.
    private func repCounter(for set: Int, foreground: Color, secondary: Color) -> some View {
        let counted = reps[set] ?? 0
        let workPhases = engine.schedule.phases.filter(\.isWork)
        let phase = workPhases.indices.contains(set) ? workPhases[set] : nil
        // Named after the move it files to, and the unit said once beside
        // the number rather than tacked onto a label that then has to
        // truncate: "BEAM FRONT SQUAT" over "8 REPS" fits a 46mm face where
        // "BEAM FRONT SQUAT · REPS" did not.
        let label = [phase?.move?.name, phase?.side]
            .compactMap(\.self).joined(separator: " · ")
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .almanacLabel(secondary, small: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(counted > 0 ? "\(counted)" : "—")
                        .font(Face.slab(19))
                        .tabular()
                        .foregroundStyle(foreground)
                    Text("reps").almanacLabel(secondary, small: true)
                }
            }
            Spacer(minLength: 2)
            WatchFieldButton(systemName: "minus", label: "One fewer rep",
                             foreground: foreground) {
                reps[set] = max((reps[set] ?? 0) - 1, 0)
                crown = Double(reps[set] ?? 0)
                WatchHaptics.transport()
            }
            WatchFieldButton(systemName: "plus", label: "One more rep",
                             foreground: foreground) {
                // Opens at eight rather than one: a first press means "I did a
                // set", not "I did one rep".
                reps[set] = (reps[set] ?? 7) + 1
                crown = Double(reps[set] ?? 0)
                WatchHaptics.transport()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reps just done")
        .accessibilityValue(counted > 0 ? "\(counted)" : "Not counted")
    }

    private func transport(foreground: Color) -> some View {
        HStack(spacing: 8) {
            WatchFieldButton(systemName: "stop", label: "End session",
                             foreground: foreground) {
                engine.end(reason: .abandoned)
                dismiss()
            }
            // Nothing to pause or skip until the session is actually running —
            // and tapping pause during the lead-in would start the engine
            // early, out of step with the count on screen.
            if stage == .running {
                WatchFieldButton(
                    systemName: engine.status == .running ? "pause.fill" : "play.fill",
                    prominent: true,
                    label: engine.status == .running ? "Pause" : "Resume",
                    foreground: foreground
                ) {
                    let wasRunning = engine.status == .running
                    engine.toggle()
                    wasRunning ? WatchHaptics.paused() : WatchHaptics.resumed()
                }
                if face.control == .done {
                    // Ending a set is the one thing she does during a rep
                    // session, so it is the prominent control while a set is
                    // open. Not a skip: the set she ended is a set she did.
                    WatchFieldButton(systemName: "checkmark", prominent: true,
                                     label: "Set done", foreground: foreground) {
                        engine.endSet()
                        WatchHaptics.transport()
                    }
                } else {
                    WatchFieldButton(systemName: "forward.end",
                                     label: "Skip this interval",
                                     foreground: foreground) {
                        engine.skip()
                        WatchHaptics.skipped()
                    }
                }
            }
        }
    }

    // MARK: - Completion

    /// What a finished session looks like. It states what happened and stops:
    /// no congratulation, no score, no prompt to go again.
    private var completion: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(routine.name)
                    .almanacLabel(Palette.mute, small: true)
                    .lineLimit(2)

                Text(completionHeadline)
                    .font(.almanacHeading)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)

                // A mark is a finished *session*. The practice keeps its own
                // record and deliberately earns none, so claiming one here
                // would be the wrist contradicting the season it points at.
                Text(completionRecordNote)
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.mute)
                    .padding(.top, 5)

                // The last set has no rest after it, so it is the one set that
                // could not be counted while she was working. Asked for here,
                // once, rather than left as the gap in every list she pastes.
                if let set = lastSet, let phase = lastWorkPhase, let move = phase.move {
                    VStack(alignment: .leading, spacing: 4) {
                        Text([("Last set"), move.name, phase.side]
                            .compactMap { $0 }.joined(separator: " · "))
                            .almanacLabel(Palette.mute, small: true)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(reps[set].map(String.init) ?? "—")
                                .font(Face.slab(19))
                                .tabular()
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 2)
                            WatchFieldButton(systemName: "minus", label: "One fewer rep",
                                             foreground: Palette.ink) {
                                reps[set] = max((reps[set] ?? 0) - 1, 0)
                                applyReps()
                                WatchHaptics.transport()
                            }
                            WatchFieldButton(systemName: "plus", label: "One more rep",
                                             foreground: Palette.ink) {
                                reps[set] = (reps[set] ?? 7) + 1
                                applyReps()
                                WatchHaptics.transport()
                            }
                        }
                    }
                    .padding(.top, 12)
                    .accessibilityElement(children: .contain)
                }

                // The lane's primary control, not watchOS's: a filled ink
                // rectangle with oat type, square-cornered like everything
                // else in the Almanac. The system's tinted capsule read as a
                // control borrowed from another app.
                Button { dismiss() } label: {
                    Text("Done")
                        .font(.almanacButton)
                        .foregroundStyle(Palette.oat)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Palette.ink)
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.oat.ignoresSafeArea())
    }

    /// Spelled out, because this line is read once and read properly.
    private var completionHeadline: String {
        let spell = NumberFormatter()
        spell.numberStyle = .spellOut
        func word(_ n: Int) -> String { spell.string(from: NSNumber(value: n)) ?? "\(n)" }
        func sentence(_ n: Int, _ singular: String, _ plural: String) -> String {
            "\(word(n).capitalized) \(n == 1 ? singular : plural)."
        }
        let rounds = engine.routine.roundCount
        let minutes = Int((engine.schedule.total / 60).rounded())
        guard minutes >= 1 else {
            let seconds = Int(engine.schedule.total.rounded())
            return sentence(rounds, "round", "rounds") + " "
                 + sentence(seconds, "second", "seconds")
        }
        return sentence(rounds, "round", "rounds") + " "
             + sentence(minutes, "minute", "minutes")
    }

    /// What this ending was recorded as, read from the subject rather than
    /// guessed from the shape.
    private var completionRecordNote: String {
        if subject.recordedSource != nil { return "Kept with your own workouts." }
        return engine.routine.roundCount > 0
            ? "One mark on the season."
            : "Kept in the practice's own record."
    }

    // MARK: - Arrival

    /// The way in. The ground rises through a document that does not move,
    /// inverting the numeral as it passes, and then three seconds to get into
    /// position — counted in the same ticks that will later mark the end of a
    /// round, because the motif is the point: dry ascending taps always mean
    /// *a boundary is three seconds away*.
    private func beginSession() async {
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: reduceMotion ? 0 : 0.45)) {
            entryProgress = 1
        }
        WatchHaptics.prepare()
        if !reduceMotion {
            try? await Task.sleep(for: .milliseconds(450))
        }

        // A resumed session skips the lead-in. Three seconds to get into
        // position is for the start of a workout; she is already mid-round.
        if let resuming {
            // Re-checked here, not only where the card was built: a running
            // session's clock keeps moving while the card sits on screen, and
            // one with nothing left to run must be discarded rather than
            // replayed from round one under its original start date.
            guard !resuming.ranOut(), !resuming.isStale() else {
                stage = .ended
                ActiveSessionStore.clear()
                dismiss()
                return
            }
            sessionStart = resuming.startedAt
            stage = .running
            bindCues()
            engine.restore(to: resuming.elapsedNow(), running: resuming.running)
            return
        }

        stage = .leadIn
        for count in stride(from: 3, through: 1, by: -1) {
            guard stage == .leadIn else { return }   // dismissed mid-lead-in
            leadIn = count
            WatchHaptics.countdownTick()
            try? await Task.sleep(for: .seconds(1))
        }
        guard stage == .leadIn else { return }

        stage = .running
        sessionStart = .now
        bindCues()
        engine.start()
        persist()
    }

    /// Everything that hangs off the engine's callbacks, in one named place.
    ///
    /// The cues are here today. The workout session and the link to the phone
    /// arrive in integration and belong here too — one function that owns the
    /// engine's single-assignment closures, so nothing downstream has to
    /// discover that assigning `onPhaseChange` silently unhooks the haptics.
    /// `onEnded` is deliberately **not** here: it is set in `onAppear`, before
    /// anything can start, so recording can never depend on this having run.
    private func bindCues() {
        WatchSessionCues().bind(to: engine)
    }

    /// Write down where the session is, so it survives the process dying.
    ///
    /// Cheap enough to do often: a routine and two dates. Called at every
    /// phase boundary, every transport change, and on a slow timer, because a
    /// force-quit gives no warning at all. The owner is the watch — this
    /// screen is where `engine.start()` was called, and the owner is the
    /// device that records.
    private func persist() {
        guard stage == .running, engine.status != .finished else { return }
        var session = ActiveSession(routine: routine,
                                    startedAt: sessionStart ?? .now,
                                    elapsed: engine.elapsed,
                                    running: engine.status == .running,
                                    savedAt: .now)
        session.setSubject(subject)
        session.owner = .watch
        ActiveSessionStore.save(session)
    }

    // MARK: - Recording

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
        guard engine.endReason == .completed,
              let start = sessionStart ?? engine.startDate else {
            onEnd(.abandoned(skipped: engine.skippedMoves))
            return
        }
        // Capped at the routine's own length rather than reported as `.now`.
        // Wall-clock includes pauses and any time the app was suspended before
        // it noticed it had finished; the floor is the same guard from the
        // other direction, since skipping to the end is a real ending.
        let end = min(.now, start.addingTimeInterval(engine.schedule.total))

        // Recorded here, by the screen that knows the workout finished, rather
        // than by whoever presented it — and by the **owner**: this device
        // called `engine.start()`, so this device writes the record, once.
        //
        // A planned session is not recorded here: it earns a mark, which needs
        // the session row, which only the presenter has.
        if let source = subject.recordedSource {
            recordedRun = RoutineRuns.record(routine, source: source,
                                             seconds: end.timeIntervalSince(start),
                                             reps: countedReps, in: context)
        }
        applyReps()

        onEnd(.completed(start: start, end: end, skipped: engine.skippedMoves,
                         reps: countedReps))
    }

    /// Files her counts against whatever this workout was recorded as.
    ///
    /// Deliberately *not* the thing that records the workout: that stays in
    /// `report()`, where the ending is detected, because a screen she
    /// dismisses quickly must never be what decides whether the session was
    /// written down. This only revisits fields on rows that already exist, so
    /// it is additive and safe to never run.
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

    // MARK: - Copy

    /// The lead-in counts in whole seconds; the session counts in `TimerFace`,
    /// which is the phone's clock too.
    private var countString: String {
        guard stage == .running else { return "\(leadIn)" }
        return face.countString
    }

    private var positionLine: String {
        guard stage == .running else { return "Find your position" }
        return face.positionLine
    }

    /// As large as the face allows, and no larger. The rest phase carries a
    /// stepper and a next-up line under the same count, so it gives up the
    /// height the stepper needs rather than pushing the transport off screen.
    private var countSize: CGFloat {
        if restingAfterSet != nil { return 34 }
        return engine.currentPhase?.isRest == true ? 42 : 50
    }

    private var accessibilityCount: String {
        guard engine.currentPhase != nil else { return "Session complete" }
        let seconds = Int(engine.remainingInPhase.rounded(.up))
        return "\(face.phaseWord), \(seconds) seconds remaining"
    }
}

/// A control for the field register at watch size — the phone's `FieldButton`,
/// which lives in the app target, at the sizes a 46mm face has room for.
///
/// Outlined at every prominence, in the register's own colour: it is drawn in
/// both layers of the knockout, so it cannot assume the dark ground.
private struct WatchFieldButton: View {
    let systemName: String
    var prominent = false
    var label: String
    var foreground: Color = Palette.oat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: prominent ? 15 : 12, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: prominent ? 40 : 32, height: prominent ? 34 : 30)
                .background {
                    Circle().strokeBorder(foreground.opacity(prominent ? 0.70 : 0.45),
                                          lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
