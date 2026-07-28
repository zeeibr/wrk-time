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
        case .rings: "Bala power rings · 5, 8, 10 lb"
        case .dumbbells: "Two 2 lb Peloton dumbbells"
        case .walkingPad: "Walking pad"
        case .bodyweight: "Bodyweight"
        }
    }

    /// What a *particular* move asks you to pick up.
    ///
    /// `label` describes the whole inventory, which is what the equipment
    /// picker wants. On a move it is wrong: the rings are three separate items,
    /// so printing "Bala power rings · 5, 8, 10 lb" under a deadlift that uses
    /// the 10 lb ring reads as an instruction to hold all three.
    func label(forLoad pounds: Double?) -> String {
        guard let pounds, pounds > 0 else { return label }
        let weight = pounds == pounds.rounded() ? "\(Int(pounds))" : "\(pounds)"
        switch self {
        case .rings: return "\(weight) lb Bala power ring"
        case .beam: return "\(weight) lb Bala Beam"
        case .dumbbells: return "Two \(weight) lb Peloton dumbbells"
        case .walkingPad, .bodyweight: return label
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
        case .rings: "5, 8 or 10 lb"
        case .dumbbells: "2 lb each"
        case .walkingPad: "incline and pace"
        case .bodyweight: "no load"
        }
    }

    /// Every load this piece can actually be set to, in pounds.
    ///
    /// The rings are the reason this exists. They are three *different* weights
    /// — not a matched set — so "one in each hand" is only true for a pair you
    /// choose, and a generated move that assumes a uniform load is wrong. The
    /// planner validates against these numbers, not against a description.
    var availableLoadsPounds: [Double] {
        switch self {
        case .beam: [15]
        case .rings: [5, 8, 10]
        case .dumbbells: [2]
        case .walkingPad: []
        case .bodyweight: []
        }
    }
}

