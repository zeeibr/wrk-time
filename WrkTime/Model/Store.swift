import Foundation
import SwiftData

/// An 84-day block. The planner writes one of these and revises it weekly.
@Model
final class Block {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var lengthInDays: Int = 84
    var goalWeightPounds: Double = 0
    var startingWeightPounds: Double = 0
    @Relationship(deleteRule: .cascade) var sessions: [PlannedSession] = []

    init(startDate: Date = .now, goalWeightPounds: Double, startingWeightPounds: Double) {
        self.startDate = startDate
        self.goalWeightPounds = goalWeightPounds
        self.startingWeightPounds = startingWeightPounds
    }

    var dayNumber: Int {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: .now).day ?? 0
        return min(max(days + 1, 1), lengthInDays)
    }

    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: lengthInDays, to: startDate) ?? startDate
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
        Block.self, PlannedSession.self, SavedRoutine.self, WeightEntry.self, FastWindow.self
    ])

    /// Local by default so the project builds and runs on a fresh checkout.
    ///
    /// CloudKit sync — which the watch app will need — requires a paid team, the
    /// iCloud capability, and a container identifier. Turn it on by adding
    /// `CLOUDKIT_SYNC` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` once that is set
    /// up; switching it on without the entitlement fails at launch, which is a
    /// worse first run than no sync.
    @MainActor
    static func container(inMemory: Bool = false) -> ModelContainer {
        #if CLOUDKIT_SYNC
        let database: ModelConfiguration.CloudKitDatabase = inMemory ? .none : .automatic
        #else
        let database: ModelConfiguration.CloudKitDatabase = .none
        #endif
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: database
        )
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // A store that cannot open is not recoverable at runtime; failing
            // loudly in development beats shipping silent data loss.
            fatalError("Could not open the store: \(error)")
        }
    }
}
