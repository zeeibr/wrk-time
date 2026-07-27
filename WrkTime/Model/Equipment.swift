import Foundation

/// The kit, and only the kit.
///
/// This enum is the guardrail for the whole app: the routine builder offers
/// nothing outside it, and the planner's response is validated against it, so a
/// generated session can never ask for a barbell.
enum Equipment: String, Codable, CaseIterable, Hashable, Identifiable {
    case beam
    case rings
    case dumbbells
    case walkingPad
    case bodyweight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .beam: "15 lb Bala Beam"
        case .rings: "Three Bala rings"
        case .dumbbells: "Two 2 lb dumbbells"
        case .walkingPad: "Walking pad"
        case .bodyweight: "Bodyweight"
        }
    }

    /// Short form for tight rows.
    var shortLabel: String {
        switch self {
        case .beam: "Beam"
        case .rings: "Rings"
        case .dumbbells: "Dumbbells"
        case .walkingPad: "Pad"
        case .bodyweight: "Bodyweight"
        }
    }

    var symbol: String {
        switch self {
        case .beam: "dumbbell"
        case .rings: "circle.circle"
        case .dumbbells: "dumbbell.fill"
        case .walkingPad: "figure.walk.motion"
        case .bodyweight: "figure.strengthtraining.functional"
        }
    }

    /// What the planner is allowed to say this can load.
    var loadDescription: String {
        switch self {
        case .beam: "15 lb"
        case .rings: "1 lb each"
        case .dumbbells: "2 lb each"
        case .walkingPad: "incline and pace"
        case .bodyweight: "no load"
        }
    }
}

/// The starting move library. The planner may add moves, but only ones whose
/// equipment is in `Equipment`, and only within the 60-second work ceiling.
enum MoveLibrary {
    static let all: [Move] = [
        Move(name: "Beam front squat", equipment: .beam,
             cue: "Beam across the collarbones. Three counts down, one to stand."),
        Move(name: "Beam deadlift", equipment: .beam,
             cue: "Hinge from the hips. The beam stays close to your shins."),
        Move(name: "Beam good morning", equipment: .beam,
             cue: "Soft knees, flat back. Stop when your hamstrings say so."),
        Move(name: "Beam hip thrust", equipment: .beam,
             cue: "Shoulders on the sofa edge, beam across the hips."),
        Move(name: "Ring halo", equipment: .rings,
             cue: "One ring in each hand, slow circles around the head."),
        Move(name: "Ring press-out", equipment: .rings,
             cue: "Press straight out from the chest and hold for a beat."),
        Move(name: "Dumbbell press", equipment: .dumbbells,
             cue: "Two pounds is enough when you go slowly."),
        Move(name: "Lateral raise", equipment: .dumbbells,
             cue: "Up to shoulder height, down over three counts."),
        Move(name: "Dead bug", equipment: .bodyweight,
             cue: "Ribs down, low back flat on the floor."),
        Move(name: "Zone 2 walk", equipment: .walkingPad,
             cue: "A pace you could hold a conversation at."),
        Move(name: "Incline walk", equipment: .walkingPad,
             cue: "Raise the incline before you raise the speed.")
    ]

    static func moves(for equipment: Equipment) -> [Move] {
        all.filter { $0.equipment == equipment }
    }
}
