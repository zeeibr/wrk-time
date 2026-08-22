import SwiftUI
import WidgetKit

@main
struct WrkTimeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        WorkoutLiveActivity()
    }
}
