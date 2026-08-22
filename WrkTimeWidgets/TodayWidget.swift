import SwiftUI
import WidgetKit

/// The day at a glance, in the document register: what today asks, whether
/// the practice is done, and the week's marks. It reads the snapshot the app
/// wrote — never live data — so its one job is to be honest about staleness:
/// practice state is only shown for the day the snapshot was written on.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(Palette.oat, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Today's session, the practice, and the week's marks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now,
                              snapshot: context.isPreview ? .sample : TodaySnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snapshot = TodaySnapshot.load()
        let now = Date()
        // One entry for now and one at midnight, so tomorrow's session appears
        // without the app having been opened. The snapshot carries the week.
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        completion(Timeline(entries: [TodayEntry(date: now, snapshot: snapshot),
                                      TodayEntry(date: midnight, snapshot: snapshot)],
                            policy: .after(midnight)))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var snapshot: TodaySnapshot? { entry.snapshot }
    private var day: TodaySnapshot.Day? { snapshot?.day(for: entry.date) }
    /// Practice state is a fact about one morning; shown only on that day.
    private var practiceKnown: Bool {
        guard let snapshot else { return false }
        return Calendar.current.isDate(snapshot.writtenOn, inSameDayAs: entry.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.date.formatted(.dateTime.weekday(.wide)).uppercased())
                    .font(Face.mono(9, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Palette.mute)
                Spacer(minLength: 4)
                if let snapshot {
                    Text("WK \(snapshot.week)")
                        .font(Face.mono(9, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(Palette.mute)
                }
            }

            Spacer(minLength: 4)

            Text(headline)
                .font(Face.slab(family == .systemSmall ? 16 : 19))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if let detail {
                Text(detail)
                    .font(Face.mono(9, weight: .medium))
                    .tracking(1.0)
                    .foregroundStyle(Palette.mute)
                    .padding(.top, 2)
            }

            Spacer(minLength: 6)

            Rectangle().fill(Palette.rule).frame(height: 1)
                .padding(.bottom, 5)

            HStack(spacing: 8) {
                statusLine("Practice", done: practiceKnown && (snapshot?.practiceDone ?? false))
                if family == .systemMedium, let snapshot {
                    Spacer(minLength: 6)
                    marks(snapshot)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var headline: String {
        guard snapshot != nil else { return "Open Almanac" }
        guard let day, let title = day.title else { return "Rest day" }
        return day.done ? "\(title) — done" : title
    }

    private var detail: String? {
        guard snapshot != nil else { return nil }
        guard let day, day.title != nil else { return "The practice still happens" }
        if day.done { return "One mark on the season" }
        return day.minutes.map { "\($0) MIN" }
    }

    private func statusLine(_ label: String, done: Bool) -> some View {
        HStack(spacing: 5) {
            // The practice square fills when this morning's is done — the same
            // vocabulary as Season's fortnight strip.
            Rectangle()
                .fill(done ? Palette.moss : Color.clear)
                .frame(width: 8, height: 8)
                .overlay(Rectangle().strokeBorder(done ? Palette.moss : Palette.ruleFirm,
                                                  lineWidth: 1))
            Text(label.uppercased())
                .font(Face.mono(8, weight: .medium))
                .tracking(1.0)
                .foregroundStyle(Palette.mute)
        }
    }

    /// The week's marks as pips, the same shape Season draws.
    private func marks(_ snapshot: TodaySnapshot) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<max(snapshot.marksTarget, 1), id: \.self) { index in
                Rectangle()
                    .fill(index < snapshot.marksThisWeek ? Palette.moss : Color.clear)
                    .frame(width: 7, height: 7)
                    .overlay(Rectangle().strokeBorder(
                        Palette.moss.opacity(index < snapshot.marksThisWeek ? 0 : 0.3),
                        lineWidth: 1))
            }
        }
        .accessibilityLabel("Marks this week")
        .accessibilityValue("\(snapshot.marksThisWeek) of \(snapshot.marksTarget)")
    }
}
