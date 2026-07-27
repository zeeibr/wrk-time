import SwiftUI
import SwiftData

@main
struct WrkTimeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Store.container())
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var blocks: [Block]

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.horizon") {
                TodayView()
            }
            Tab("Timer", systemImage: "timer") {
                RoutineListView()
            }
            Tab("Season", systemImage: "circle.hexagongrid") {
                PlaceholderView(title: "Season",
                                note: "The growth form at full size, week by week, with the block's history beneath it.")
            }
            Tab("Signals", systemImage: "waveform.path.ecg") {
                PlaceholderView(title: "Signals",
                                note: "Weight against projection, sleep and HRV from Whoop, and the eating window as a stated input.")
            }
        }
        .tint(Palette.ink)
        .task { seedIfEmpty() }
    }

    /// First run puts a real block and a real session on screen rather than an
    /// empty state, because an interval app with nothing in it teaches nothing.
    private func seedIfEmpty() {
        guard blocks.isEmpty else { return }
        let block = Block(goalWeightPounds: 148, startingWeightPounds: 168.4)
        context.insert(block)

        let routine = IntervalRoutine(
            name: "Beam & rings, steady",
            work: 60,
            rest: 45,
            rounds: 8,
            moves: [MoveLibrary.all[0], MoveLibrary.all[4], MoveLibrary.all[6]]
        )
        let session = PlannedSession(scheduledFor: .now, title: routine.name, routine: routine)
        context.insert(session)
        // Set the inverse; SwiftData maintains the other side.
        session.block = block
        context.insert(FastWindow())
    }
}

/// Honest placeholder. Named so it is obvious in a build what is not yet real.
struct PlaceholderView: View {
    let title: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.almanacTitle).foregroundStyle(Palette.ink)
            Rule(firm: true)
            Text(note)
                .font(.almanacBody)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.oat.ignoresSafeArea())
    }
}
