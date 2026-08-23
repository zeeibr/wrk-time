import Testing
import Foundation
@testable import WrkTime

@Suite("Plates by movement")
struct PlateKeyTests {
    @Test("A strip with kit in hand is only given to a move on that kit")
    func kitAgrees() {
        for move in MoveLibrary.all {
            guard let strip = MovePlates.strip(for: move), let kit = strip.equipment else { continue }
            #expect(kit == move.equipment, "\(move.name) drew with \(strip.key) on \(kit)")
        }
    }

    @Test("The drawn set is the one the port started with")
    func drawnSet() {
        let drawn = MoveLibrary.all.filter { MovePlates.strip(for: $0) != nil }.map(\.name)
        #expect(drawn.count == PlateSnapshot.drawnCount, "\(drawn.count) drawn")
        for name in PlateSnapshot.drawn where !drawn.contains(name) { Issue.record("\(name) lost its drawing") }
        for name in drawn where !PlateSnapshot.drawn.contains(name) { Issue.record("\(name) gained one unexpectedly") }
    }
}

/// The drawn set on 22 August 2026, after the mat was drawn. Regenerate on purpose.
enum PlateSnapshot {
    static let drawnCount = 108
    static let drawn: [String] = [
        "Beam deadlift",
        "Ring deadlift",
        "Kettlebell deadlift",
        "Beam good morning",
        "Kickstand deadlift",
        "Suitcase deadlift",
        "Ring goblet squat",
        "Kettlebell goblet squat",
        "Single-dumbbell goblet squat",
        "Beam front squat",
        "Kettlebell sumo squat",
        "Air squat",
        "Wall sit",
        "Beam reverse lunge",
        "Reverse lunge",
        "Beam lateral lunge",
        "Split squat",
        "Beam row",
        "Ring row",
        "Kettlebell row",
        "Dumbbell row",
        "Single-dumbbell row",
        "Rear delt fly",
        "Upright row",
        "Pullover",
        "Wall angel",
        "Beam overhead press",
        "Ring overhead press",
        "Dumbbell press",
        "Single-dumbbell overhead press",
        "Tall-kneeling press",
        "Ring Arnold press",
        "Arnold press",
        "Beam floor press",
        "Dumbbell floor press",
        "Single-dumbbell floor press",
        "Ring press-out",
        "Squeeze press",
        "Floor fly",
        "Boxer punches",
        "Incline push-up",
        "Beam overhead hold",
        "Ring half-kneeling overhead hold",
        "Kettlebell carry",
        "Dumbbell march",
        "Ring halo",
        "Kettlebell around the body",
        "Dead bug",
        "Dumbbell dead bug press",
        "Plank pull-through",
        "Bird dog",
        "Forearm plank",
        "Side plank",
        "Plank shoulder tap",
        "Russian twist",
        "Standing side bend",
        "Lying leg raise",
        "Bicycle crunch",
        "Glute bridge",
        "Ring bridge",
        "Beam hip thrust",
        "One-leg bridge",
        "Superman",
        "Reverse tabletop hold",
        "Bicep curl",
        "Beam curl",
        "Ring bicep curl",
        "Single-dumbbell curl",
        "Ring triceps extension",
        "Overhead extension",
        "Beam triceps extension",
        "Tricep kickback",
        "Ring kickback",
        "Tricep press-back",
        "Lateral raise",
        "Front raise",
        "Ring front raise",
        "Ring behind-back raise",
        "Around the world",
        "Dumbbell shrug",
        "Raise the platters",
        "Side leg lift",
        "Lymphatic bounce",
        "Arm swings",
        "Shoulder rolls",
        "Neck release",
        "Spinal wave",
        "Hip circles",
        "Cat cow",
        "Lymphatic tapping",
        "Standing twist",
        "Ankle and wrist circles",
        "Forward fold hang",
        "Chest opener",
        "Standing march",
        "Arm circles",
        "Deep squat hold",
        "Ankle rocking",
        "Corkscrew",
        "Allen wrench",
        "Vertical arm swings",
        "Bent-over trunk twists",
        "Slam dunks",
        "Golf swings",
        "High knee circles",
        "Thread the needle",
        "Child\'s pose reach",
        "Sun breath",
    ]
}
