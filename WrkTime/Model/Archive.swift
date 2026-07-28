import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The whole store, as one readable file.
///
/// CloudKit already protects against a lost phone, but it is not a backup: it
/// is a mirror. Delete a session by accident and the deletion syncs; sign out
/// of iCloud, or hit a sync problem, and there is nothing to fall back to. This
/// is the copy you hold yourself, in a format you can open and read.
///
/// It deliberately does **not** carry the Claude API key. Secrets live in the
/// Keychain, marked this-device-only, and writing one into a file the user is
/// invited to put in iCloud Drive or email to themselves would undo the point
/// of that. Re-enter the key after a restore; nothing else needs re-entering.
struct Archive: Codable {
    /// Bumped when the shape changes, so a future version can refuse or migrate
    /// rather than decode something it half-understands.
    var version = 1
    var exportedAt: Date

    var blocks: [BlockRecord] = []
    var sessions: [SessionRecord] = []
    var routines: [RoutineRecord] = []
    var weights: [WeightRecord] = []
    var fasts: [FastRecord] = []
    var loggedSets: [LoggedSetRecord] = []

    struct BlockRecord: Codable {
        var id: UUID
        var startDate: Date
        var lengthInDays: Int
        var goalWeightPounds: Double
        var startingWeightPounds: Double
    }

    struct SessionRecord: Codable {
        var id: UUID
        var scheduledFor: Date
        var title: String
        var routineData: Data?
        var completedAt: Date?
        var perceivedEffort: Int?
        var blockID: UUID?
    }

    struct RoutineRecord: Codable {
        var id: UUID
        var createdAt: Date
        var lastRunAt: Date?
        var routineData: Data
    }

    struct WeightRecord: Codable {
        var id: UUID
        var date: Date
        var pounds: Double
        var sourceRaw: String
    }

    struct LoggedSetRecord: Codable {
        var id: UUID
        var date: Date
        var moveName: String
        var equipmentRaw: String
        var reps: Int
        var loadPounds: Double?
    }

    struct FastRecord: Codable {
        var id: UUID
        var lastBite: Date
        var windowOpensHour: Int
        var windowOpensMinute: Int
        var windowClosesHour: Int
        var windowClosesMinute: Int
    }

    /// A filename you can recognise in a folder a year from now.
    var suggestedFilename: String {
        let stamp = exportedAt.formatted(.iso8601.year().month().day())
        return "Almanac \(stamp).almanac"
    }
}

// MARK: - Reading and writing the store

@MainActor
enum ArchiveService {

    static func export(from context: ModelContext) throws -> Archive {
        var archive = Archive(exportedAt: .now)

        archive.blocks = try context.fetch(FetchDescriptor<Block>()).map {
            .init(id: $0.id, startDate: $0.startDate, lengthInDays: $0.lengthInDays,
                  goalWeightPounds: $0.goalWeightPounds,
                  startingWeightPounds: $0.startingWeightPounds)
        }
        archive.sessions = try context.fetch(FetchDescriptor<PlannedSession>()).map {
            .init(id: $0.id, scheduledFor: $0.scheduledFor, title: $0.title,
                  routineData: $0.routineData, completedAt: $0.completedAt,
                  perceivedEffort: $0.perceivedEffort, blockID: $0.block?.id)
        }
        archive.routines = try context.fetch(FetchDescriptor<SavedRoutine>()).map {
            .init(id: $0.id, createdAt: $0.createdAt, lastRunAt: $0.lastRunAt,
                  routineData: $0.routineData)
        }
        archive.weights = try context.fetch(FetchDescriptor<WeightEntry>()).map {
            .init(id: $0.id, date: $0.date, pounds: $0.pounds, sourceRaw: $0.sourceRaw)
        }
        archive.loggedSets = try context.fetch(FetchDescriptor<LoggedSet>()).map {
            .init(id: $0.id, date: $0.date, moveName: $0.moveName,
                  equipmentRaw: $0.equipmentRaw, reps: $0.reps, loadPounds: $0.loadPounds)
        }
        archive.fasts = try context.fetch(FetchDescriptor<FastWindow>()).map {
            .init(id: $0.id, lastBite: $0.lastBite,
                  windowOpensHour: $0.windowOpensHour,
                  windowOpensMinute: $0.windowOpensMinute,
                  windowClosesHour: $0.windowClosesHour,
                  windowClosesMinute: $0.windowClosesMinute)
        }
        return archive
    }

    /// What a restore did, so the app can say something true about it.
    struct Summary {
        var added = 0
        var alreadyPresent = 0
    }

