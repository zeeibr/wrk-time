import SwiftUI

/// The field register.
///
/// The screen is oat, and a dark field rises from the bottom to the height of
/// the time remaining in the phase. The count is drawn twice in identical
/// layout — ink on oat, then oat on field, the second masked to the field —
/// so the boundary cuts straight through the digits and the numeral stays one
/// continuous form rather than two stacked halves.
struct WorkoutTimerView: View {
    @State private var engine: IntervalEngine
    @State private var liveActivity = LiveActivityController()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    private let routine: IntervalRoutine

    init(routine: IntervalRoutine) {
        self.routine = routine
        _engine = State(initialValue: IntervalEngine(routine: routine))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Palette.oat.ignoresSafeArea()

                // Base layer: everything as it reads on oat.
                content(foreground: Palette.ink, secondary: Palette.mute)

                // Field layer: the same content, inverted, clipped to the
                // draining block. Identical layout is what makes the knockout
                // work — the two layers must agree to the pixel.
                ZStack(alignment: .bottom) {
                    Palette.field.ignoresSafeArea(edges: .bottom)
                    content(foreground: Palette.oat, secondary: Palette.sage)
                }
                .mask(alignment: .bottom) {
                    Rectangle()
                        .frame(height: fieldHeight(in: proxy.size.height))
                        .ignoresSafeArea(edges: .bottom)
                }
                .animation(.linear(duration: 0.05), value: engine.elapsed)
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.light)
        .onAppear {
            Haptics.bind(to: engine)
            engine.start()
            liveActivity.start(routine: routine, engine: engine)
        }
        .onDisappear {
            engine.pause()
            liveActivity.end()
        }
        // One Live Activity update per phase, not per second — the widget
        // renders its own countdown from the phase bounds.
        .onChange(of: engine.currentPhase) { _, _ in
            liveActivity.update(engine: engine)
        }
        // Returning from the background recomputes from the clock rather than
        // resuming a stale count.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { engine.refresh() }
        }
        .onChange(of: engine.status) { _, status in
            if status == .finished { liveActivity.end() }
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    /// The field fills from the bottom in proportion to time left in the phase.
    /// During rest it is deliberately still — resting is not a countdown you
    /// should feel chased by, so it holds at full height and only the digits
    /// move.
    private func fieldHeight(in total: CGFloat) -> CGFloat {
        guard let phase = engine.currentPhase else { return total }
        guard phase.isWork else { return total }
        return total * CGFloat(engine.phaseRemainingFraction)
    }

    // MARK: - Content

    private func content(foreground: Color, secondary: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(foreground: foreground, secondary: secondary)

            Text(engine.remainingInPhase.clockString)
                .font(.almanacCount(112))
                .tracking(-5)
                .foregroundStyle(foreground)
                .padding(.top, 6)
                .padding(.horizontal, 22)
                .accessibilityLabel(accessibilityCount)

            Text(phaseCaption)
                .almanacLabel(secondary)
                .padding(.horizontal, 22)

            Spacer(minLength: 12)

            if let move = engine.currentPhase?.move {
                VStack(alignment: .leading, spacing: 6) {
                    Text(move.name)
                        .font(Face.slab(30))
                        .foregroundStyle(foreground)
                    Text(move.cue)
                        .font(.almanacBody)
                        .foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    private func header(foreground: Color, secondary: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Round \(engine.currentPhase?.round ?? engine.routine.rounds) / \(engine.routine.rounds)")
                .almanacLabel(secondary)
                .tabular()
            Spacer()
            Text(engine.remainingInRoutine.durationString + " left")
                .almanacLabel(secondary)
                .tabular()
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
            FieldButton(systemName: "stop", label: "End session") {
                engine.end()
                dismiss()
            }
            FieldButton(
                systemName: engine.status == .running ? "pause.fill" : "play.fill",
                prominent: true,
                label: engine.status == .running ? "Pause" : "Resume"
            ) {
                engine.toggle()
                Haptics.transport()
            }
            FieldButton(systemName: "forward.end", label: "Skip this interval") {
                engine.skip()
                Haptics.transport()
            }
        }
    }

    // MARK: - Copy

    private var phaseCaption: String {
        guard let phase = engine.currentPhase else { return "Finished" }
        return phase.isWork ? "left of sixty seconds" : "rest — walk it off"
    }

    private var accessibilityCount: String {
        guard let phase = engine.currentPhase else { return "Session complete" }
        let seconds = Int(engine.remainingInPhase.rounded(.up))
        return "\(phase.isWork ? "Work" : "Rest"), \(seconds) seconds remaining"
    }

    private func nextDescription(_ phase: Phase) -> String {
        if phase.isWork, let move = phase.move {
            return "\(move.name) · \(phase.duration.clockString)"
        }
        return "Rest \(phase.duration.clockString)"
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
