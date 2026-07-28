import Foundation
import SwiftData

/// How hard the block pushes — the one dial the reader gets over the plan.
///
/// This changes how often you train and how quickly load and rounds climb. It
/// deliberately does **not** claim to change how fast the scale moves: with
/// thirteen-minute sessions and 2–15 lb kit, the sessions are not where the
/// energy balance is decided, and a dial that implied otherwise would be
/// lying. What it genuinely buys is a faster strength curve and more days
/// under tension — which is worth having, and worth being honest about.
enum Pace: String, Codable, CaseIterable, Identifiable, Sendable {
    case steady
    case building
    case hard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .steady: "Steady"
        case .building: "Building"
        case .hard: "Hard"
        }
    }

    /// What it actually changes, in the units the plan is written in.
    var note: String {
        switch self {
        case .steady: "Three sessions a week. Load moves every third week."
        case .building: "Four a week. Load moves every other week."
        case .hard: "Five a week. Load moves weekly, and rounds climb."
        }
    }

    /// The honest line about what this does and does not do.
    var expectation: String {
        switch self {
        case .steady:
            "Room to miss a day without losing the week."
        case .building:
            "The middle setting, and the one most weeks survive contact with."
        case .hard:
            "Strength climbs fastest here. It will not move the scale faster — that is decided by the walking and the eating window, not by these thirteen minutes."
        }
    }

    var sessionsPerWeek: Int {
        switch self {
        case .steady: 3
        case .building: 4
        case .hard: 5
        }
    }

    /// Weeks between one step up in load or rounds.
    var progressionWeeks: Int {
        switch self {
        case .steady: 3
        case .building: 2
        case .hard: 1
        }
    }

    /// Rounds added at each progression step.
    var roundStep: Int { self == .hard ? 1 : 0 }
}

/// An 84-day block. The planner writes one of these and revises it weekly.
@Model
final class Block {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var lengthInDays: Int = 84
    var goalWeightPounds: Double = 0
    var startingWeightPounds: Double = 0
    /// Stored raw because SwiftData + CloudKit want a primitive with a default.
    var paceRaw: String = Pace.building.rawValue
    /// CloudKit requires every relationship to declare its inverse, so this
    /// pairs with `PlannedSession.block`.
    @Relationship(deleteRule: .cascade, inverse: \PlannedSession.block)
    var sessions: [PlannedSession]? = []

    init(startDate: Date = .now,
         goalWeightPounds: Double,
         startingWeightPounds: Double,
         pace: Pace = .building) {
        self.startDate = startDate
        self.goalWeightPounds = goalWeightPounds
        self.startingWeightPounds = startingWeightPounds
        self.paceRaw = pace.rawValue
    }

    var pace: Pace {
        get { Pace(rawValue: paceRaw) ?? .building }
        set { paceRaw = newValue.rawValue }
    }

    /// Pounds between where you started and where you said you were going.
    /// Negative when the goal is above the start, which is a legitimate goal
    /// and one the projection has to handle without editorialising.
    var goalDelta: Double { startingWeightPounds - goalWeightPounds }

    var hasGoal: Bool { goalWeightPounds > 0 && startingWeightPounds > 0 }

    var dayNumber: Int {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: .now).day ?? 0
        return min(max(days + 1, 1), lengthInDays)
    }

    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: lengthInDays, to: startDate) ?? startDate
    }

    var weekCount: Int { max(lengthInDays / 7, 1) }

    /// The week you are actually in, from the calendar.
    ///
    /// Derived from elapsed time rather than from how many sessions you have
    /// finished: a block is a span of time, not a queue of work, and a quiet
    /// week has to be able to exist. This lives on the block rather than in a
    /// view because the planner needs the same answer — the week the planner
    /// writes and the week Today draws must never be able to disagree.
    var currentWeek: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: startDate),
                                           to: .now).day ?? 0
        return min(max(days / 7 + 1, 1), weekCount)
    }

    /// True once the twelve weeks are up. The planner stops here rather than
    /// quietly extending a block she has finished.
    var hasEnded: Bool { Date.now >= endDate }

    /// Seeds this block's growth form, so one season's drawing is not another's.
    ///
    /// Built from the identifier's bytes rather than `hashValue`, which Swift
    /// seeds randomly per process — using it would redraw the form differently
    /// on every launch, which is precisely what the form promises not to do.
    var formSeed: UInt64 {
        let b = id.uuid
        let bytes = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7]
        return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}

/// A session the planner scheduled. `completedAt` is the only thing that turns
/// it into a mark on the growth form — a session you started and abandoned does
/// not count, and the app does not pretend otherwise.
@Model
final class PlannedSession {
    var id: UUID = UUID()
    var scheduledFor: Date = Date()
    var title: String = ""
    /// The routine encoded, so a session runs through the same engine as a
    /// hand-built one.
    var routineData: Data?
    var completedAt: Date?
    var perceivedEffort: Int?
    var block: Block?

    init(scheduledFor: Date, title: String, routine: IntervalRoutine?) {
        self.scheduledFor = scheduledFor
        self.title = title
        self.routineData = routine.flatMap { try? JSONEncoder().encode($0) }
    }

