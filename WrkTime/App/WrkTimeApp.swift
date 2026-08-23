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
    @AppStorage("renamedUntitledRows") private var renamedUntitled = false
    @AppStorage("seededPostureRoutine") private var seededPosture = false
    @AppStorage("seededCoreRoutine") private var seededCore = false
    @AppStorage("seededAfterMealRoutine") private var seededAfterMeal = false
    @AppStorage("seededUpperRoutines") private var seededUpper = false

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.horizon") {
                TodayView()
            }
            // "Moves", because the tab stopped being a timer some time ago:
            // it holds the material — her routines, the library, the loads,
            // the history — and the timer is just how a routine runs. The
            // library used to live behind Settings, which meant the screen
            // with her rep history and the step-up nudges was three modals
            // deep. Today · Moves · Season · Signals: the day, the material,
            // the record, the inputs.
            Tab("Moves", systemImage: "dumbbell") {
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
            renameUntitledRows()
            seedStatedEquipment()
            seedPostureRoutine()
            seedCoreRoutine()
            seedAfterMealRoutine()
            // Her additions' pattern and position, so the taxonomy answers
            // for them from the first screen.
            CustomMoves.registerTaxonomy(in: context)
            seedUpperRoutines()
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
            if phase == .background {
                PlanScheduler.schedule()
                // The widget is only visible when the app is not, so leaving
                // is the one moment its fact sheet must be fresh — and the
                // moment that sees every change she made while it was open.
                WidgetSnapshots.refresh(in: context)
            }
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
                Task { await plan(week: 1, of: block) }
            }
            .interactiveDismissDisabled()
        }
    }

    /// One-time repair: rows saved before the builder derived names went in as
    /// "Untitled routine", and seven of them across three screens told her
    /// nothing. Renamed with the same derivation the builder now uses; runs
    /// once, and never touches a name she typed herself.
    private func renameUntitledRows() {
        guard !renamedUntitled else { return }
        renamedUntitled = true

        for saved in (try? context.fetch(FetchDescriptor<SavedRoutine>())) ?? []
        where saved.routine.map({ $0.name.hasPrefix("Untitled") }) == true {
            guard var routine = saved.routine else { continue }
            routine.name = routine.derivedName
            saved.update(to: routine)
        }
        for run in (try? context.fetch(FetchDescriptor<RoutineRun>())) ?? []
        where run.name.hasPrefix("Untitled") {
            // A run keeps names and counts, not a schedule, so its name is
            // derived from what it recorded.
            let kit = run.moveNames.first.flatMap { name in
                MoveLibrary.all.first { $0.name == name }?.equipment
            }
            let shape = run.roundsCompleted > 0
                ? "\(run.roundsCompleted) rounds" : run.seconds.durationString
            run.name = "\(kit?.shortLabel ?? "Timer") · \(shape)"
        }
        try? context.save()
    }

    /// One-time seed: the posture routine the band was bought for. Her ask, in
    /// her words: a routine "that will get rid of my tech neck/slouch hump".
    ///
    /// The shape is the standard prescription for a rounded upper back and
    /// forward head, ordered easy-to-hard on the neck: wake the deep neck
    /// flexors, then pull the shoulder blades home from three angles, with
    /// the rotator cuff getting a full interval per side. It opens with the
    /// neck-and-chest flows the library already had. About nine minutes, so a
    /// finished run clears the tick floor and lands on the season's rings.
    /// Seeded once and then hers — edit or delete it like anything she built.
    private func seedPostureRoutine() {
        guard !seededPosture else { return }
        seededPosture = true
        let saved = (try? context.fetch(FetchDescriptor<SavedRoutine>())) ?? []
        guard !saved.contains(where: { $0.routine?.name == "Posture reset" }) else { return }

        func move(_ name: String) -> Move? {
            MoveLibrary.all.first { $0.name == name }
        }
        let rotation = ["Chin tuck", "Band pull-apart", "Wall angel",
                        "Band face pull", "Band external rotation",
                        "Band W raise"].compactMap(move)
        let warm = ["Neck release", "Shoulder rolls", "Chest opener"].compactMap(move)
        // If a rename upstream ever breaks a lookup, seed nothing rather than
        // a routine with holes in it.
        guard rotation.count == 6, warm.count == 3 else { return }

        let routine = IntervalRoutine(name: "Posture reset",
                                      work: 40, rest: 20, rounds: 6,
                                      moves: rotation)
            .warmingUp(with: warm)
        context.insert(SavedRoutine(routine: routine))
        try? context.save()
    }

    /// One-time seed: the core routine she asked for alongside the 10 lb
    /// dumbbell. Her ask, in her words: she does not have a very strong core
    /// yet, wants to start by getting a feel for the core moves, and still
    /// wants a bit of a challenge.
    ///
    /// So the shape is ordered easy-to-hard: the floor patterns that teach
    /// bracing first (dead bug, bird dog), then the harder flexion and
    /// rotation work, and the holds last — the side plank takes a full
    /// interval per side, which with the plank finisher is where the
    /// challenge lives. Thirty-second intervals rather than forty, because a
    /// first plank should end before form does. About eight minutes with its
    /// warm-up, so a finished run clears the tick floor and lands on the
    /// season's rings. Seeded once and then hers — edit or delete it like
    /// anything she built.
    private func seedCoreRoutine() {
        guard !seededCore else { return }
        seededCore = true
        let saved = (try? context.fetch(FetchDescriptor<SavedRoutine>())) ?? []
        guard !saved.contains(where: { $0.routine?.name == "Core foundation" }) else { return }

        func move(_ name: String) -> Move? {
            MoveLibrary.all.first { $0.name == name }
        }
        let rotation = ["Dead bug", "Bird dog", "Lying leg raise",
                        "Russian twist", "Side plank",
                        "Forearm plank"].compactMap(move)
        let warm = ["Cat cow", "Hip circles", "Standing twist"].compactMap(move)
        // If a rename upstream ever breaks a lookup, seed nothing rather than
        // a routine with holes in it.
        guard rotation.count == 6, warm.count == 3 else { return }

        let routine = IntervalRoutine(name: "Core foundation",
                                      work: 30, rest: 20, rounds: 6,
                                      moves: rotation)
            .warmingUp(with: warm)
        context.insert(SavedRoutine(routine: routine))
        try? context.save()
    }

    /// One-time seed: ten minutes after a meal, her ask on 22 August 2026
    /// ("some sort of 10 min post meal routine in there to get things
    /// moving"). A flow, not a workout: ten gentle standing movements held
    /// a minute each, nothing on the floor and nothing inverted after
    /// eating, built to get her walking about rather than working. Light
    /// movement after a meal is a well-supported habit and the app says
    /// only that — it earns no mark and is hers to edit or delete.
    private func seedAfterMealRoutine() {
        guard !seededAfterMeal else { return }
        seededAfterMeal = true
        let saved = (try? context.fetch(FetchDescriptor<SavedRoutine>())) ?? []
        guard !saved.contains(where: { $0.routine?.name == "After a meal" }) else { return }

        func move(_ name: String) -> Move? {
            MoveLibrary.all.first { $0.name == name }
        }
        let flow = ["Standing march", "Shoulder rolls", "Arm swings", "Ankle rocking",
                    "Hip circles", "Knee sways", "Standing twist", "Golf swings",
                    "Arm circles", "Lymphatic bounce"].compactMap(move)
        guard flow.count == 10 else { return }

        let routine = IntervalRoutine(name: "After a meal",
                                      work: 0, rest: 0, rounds: 0, moves: [])
            .warmingUp(with: flow, seconds: 60)
        context.insert(SavedRoutine(routine: routine))
        try? context.save()
    }

    /// One-time seed: the two upper-body routines she asked for — a full
    /// arms and upper body round, and a triceps-focused one.
    ///
    /// Both are ordered the way the other seeds are: the biggest patterns
    /// first, while she is fresh, and the small-lever isolation last. Neither
    /// uses the band, because she does not have it. The triceps round leans on
    /// the beam and the 8 lb ring rather than sitting entirely on the 2 lb
    /// pairs — the coach audit's finding was that every triceps move in the
    /// library had no path heavier than two pounds.
    ///
    /// Seeded once and then hers, like the others.
    private func seedUpperRoutines() {
        guard !seededUpper else { return }
        seededUpper = true
        let saved = (try? context.fetch(FetchDescriptor<SavedRoutine>())) ?? []

        func move(_ name: String) -> Move? {
            MoveLibrary.all.first { $0.name == name }
        }
        let warm = ["Shoulder rolls", "Chest opener", "Arm swings"].compactMap(move)
        guard warm.count == 3 else { return }

        // Push, pull, push, pull, then the arms — and the pull side leads on
        // the two heaviest things she owns, because this kit is push-heavy.
        if !saved.contains(where: { $0.routine?.name == "Upper body" }) {
            let rotation = ["Beam overhead press", "Kettlebell row", "Dumbbell floor press",
                            "Ring row", "Bicep curl", "Tricep kickback"].compactMap(move)
            if rotation.count == 6 {
                context.insert(SavedRoutine(routine:
                    IntervalRoutine(name: "Upper body", work: 40, rest: 25, rounds: 6,
                                    moves: rotation)
                        .warmingUp(with: warm)))
            }
        }

        // Every angle the elbow extends through: overhead, lying, and by the
        // side. The two presses open it because a triceps round on a beginner's
        // arms alone is over before it has done anything.
        if !saved.contains(where: { $0.routine?.name == "Triceps" }) {
            let rotation = ["Beam triceps extension", "Ring triceps extension",
                            "Overhead extension", "Tricep kickback",
                            "Tricep press-back", "Squeeze press"].compactMap(move)
            if rotation.count == 6 {
                context.insert(SavedRoutine(routine:
                    IntervalRoutine(name: "Triceps", work: 35, rest: 25, rounds: 6,
                                    moves: rotation)
                        .warmingUp(with: warm)))
            }
        }
        try? context.save()
    }

    /// One-time seed: the band is in the app but not in the house.
    ///
    /// Her words, August 2026: *"i dont have the resistance bands yet"*. The
    /// posture moves and the seeded Posture reset routine went in before the
    /// band did, so the honest starting state is the drawer switched off —
    /// and it is one tap in Settings the day it arrives. Only ever runs when
    /// she has said nothing about her kit herself.
    /// Guarded on the stored value itself rather than on a separate "have I
    /// done this" flag. The flag version set itself first and then wrote, and
    /// when the write did not land the flag said the job was done for good —
    /// a one-shot marker that can outlive the thing it marks. The value's own
    /// presence is the honest record, and it cannot drift from itself.
    private func seedStatedEquipment() {
        guard !Tuning.hasSetEquipment else { return }
        Tuning.ownedEquipment = Set(Equipment.allCases).subtracting([.band])
    }

    private func seedStatedPreferences() {
        guard !seededPreferences else { return }
        seededPreferences = true
        // Matching is by containment, so this one entry also covers the incline
        // and knee variants the planner likes to reach for.
        MovePreferences.set(.disliked, for: "push-up", in: context)
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
        guard !block.hasEnded, !PlannerService.isPlanned(block.currentWeek, of: block, in: context) else { return }
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