/// The starting move library. The planner may add moves, but only ones whose
/// equipment is in `Equipment`, and only within the 60-second work ceiling.
enum MoveLibrary {
    static let all: [Move] = [
        Move(name: "Beam front squat", equipment: .beam,
             cue: "Beam across the collarbones. Three counts down, one to stand.",
             loadPounds: 15),
        Move(name: "Beam deadlift", equipment: .beam,
             cue: "Hinge from the hips. The beam stays close to your shins.",
             loadPounds: 15),
        Move(name: "Beam good morning", equipment: .beam,
             cue: "Soft knees, flat back. Stop when your hamstrings say so.",
             loadPounds: 15),
        Move(name: "Beam hip thrust", equipment: .beam,
             cue: "Shoulders on the sofa edge, beam across the hips.",
             loadPounds: 15),
        Move(name: "Ring halo", equipment: .rings,
             cue: "The 5 lb ring in both hands, slow circles around the head.",
             loadPounds: 5),
        Move(name: "Ring press-out", equipment: .rings,
             cue: "Hold the 8 lb ring at the chest and press straight out.",
             loadPounds: 8),
        Move(name: "Ring deadlift", equipment: .rings,
             cue: "The 10 lb ring between the feet. Hinge, don't squat.",
             loadPounds: 10),
        // Two pounds is a real load on a long lever held slowly, which is why
        // these are all shoulder and arm work. The weight never changes here —
        // tempo, range and rest do — so the library carries enough variety to
        // make a whole session out of them.
        Move(name: "Dumbbell press", equipment: .dumbbells,
             cue: "Two pounds is enough when you go slowly.",
             loadPounds: 2),
        Move(name: "Lateral raise", equipment: .dumbbells,
             cue: "Up to shoulder height, down over three counts.",
             loadPounds: 2),
        Move(name: "Front raise", equipment: .dumbbells,
             cue: "Straight arms to eye height. Stop before the shoulders shrug.",
             loadPounds: 2),
        Move(name: "Rear delt fly", equipment: .dumbbells,
             cue: "Hinge forward, open wide, squeeze between the shoulder blades.",
             loadPounds: 2),
        Move(name: "Arnold press", equipment: .dumbbells,
             cue: "Palms in at the chin, rotate out as you press up.",
             loadPounds: 2),
        Move(name: "Bicep curl", equipment: .dumbbells,
             cue: "Elbows pinned to your sides. Three counts down every time.",
             loadPounds: 2),
        Move(name: "Tricep kickback", equipment: .dumbbells,
             cue: "Upper arm still and parallel to the floor. Only the forearm moves.",
             loadPounds: 2),
        Move(name: "Floor fly", equipment: .dumbbells,
             cue: "On your back, soft elbows, open until the arms touch the floor.",
             loadPounds: 2),
        Move(name: "Around the world", equipment: .dumbbells,
             cue: "Arms wide, sweep overhead until they meet, and back the same way.",
             loadPounds: 2),
        Move(name: "Boxer punches", equipment: .dumbbells,
             cue: "Alternating, chest height, controlled. The shoulders do the work.",
             loadPounds: 2),
        // Bodyweight is equipment. It needs no load and it is always to hand,
        // which makes it the one part of the kit that never runs out of
        // progressions — and the library had exactly one of them, so a
        // hand-built session could barely use it.
        Move(name: "Dead bug", equipment: .bodyweight,
             cue: "Ribs down, low back flat on the floor."),
        Move(name: "Incline push-up", equipment: .bodyweight,
             cue: "Hands on the counter. The higher the hands, the easier it is."),
        Move(name: "Reverse lunge", equipment: .bodyweight,
             cue: "Step back, not forward. The front knee stays over the ankle."),
        Move(name: "Glute bridge", equipment: .bodyweight,
             cue: "Heels close, press through them, hold a beat at the top."),
        Move(name: "Split squat", equipment: .bodyweight,
             cue: "Back knee straight down. Most of the weight on the front foot."),
        Move(name: "Bird dog", equipment: .bodyweight,
             cue: "Opposite arm and leg, slowly. The hips do not tip."),
        Move(name: "Wall sit", equipment: .bodyweight,
             cue: "Thighs parallel if you can, higher if you cannot. Breathe."),

        // Flow work: qi gong and lymphatic movement she already does in the
        // morning. These are the long-established generic movements, not a
        // transcription of anyone's video — if a specific sequence should be
        // matched, it belongs here as its own named routine rather than being
        // guessed at.
        //
        // They are `.flow` rather than `.strength` because they are a practice,
        // not a set: continuous, unhurried, and not improved by a countdown.
        Move(name: "Lymphatic bounce", equipment: .bodyweight, kind: .flow,
             cue: "Soft knees, heels barely leaving the floor. Loose everywhere above the waist."),
        Move(name: "Arm swings", equipment: .bodyweight, kind: .flow,
             cue: "Let the arms swing across the body and wrap. The waist turns, the arms are heavy."),
        Move(name: "Shoulder rolls", equipment: .bodyweight, kind: .flow,
             cue: "Big and slow, back rather than forward. Let the breath set the pace."),
        Move(name: "Neck release", equipment: .bodyweight, kind: .flow,
             cue: "Ear toward shoulder, then slowly across. Never roll back through the neck."),
        Move(name: "Spinal wave", equipment: .bodyweight, kind: .flow,
             cue: "Move one vertebra at a time, tailbone to head and back down."),
        Move(name: "Hip circles", equipment: .bodyweight, kind: .flow,
             cue: "Hands on the hips, wide slow circles. Both directions, evenly."),
        Move(name: "Cat cow", equipment: .bodyweight, kind: .flow,
             cue: "On all fours. Arch on the breath in, round on the breath out."),
        Move(name: "Lymphatic tapping", equipment: .bodyweight, kind: .flow,
             cue: "Light cupped taps: collarbones, under the arms, then down the inside of the legs."),
        Move(name: "Standing twist", equipment: .bodyweight, kind: .flow,
             cue: "Feet planted, turn from the middle. The arms follow rather than lead."),
        Move(name: "Ankle and wrist circles", equipment: .bodyweight, kind: .flow,
             cue: "Small, slow, both directions. The joints furthest out get the least attention."),
        Move(name: "Forward fold hang", equipment: .bodyweight, kind: .flow,
             cue: "Knees soft, hang from the hips. Let the head be heavy."),
        Move(name: "Zone 2 walk", equipment: .walkingPad,
             cue: "A pace you could hold a conversation at."),
        Move(name: "Incline walk", equipment: .walkingPad,
             cue: "Raise the incline before you raise the speed.")
    ]

    /// Every move by name, for the places that need the whole closed set:
    /// the planner's schema, the validator, and the plate lookup.
    static let names: [String] = all.map(\.name)

    static func moves(for equipment: Equipment) -> [Move] {
        all.filter { $0.equipment == equipment && $0.kind == .strength }
    }

    /// The morning practice: qi gong and lymphatic movement, kept apart from
    /// the strength library so a flow never turns up inside a work interval.
    static var flow: [Move] { all.filter { $0.kind == .flow } }

    /// Another move using the same equipment, avoiding a set of names.
    ///
    /// The offline planner's templates are fixed, so without this a fallback
    /// week would hand back the exact move she had just rejected — which would
    /// read as the app not listening, and be right.
    static func substitute(for move: Move, avoiding excluded: Set<String>) -> Move? {
        moves(for: move.equipment).first {
            !excluded.contains($0.name.lowercased())
                && $0.name.lowercased() != move.name.lowercased()
        }
    }
}
