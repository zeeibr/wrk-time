import SwiftUI
import SwiftData

@main
struct WrkTimeApp: App {
    /// Held rather than called twice. `Store.container()` opens a store each
    /// time it is asked, so handing one to the scene and another to the
    /// background task would give the two of them different views of the same
    /// database — the six a.m. plan would be written where nothing reads it.
    private let container: ModelContainer

    init() {
        let container = Store.container()
        self.container = container
        // Registration has to happen before launch finishes, which rules out
        // `.task` and every other view lifecycle hook.
        PlanScheduler.register(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    /// Sorted, like every other screen's query. This one was unordered and
    /// then read `.first`, so "the current block" here could be a different
    /// block from the one Today, Season and Settings were all showing — and
    /// this is the query that decides which block gets *planned*.
    @Query(sort: \Block.startDate, order: .reverse) private var blocks: [Block]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    @Environment(\.scenePhase) private var scenePhase

    @State private var needsSetup = false
    @State private var checkedForBlock = false
    /// Planning is a network call; two of them racing would write the week
    /// twice and delete each other's sessions on the way past.
    @State private var planning = false
    @State private var activity = PlannerActivity()
    /// One-time, because she said so in as many words: "deweight things like
    /// pushups i dont like those". Recorded as a preference rather than
    /// hard-coded into the library, so it shows up in the same place as every
    /// other opinion and can be undone from the same menu.
    @AppStorage("seededStatedPreferences") private var seededPreferences = false

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.horizon") {
                TodayView()
            }
            Tab("Timer", systemImage: "timer") {
                RoutineListView()
            }
            Tab("Season", systemImage: "circle.hexagongrid") {
                SeasonView()
            }
            Tab("Signals", systemImage: "waveform.path.ecg") {
                SignalsView()
            }
        }
        .tint(Palette.ink)
        .environment(activity)
        .task {
            // Anything still on the lock screen at launch belongs to a session
            // that is long over — the process that owned it is gone and nothing
            // else will ever clear it.
            LiveActivityController.endAll()
            guard !checkedForBlock else { return }
            checkedForBlock = true
            needsSetup = blocks.isEmpty
            seedStatedPreferences()
            await planCurrentWeekIfNeeded()
        }
        // Opening the app on the first day of a new week is what writes that
        // week. A phone left running for a fortnight would otherwise sit on a
        // block that stopped a week ago.
        .onChange(of: scenePhase) { _, phase in
            // Asked for on the way out rather than at launch: a submitted task
            // only becomes eligible once the app is in the background, and
            // re-submitting the same identifier replaces the pending request
            // rather than stacking another one behind it.
            if phase == .background { PlanScheduler.schedule() }
            guard phase == .active else { return }
            Task { await planCurrentWeekIfNeeded() }
        }
        .fullScreenCover(isPresented: $needsSetup) {
            // The first run asks rather than assumes. This screen replaced a
            // seed that opened the app with a starting weight and a goal
            // already filled in — numbers nobody had entered, presented as
            // hers. An almanac records what happened; it does not invent the
            // first two entries.
            BlockSetupView(knownWeight: weights.first?.pounds) { block in
                if fastWindowIsMissing { context.insert(FastWindow()) }
                Task { await plan(week: 1, of: block) }
            }
            .interactiveDismissDisabled()
        }
    }

    private func seedStatedPreferences() {
        guard !seededPreferences else { return }
        seededPreferences = true
        // Matching is by containment, so this one entry also covers the incline
        // and knee variants the planner likes to reach for.
        MovePreferences.set(.disliked, for: "push-up", in: context)
    }

    private var fastWindowIsMissing: Bool {
        ((try? context.fetch(FetchDescriptor<FastWindow>()))?.isEmpty ?? true)
    }

    private func plan(week: Int, of block: Block) async {
        guard !planning else { return }
        planning = true
        activity.begin(week: week)
        defer { planning = false; activity.finish() }
        _ = await PlannerService.planWeek(week, of: block, in: context)
    }

    /// Writes the week the block is in, if it is still empty. Runs at launch
    /// and on every return to the foreground, which is what carries a block
    /// past week one.
    private func planCurrentWeekIfNeeded() async {
        guard let block = blocks.first, !planning else { return }
        guard !block.hasEnded, !PlannerService.isPlanned(block.currentWeek, of: block) else { return }
        planning = true
        activity.begin(week: block.currentWeek)
        defer { planning = false; activity.finish() }
        _ = await PlannerService.planCurrentWeekIfNeeded(for: block, in: context)
    }
}

/// Honest placeholder. Named so it is obvious in a build what is not yet real.
struct PlaceholderView: View {
    let title: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Masthead(context: title)
            Text(title)
                .font(.almanacTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
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