    var routine: IntervalRoutine? {
        guard let routineData else { return nil }
        return try? JSONDecoder().decode(IntervalRoutine.self, from: routineData)
    }

    var isComplete: Bool { completedAt != nil }
}

/// A routine the user built themselves. Kept separate from planned sessions so
/// the planner can never overwrite something you made.
@Model
final class SavedRoutine {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var lastRunAt: Date?
    var routineData: Data = Data()

    init(routine: IntervalRoutine) {
        self.routineData = (try? JSONEncoder().encode(routine)) ?? Data()
    }

    var routine: IntervalRoutine? {
        try? JSONDecoder().decode(IntervalRoutine.self, from: routineData)
    }
}

/// A set done off the plan — twenty squats while the kettle boils.
///
/// Deliberately **not** a mark. Rule 3 stands: one mark is one finished planned
/// session, and if loose work drew on the growth form the form would stop
/// meaning "I did the plan" and become a general activity log. It is still
/// worth keeping — it is real work, it is volume the planner should know about
/// when it decides next week, and an almanac records what happened rather than
/// only what was scheduled.
@Model
final class LoggedSet {
    var id: UUID = UUID()
    var date: Date = Date()
    /// Stored by name and equipment rather than as a `Move`, so a set kept
    /// today still reads correctly if the move library changes under it.
    var moveName: String = ""
    var equipmentRaw: String = Equipment.bodyweight.rawValue
    var reps: Int = 0
    /// Nil for bodyweight and the pad, which have nothing to load.
    var loadPounds: Double?

    init(move: Move, reps: Int, loadPounds: Double?, date: Date = .now) {
        self.date = date
        self.moveName = move.name
        self.equipmentRaw = move.equipment.rawValue
        self.reps = reps
        self.loadPounds = loadPounds
    }

    var equipment: Equipment { Equipment(rawValue: equipmentRaw) ?? .bodyweight }

    /// "12 × Beam front squat · 15 lb"
    var summary: String {
        let load = loadPounds.map { " · \(Int($0)) lb" } ?? ""
        return "\(reps) × \(moveName)\(load)"
    }
}

/// A weight reading. Source is recorded because a Health-sourced number and a
/// typed one deserve different trust when projecting.
@Model
final class WeightEntry {
    enum Source: String, Codable { case health, manual }

    var id: UUID = UUID()
    var date: Date = Date()
    var pounds: Double = 0
    var sourceRaw: String = Source.manual.rawValue

    init(date: Date, pounds: Double, source: Source) {
        self.date = date
        self.pounds = pounds
        self.sourceRaw = source.rawValue
    }

    var source: Source { Source(rawValue: sourceRaw) ?? .manual }
}

/// An eating window. Fasting is not a feature of this app so much as an input
/// to it — this exists to feed the projection and to show one line on Today.
@Model
final class FastWindow {
    var id: UUID = UUID()
    var lastBite: Date = Date()
    var windowOpensHour: Int = 12
    var windowOpensMinute: Int = 30
    var windowClosesHour: Int = 20
    var windowClosesMinute: Int = 30

    init(lastBite: Date = .now) {
        self.lastBite = lastBite
    }

    var elapsed: TimeInterval { Date.now.timeIntervalSince(lastBite) }

    var opensToday: Date? {
        Calendar.current.date(bySettingHour: windowOpensHour, minute: windowOpensMinute, second: 0, of: .now)
    }

    var summaryLine: String {
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        return "\(hours)h \(String(format: "%02d", minutes))m fasted"
    }
}

// MARK: - Container

enum Store {
    static let schema = Schema([
        Block.self, PlannedSession.self, SavedRoutine.self, WeightEntry.self,
        FastWindow.self, LoggedSet.self, MovePreference.self, MorningPractice.self
    ])

    /// Local-first, synced through the user's own private CloudKit database.
    /// No server of ours, and the watch app reads the same store.
    ///
    /// If the container fails to open we fall back to a local store rather than
    /// crashing: a signed-out iCloud account or a provisioning problem should
    /// cost you sync, not the ability to run a workout.
    ///
    /// Sync is behind `CLOUDKIT_SYNC` because that fallback cannot catch the
    /// failure that matters. Handed a container the process is not entitled to,
    /// CloudKit traps inside CoreData's mirroring delegate on its own queue —
    /// `try?` never sees it and the app dies at launch. iOS gives an app no
    /// supported way to read its own entitlements, so whether this build is
    /// provisioned for sync has to be stated at build time. Turn the flag on
    /// once the team, bundle identifier and iCloud container are real; until
    /// then the app runs local-only, which is the intended degradation anyway.
    @MainActor
    static func container(inMemory: Bool = false) -> ModelContainer {
        #if CLOUDKIT_SYNC
        if !inMemory {
            let synced = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudKitContainerIdentifier)
            )
            if let container = try? ModelContainer(for: schema, configurations: synced) {
                return container
            }
        }
        #endif

        let local = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: schema, configurations: local) {
            return container
        }

        // Neither store would open. There is no sensible way to continue.
        fatalError("Could not open the store, synced or local.")
    }

    static let cloudKitContainerIdentifier = "iCloud.com.wrktime.app"
}
