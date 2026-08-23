import SwiftUI
import WidgetKit

@main
struct WrkTimeWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchTodayWidget()
    }
}

/// The day on the watch face, and the session while it runs.
///
/// It reads `TodaySnapshot` from the **watch's** app group, which
/// `WatchSnapshots` writes — the phone's container is a different container
/// and this process cannot see it. Three accessory families, one fact sheet,
/// and no live data: the one job of a complication fed by a snapshot is to be
/// honest about what it does not know.
struct WatchTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchToday", provider: WatchTodayProvider()) { entry in
            WatchTodayComplication(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Today")
        .description("Today's session, and the one running.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct WatchTodayEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot?
}

struct WatchTodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchTodayEntry {
        WatchTodayEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchTodayEntry) -> Void) {
        completion(WatchTodayEntry(date: .now,
                                   snapshot: context.isPreview ? .sample : TodaySnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchTodayEntry>) -> Void) {
        let snapshot = TodaySnapshot.load()
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)

        // While a session runs, the countdown itself is the system's job — the
        // rectangular family hands it a `Text(timerInterval:)` and it ticks
        // without waking this process. What the timeline is for is the two
        // moments the *content* changes: the phase ending, and the session
        // ending. Per-second entries would be the Live Activity mistake with a
        // smaller screen.
        var entries = [WatchTodayEntry(date: now, snapshot: snapshot)]
        if let snapshot, snapshot.isRunning(at: now) {
            let marks = [snapshot.runningPhaseEnds, snapshot.runningEnds]
                .compactMap { $0 }
                .filter { $0 > now }
                .sorted()
            entries += marks.map { WatchTodayEntry(date: $0, snapshot: snapshot) }
            let last = marks.last ?? now
            completion(Timeline(entries: entries, policy: .after(last)))
            return
        }

        // Otherwise one entry now and one at midnight, so tomorrow's session
        // appears without the app having been opened. The snapshot carries
        // the whole week.
        entries.append(WatchTodayEntry(date: midnight, snapshot: snapshot))
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

// MARK: - Drawing

/// Nothing here sets a colour.
///
/// The system renders a complication in its own tint — full colour, tinted,
/// or the always-on vibrant pass — and a fixed oat-and-ink palette fights all
/// three, coming out as a grey slab on a coloured face. Hierarchy is the
/// vocabulary that survives: `.widgetAccentable` for the thing that should
/// carry the accent, `.secondary` for what should recede.
struct WatchTodayComplication: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchTodayEntry

    private var snapshot: TodaySnapshot? { entry.snapshot }
    private var day: TodaySnapshot.Day? { snapshot?.day(for: entry.date) }
    private var running: Bool { snapshot?.isRunning(at: entry.date) ?? false }

    @ViewBuilder
    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: rectangular
        }
    }

    // MARK: Rectangular

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if running, let snapshot {
                Text(snapshot.runningPhase ?? "Session")
                    .font(.system(size: 12, weight: .semibold))
                    .widgetAccentable()
                // The system ticks this. The entry is redrawn once a phase,
                // never once a second.
                if let ends = snapshot.runningPhaseEnds, ends > entry.date {
                    Text(timerInterval: entry.date...ends, countsDown: true)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text(snapshot.runningTitle ?? "Running")
                        .font(.system(size: 15, weight: .medium))
                }
                Text(snapshot.runningTitle ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(headline)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .widgetAccentable()
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let snapshot {
                    Text("\(snapshot.marksThisWeek)/\(snapshot.marksTarget) this week")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Circular

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if running {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 18))
                    .widgetAccentable()
            } else if let snapshot {
                VStack(spacing: -1) {
                    // A finished day is a tick rather than a fraction: the
                    // number is the same all evening and the tick says the
                    // thing she opened the face to check.
                    if day?.done == true {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .widgetAccentable()
                        Text("\(snapshot.marksThisWeek)/\(snapshot.marksTarget)")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(snapshot.marksThisWeek)")
                            .font(.system(size: 20, weight: .medium))
                            .monospacedDigit()
                            .widgetAccentable()
                        Text("of \(snapshot.marksTarget)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "leaf")
                    .font(.system(size: 16))
            }
        }
        .accessibilityLabel("Marks this week")
        .accessibilityValue(snapshot.map { "\($0.marksThisWeek) of \($0.marksTarget)" } ?? "Open Almanac")
    }

    // MARK: Inline

    @ViewBuilder
    private var inline: some View {
        if running, let snapshot {
            Text("\(snapshot.runningPhase ?? "Session") · \(snapshot.runningTitle ?? "")")
        } else {
            Text(headline)
        }
    }

    // MARK: Copy

    /// The one line, in the app's voice: a rest day is the plan, never a gap.
    private var headline: String {
        guard snapshot != nil else { return "Open Almanac" }
        guard let day, let title = day.title else { return "Rest day" }
        return day.done ? "\(title) — done" : title
    }

    private var detail: String? {
        guard snapshot != nil else { return nil }
        guard let day, day.title != nil else { return "The practice still happens" }
        if day.done { return "One mark on the season" }
        return day.minutes.map { "\($0) min" }
    }
}
