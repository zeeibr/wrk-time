import Testing
import Foundation
import SwiftData
@testable import WrkTime

/// The coach's session shape, `docs/COACH-BRIEF.md` §8–9, held by the one
/// rotation builder so every rotation the app writes has it.
@Suite("A rotation has the coach's shape")
struct RotationShapeTests {

    private func families(_ moves: [Move]) -> [MovePattern.Family] {
        moves.compactMap { MoveTaxonomy.pattern(for: $0.name)?.family }
    }

    @Test("Five moves cover lower, lower, pull, push and core")
    func fiveCover() {
        for turn in 0..<30 {
            let out = MoveLibrary.rotation(of: 5, varying: turn)
            let f = families(out)
            #expect(out.count == 5)
            #expect(f.filter { $0 == .lower }.count == 2, "turn \(turn): \(out.map(\.name))")
            #expect(f.contains(.pull), "turn \(turn): \(out.map(\.name))")
            #expect(f.contains(.push), "turn \(turn): \(out.map(\.name))")
            #expect(f.contains(.core), "turn \(turn): \(out.map(\.name))")
        }
    }

    @Test("The first move is a hinge and the squat and lunge alternate")
    func hingeThenSquatOrLunge() {
        for turn in 0..<20 {
            let out = MoveLibrary.rotation(of: 5, varying: turn)
            #expect(MoveTaxonomy.pattern(for: out[0].name) == .hinge, "turn \(turn): \(out[0].name)")
            let second = MoveTaxonomy.pattern(for: out[1].name)
            #expect(second == (turn.isMultiple(of: 2) ? .squat : .lunge), "turn \(turn): \(out[1].name)")
        }
    }

    @Test("Standing first, the floor last, and she never gets back up")
    func neverBackUp() {
        for kit in [Set<Equipment>(), [.kettlebell], [.beam], [.rings], [.dumbbells], [.singleDumbbell]] {
            for turn in 0..<20 {
                let out = MoveLibrary.rotation(of: 5, preferring: kit, varying: turn)
                let positions = out.map { MoveTaxonomy.position(for: $0.name) ?? .standing }
                let wentDown = positions.firstIndex { $0 != .standing } ?? positions.count
                #expect(positions[wentDown...].allSatisfy { $0 != .standing },
                        "\(kit) turn \(turn): \(out.map(\.name))")
            }
        }
    }

    @Test("A session fetches at most two implements")
    func twoImplements() {
        for kit in [Set<Equipment>(), [.kettlebell], [.beam], [.rings], [.dumbbells], [.singleDumbbell]] {
            for turn in 0..<20 {
                let out = MoveLibrary.rotation(of: 5, preferring: kit, varying: turn)
                #expect(MoveLibrary.implements(in: out).count <= 2,
                        "\(kit) turn \(turn): \(out.map(\.name))")
            }
        }
    }

    @Test("A kettlebell day stays on the bell while the bell has the pattern")
    func bellDay() {
        for turn in 0..<10 {
            let out = MoveLibrary.rotation(of: 5, preferring: [.kettlebell], varying: turn)
            // The hinge and the row exist on the bell, so they are the
            // bell's. The lunge does not (no kettlebell lunge is written),
            // the push and the floor core do not either, and bodyweight is
            // not a fetch — so those may go empty-handed.
            #expect(out[0].equipment == .kettlebell, "turn \(turn): \(out.map(\.name))")
            let row = out.first { MoveTaxonomy.pattern(for: $0.name)?.family == .pull }
            #expect(row?.equipment == .kettlebell, "turn \(turn): \(out.map(\.name))")
        }
    }

    @Test("Ordering is stable and never drops or adds a move")
    func orderedIsPermutation() {
        let squat = MoveLibrary.all.first { $0.name == "Air squat" }!
        let bug = MoveLibrary.all.first { $0.name == "Dead bug" }!
        let row = MoveLibrary.all.first { $0.name == "Kettlebell row" }!
        let hinge = MoveLibrary.all.first { $0.name == "Kettlebell deadlift" }!
        let custom = Move(name: "Her own move", equipment: .bodyweight, cue: "")
        let out = MoveLibrary.ordered([bug, custom, row, squat, hinge])
        #expect(out.map(\.name) == ["Kettlebell deadlift", "Air squat", "Kettlebell row",
                                    "Her own move", "Dead bug"])
    }

    @Test("Growing a rotation fills what it lacks, not what it has")
    func holdingCovers() {
        let hinge = MoveLibrary.all.first { $0.name == "Kettlebell deadlift" }!
        let squat = MoveLibrary.all.first { $0.name == "Kettlebell goblet squat" }!
        let added = MoveLibrary.rotation(of: 3, preferring: [.kettlebell],
                                         excluding: Set([hinge, squat].map { MovePreference.key($0.name) }),
                                         holding: [hinge, squat], varying: 0)
        let f = families(added)
        #expect(added.count == 3)
        #expect(!f.contains(.lower), "\(added.map(\.name))")
        #expect(f.contains(.pull) && f.contains(.push) && f.contains(.core), "\(added.map(\.name))")
    }

    @Test("The offline week is five full-body sessions in the shape")
    func offlineWeek() throws {
        // `moves:` spelled out: another suite sets `Tuning.movesPerSession` and
        // the suites run in parallel.
        let draft = OfflinePlanner.week(1, pace: .steady, moves: 5)
        for session in draft.sessions {
            let moves = session.moves.compactMap { d in MoveLibrary.all.first { $0.name == d.name } }
            #expect(moves.count == session.moves.count, "\(session.title)")
            let f = families(moves)
            #expect(f.filter { $0 == .lower }.count == 2, "\(session.title): \(moves.map(\.name))")
            #expect(f.contains(.pull) && f.contains(.push) && f.contains(.core),
                    "\(session.title): \(moves.map(\.name))")
            #expect(MoveLibrary.implements(in: moves).count <= 2)
            print("  \(session.title): " + moves.map { "\($0.name) [\($0.equipmentLabel)]" }.joined(separator: " · "))
        }
    }
}

@Suite("A written week runs in the new order")
struct PendingOrderTests {
    private func store() throws -> ModelContext {
        let container = try ModelContainer(for: PlannedSession.self, MoveOverride.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func named(_ name: String) -> Move { MoveLibrary.all.first { $0.name == name }! }

    @Test("A pending session reads back standing first, floor last")
    func pendingIsOrdered() throws {
        let context = try store()
        let chop = [named("Dead bug"), named("Beam row"), named("Glute bridge"),
                    named("Kettlebell deadlift"), named("Incline push-up")]
        let session = PlannedSession(scheduledFor: .now, title: "Old week",
                                     routine: IntervalRoutine(name: "Old week", work: 40, rest: 20,
                                                              rounds: 5, moves: chop))
        context.insert(session)
        let names = try #require(session.routine?.moves.map(\.name))
        // Both floor moves are core, so inside the floor block their
        // original order holds — the sort is stable on purpose.
        #expect(names == ["Kettlebell deadlift", "Beam row", "Incline push-up",
                          "Dead bug", "Glute bridge"])
    }

    @Test("A finished session is a record and keeps the order it ran in")
    func finishedIsFrozen() throws {
        let context = try store()
        let chop = [named("Dead bug"), named("Beam row"), named("Kettlebell deadlift")]
        let session = PlannedSession(scheduledFor: .now, title: "Ran",
                                     routine: IntervalRoutine(name: "Ran", work: 40, rest: 20,
                                                              rounds: 3, moves: chop))
        session.completedAt = .now
        context.insert(session)
        #expect(session.routine?.moves.map(\.name) == chop.map(\.name))
    }
}
