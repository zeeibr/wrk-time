import Foundation
import SwiftData

/// A turn in the conversation with the coach, kept locally.
///
/// The same coach the planner and the reviewer are — the brief as the
/// system prompt, her live numbers after it — finally with a mouth and
/// ears. Her words and its answers are stored here, and so are the
/// changes it proposed, because a proposal is a card she acts on and the
/// outcome is what the coach is told next.
///
/// The coach **proposes; the app applies.** A proposed change is never
/// executed by the model's say-so: it sits on the card until she taps it,
/// and then it goes through the same path a tap anywhere else would —
/// `MoveOverrides`, `MovePreferences` with its plan repair. That is the
/// brief's rule and the app's, and it is why the tools exist at all.
@Model
final class CoachMessage {
    var id: UUID = UUID()
    var date: Date = Date()
    /// "user" or "assistant".
    var role: String = "user"
    var text: String = ""
    /// Proposals the coach made in this turn, encoded `[Proposal]`. Nil on
    /// her turns and on answers that proposed nothing.
    var proposalsData: Data?
    /// What this turn cost, for the running line on the screen.
    var inputTokens: Int = 0
    var outputTokens: Int = 0

    init(role: String, text: String) {
        self.role = role
        self.text = text
        self.date = .now
    }

    var proposals: [CoachProposal] {
        get { proposalsData.flatMap { try? JSONDecoder().decode([CoachProposal].self, from: $0) } ?? [] }
        set { proposalsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var isHers: Bool { role == "user" }
}

/// One change the coach proposed, and what became of it.
struct CoachProposal: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case changeLoad, ruleOutMove }
    enum Outcome: String, Codable { case pending, applied, declined }

    /// The `tool_use` id, so the outcome can be sent back against it.
    var id: String
    var kind: Kind
    var moveName: String
    var pounds: Double?
    var outcome: Outcome = .pending

    /// "Move Kettlebell deadlift to 35 lb", "Rule out Beam good morning".
    var title: String {
        switch kind {
        case .changeLoad: "Move \(moveName) to \(Int(pounds ?? 0)) lb"
        case .ruleOutMove: "Rule out \(moveName)"
        }
    }

    /// The tool result the coach is told, in plain words.
    var result: String {
        switch outcome {
        case .pending: "She has not acted on this yet."
        case .applied: "Done — applied everywhere, including the sessions already written."
        case .declined: "She declined this."
        }
    }
}
