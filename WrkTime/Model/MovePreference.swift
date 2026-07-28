import Foundation
import SwiftData

/// Why a move got skipped, and what the plan should do about it.
///
/// The options exist because "skipped" on its own is unreadable. Skipping a
/// move because it hurt and skipping it because the kettle boiled are opposite
/// facts, and a planner that treats them the same will either keep prescribing
/// something painful or quietly delete a move she likes.
enum SkipReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case hurt
    case disliked
    case tooHard
    case noRoom
    case noTime

    var id: String { rawValue }

    /// Plain, and never phrased as a failure.
    var label: String {
        switch self {
        case .hurt: "It hurt, or felt wrong"
        case .disliked: "I just don't like it"
        case .tooHard: "Too hard today"
        case .noRoom: "No room, or the kit wasn't to hand"
        case .noTime: "Ran out of time"
        }
    }

    /// What the plan does about it, said out loud so the consequence is never
    /// a surprise.
    var consequence: String {
        switch self {
        case .hurt: "Dropped from the plan."
        case .disliked: "You'll see much less of it."
        case .tooHard: "Kept, but easier next time."
        case .noRoom: "Kept — that's about the room, not the move."
        case .noTime: "No change. A short day is a short day."
        }
    }

    /// The verdict this reason records, if any. Two of the five deliberately
    /// record nothing: running out of time says nothing about the move.
    var verdict: MoveVerdict? {
        switch self {
        case .hurt: .avoided
        case .disliked: .disliked
        case .tooHard: .hard
        case .noRoom, .noTime: nil
        }
    }
}

/// How a move stands with her.
enum MoveVerdict: String, Codable, Sendable {
    /// Never program it again. Reserved for pain — the one signal that should
    /// override everything else the planner wants to do.
    case avoided
    /// Program it rarely. She can still choose it herself.
    case disliked
    /// Fine, but scale it down.
    case hard
    /// She asked for more of this.
    case liked
}

/// A standing opinion about one move.
///
/// Keyed by name rather than by a `Move` identifier because the planner invents
/// moves that were never in the library — "single-arm ring row" arrives from
/// Claude, not from `MoveLibrary` — and an opinion about it has to survive
/// anyway. Names are compared case- and whitespace-insensitively for the same
/// reason: two spellings of the same movement are the same movement.
@Model
final class MovePreference {
    var id: UUID = UUID()
    var moveName: String = ""
    var verdictRaw: String = MoveVerdict.disliked.rawValue
    var updatedAt: Date = Date()
    /// How many times it has been skipped, so a pattern can outweigh one bad day.
    var skipCount: Int = 0

    init(moveName: String, verdict: MoveVerdict) {
        self.moveName = moveName
        self.verdictRaw = verdict.rawValue
        self.updatedAt = .now
        self.skipCount = 1
    }

    var verdict: MoveVerdict {
        get { MoveVerdict(rawValue: verdictRaw) ?? .disliked }
        set { verdictRaw = newValue.rawValue }
    }

    /// The comparison key. One place, so storing and looking up cannot drift.
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var key: String { Self.key(moveName) }

    /// Whether this opinion covers `name`.
    ///
    /// Containment in either direction, because a dislike is usually about a
    /// *family* of movement rather than one spelling of it. Saying you dislike
    /// push-ups should quietly cover the incline and knee variants — the
    /// planner invents those names freely, and a preference that only matched
    /// the exact string would be defeated by the first adjective.
    func covers(_ name: String) -> Bool {
        let candidate = Self.key(name)
        let mine = key
        guard !candidate.isEmpty, !mine.isEmpty else { return false }
        return candidate.contains(mine) || mine.contains(candidate)
    }
}

// MARK: - Reading and writing

@MainActor
enum MovePreferences {
    static func all(in context: ModelContext) -> [MovePreference] {
        (try? context.fetch(FetchDescriptor<MovePreference>())) ?? []
    }

    static func verdict(for name: String, in context: ModelContext) -> MoveVerdict? {
        // Avoidance wins any tie: if one opinion says a movement hurt, that
        // outranks a milder verdict on an overlapping name.
        let matches = all(in: context).filter { $0.covers(name) }
        if matches.contains(where: { $0.verdict == .avoided }) { return .avoided }
        return matches.first?.verdict
    }

    /// Sets a verdict directly, without a skip — used by the move rows on
    /// Today, so an opinion can be recorded without having to abandon a set to
    /// express it.
    static func set(_ verdict: MoveVerdict, for name: String, in context: ModelContext) {
        if let existing = all(in: context).first(where: { $0.key == MovePreference.key(name) }) {
            existing.verdict = verdict
            existing.updatedAt = .now
        } else {
            context.insert(MovePreference(moveName: name, verdict: verdict))
        }
    }

    static func clear(_ name: String, in context: ModelContext) {
        for preference in all(in: context) where preference.key == MovePreference.key(name) {
            context.delete(preference)
        }
    }

    /// Records what she said. Pain is sticky: once a move is avoided, a later
    /// "too hard" does not quietly promote it back into the rotation.
    static func record(_ reason: SkipReason, for name: String, in context: ModelContext) {
        guard let verdict = reason.verdict else { return }
        let key = MovePreference.key(name)

        if let existing = all(in: context).first(where: { $0.key == key }) {
            existing.skipCount += 1
            existing.updatedAt = .now
            if existing.verdict != .avoided { existing.verdict = verdict }
        } else {
            context.insert(MovePreference(moveName: name, verdict: verdict))
        }
    }

    /// Names the planner must not use, and names it should use sparingly.
    static func lists(in context: ModelContext) -> (avoided: [String], disliked: [String], hard: [String]) {
        let preferences = all(in: context)
        return (
            preferences.filter { $0.verdict == .avoided }.map(\.moveName),
            preferences.filter { $0.verdict == .disliked }.map(\.moveName),
            preferences.filter { $0.verdict == .hard }.map(\.moveName)
        )
    }
}
