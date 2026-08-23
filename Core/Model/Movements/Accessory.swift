import Foundation

/// Isolation work: curls, raises, extensions, the calf raise, the chin tuck.
/// `MovePattern.accessory` fills a slot in a session rather than covering a
/// pattern, and the family is the clearest case the catalog makes: one curl
/// done four ways, one kickback done two, one calf raise loaded and not.
///
/// Two splits look like duplicates and are not. The beam triceps extension
/// is done lying down, and a movement has one `position`, so the standing
/// extension and the lying one are two movements sharing a display name.
/// The hammer curl, the Zottman curl and the wrist curl each keep their own
/// entry because what names them is the grip, not the implement.
extension MovementCatalog {
    static let accessory: [Movement] = [
        // The one movement every implement in the house can do. The pair is it
        // written plain; the beam takes both hands under it, the ring takes one,
        // and the single dumbbell is the pair's form done one arm at a time.
        Movement(
            id: "curl",
            display: "Curl",
            pattern: .accessory,
            position: .standing,
            muscles: "arms",
            form: MoveForm(
                setUp: "Standing tall, a dumbbell in each hand, elbows pinned to the sides.",
                movement: "Curl to the shoulders and lower over three counts; only the forearms move.",
                feel: "The front of the upper arms.",
                wrong: "Swinging the body or the elbows drifting forward; pin them.",
                stopIf: "Elbow pain."),
            variants: [
                .init(
                    name: "Bicep curl",
                    equipment: .dumbbells,
                    hold: .pair,
                    loadPounds: 2,
                    cue: "Elbows pinned to your sides. Three counts down every time."),
                .init(
                    name: "Beam curl",
                    equipment: .beam,
                    hold: .twoHands,
                    loadPounds: 15,
                    cue: "Both hands under the beam, elbows pinned to your sides. Curl to the collarbones, three counts down.",
                    form: MoveForm(
                        setUp: "Standing tall, both hands under the beam, elbows pinned to the sides.",
                        movement: "Curl to the collarbones and lower over three counts.",
                        feel: "The front of the upper arms.",
                        wrong: "Leaning back to lift; stay tall.",
                        stopIf: "Elbow or wrist pain.")),
                .init(
                    name: "Ring bicep curl",
                    equipment: .rings,
                    hold: .oneHand,
                    loadPounds: 5,
                    sided: .sides,
                    cue: "The 5 lb ring in one hand, elbow pinned to your side. Three counts down.",
                    form: MoveForm(
                        setUp: "The 5 lb ring in one hand, elbow pinned to the side.",
                        movement: "Curl to the shoulder and lower over three counts.",
                        feel: "The front of that upper arm.",
                        wrong: "The elbow drifting forward; pin it.",
                        stopIf: "Elbow pain.")),
                .init(
                    name: "Single-dumbbell curl",
                    equipment: .singleDumbbell,
                    hold: .oneHand,
                    loadPounds: 10,
                    sided: .sides,
                    cue: "The dumbbell in one hand, elbow pinned to your side. Three counts down every time."),
            ]),
        Movement(
            id: "hammer-curl",
            display: "Hammer curl",
            pattern: .accessory,
            position: .standing,
            muscles: "arms",
            form: MoveForm(
                setUp: "One hand through the 5 lb ring, thumb up, elbow pinned.",
                movement: "Curl with the thumb up the whole way and lower slowly.",
                feel: "The front and outer upper arm and the forearm.",
                wrong: "Turning the palm; it stays thumb-up.",
                stopIf: "Elbow pain."),
            variants: [
                .init(
                    name: "Ring hammer curl",
                    equipment: .rings,
                    hold: .oneHand,
                    loadPounds: 5,
                    sided: .sides,
                    cue: "One hand through the 5 lb ring, thumb up the whole way. The elbow stays pinned."),
            ]),
        Movement(
            id: "zottman-curl",
            display: "Zottman curl",
            pattern: .accessory,
            position: .standing,
            muscles: "arms",
            form: MoveForm(
                setUp: "Standing tall, dumbbells at the sides, palms forward.",
                movement: "Curl up palms up, turn the palms down at the top, and lower slowly over three counts.",
                feel: "The front of the arms up, the forearms down.",
                wrong: "Rushing the lowering; the way down is the point.",
                stopIf: "Wrist or elbow pain."),
            variants: [
                .init(
                    name: "Zottman curl",
                    equipment: .dumbbells,
                    hold: .pair,
                    loadPounds: 3,
                    cue: "Curl palms up, turn palms down at the top, lower over three counts. The way down is the point."),
            ]),
        Movement(
            id: "wrist-curl",
            display: "Wrist curl",
            pattern: .accessory,
            position: .floor,
            muscles: "arms",
            form: MoveForm(
                setUp: "Seated, the forearm resting along the thigh with the hand past the knee, the 5 lb ring in that hand.",
                movement: "Curl only the wrist up, pause, and lower.",
                feel: "The forearm.",
                wrong: "Lifting the forearm off the thigh; only the wrist moves.",
                stopIf: "Wrist pain rather than forearm work."),
            variants: [
                .init(
                    name: "Ring wrist curl",
                    equipment: .rings,
                    hold: .oneHand,
                    loadPounds: 5,
                    sided: .sides,
                    cue: "Seated, forearm resting along the thigh, the 5 lb ring in that hand. Curl just the wrist, slow both ways."),
            ]),
        // Standing, the weight behind the head. The beam version is its own
        // movement below because it is done lying down, and a movement has one
        // position.
        Movement(
            id: "triceps-extension",
            display: "Triceps extension",
            pattern: .accessory,
            position: .standing,
            muscles: "arms",
            form: MoveForm(
                setUp: "The 8 lb ring in both hands behind the head, elbows pointing at the ceiling.",
                movement: "Straighten the elbows, pause, and lower.",
                feel: "The back of the upper arms.",
                wrong: "Elbows drifting out; keep them close.",
                stopIf: "Elbow or shoulder pain."),
            variants: [
                .init(
                    name: "Ring triceps extension",
                    equipment: .rings,
                    hold: .twoHands,
                    loadPounds: 8,
                    cue: "The 8 lb ring in both hands behind the head, elbows pointing at the ceiling. Only the forearms move."),
                .init(
                    name: "Overhead extension",
                    equipment: .dumbbells,
                    hold: .pair,
                    loadPounds: 2,
                    cue: "Both hands on one weight behind the head. Only the forearms move.",
                    form: MoveForm(
                        setUp: "Standing tall, both hands on one dumbbell held behind the head, elbows pointing at the ceiling.",
                        movement: "Straighten the elbows to press it overhead, then lower slowly behind the head.",
                        feel: "The back of the upper arms.",
                        wrong: "The elbows flaring wide; keep them pointing up and close to the head.",
                        stopIf: "Elbow or shoulder pain.")),
            ]),
        // The same muscles as the standing extension, from the mat.
        Movement(
            id: "lying-triceps-extension",
            display: "Triceps extension",
            pattern: .accessory,
            position: .floor,
            muscles: "arms",
            form: MoveForm(
                setUp: "On your back, the beam pressed over the chest, hands shoulder width.",
                movement: "Bend only the elbows to lower it toward the forehead, then straighten.",
                feel: "The back of the upper arms.",
                wrong: "The upper arms moving; they stay vertical.",
                stopIf: "Elbow pain."),
            variants: [
                .init(
                    name: "Beam triceps extension",
                    equipment: .beam,
                    hold: .twoHands,
                    loadPounds: 15,
                    cue: "On your back, the beam pressed over the chest. Bend only the elbows, lower it toward your forehead, press back up."),
            ]),
        Movement(
            id: "kickback",
            display: "Kickback",
            pattern: .accessory,
            position: .standing,
            muscles: "arms",
            form: MoveForm(
                setUp: "Hinge forward with a flat back, a dumbbell in each hand, upper arms parallel to the floor.",
                movement: "Straighten the elbows until the arms are long, squeeze, and bend again; the upper arm stays still.",
                feel: "The back of the upper arms.",
                wrong: "The upper arm swinging to help; it does not move.",
                stopIf: "Elbow pain."),
            variants: [
                .init(
                    name: "Tricep kickback",
                    equipment: .dumbbells,
                    hold: .pair,
                    loadPounds: 2,
                    cue: "Upper arm still and parallel to the floor. Only the forearm moves."),
                .init(
                    name: "Ring kickback",
                    equipment: .rings,
                    hold: .oneHand,
                    loadPounds: 5,
                    sided: .sides,
                    cue: "Hinge, the 5 lb ring in one hand, upper arm parallel to the floor. Straighten the elbow and hold a beat.",
                    form: MoveForm(
                        setUp: "Hinge forward with a flat back, the 5 lb ring in one hand, upper arm parallel to the floor.",
                        movement: "Straighten the elbow, hold a beat, and bend.",
                        feel: "The back of that upper arm.",
                        wrong: "Dropping the upper arm; keep it level.",
                        stopIf: "Elbow pain.")),
            ]),
        Movement(
            id: "press-back",
            display: "Press-back",
            pattern: .accessory,
            position: .standing,
            muscles: "arms",
            form: MoveForm(
                setUp: "Standing tall, dumbbells at the sides, palms facing behind you, arms straight.",
                movement: "Press the weights back and up, hold a beat, and return.",
                feel: "The back of the upper arms and the back of the shoulders.",
                wrong: "Leaning forward to swing them higher; stay tall and keep it small.",
                stopIf: "Shoulder pinch."),
            variants: [
                .init(
                    name: "Tricep press-back",
                    equipment: .dumbbells,
                    hold: .pair,
                    loadPounds: 2,
                    cue: "Arms straight at your sides, palms facing behind you. Press the weights back and up, and hold a beat at the top."),
            ]),
        Movement(
            id: "lateral-raise",
            display: "Lateral raise",
            pattern: .accessory,
            position: .standing,
            muscles: "shoulders",
            form: MoveForm(
                setUp: "Standing tall, light dumbbells at the sides, elbows very slightly bent.",
                movement: "Raise the arms out to the sides to shoulder height, lead with the elbows, and lower over three counts.",
                feel: "The tops of the shoulders.",
                wrong: "Shrugging or swinging; if you need to swing, the weight is too heavy.",
                stopIf: "A pinch at the top of the shoulder — stop a little below shoulder height."),
            variants: [
                .init(
                    name: "Lateral raise",
                    equipment: .dumbbells,
                    hold: .pair,
                    loadPounds: 2,
                    cue: "Up to shoulder height, down over three counts."),
            ]),
        Movement(
            id: "front-raise",
            display: "Front raise",
            pattern: .accessory,
            position: .standing,
            muscles: "shoulders",
            form: MoveForm(
                setUp: "Standing tall, dumbbells in front of the thighs, arms straight.",
                movement: "Raise the arms straight out in front to eye height and lower slowly.",
                feel: "The front of the shoulders.",
                wrong: "Swinging the body; stop before the shoulders shrug.",
                stopIf: "Shoulder pinch."),
            variants: [
                .init(
                    name: "Front raise",
                    equipment: .dumbbells,
                    hold: .pair,
                    loadPounds: 2,
                    cue: "Straight arms to eye height. Stop before the shoulders shrug."),
                .init(
                    name: "Ring front raise",
                    equipment: .rings,
                    hold: .twoHands,
                    loadPounds: 5,
                    cue: "The 5 lb ring in both hands, straight out to eye height.",
                    form: MoveForm(
                        setUp: "The 5 lb ring held in both hands in front of the thighs.",
                        movement: "Raise it straight out to eye height and lower slowly.",
                        feel: "The front of the shoulders.",
                        wrong: "Leaning back; stay tall.",
                        stopIf: "Shoulder pinch.")),
            ]),
        Movement(
            id: "scaption-raise",
            display: "Scaption raise",
            pattern: .accessory,
            position: .standing,
            muscles: "shoulders",
            form: MoveForm(
                setUp: "Standing tall, dumbbells at the sides, thumbs up.",
                movement: "Raise the straight arms halfway between front and side to shoulder height, and lower.",
                feel: "The shoulders and the muscles around the blade.",
                wrong: "Going above shoulder height; stop there.",
                stopIf: "Shoulder pinch."),
            variants: [
                .init(
                    name: "Scaption raise",
                    equipment: .dumbbells,
                    hold: .pair,
                    loadPounds: 2,
                    cue: "Straight arms, thumbs up, lifted halfway between front and side. To shoulder height and no higher."),
            ]),
        Movement(
            id: "behind-back-raise",
            display: "Behind-back raise",
            pattern: .accessory,
            position: .standing,
            muscles: "shoulders, back",
            form: MoveForm(
                setUp: "Standing, both hands on the 5 lb ring behind the back, arms long.",
                movement: "Hinge slightly forward, lift the ring up and away from the body, and lower.",
                feel: "The back of the shoulders and the chest opening.",
                wrong: "Rounding the shoulders forward; keep the chest open.",
                stopIf: "Shoulder pinch."),
            variants: [
                .init(
                    name: "Ring behind-back raise",
                    equipment: .rings,
                    hold: .twoHands,
                    loadPounds: 5,
                    cue: "Both hands on the 5 lb ring behind your back. Hinge, then lift it up and away."),
            ]),
        Movement(
            id: "around-the-world",
            display: "Around the world",
            pattern: .accessory,
            position: .standing,
            muscles: "shoulders, chest",
            form: MoveForm(
                setUp: "Standing tall, light dumbbells at the sides, palms forward.",
                movement: "Sweep the straight arms out and up until they meet overhead, then back down the same path.",
                feel: "The shoulders all the way around.",
                wrong: "Bending the elbows or arching the back; keep both long and the ribs down.",
                stopIf: "Shoulder pinch — it is fine to stop the sweep below the top."),
            variants: [
                .init(
                    name: "Around the world",
                    equipment: .dumbbells,
                    hold: .pair,
                    loadPounds: 2,
                    cue: "Arms wide, sweep overhead until they meet, and back the same way."),
            ]),
        Movement(
            id: "shrug",
            display: "Shrug",
            pattern: .accessory,
            position: .standing,
            muscles: "back, shoulders",
            form: MoveForm(
                setUp: "Standing tall, dumbbells at the sides.",
                movement: "Lift the shoulders straight up toward the ears, hold a beat, and let them down.",
                feel: "The top of the shoulders and neck.",
                wrong: "Rolling the shoulders in a circle; straight up and down only.",
                stopIf: "Neck pain."),
            variants: [
                .init(
                    name: "Dumbbell shrug",
                    equipment: .dumbbells,
                    hold: .pair,
                    loadPounds: 2,
                    cue: "Shoulders straight up toward the ears, hold a beat, then let them go."),
            ]),
        Movement(
            id: "raise-the-platters",
            display: "Raise the platters",
            pattern: .accessory,
            position: .standing,
            muscles: "arms, shoulders",
            form: MoveForm(
                setUp: "Standing tall, dumbbells at the waist, palms up as if carrying two platters.",
                movement: "Extend the arms forward, lift to shoulder height, and bring them back the same way.",
                feel: "The front of the shoulders and the biceps.",
                wrong: "Letting the palms turn in; they stay up.",
                stopIf: "Shoulder pinch."),
            variants: [
                .init(
                    name: "Raise the platters",
                    equipment: .dumbbells,
                    hold: .pair,
                    loadPounds: 2,
                    cue: "Palms up at the waist, as if carrying two platters. Extend the arms forward, lift to shoulder height, and lower over three counts."),
            ]),
        // Loaded with the bell in one hand, or unloaded on one leg. Both are the
        // calves and both are standing, so they are one movement.
        Movement(
            id: "calf-raise",
            display: "Calf raise",
            pattern: .accessory,
            position: .standing,
            muscles: "legs",
            form: MoveForm(
                setUp: "Standing tall, the bell in one hand, the other hand on a wall for balance.",
                movement: "Rise onto the balls of the feet, pause at the top, and lower slowly.",
                feel: "The calves.",
                wrong: "Bouncing; pause at the top and lower over two counts.",
                stopIf: "Achilles pain."),
            variants: [
                .init(
                    name: "Kettlebell calf raise",
                    equipment: .kettlebell,
                    hold: .oneHand,
                    loadPounds: 18,
                    cue: "The bell in one hand, the other hand on the wall. Rise to the balls of the feet, pause, lower slowly."),
                .init(
                    name: "Single-leg calf raise",
                    equipment: .bodyweight,
                    hold: .none,
                    sided: .sides,
                    cue: "All your weight on one foot, fingertips on the wall. Rise to the ball of the foot, pause, lower with control.",
                    form: MoveForm(
                        setUp: "All your weight on one foot, fingertips on a wall.",
                        movement: "Rise onto the ball of that foot, pause, and lower slowly.",
                        feel: "That calf.",
                        wrong: "Rolling onto the outside of the foot; rise through the big toe.",
                        stopIf: "Achilles pain.")),
            ]),
        Movement(
            id: "external-rotation",
            display: "External rotation",
            pattern: .accessory,
            position: .standing,
            muscles: "shoulders",
            form: MoveForm(
                setUp: "Elbow pinned to the side at ninety degrees, the band held across the body.",
                movement: "Swing the forearm outward against the band, slowly, and slower back.",
                feel: "The back of the shoulder, deep.",
                wrong: "The elbow leaving the side; pin it.",
                stopIf: "Shoulder pain."),
            variants: [
                .init(
                    name: "Band external rotation",
                    equipment: .band,
                    hold: .oneHand,
                    sided: .sides,
                    cue: "Elbow pinned at your side, forearm swings out against the band. Slow out, slower back."),
            ]),
        Movement(
            id: "chin-tuck",
            display: "Chin tuck",
            pattern: .accessory,
            position: .standing,
            muscles: "back, core",
            form: MoveForm(
                setUp: "Sitting or standing tall, eyes level, shoulders relaxed.",
                movement: "Draw the chin straight back as if making a double chin, hold two counts, and release.",
                feel: "The front of the neck working and the back of the neck lengthening.",
                wrong: "Tipping the head down; the eyes stay level and the head glides back.",
                stopIf: "Dizziness or sharp neck pain."),
            variants: [
                .init(
                    name: "Chin tuck",
                    equipment: .bodyweight,
                    hold: .none,
                    cue: "Draw the chin straight back — yes, a double chin. Hold two counts, release. Eyes level the whole time."),
            ]),
        Movement(
            id: "side-leg-lift",
            display: "Side leg lift",
            pattern: .accessory,
            position: .floor,
            muscles: "glutes",
            form: MoveForm(
                setUp: "Lying on one side, bottom knee bent for balance, top leg long, hips stacked.",
                movement: "Lift the top leg to hip height, no higher, and lower slowly.",
                feel: "The outer hip of the top leg.",
                wrong: "Rolling the hip back so the leg comes forward; keep the hips stacked and the toes pointing forward.",
                stopIf: "Hip pinch."),
            variants: [
                .init(
                    name: "Side leg lift",
                    equipment: .bodyweight,
                    hold: .none,
                    sided: .sides,
                    cue: "Side lying, bottom knee bent, top leg long. Lift to hip height, no higher, and lower slowly."),
            ]),
    ]
}
