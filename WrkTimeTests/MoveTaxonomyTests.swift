import Testing
import Foundation
@testable import WrkTime

@Suite("Move taxonomy")
struct MoveTaxonomyTests {

    private func named(_ name: String) -> Move {
        MoveLibrary.all.first { $0.name == name }!
    }

    // A strength move the builder cannot place is a move it will order
    // wrongly. The table is hand-written, so the library and the table drift
    // the moment someone adds a move to one and not the other.
    @Test("Every strength move has a pattern and a position")
    func everyStrengthMoveClassified() {
        let missing = MoveLibrary.all
            .filter { $0.kind == .strength }
            .filter { MoveTaxonomy.pattern(for: $0.name) == nil
                   || MoveTaxonomy.position(for: $0.name) == nil }
            .map(\.name)
        #expect(missing.isEmpty, "unclassified: \(missing)")
    }

    @Test("Flow movements are not in the table")
    func flowIsNotStrength() {
        let classified = MoveLibrary.flow.filter { MoveTaxonomy.pattern(for: $0.name) != nil }
        #expect(classified.isEmpty, "flow classified as strength: \(classified.map(\.name))")
    }

    // The coach's five-move shape (brief §9) needs a hinge, a squat or lunge,
    // a row, a push and a floor core move — from what is actually owned and
    // from bodyweight alone, so a rotation can always be completed.
    @Test("Every family the session shape needs is reachable from the owned kit",
          arguments: MovePattern.Family.allCases.filter { $0 != .accessory })
    func familiesReachable(family: MovePattern.Family) {
        let owned = MoveLibrary.available.filter { $0.kind == .strength }
        let hits = owned.filter { MoveTaxonomy.pattern(for: $0.name)?.family == family }
        #expect(!hits.isEmpty, "no owned move for \(family)")
    }

    @Test("A floor core move exists with no equipment at all")
    func floorCoreBodyweight() {
        let hits = MoveLibrary.all.filter {
            $0.equipment == .bodyweight
                && MoveTaxonomy.pattern(for: $0.name)?.family == .core
                && MoveTaxonomy.position(for: $0.name) == .floor
        }
        #expect(hits.count >= 3)
    }

    @Test("Kneeling counts as already down")
    func kneelingIsDown() {
        #expect(MovePosition.standing.changes(to: .kneeling))
        #expect(MovePosition.standing.changes(to: .floor))
        #expect(!MovePosition.kneeling.changes(to: .floor))
        #expect(!MovePosition.floor.changes(to: .kneeling))
        #expect(MovePosition.floor.changes(to: .standing))
    }

    // Brief §8: 20 for a position change, 15 for an implement change, 30 for
    // both, nothing when neither changes.
    @Test("Setup seconds follow the brief")
    func setupSeconds() {
        let deadlift = named("Kettlebell deadlift")
        let goblet = named("Kettlebell goblet squat")
        let beamRow = named("Beam row")
        let deadBug = named("Dead bug")
        let floorPress = named("Dumbbell floor press")
        let pushUp = named("Incline push-up")

        #expect(MoveTaxonomy.setupSeconds(from: deadlift, to: goblet) == 0)
        #expect(MoveTaxonomy.setupSeconds(from: deadlift, to: beamRow) == 15)
        #expect(MoveTaxonomy.setupSeconds(from: deadlift, to: deadBug) == 20)
        #expect(MoveTaxonomy.setupSeconds(from: deadlift, to: floorPress) == 30)
        // Putting the bell down to push is not a fetch.
        #expect(MoveTaxonomy.setupSeconds(from: deadlift, to: pushUp) == 0)
        // Picking one up after bodyweight is.
        #expect(MoveTaxonomy.setupSeconds(from: pushUp, to: deadlift) == 15)
    }

    @Test("Rest between sets follows the brief")
    func rest() {
        #expect(MovePattern.hinge.restSeconds == 90)
        #expect(MovePattern.pullHorizontal.restSeconds == 75)
        #expect(MovePattern.coreAntiRotation.restSeconds == 45)
        #expect(MovePattern.accessory.restSeconds == 60)
        #expect(MovePattern.lunge.isBigLift)
        #expect(!MovePattern.pushVertical.isBigLift)
    }
}

@Suite("Form notes")
struct MoveFormTests {
    @Test("Every strength move has form notes")
    func everyStrengthMove() {
        let missing = MoveLibrary.all
            .filter { $0.kind == .strength && MoveForm.notes(for: $0.name) == nil }
            .map(\.name)
        #expect(missing.isEmpty, "no form notes: \(missing)")
    }

    @Test("Notes are five sentences and never empty")
    func fiveLines() {
        for move in MoveLibrary.all where move.kind == .strength {
            guard let form = MoveForm.notes(for: move.name) else { continue }
            for line in [form.setUp, form.movement, form.feel, form.wrong, form.stopIf] {
                #expect(!line.isEmpty, "\(move.name)")
                #expect(!line.contains("!"), "\(move.name) exclaims")
            }
        }
    }

    @Test("Flow movements carry no strength form")
    func flowHasNone() {
        #expect(MoveLibrary.flow.allSatisfy { MoveForm.notes(for: $0.name) == nil })
    }
}
