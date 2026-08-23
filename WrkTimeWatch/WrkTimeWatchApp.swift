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
            WatchRootView()
        }
        .modelContainer(container)
    }
}

/// Phase 0 placeholder; `WatchTodayView` replaces it.
struct WatchRootView: View {
    var body: some View {
        Text("Almanac")
            .font(.almanacHeading)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.oat.ignoresSafeArea())
    }
}
