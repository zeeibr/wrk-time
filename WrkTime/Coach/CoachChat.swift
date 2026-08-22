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

/// The request side: the brief as a cached system block, the live context
/// after it, the conversation as it stands, and two tools the coach may use
/// to *propose* a change. Never applies anything.
struct CoachChat: Sendable {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let version = "2023-06-01"
    /// The same model as the planner, deliberately — one coach. Chat is
    /// shorter work, so the effort is a step below the planner's.
    static let model = ClaudePlanner.model
    static let effort = "medium"
    static let maxTokens = 8_000
    static let timeout: TimeInterval = 120

    var session: URLSession = .shared

    struct Reply: Sendable {
        var text: String
        var proposals: [CoachProposal]
        var usage: ClaudePlanner.Usage
    }

    enum Failure: LocalizedError {
        case noKey, http(Int, String), transport(Error), empty
        var errorDescription: String? {
            switch self {
            case .noKey: "No API key is set. Add one in Settings to talk to the coach."
            case .http(let code, let reason): "The coach could not answer (\(code)). \(reason)"
            case .transport(let error): "No connection. \(error.localizedDescription)"
            case .empty: "The coach sent nothing back."
            }
        }
    }

    /// The tools, as the API sees them. Two, deliberately small: the two
    /// changes the app already lets her make with a tap, and nothing the
    /// tap could not do.
    static var tools: [[String: Any]] {
        let names = MoveLibrary.available.filter { $0.kind == .strength }.map(\.name)
        return [
            [
                "name": "change_load",
                "description": "Propose moving one move to another load on its own equipment's ladder. She sees it as a card and decides; nothing changes until she taps it. Only a load the equipment can be set to.",
                "strict": true,
                "input_schema": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["move", "pounds", "why"],
                    "properties": [
                        "move": ["type": "string", "enum": names],
                        "pounds": ["type": "number", "enum": ClaudePlanner.legalLoads.filter { $0 > 0 }],
                        "why": ["type": "string", "description": "One sentence, in the brief's voice, that will sit on the card."]
                    ]
                ]
            ],
            [
                "name": "rule_out_move",
                "description": "Propose ruling a move out of her programme. She sees it as a card and decides; if she accepts, the sessions already written are repaired too.",
                "strict": true,
                "input_schema": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["move", "why"],
                    "properties": [
                        "move": ["type": "string", "enum": names],
                        "why": ["type": "string"]
                    ]
                ]
            ]
        ]
    }

    /// What only the chat needs to be told, after the brief.
    static var chatInstructions: String {
        """
        YOU ARE IN CONVERSATION
        She is talking to you from the app, usually on her phone, often between \
        sets. Answer in the brief's voice: plain, warm, specific, short — a few \
        sentences unless she asks for more. Name real numbers and real moves. \
        You know her plan and her numbers from the context that follows the \
        brief; use them rather than asking for them.

        You can propose two changes with the tools: moving a move to another \
        load, and ruling a move out. Each becomes a card she taps. Propose only \
        what her counts or her words have earned, never more than one or two at \
        a time, and say in words what you are proposing and why. Everything \
        else — the week's shape, a new move, how a session went — you discuss \
        and she decides; the planner writes weeks, you do not.

        You do not advise on food, fasting, supplements or medicine. You do not \
        invent studies. Health content is educational, never medical. No \
        exclamation marks, no emoji.

        \(ClaudePlanner.kitSection)

        \(ClaudePlanner.librarySection)
        """
    }

    /// One exchange. `priorMessages` is the stored conversation already in
    /// wire shape (`messages(from:)`), built on the main actor; `context` is
    /// the planner's own context, so the coach in conversation knows exactly
    /// what the coach writing the week knows.
    func reply(to text: String, priorMessages: Data,
               context: PlanContext) async throws -> Reply {
        guard let key = KeychainStore.read(.claudeAPIKey) else { throw Failure.noKey }

        // Serialised on the way in because a `[String: Any]` cannot cross an
        // actor; JSON can.
        var messages = (try? JSONSerialization.jsonObject(with: priorMessages) as? [[String: Any]]) ?? []
        // Results for the last answer's proposals ride with this message.
        if let last = messages.last, last["role"] as? String == "user",
           let content = last["content"] as? [[String: Any]],
           content.allSatisfy({ $0["type"] as? String == "tool_result" }) {
            messages[messages.count - 1]["content"] = content + [["type": "text", "text": text]]
        } else {
            messages.append(["role": "user", "content": text])
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = Self.timeout

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": Self.maxTokens,
            // The brief and the chat rules first, cached — they are the same
            // on every turn. Her live context after the breakpoint, because
            // it changes every day and must not break the cache.
            "system": [
                ["type": "text", "text": Self.systemText,
                 "cache_control": ["type": "ephemeral"]],
                ["type": "text", "text": "WHERE SHE IS TODAY\n" + context.prompt]
            ],
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": Self.effort],
            "tools": Self.tools,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.transport(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure.http(status, ClaudePlanner.reason(from: data))
        }
        return try Self.decode(data)
    }

    static var systemText: String {
        """
        You are the coach described below, in conversation with the one person \
        you coach, inside an app called Almanac.

        ===== THE COACH BRIEF =====
        \(CoachBrief.text)
        ===== END OF THE BRIEF =====

        \(chatInstructions)
        """
    }

    /// The stored turns as the API wants them. A proposal is a `tool_use`
    /// on the coach's turn and a `tool_result` at the head of her next one;
    /// a proposal she has not acted on is reported as exactly that, so the
    /// coach never assumes a change it only proposed.
    static func messages(from history: [CoachMessage]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var pendingResults: [[String: Any]] = []
        for turn in history {
            if turn.isHers {
                var content: [[String: Any]] = pendingResults
                pendingResults = []
                content.append(["type": "text", "text": turn.text])
                out.append(["role": "user", "content": content])
            } else {
                var content: [[String: Any]] = []
                if !turn.text.isEmpty { content.append(["type": "text", "text": turn.text]) }
                for proposal in turn.proposals {
                    var input: [String: Any] = ["move": proposal.moveName]
                    if let pounds = proposal.pounds { input["pounds"] = pounds }
                    content.append(["type": "tool_use", "id": proposal.id,
                                    "name": proposal.kind == .changeLoad ? "change_load" : "rule_out_move",
                                    "input": input])
                    pendingResults.append(["type": "tool_result", "tool_use_id": proposal.id,
                                           "content": proposal.result])
                }
                guard !content.isEmpty else { continue }
                out.append(["role": "assistant", "content": content])
            }
        }
        // Results for the last answer's proposals ride with her next message;
        // the caller appends it.
        if !pendingResults.isEmpty, let last = out.last, last["role"] as? String == "assistant" {
            out.append(["role": "user", "content": pendingResults])
        }
        return out
    }

    static func decode(_ data: Data) throws -> Reply {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]]
        else { throw Failure.empty }
        var text: [String] = []
        var proposals: [CoachProposal] = []
        for block in content {
            switch block["type"] as? String {
            case "text":
                if let t = block["text"] as? String, !t.isEmpty { text.append(t) }
            case "tool_use":
                guard let id = block["id"] as? String,
                      let name = block["name"] as? String,
                      let input = block["input"] as? [String: Any],
                      let move = input["move"] as? String else { continue }
                switch name {
                case "change_load":
                    let pounds = (input["pounds"] as? NSNumber)?.doubleValue
                    proposals.append(CoachProposal(id: id, kind: .changeLoad, moveName: move, pounds: pounds))
                case "rule_out_move":
                    proposals.append(CoachProposal(id: id, kind: .ruleOutMove, moveName: move))
                default: continue
                }
            default: continue
            }
        }
        let joined = text.joined(separator: "\n\n")
        guard !joined.isEmpty || !proposals.isEmpty else { throw Failure.empty }
        return Reply(text: joined, proposals: proposals, usage: ClaudePlanner.Usage.read(object))
    }
}

/// Applying a proposal: the same paths a tap takes anywhere else.
@MainActor
enum CoachActions {
    /// Carries out a proposal she accepted and returns the line to show.
    static func apply(_ proposal: CoachProposal, in context: ModelContext) -> String {
        let library = MoveLibrary.all + CustomMoves.strength(in: context)
        guard let move = library.first(where: {
            MovePreference.key($0.name) == MovePreference.key(proposal.moveName)
        }) else { return "That move is not in the library." }
        switch proposal.kind {
        case .changeLoad:
            guard let pounds = proposal.pounds,
                  move.equipment.availableLoadsPounds.contains(pounds)
            else { return "\(move.equipment.label) cannot be set to that." }
            MoveOverrides.set(pounds, for: move, in: context)
            return "\(move.name) now asks for \(Int(pounds)) lb — everywhere, including sessions already written."
        case .ruleOutMove:
            let summary = MovePreferences.set(.avoided, for: move.name, in: context)
            try? context.save()
            return summary.sessionsChanged > 0
                ? "\(move.name) is out, and \(summary.sessionsChanged) written \(summary.sessionsChanged == 1 ? "session" : "sessions") changed with it."
                : "\(move.name) is out."
        }
    }
}
