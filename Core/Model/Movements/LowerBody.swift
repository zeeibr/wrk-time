import Foundation

/// The lower body: everything the coach brief counts as a hinge, a squat or
/// a lunge.
///
/// Thirteen movements across eighteen of the old library's rows. The
/// deadlift alone was typed three times — beam, ring, bell — with the same
/// pattern, the same muscles and five form lines that differed only in
/// which implement they named; here it is one movement whose variants
/// override the lines the implement actually changes. The kickstand and the
/// suitcase are their own movements rather than deadlift variants: one leg
/// and one loaded side change the muscles and every form line. The front
/// squat is not a goblet squat for the same reason — the beam sits on the
/// shoulders, and the whole of its form is about keeping it there.
extension MovementCatalog {
    static let lowerBody: [Movement] = [
        Movement(
            id: "deadlift", display: "Deadlift",
            pattern: .hinge, position: .standing,
            muscles: "glutes, back, legs",
            form: MoveForm(
                setUp: "Feet under the hips, the bell on the floor between the arches, toes pointing slightly out.",
                movement: "Push the hips back until the hands reach the handle, grip, then stand by driving the floor away — hips and shoulders rise together.",
                feel: "The back of the thighs stretch on the way down and the glutes finish the stand.",
                wrong: "Bending the knees first turns it into a squat; lead with the hips and keep the shins nearly vertical.",
                stopIf: "The low back rounds or aches rather than the hamstrings working — lighten the bell and hinge less deep."),
            variants: [
                .init(
                    name: "Beam deadlift", equipment: .beam, hold: .twoHands,
                    loadPounds: 15,
                    cue: "Hinge from the hips. The beam stays close to your shins.",
                    form: MoveForm(
                        setUp: "The beam on the floor against the shins, feet hip width, hands just outside the legs.",
                        movement: "Push the hips back, take the beam, and stand up tall keeping it close to the legs the whole way.",
                        feel: "Hamstrings load on the way down; standing up is the glutes.",
                        wrong: "Letting the beam drift forward away from the shins, which pulls on the low back.",
                        stopIf: "The back rounds or you feel it in the spine rather than the legs.")),
                .init(
                    name: "Ring deadlift", equipment: .rings, hold: .twoHands,
                    loadPounds: 10,
                    cue: "The 10 lb ring between the feet. Hinge, don't squat.",
                    form: MoveForm(
                        setUp: "The 10 lb ring flat on the floor between the feet, feet hip width.",
                        movement: "Hips back, flat back, reach the ring with both hands, and stand by driving through the heels.",
                        feel: "Hamstrings stretch on the way down; glutes squeeze at the top.",
                        wrong: "Squatting down to it; push the hips back and keep the shins still.",
                        stopIf: "The low back rounds or aches.")),
                .init(
                    name: "Kettlebell deadlift", equipment: .kettlebell, hold: .twoHands,
                    loadPounds: 18,
                    cue: "The bell between the feet. Hinge, flat back, stand all the way up."),
            ]),
        Movement(
            id: "good-morning", display: "Good morning",
            pattern: .hinge, position: .standing,
            muscles: "glutes, back",
            form: MoveForm(
                setUp: "The beam across the back of the shoulders, never on the neck, feet hip width, knees soft.",
                movement: "Hinge forward from the hips with a flat back until the hamstrings stop you, then stand.",
                feel: "A stretch down the back of the thighs; the glutes bring you back up.",
                wrong: "Rounding the back to go lower; the range is whatever your hamstrings allow with a flat back.",
                stopIf: "Any pinch in the low back — this move has no business there."),
            variants: [
                .init(
                    name: "Beam good morning", equipment: .beam, hold: .twoHands,
                    loadPounds: 15,
                    cue: "The beam rests across the back of the shoulders, never the neck. Soft knees, flat back, stop when your hamstrings say so."),
            ]),
        Movement(
            id: "kickstand-deadlift", display: "Kickstand deadlift",
            pattern: .hinge, position: .standing,
            muscles: "glutes, legs, back",
            form: MoveForm(
                setUp: "The bell inside the front foot; the back foot a step behind with only the toes down, like a kickstand.",
                movement: "Hinge over the front leg, hips back, reach the bell, and stand through the front heel.",
                feel: "The front hamstring and glute do nearly all of it; the back foot only balances.",
                wrong: "Loading the back foot makes it a split squat; keep nine tenths of your weight on the front leg.",
                stopIf: "The front knee caves inward or the low back takes the load."),
            variants: [
                .init(
                    name: "Kickstand deadlift", equipment: .kettlebell, hold: .oneHand,
                    loadPounds: 18, sided: .sides,
                    cue: "The bell inside the front foot, back toes down just for balance. Hinge over the front leg, flat back."),
            ]),
        Movement(
            id: "suitcase-deadlift", display: "Suitcase deadlift",
            pattern: .hinge, position: .standing,
            muscles: "glutes, legs, core",
            form: MoveForm(
                setUp: "The dumbbell on the floor beside one foot, feet hip width, shoulders level.",
                movement: "Hinge, grip, and stand tall without leaning toward the weight; then lower it the same way.",
                feel: "The hamstrings on the way down, and the side of the trunk opposite the weight holding you level.",
                wrong: "Tipping sideways toward the load; the whole point is to stay square.",
                stopIf: "You cannot stay level without the low back twisting."),
            variants: [
                .init(
                    name: "Suitcase deadlift", equipment: .singleDumbbell, hold: .oneHand,
                    loadPounds: 10, sided: .sides,
                    cue: "The dumbbell beside one foot. Hinge, take a firm grip, and stand tall — no lean toward the load."),
            ]),
        Movement(
            id: "goblet-squat", display: "Goblet squat",
            pattern: .squat, position: .standing,
            muscles: "legs, glutes, core",
            form: MoveForm(
                setUp: "The bell held by the horns at the chest, elbows down, feet a little wider than the hips, toes slightly out.",
                movement: "Sit straight down between the heels, elbows inside the knees, chest tall, then stand.",
                feel: "The thighs and glutes doing the work; the bell only asks the core to stay tall.",
                wrong: "The heels lifting or the knees caving in; push the knees out toward the little toes.",
                stopIf: "Sharp knee pain on the way down, as opposed to thighs burning."),
            variants: [
                .init(
                    name: "Ring goblet squat", equipment: .rings, hold: .twoHands,
                    loadPounds: 10,
                    cue: "The 10 lb ring held at the chest. Sit down between the hips, chest tall.",
                    form: MoveForm(
                        setUp: "The 10 lb ring held at the chest in both hands, feet a little wider than the hips.",
                        movement: "Sit down between the hips, chest tall, pause at the bottom, and stand.",
                        feel: "Thighs and glutes.",
                        wrong: "Knees falling inward; think about spreading the floor apart.",
                        stopIf: "Sharp knee pain.")),
                .init(
                    name: "Kettlebell goblet squat", equipment: .kettlebell, hold: .twoHands,
                    loadPounds: 18,
                    cue: "Held by the horns at the chest. Sit between the hips, elbows inside the knees."),
                .init(
                    name: "Single-dumbbell goblet squat", equipment: .singleDumbbell, hold: .twoHands,
                    loadPounds: 10,
                    cue: "The dumbbell held upright at the chest in both hands. Sit between the hips, elbows inside the knees."),
            ]),
        Movement(
            id: "front-squat", display: "Front squat",
            pattern: .squat, position: .standing,
            muscles: "legs, glutes, core",
            form: MoveForm(
                setUp: "The beam across the collarbones, resting on the front of the shoulders, elbows lifted, feet a little wider than the hips.",
                movement: "Sit down over three counts with the chest tall, then stand in one.",
                feel: "Thighs and glutes; the upper back works to keep the beam up.",
                wrong: "Letting the elbows drop so the beam rolls forward; keep the elbows up and the chest proud.",
                stopIf: "Sharp knee pain or a wrist that cannot tolerate the beam's position."),
            variants: [
                .init(
                    name: "Beam front squat", equipment: .beam, hold: .twoHands,
                    loadPounds: 15,
                    cue: "Beam across the collarbones. Three counts down, one to stand."),
            ]),
        Movement(
            id: "sumo-squat", display: "Sumo squat",
            pattern: .squat, position: .standing,
            muscles: "legs, glutes",
            form: MoveForm(
                setUp: "Feet wide, toes turned out, the bell hanging in both hands between the legs.",
                movement: "Sit straight down between the heels, chest up, then drive through the feet to stand.",
                feel: "The inner thighs and glutes.",
                wrong: "Leaning forward so the bell swings; keep the torso tall and the bell hanging straight down.",
                stopIf: "Knee or groin pain that is sharp, not a stretch."),
            variants: [
                .init(
                    name: "Kettlebell sumo squat", equipment: .kettlebell, hold: .twoHands,
                    loadPounds: 18,
                    cue: "Feet wide, toes out, the bell hanging in both hands. Sit straight down between the heels, chest tall."),
            ]),
        Movement(
            id: "air-squat", display: "Air squat",
            pattern: .squat, position: .standing,
            muscles: "legs, glutes",
            form: MoveForm(
                setUp: "Feet under the hips or a little wider, toes slightly out, arms out in front for balance.",
                movement: "Sit down and back as if to a chair, chest tall, as low as your heels stay down, then stand all the way up.",
                feel: "Thighs and glutes.",
                wrong: "Heels rising or knees caving; slow down and let the knees track over the toes.",
                stopIf: "Sharp knee pain."),
            variants: [
                .init(
                    name: "Air squat", equipment: .bodyweight, hold: .none,
                    cue: "Feet under the hips, sit down and back, chest tall. Stand all the way up every time."),
            ]),
        Movement(
            id: "wall-sit", display: "Wall sit",
            pattern: .squat, position: .standing,
            muscles: "legs",
            form: MoveForm(
                setUp: "Back flat against the wall, feet a step out, hip width.",
                movement: "Slide down until the thighs are parallel to the floor, or higher if they cannot be, and hold.",
                feel: "The front of the thighs burning; that is the whole move.",
                wrong: "Hands on the thighs; they rest by your sides or across the chest.",
                stopIf: "Knee pain behind the kneecap rather than thigh burn."),
            variants: [
                .init(
                    name: "Wall sit", equipment: .bodyweight, hold: .none,
                    cue: "Thighs parallel if you can, higher if you cannot. Breathe."),
            ]),
        Movement(
            id: "reverse-lunge", display: "Reverse lunge",
            pattern: .lunge, position: .standing,
            muscles: "legs, glutes",
            form: MoveForm(
                setUp: "Standing tall, feet under the hips, hands on the hips or at the chest.",
                movement: "Step one foot back, lower until the back knee nearly touches the floor, and push through the front heel to return.",
                feel: "The front thigh and glute; the back leg only steadies you.",
                wrong: "Stepping forward instead, which loads the knee; step back, and keep the front knee over the ankle.",
                stopIf: "Sharp pain in the front knee."),
            variants: [
                .init(
                    name: "Beam reverse lunge", equipment: .beam, hold: .twoHands,
                    loadPounds: 15, sided: .sides,
                    cue: "Beam across the chest. Step back, and the front knee stays over the ankle.",
                    form: MoveForm(
                        setUp: "The beam across the chest or the front of the shoulders, feet under the hips.",
                        movement: "Step back, lower the back knee toward the floor, and drive through the front heel to stand.",
                        feel: "Front thigh and glute; the core holds the beam still.",
                        wrong: "The front knee drifting past the toes; keep it over the ankle.",
                        stopIf: "Sharp knee pain or balance so poor the beam is moving.")),
                .init(
                    name: "Reverse lunge", equipment: .bodyweight, hold: .none,
                    sided: .sides,
                    cue: "Step back, not forward. The front knee stays over the ankle."),
            ]),
        Movement(
            id: "lateral-lunge", display: "Lateral lunge",
            pattern: .lunge, position: .standing,
            muscles: "legs, glutes",
            form: MoveForm(
                setUp: "The beam across the collarbones, feet together.",
                movement: "Step wide to one side, sit back into that hip with the other leg straight, then push back to standing.",
                feel: "The glute and inner thigh of the bent leg.",
                wrong: "The bent knee falling inward; keep it over the foot and the chest up.",
                stopIf: "Sharp knee or groin pain."),
            variants: [
                .init(
                    name: "Beam lateral lunge", equipment: .beam, hold: .twoHands,
                    loadPounds: 15, sided: .sides,
                    cue: "Beam across the collarbones. Step wide to one side, sit into that hip, and push back to standing."),
            ]),
        Movement(
            id: "curtsy-lunge", display: "Curtsy lunge",
            pattern: .lunge, position: .standing,
            muscles: "glutes, legs",
            form: MoveForm(
                setUp: "The beam across the collarbones, feet under the hips.",
                movement: "Step one foot back and across behind the other, sink straight down, and stand.",
                feel: "The outer glute of the front leg.",
                wrong: "Twisting the hips; they stay square to the front.",
                stopIf: "Any knee pain on the front leg."),
            variants: [
                .init(
                    name: "Beam curtsy lunge", equipment: .beam, hold: .twoHands,
                    loadPounds: 15, sided: .sides,
                    cue: "Beam across the collarbones. Step back and across, sink straight down; the front knee stays steady."),
            ]),
        Movement(
            id: "split-squat", display: "Split squat",
            pattern: .lunge, position: .standing,
            muscles: "legs, glutes",
            form: MoveForm(
                setUp: "One foot forward, one back, a long stride apart, most of your weight on the front foot.",
                movement: "Lower the back knee straight down toward the floor, then stand; the feet stay where they are.",
                feel: "Front thigh and glute.",
                wrong: "Leaning forward over the front knee; keep the torso upright and the hips square.",
                stopIf: "Sharp knee pain."),
            variants: [
                .init(
                    name: "Split squat", equipment: .bodyweight, hold: .none,
                    sided: .sides,
                    cue: "Back knee straight down. Most of the weight on the front foot."),
            ]),
    ]
}
