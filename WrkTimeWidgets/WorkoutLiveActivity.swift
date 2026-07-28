import ActivityKit
import SwiftUI
import WidgetKit

/// The lock screen and Dynamic Island presentation of a running interval.
///
/// It keeps the field register: dark ground, oat type, and a saffron bar that
/// drains with the interval — the same language as the in-app timer, so
/// glancing at your lock screen and looking at the phone are the same design.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Palette.field)
                .activitySystemActionForegroundColor(Palette.oat)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.isPaused ? "PAUSED"
                                                    : context.state.phase.label.uppercased())
                            .font(.system(size: 11, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(context.state.isPaused ? Palette.sage
                                             : context.state.phase == .work ? Palette.saffron
                                                                            : Palette.sage)
                        Text(context.state.position)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Palette.sage)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PhaseClock(state: context.state, size: 34,
                               maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(context.state.moveName)
                            .font(.custom("Superclarendon", size: 17))
                            .foregroundStyle(Palette.oat)
                        DrainBar(state: context.state)
                        Text("Next — \(context.state.nextUp)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Palette.sage)
                    }
                }
            } compactLeading: {
                PhaseDot(state: context.state)
            } compactTrailing: {
                PhaseClock(state: context.state, size: 13, maxWidth: 44, alignment: .trailing)
            } minimal: {
                PhaseDot(state: context.state)
            }
            .keylineTint(Palette.saffron)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(context.state.isPaused ? "PAUSED"
                                            : context.attributes.routineName.uppercased())
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(1.7)
                    .foregroundStyle(Palette.sage)
                Spacer()
                Text(context.state.position.uppercased())
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Palette.sage)
            }

            HStack(alignment: .firstTextBaseline) {
                PhaseClock(state: context.state, size: 46, maxWidth: 128)

                Spacer(minLength: 10)

                Text(context.state.moveName)
                    .font(.custom("Superclarendon", size: 19))
                    .foregroundStyle(Palette.oat)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }

            DrainBar(state: context.state)

            Text("Next — \(context.state.nextUp)")
                .font(.system(size: 11, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Palette.sage)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

/// Work or rest, in the compact presentations.
///
/// The two states used to differ only in hue — saffron against sage, which is
/// 1.12:1 apart in luminance. In the one element you glance at with the phone
/// in your pocket, that is no distinction at all for a red-green deficiency and
/// barely one for anybody else. Filled means work, hollow means rest, and the
/// colour is now confirmation rather than the whole message.
private struct PhaseDot: View {
    let state: WorkoutActivityAttributes.ContentState

    private var tint: Color {
        state.isPaused ? Palette.sage
            : state.phase == .work ? Palette.saffron : Palette.sage
    }

    var body: some View {
        Group {
            if state.phase == .work && !state.isPaused {
                Circle().fill(tint)
            } else {
                Circle().strokeBorder(tint, lineWidth: 2)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityLabel(state.isPaused ? "Paused" : state.phase.label)
    }
}

/// The interval, drained.
///
/// The system animates this from the phase's dates. Computing a fraction here
/// would freeze it solid: ActivityKit re-renders only when a new state is
/// pushed, and by design there is exactly one push per phase — so a bar bound
/// to `Date.now` at render time never moves again.
private struct DrainBar: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isPaused {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.oat.opacity(0.18))
                        Capsule()
                            .fill(Palette.sage)
                            .frame(width: proxy.size.width * pausedFraction)
                    }
                }
            } else {
                ProgressView(
                    timerInterval: state.phaseBegan...state.phaseEnds,
                    countsDown: true
                ) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(state.phase == .work ? Palette.saffron : Palette.sage)
            }
        }
        .frame(height: 5)
    }

    /// Held where the pause caught it — the dates cannot tell the truth once
    /// the clock has stopped.
    private var pausedFraction: Double {
        guard state.duration > 0, let left = state.pausedRemaining else { return 0 }
        return min(1, max(0, left / state.duration))
    }
}

/// The phase clock. Ticks itself from the dates while running; holds a plain
/// number while paused, because a countdown that keeps falling on a stopped
/// workout is simply wrong.
private struct PhaseClock: View {
    let state: WorkoutActivityAttributes.ContentState
    let size: CGFloat
    var maxWidth: CGFloat?
    var alignment: Alignment = .leading

    var body: some View {
        Group {
            if state.isPaused {
                Text(pausedClock).foregroundStyle(Palette.sage)
            } else {
                Text(timerInterval: state.phaseBegan...state.phaseEnds, countsDown: true)
                    .foregroundStyle(Palette.oat)
            }
        }
        .font(.system(size: size, weight: .light).monospacedDigit())
        .frame(maxWidth: maxWidth, alignment: alignment)
    }

    private var pausedClock: String {
        let seconds = Int((state.pausedRemaining ?? 0).rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
