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
    var loggedSets: [LoggedSetRecord] = []

    /// Both default to empty, so a file written by an earlier build still
    /// decodes — and both are Optional-free arrays for the same reason every
    /// stored type here is careful: a missing key must not throw.
    ///
    /// These were simply missing. The store has eight model types and the
    /// archive carried six, so a restore onto a new phone silently dropped
    /// every opinion she had recorded about a move. The consequence is not a
    /// cosmetic gap: `PlannerService` passes those refusals to both planners as
    /// the excluded set, so the first week after a restore would program the
    /// movement that hurt her — and she would have to be hurt by it again to
    /// say so again. Her practice history went the same way, taking a streak
    /// with it.
    var preferences: [PreferenceRecord] = []
    var practices: [PracticeRecord] = []
    /// Workouts she did that the plan did not ask for. Added with the type, not
    /// after the fact — the store had eight models and this file carried six,
    /// and the two it dropped were her opinions about moves and her practice
    /// history. A new model is not finished until it is in here.
    var routineRuns: [RoutineRunRecord] = []

    struct BlockRecord: Codable {
        var id: UUID
        var startDate: Date
        var lengthInDays: Int
        var goalWeightPounds: Double
        var startingWeightPounds: Double
        /// Optional so older files decode. Its absence is why a restored block
        /// quietly switched to the default pace, changing how many sessions a
        /// week it wrote and how fast the load climbed.
        var paceRaw: String?
    }

    struct PreferenceRecord: Codable {
        var id: UUID
        var moveName: String
        var verdictRaw: String
        var updatedAt: Date
        var skipCount: Int
    }

    struct RoutineRunRecord: Codable {
        var id: UUID
        var finishedAt: Date
        var name: String
        var roundsCompleted: Int
        var seconds: TimeInterval
        var moveNames: [String]
        var sourceRaw: String
    }

    struct PracticeRecord: Codable {
        var id: UUID
        var day: Date
        var completedAt: Date
        var moveNames: [String]
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
                  startingWeightPounds: $0.startingWeightPounds,
                  paceRaw: $0.paceRaw)
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
        archive.preferences = try context.fetch(FetchDescriptor<MovePreference>()).map {
            .init(id: $0.id, moveName: $0.moveName, verdictRaw: $0.verdictRaw,
                  updatedAt: $0.updatedAt, skipCount: $0.skipCount)
        }
        archive.practices = try context.fetch(FetchDescriptor<MorningPractice>()).map {
            .init(id: $0.id, day: $0.day, completedAt: $0.completedAt,
                  moveNames: $0.moveNames)
        }
        archive.routineRuns = try context.fetch(FetchDescriptor<RoutineRun>()).map {
            .init(id: $0.id, finishedAt: $0.finishedAt, name: $0.name,
                  roundsCompleted: $0.roundsCompleted, seconds: $0.seconds,
                  moveNames: $0.moveNames, sourceRaw: $0.sourceRaw)
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
            // Only when the file carried one. An older archive has no pace, and
            // overwriting the default with nothing would be worse than keeping
            // it.
            if let paceRaw = record.paceRaw { block.paceRaw = paceRaw }
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

        // Her opinions about moves, which the archive used not to carry at all.
        // Restored before anything asks the planner for a week, so the first
        // week on a new phone already knows what hurt.
        let existingPreferences = Set(try context.fetch(FetchDescriptor<MovePreference>()).map(\.id))
        for record in archive.preferences {
            guard !existingPreferences.contains(record.id) else {
                summary.alreadyPresent += 1
                continue
            }
            let preference = MovePreference(moveName: record.moveName,
                                            verdict: MoveVerdict(rawValue: record.verdictRaw) ?? .disliked)
            preference.id = record.id
            preference.updatedAt = record.updatedAt
            preference.skipCount = record.skipCount
            context.insert(preference)
            summary.added += 1
        }

        // Matched on the day as well as the id, because these rows are the one
        // place a duplicate is silently wrong rather than visibly wrong: two
        // rows for one day do not show up anywhere, they just make the streak
        // and the fortnight strip disagree.
        let existingPractices = try context.fetch(FetchDescriptor<MorningPractice>())
        let practiceIDs = Set(existingPractices.map(\.id))
        var practiceDays = Set(existingPractices.map { Calendar.current.startOfDay(for: $0.day) })
        for record in archive.practices {
            let day = Calendar.current.startOfDay(for: record.day)
            guard !practiceIDs.contains(record.id), !practiceDays.contains(day) else {
                summary.alreadyPresent += 1
                continue
            }
            let practice = MorningPractice(day: record.day, moveNames: record.moveNames,
                                           completedAt: record.completedAt)
            practice.id = record.id
            practiceDays.insert(day)
            context.insert(practice)
            summary.added += 1
        }

        let existingRuns = Set(try context.fetch(FetchDescriptor<RoutineRun>()).map(\.id))
        for record in archive.routineRuns {
            guard !existingRuns.contains(record.id) else {
                summary.alreadyPresent += 1
                continue
            }
            let run = RoutineRun(name: record.name,
                                 roundsCompleted: record.roundsCompleted,
                                 seconds: record.seconds,
                                 moveNames: record.moveNames,
                                 source: RunSource(rawValue: record.sourceRaw) ?? .saved,
                                 finishedAt: record.finishedAt)
            run.id = record.id
            context.insert(run)
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
