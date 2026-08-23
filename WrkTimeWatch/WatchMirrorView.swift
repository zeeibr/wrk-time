import SwiftUI

/// A phone-owned session, watched from the wrist.
///
/// A mirror is not a timer that happens to be quiet — it is a different
/// thing, and keeping it a separate view is what keeps the difference
/// honest. The engine here is a local copy restored from the owner's
/// announcements and read for display only: its `onEnded` is never set, its
/// transport is never driven by a tap, and nothing on this screen can write
/// a record. Every control speaks to the phone instead — `.transport` for
/// the buttons, `.reps` for the stepper — and what the screen shows is
/// whatever the owner last said, run forward by the local clock between
/// announcements (the engine derives state from wall-clock elapsed, so a
/// mirror stays smooth on one message per phase).
///
/// The phone going quiet mid-session is shown, not guessed at: after a
/// stretch with no announcement the screen says so and offers to leave.
struct WatchMirrorView: View {
    @State private var engine: IntervalEngine
    @State private var link = SessionLink.shared
    /// Reps counted here, mirrored locally so the stepper reads back what
    /// she turned; the owner's dictionary is the one that files them.
    @State private var reps: [Int: Int] = [:]
    @State private var crown: Double = 0
    /// When the owner last spoke, for the gone-quiet notice.
    @State private var lastHeard: Date = .now
    @State private var ended = false
    @Environment(\.dismiss) private var dismiss

    private let session: ActiveSession

    init(session: ActiveSession) {
        self.session = session
        _engine = State(initialValue: IntervalEngine(routine: session.routine))
    }

    private var face: TimerFace {
        TimerFace(routine: engine.routine, schedule: engine.schedule,
                  phase: engine.currentPhase, elapsed: engine.elapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if engine.currentPhase?.isWork == true, engine.status == .running {
                    Rectangle().fill(Palette.saffron).frame(width: 7, height: 7)
                }
                Text(face.positionLine)
                    .font(Face.mono(12))
                    .foregroundStyle(Palette.sage)
                    .tabular()
                Spacer()
            }
            Text(face.countString)
                .font(Face.slab(52))
                .tabular()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(Palette.oat)
            if let move = engine.currentPhase?.move, engine.currentPhase?.isRest == false {
                Text(move.name)
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.oat)
                    .lineLimit(2)
            } else if let next = engine.nextPhase?.move {
                Text("Next up")
                    .font(Face.mono(11))
                    .foregroundStyle(Palette.sage)
                Text(next.name)
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.oat)
                    .lineLimit(2)
            }
            Text("On your phone")
                .font(Face.mono(11))
                .foregroundStyle(Palette.sage)
                .padding(.top, 2)

            if quiet {
                Text("The phone has gone quiet. It may have finished without saying so.")
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.sage)
            }

            Spacer(minLength: 4)

            if let set = restingAfterSet {
                stepper(for: set)
            }

            transport
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.field.ignoresSafeArea())
        .focusable(true)
        .digitalCrownRotation($crown, from: 0, through: 50, by: 1,
                              sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, turned in
            guard let set = restingAfterSet else { return }
            let count = max(0, Int(turned.rounded()))
            guard count != reps[set] else { return }
            reps[set] = count
            link.send(.reps(setOrdinal: set, count: count))
        }
        .onChange(of: restingAfterSet) { _, set in
            crown = Double(set.flatMap { reps[$0] } ?? 0)
        }
        .onAppear {
            link.onMessage = { message in handle(message) }
            // Whatever the row was built from is a start; the owner's answer
            // replaces it within a message.
            apply(session)
            link.send(.whatIsRunning)
        }
        .onDisappear {
            engine.pause()
            link.onMessage = nil
        }
    }

    /// Nothing heard for two phases' worth of a long interval. The engine
    /// keeps counting regardless — it is wall-clock — so the screen stays
    /// plausible; the notice is the honesty.
    private var quiet: Bool {
        Date.now.timeIntervalSince(lastHeard) > 150 && !ended
    }

    private var restingAfterSet: Int? {
        guard let index = engine.currentIndex,
              engine.currentPhase?.isRest == true,
              let set = engine.schedule.setEnding(before: index)
        else { return nil }
        return set
    }

    private func stepper(for set: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Reps just done")
                    .font(Face.mono(10))
                    .foregroundStyle(Palette.sage)
                Text(reps[set].map(String.init) ?? "—")
                    .font(Face.slab(24))
                    .tabular()
                    .foregroundStyle(Palette.oat)
            }
            Spacer()
            Button {
                send(reps: max((reps[set] ?? 0) - 1, 0), for: set)
            } label: { Image(systemName: "minus") }
            .buttonStyle(.plain)
            .frame(width: 34, height: 34)
            .overlay(Circle().stroke(Palette.oat.opacity(0.5), lineWidth: 1))
            Button {
                send(reps: (reps[set] ?? 7) + 1, for: set)
            } label: { Image(systemName: "plus") }
            .buttonStyle(.plain)
            .frame(width: 34, height: 34)
            .overlay(Circle().stroke(Palette.oat.opacity(0.5), lineWidth: 1))
        }
        .foregroundStyle(Palette.oat)
    }

    private func send(reps count: Int, for set: Int) {
        reps[set] = count
        crown = Double(count)
        link.send(.reps(setOrdinal: set, count: count))
        WatchHaptics.transport()
    }

    private var transport: some View {
        HStack(spacing: 14) {
            // No stop on a mirror. Ending the phone's session from the wrist
            // is a bigger decision than a watch button should carry; leaving
            // the mirror is what this screen offers.
            Button {
                let action: TransportAction = engine.status == .running ? .pause : .resume
                link.send(.transport(action))
                WatchHaptics.transport()
                // Reflected locally at once; the owner's next announcement
                // corrects any disagreement.
                engine.toggle()
            } label: {
                Image(systemName: engine.status == .running ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.plain)
            .frame(width: 40, height: 40)
            .overlay(Circle().stroke(Palette.oat.opacity(0.7), lineWidth: 1.1))

            Button {
                link.send(.transport(face.isOpenSet ? .endSet : .skip))
                WatchHaptics.transport()
            } label: {
                Image(systemName: face.isOpenSet ? "checkmark" : "forward.end")
            }
            .buttonStyle(.plain)
            .frame(width: 40, height: 40)
            .overlay(Circle().stroke(Palette.oat.opacity(0.7), lineWidth: 1.1))
        }
        .foregroundStyle(Palette.oat)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
    }

    private func handle(_ message: SessionLinkMessage) {
        switch message {
        case .running(let session, owner: .phone):
            lastHeard = .now
            apply(session)
        case .ended:
            lastHeard = .now
            ended = true
            dismiss()
        case .running, .reps, .transport, .whatIsRunning:
            // A mirror acts on nothing else. Counts and transport belong to
            // the owner; a watch-owned .running means this screen should not
            // be up at all.
            break
        }
    }

    /// Place the local engine where the owner says the session is. Restore,
    /// not start: a mirror engine has no `onEnded` and records nothing, and
    /// restore is cheap because the engine derives everything from the clock.
    private func apply(_ session: ActiveSession) {
        engine.restore(to: session.elapsedNow(), running: session.running)
    }
}
