import SwiftUI
import SwiftData

/// Almanac on the wrist.
///
/// The watch does; the phone reads and decides. It opens the same store
/// through the same CloudKit container, runs the same engine, and records a
/// session it started exactly as the phone would — once, never twice. The
/// coach chat, the library, the builder and Settings stay on the phone.
@main
struct WrkTimeWatchApp: App {
    private let container: ModelContainer

    init() {
        container = Store.container()
    }

    var body: some Scene {
        WindowGroup {
            WatchTodayView()
        }
        .modelContainer(container)
    }
}