    /// Merge, never replace.
    ///
    /// Records are matched on their identifier, so restoring the same file
    /// twice adds nothing the second time, and restoring an old file onto a
    /// newer store cannot delete work done since. A restore should be a safe
    /// thing to try when you are not sure whether you need it.
    @discardableResult
    static func restore(_ archive: Archive, into context: ModelContext) throws -> Summary {
        var summary = Summary()

        let existingBlocks = Set(try context.fetch(FetchDescriptor<Block>()).map(\.id))
        var blocksByID: [UUID: Block] = [:]
        for record in archive.blocks where !existingBlocks.contains(record.id) {
            let block = Block(startDate: record.startDate,
                              goalWeightPounds: record.goalWeightPounds,
                              startingWeightPounds: record.startingWeightPounds)
            block.id = record.id
            block.lengthInDays = record.lengthInDays
            context.insert(block)
            blocksByID[record.id] = block
            summary.added += 1
        }
        // Blocks already present still need to be findable, so restored
        // sessions can be re-attached to the right one.
        for block in try context.fetch(FetchDescriptor<Block>()) {
            blocksByID[block.id] = block
        }
        summary.alreadyPresent += archive.blocks.count - blocksByID.filter {
            !existingBlocks.contains($0.key)
        }.count

        let existingSessions = Set(try context.fetch(FetchDescriptor<PlannedSession>()).map(\.id))
        for record in archive.sessions {
            guard !existingSessions.contains(record.id) else {
                summary.alreadyPresent += 1
                continue
            }
            let session = PlannedSession(scheduledFor: record.scheduledFor,
                                         title: record.title, routine: nil)
            session.id = record.id
            session.routineData = record.routineData
            session.completedAt = record.completedAt
            session.perceivedEffort = record.perceivedEffort
            context.insert(session)
            if let blockID = record.blockID { session.block = blocksByID[blockID] }
            summary.added += 1
        }

        let existingRoutines = Set(try context.fetch(FetchDescriptor<SavedRoutine>()).map(\.id))
        for record in archive.routines {
            guard !existingRoutines.contains(record.id) else {
                summary.alreadyPresent += 1
                continue
            }
            // The stored blob is the source of truth; the initialiser only
            // needs something to encode over.
            let routine = SavedRoutine(routine: IntervalRoutine(name: "", work: 60, rest: 0,
                                                                rounds: 1, moves: []))
            routine.id = record.id
            routine.createdAt = record.createdAt
            routine.lastRunAt = record.lastRunAt
            routine.routineData = record.routineData
            context.insert(routine)
            summary.added += 1
        }

        let existingWeights = Set(try context.fetch(FetchDescriptor<WeightEntry>()).map(\.id))
        for record in archive.weights {
            guard !existingWeights.contains(record.id) else {
                summary.alreadyPresent += 1
                continue
            }
            let entry = WeightEntry(date: record.date, pounds: record.pounds,
                                    source: WeightEntry.Source(rawValue: record.sourceRaw) ?? .manual)
            entry.id = record.id
            context.insert(entry)
            summary.added += 1
        }

        let existingSets = Set(try context.fetch(FetchDescriptor<LoggedSet>()).map(\.id))
        for record in archive.loggedSets {
            guard !existingSets.contains(record.id) else {
                summary.alreadyPresent += 1
                continue
            }
            // Rebuilt from the stored name and equipment rather than looked up
            // in the move library, so a set kept months ago survives the
            // library changing under it.
            let equipment = Equipment(rawValue: record.equipmentRaw) ?? .bodyweight
            let move = Move(name: record.moveName, equipment: equipment, cue: "")
            let set = LoggedSet(move: move, reps: record.reps,
                                loadPounds: record.loadPounds, date: record.date)
            set.id = record.id
            context.insert(set)
            summary.added += 1
        }

        let existingFasts = Set(try context.fetch(FetchDescriptor<FastWindow>()).map(\.id))
        for record in archive.fasts {
            guard !existingFasts.contains(record.id) else {
                summary.alreadyPresent += 1
                continue
            }
            let window = FastWindow(lastBite: record.lastBite)
            window.id = record.id
            window.windowOpensHour = record.windowOpensHour
            window.windowOpensMinute = record.windowOpensMinute
            window.windowClosesHour = record.windowClosesHour
            window.windowClosesMinute = record.windowClosesMinute
            context.insert(window)
            summary.added += 1
        }

        try context.save()
        return summary
    }
}

// MARK: - Document

extension UTType {
    /// Its own type, so a restore cannot be handed an arbitrary JSON file.
    static let almanacArchive = UTType(exportedAs: "com.zee.almanac.archive")
}

/// Wraps the archive for `fileExporter`. Pretty-printed with sorted keys: a
/// backup you can open in a text editor and read is a backup you can trust.
struct ArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.almanacArchive, .json] }

    var archive: Archive

    init(archive: Archive) { self.archive = archive }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        archive = try Archive.decoder.decode(Archive.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Archive.encoder.encode(archive))
    }
}

extension Archive {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
