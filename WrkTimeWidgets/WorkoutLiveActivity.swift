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
                        Text(context.state.phase.label.uppercased())
                            .font(.system(size: 11, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(context.state.phase == .work ? Palette.saffron : Palette.sage)
                        Text("Round \(context.state.round) / \(context.attributes.totalRounds)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Palette.sage)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.phaseBegan...context.state.phaseEnds,
                         countsDown: true)
                        .font(.system(size: 34, weight: .light).monospacedDigit())
                        .foregroundStyle(Palette.oat)
                        .frame(maxWidth: .infinity, alignment: .trailing)
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
                Circle()
                    .fill(context.state.phase == .work ? Palette.saffron : Palette.sage)
                    .frame(width: 8, height: 8)
            } compactTrailing: {
                Text(timerInterval: context.state.phaseBegan...context.state.phaseEnds,
                     countsDown: true)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Palette.oat)
                    .frame(width: 44)
            } minimal: {
                Circle()
                    .fill(context.state.phase == .work ? Palette.saffron : Palette.sage)
                    .frame(width: 8, height: 8)
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
                Text(context.attributes.routineName.uppercased())
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(1.7)
                    .foregroundStyle(Palette.sage)
                Spacer()
                Text("ROUND \(context.state.round) / \(context.attributes.totalRounds)")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Palette.sage)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(timerInterval: context.state.phaseBegan...context.state.phaseEnds,
                     countsDown: true)
                    .font(.system(size: 46, weight: .light).monospacedDigit())
                    .foregroundStyle(Palette.oat)
                    .frame(maxWidth: 128, alignment: .leading)

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

/// The interval, drained. Segments rather than a smooth bar, because rounds are
/// countable and a bar that is merely shrinking tells you less than one that
/// shows how many are left.
private struct DrainBar: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.oat.opacity(0.18))
                Capsule()
                    .fill(state.phase == .work ? Palette.saffron : Palette.sage)
                    .frame(width: proxy.size.width * state.remainingFraction)
            }
        }
        .frame(height: 5)
    }
}
