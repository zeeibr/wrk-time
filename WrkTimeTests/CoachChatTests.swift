import Testing
import Foundation
import SwiftData
@testable import WrkTime

/// The chat's request and response shapes. Nothing here reaches the API:
/// the wire shape is built and read, never sent.
@Suite("The coach in conversation")
@MainActor
struct CoachChatTests {

    @Test("The system text is the brief plus the chat's own rules")
    func system() {
        let text = CoachChat.systemText
        #expect(text.contains("===== THE COACH BRIEF ====="))
        #expect(text.contains("YOU ARE IN CONVERSATION"))
        #expect(text.contains("THE LIBRARY, BY PATTERN"))
        #expect(!text.contains("!"))
    }

    @Test("Two tools, strict, naming only library moves and real loads")
    func tools() {
        let tools = CoachChat.tools
        #expect(tools.map { $0["name"] as? String } == ["change_load", "rule_out_move"])
        for tool in tools {
            #expect(tool["strict"] as? Bool == true)
            let schema = tool["input_schema"] as? [String: Any]
            let move = (schema?["properties"] as? [String: Any])?["move"] as? [String: Any]
            let names = move?["enum"] as? [String] ?? []
            #expect(names.contains("Kettlebell deadlift"))
            #expect(!names.contains("Arm circles"), "flow is not a move the coach may change")
        }
        let load = ((tools[0]["input_schema"] as? [String: Any])?["properties"] as? [String: Any])?["pounds"] as? [String: Any]
        let pounds = load?["enum"] as? [Double] ?? []
        #expect(pounds.contains(35) && !pounds.contains(0))
    }

    @Test("A proposal becomes a tool_use, and its outcome a tool_result on her next turn")
    func wire() {
        let hers = CoachMessage(role: "user", text: "Is the 18 too light?")
        let coach = CoachMessage(role: "assistant", text: "Your counts say so.")
        var proposal = CoachProposal(id: "toolu_1", kind: .changeLoad, moveName: "Kettlebell deadlift", pounds: 35)
        proposal.outcome = .applied
        coach.proposals = [proposal]
        let again = CoachMessage(role: "user", text: "Thanks")

        let wire = CoachChat.messages(from: [hers, coach, again])
        #expect(wire.count == 3)
        let assistant = wire[1]["content"] as? [[String: Any]]
        #expect(assistant?.count == 2)
        #expect(assistant?[1]["type"] as? String == "tool_use")
        #expect(assistant?[1]["id"] as? String == "toolu_1")
        let next = wire[2]["content"] as? [[String: Any]]
        #expect(next?[0]["type"] as? String == "tool_result")
        #expect(next?[0]["tool_use_id"] as? String == "toolu_1")
        #expect((next?[0]["content"] as? String)?.hasPrefix("Done") == true)
        #expect(next?[1]["type"] as? String == "text")
    }

    @Test("A proposal she has not acted on is reported as exactly that")
    func pending() {
        let coach = CoachMessage(role: "assistant", text: "")
        coach.proposals = [CoachProposal(id: "toolu_2", kind: .ruleOutMove, moveName: "Beam good morning")]
        let wire = CoachChat.messages(from: [CoachMessage(role: "user", text: "hi"), coach])
        // The results ride as a trailing user turn, for the caller to append to.
        let last = wire.last?["content"] as? [[String: Any]]
        #expect(wire.count == 3)
        #expect(last?.first?["type"] as? String == "tool_result")
        #expect((last?.first?["content"] as? String)?.contains("not acted") == true)
    }

    @Test("The response's text and tool calls are read; the rest is ignored")
    func decode() throws {
        let json = """
        {"content":[{"type":"thinking","thinking":""},
                    {"type":"text","text":"Twelve on every set, twice."},
                    {"type":"tool_use","id":"toolu_9","name":"change_load",
                     "input":{"move":"Kettlebell deadlift","pounds":35,"why":"Earned."}}],
         "usage":{"input_tokens":7000,"output_tokens":120}}
        """
        let reply = try CoachChat.decode(Data(json.utf8))
        #expect(reply.text == "Twelve on every set, twice.")
        #expect(reply.proposals == [CoachProposal(id: "toolu_9", kind: .changeLoad,
                                                  moveName: "Kettlebell deadlift", pounds: 35)])
        #expect(reply.usage.inputTokens == 7000)
    }

    @Test("Applying a proposal goes through the same paths a tap takes")
    func apply() throws {
        let container = try ModelContainer(for: MoveOverride.self, MovePreference.self, PlannedSession.self,
                                           CustomMove.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let line = CoachActions.apply(CoachProposal(id: "a", kind: .changeLoad,
                                                    moveName: "Kettlebell deadlift", pounds: 35), in: context)
        #expect(line.contains("35 lb"))
        #expect(MoveOverrides.table(in: context)["kettlebell deadlift"] == 35)
        // A load the kit cannot be set to is refused here too, whatever the model said.
        let bad = CoachActions.apply(CoachProposal(id: "b", kind: .changeLoad,
                                                   moveName: "Kettlebell deadlift", pounds: 40), in: context)
        #expect(bad.contains("cannot"))
        let out = CoachActions.apply(CoachProposal(id: "c", kind: .ruleOutMove,
                                                   moveName: "Beam good morning"), in: context)
        #expect(out.contains("is out"))
        #expect(MovePreferences.verdict(for: "Beam good morning", in: context) == .avoided)
    }
}
