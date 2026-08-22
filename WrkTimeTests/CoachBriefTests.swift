import Testing
import Foundation
@testable import WrkTime

/// The one coach, as the model calls will read it. No API is reached here:
/// these read the prompt and the schema, never send them.
@Suite("The coach brief")
struct CoachBriefTests {

    @Test("The brief ships in the bundle and is the one in docs")
    func loads() {
        #expect(CoachBrief.isLoaded)
        #expect(CoachBrief.text.contains("## 10. Loads and progression"))
        #expect(CoachBrief.text.contains("The coach **proposes; the app applies.**"))
    }

    @Test("The planner's prompt is the brief plus what only code can say")
    func plannerPrompt() {
        let prompt = ClaudePlanner.systemPrompt
        #expect(prompt.contains("===== THE COACH BRIEF ====="))
        #expect(prompt.contains("## 7. Rest"))
        // Generated from the enum, not typed: the 35 and the 15 are there.
        #expect(prompt.contains("9, 13, 18, 35 lb"))
        #expect(prompt.contains("10, 15 lb"))
        // And the library by pattern, with the mat marked.
        #expect(prompt.contains("- Hinge: "))
        #expect(prompt.contains("Dead bug [mat]"))
        // The old prose rules are gone.
        #expect(!prompt.contains("45 seconds is the standing default"))
        #expect(!prompt.contains("The kit tops out at"))
        #expect(!prompt.contains("!"), "the prompt exclaims")
    }

    @Test("The reviewer reads the same brief and asks for form")
    func reviewerPrompt() {
        let prompt = MoveReviewer.systemPrompt
        #expect(prompt.contains("===== THE COACH BRIEF ====="))
        #expect(prompt.contains("FORM"))
        #expect(!prompt.contains("A light resistance band"))
        let schema = MoveReviewer.schema as NSDictionary
        let defs = (schema["$defs"] as? [String: Any])?["move"] as? [String: Any]
        #expect((defs?["required"] as? [String])?.contains("form") == true)
    }

    @Test("The week's schema asks for a mode on every session")
    func schemaMode() {
        let schema = ClaudePlanner.schema(sessions: 5, moves: 5) as NSDictionary
        let defs = schema["$defs"] as? [String: Any]
        let session = defs?["session"] as? [String: Any]
        #expect((session?["required"] as? [String])?.contains("mode") == true)
        let mode = (session?["properties"] as? [String: Any])?["mode"] as? [String: Any]
        #expect((mode?["enum"] as? [String]) == ["intervals", "reps", "emom"])
    }

    @Test("A session on three implements is rejected whole")
    func threeImplements() {
        func draft(_ names: [(String, Equipment)]) -> PlanDraft {
            let moves = names.map { DraftMove(name: $0.0, equipment: $0.1.rawValue, cue: "", loadPounds: 0) }
            return PlanDraft(explanation: "", sessions: [
                DraftSession(dayOffset: 0, title: "Test", work: 40, rest: 20, rounds: 5, moves: moves)
            ], walkMinutes: 90)
        }
        let three = draft([("Kettlebell deadlift", .kettlebell), ("Beam row", .beam),
                           ("Dumbbell press", .dumbbells), ("Incline push-up", .bodyweight),
                           ("Dead bug", .bodyweight)])
        #expect(throws: PlanValidator.Failure.tooManyImplements("Test", 3)) {
            try PlanValidator.routines(from: three)
        }
        let two = draft([("Kettlebell deadlift", .kettlebell), ("Beam row", .beam),
                        ("Incline push-up", .bodyweight), ("Dead bug", .bodyweight)])
        #expect(throws: Never.self) { try PlanValidator.routines(from: two) }
    }

    @Test("Every offline week passes the validator, modes and all")
    func offlineWeeksValidate() throws {
        for pace in Pace.allCases {
            for week in 1...4 {
                let draft = OfflinePlanner.week(week, pace: pace, moves: 5)
                let routines = try PlanValidator.routines(from: draft)
                #expect(routines.count == pace.sessionsPerWeek)
                let modes = routines.map { $0.routine.mode }
                #expect(modes.contains(.reps), "\(pace) week \(week): \(modes)")
                #expect(modes.filter { $0 == .intervals }.count == 1, "\(pace) week \(week): \(modes)")
                for (_, routine) in routines where routine.mode == .emom {
                    #expect(routine.rounds == OfflinePlanner.emomMinutes)
                }
            }
        }
    }
}
