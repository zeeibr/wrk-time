import SwiftUI
import WidgetKit

@main
struct WrkTimeWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchTodayWidget()
    }
}

/// Phase 0 placeholder; Phase 4 draws the accessory families from
/// `TodaySnapshot`.
struct WatchTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchToday", provider: WatchTodayProvider()) { entry in
            Text(entry.title)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Today")
        .description("Today's session, and the one running.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct WatchTodayEntry: TimelineEntry {
    var date: Date
    var title: String
}

struct WatchTodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchTodayEntry { .init(date: .now, title: "Almanac") }
    func getSnapshot(in context: Context, completion: @escaping (WatchTodayEntry) -> Void) {
        completion(placeholder(in: context))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchTodayEntry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}
