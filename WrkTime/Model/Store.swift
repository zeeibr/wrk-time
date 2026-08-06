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
    /// CloudKit requires every relationship to declare its inverse, so this
    /// pairs with `PlannedSession.block`.
    @Relationship(deleteRule: .cascade, inverse: \PlannedSession.block)
    var sessions: [PlannedSession]? = []

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

// MARK: - Container

enum Store {
    static let schema = Schema([
        Block.self, PlannedSession.self, SavedRoutine.self, WeightEntry.self
    ])

    /// Local-first, synced through the user's own private CloudKit database.
    /// No server of ours, and the watch app reads the same store.
    ///
    /// If the container fails to open we fall back to a local store rather than
    /// crashing: a signed-out iCloud account or a provisioning problem should
    /// cost you sync, not the ability to run a workout.
    @MainActor
    static func container(inMemory: Bool = false) -> ModelContainer {
        let synced = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inMemory ? .none : .private(cloudKitContainerIdentifier)
        )
        if let container = try? ModelContainer(for: schema, configurations: synced) {
            return container
        }

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
