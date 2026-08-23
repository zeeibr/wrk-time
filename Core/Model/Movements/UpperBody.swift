import Foundation

/// The pushes and the pulls: every movement whose pattern is a row, a pull,
/// a press or a push.
///
/// This is the family the old library repeated most — a row on five
/// implements, an overhead press on five, a floor press on three — so it is
/// the family the catalog earns the most from. The movement carries the
/// pattern, the position, the muscles and the form; a variant carries the
/// name the app has always stored, the implement, the grip, the load and
/// the one line the timer says. Where an implement changes what the form
/// has to say — a beam across the collarbones is not two dumbbells at the
/// shoulders — the variant overrides that form and nothing else.
extension MovementCatalog {
    static let upperBody: [Movement] = [

        // MARK: - Pull, horizontal

        // The movement's form is the pair's, so "Single-dumbbell row" —
        // which has always borrowed the pair's facts by alias — keeps
        // borrowing them by sitting in the same movement.
        Movement(
            id: "row",
            display: "Row",
            pattern: .pullHorizontal,
            position: .standing,
            muscles: "back, arms",
            form: MoveForm(
                setUp: "Hinge forward with a flat back, a dumbbell in each hand hanging under the shoulders.",
                movement: "Pull both to the hips, blades together at the top, and lower over three counts.",
                feel: "Between the shoulder blades.",
                wrong: "Elbows flaring wide; they go back, close to the body.",
                stopIf: "Low back pain."),
            variants: [
                Movement.Variant(
                    name: "Beam row", equipment: .beam, hold: .twoHands, loadPounds: 15,
                    cue: "Hinge and hold it there. Pull the beam to your belly, elbows back not out.",
                    form: MoveForm(
                        setUp: "Hinge forward with a flat back, the beam hanging at arm's length, hands shoulder width.",
                        movement: "Pull the beam to the belly, elbows back, squeeze the shoulder blades, lower slowly.",
                        feel: "Between and below the shoulder blades.",
                        wrong: "Standing up to meet the beam; the torso stays still and the beam comes to you.",
                        stopIf: "Low back pain rather than upper back work.")),
                Movement.Variant(
                    name: "Ring row", equipment: .rings, hold: .twoHands, loadPounds: 8,
                    cue: "Hinge, hold the 8 lb ring, pull it to your hip. The elbow goes back.",
                    form: MoveForm(
                        setUp: "Hinge forward with a flat back, the 8 lb ring in one hand hanging under the shoulder.",
                        movement: "Pull the ring to the hip, elbow going back, pause, then lower.",
                        feel: "Beside the shoulder blade on that side.",
                        wrong: "Twisting the torso to lift; the shoulders stay square to the floor.",
                        stopIf: "Low back pain.")),
                Movement.Variant(
                    name: "Kettlebell row", equipment: .kettlebell, hold: .oneHand, loadPounds: 18,
                    sided: .sides,
                    cue: "Hinge, free hand braced on your thigh. Pull the bell to your hip; the elbow goes back, not out.",
                    form: MoveForm(
                        setUp: "Hinge forward with a flat back, the free hand braced on the thigh, the bell hanging under the shoulder.",
                        movement: "Pull the bell to the hip, elbow going back not out, pause, then lower slowly.",
                        feel: "The muscles beside the shoulder blade; the arm is just the handle.",
                        wrong: "Shrugging the shoulder toward the ear; keep it down and pull with the back.",
                        stopIf: "The low back aches from holding the hinge — rest it, then hinge less deep.")),
                Movement.Variant(
                    name: "Dumbbell row", equipment: .dumbbells, hold: .pair, loadPounds: 5,
                    cue: "Hinge and hold it there. Pull both 5 lb dumbbells to your hips, blades together at the top."),
                Movement.Variant(
                    name: "Single-dumbbell row", equipment: .singleDumbbell, hold: .oneHand,
                    loadPounds: 10, sided: .sides,
                    cue: "Hinge, free hand braced on your thigh, the dumbbell in the other. Pull it to your hip; the elbow goes back, not out."),
            ]),

        // A row done sitting on the floor: the same pull, a different
        // position, so it is its own movement rather than a variant.
        Movement(
            id: "seated-row",
            display: "Seated row",
            pattern: .pullHorizontal,
            position: .floor,
            muscles: "back, arms",
            form: MoveForm(
                setUp: "Seated on the floor, legs long, the band looped around both feet, handles in the hands.",
                movement: "Pull to the ribs with the elbows close, blades together, then let the arms out slowly.",
                feel: "Between the shoulder blades.",
                wrong: "Rounding the back as the arms go out; sit tall the whole way.",
                stopIf: "Low back pain."),
            variants: [
                Movement.Variant(
                    name: "Band seated row", equipment: .band, hold: .twoHands,
                    cue: "Seated, legs long, the band looped around both feet. Pull to the ribs, blades together, let it return slowly."),
            ]),

        Movement(
            id: "rear-delt-fly",
            display: "Rear delt fly",
            pattern: .pullHorizontal,
            position: .standing,
            muscles: "shoulders, back",
            form: MoveForm(
                setUp: "Hinge forward with a flat back, a light dumbbell in each hand hanging below the chest, palms facing each other.",
                movement: "Open the arms wide with soft elbows until they are level with the shoulders, squeeze, and lower.",
                feel: "The back of the shoulders and between the blades.",
                wrong: "Swinging the weights up; they should be light enough to move slowly.",
                stopIf: "A pinch in the front of the shoulder."),
            variants: [
                Movement.Variant(
                    name: "Rear delt fly", equipment: .dumbbells, hold: .pair, loadPounds: 2,
                    cue: "Hinge forward, open wide, squeeze between the shoulder blades."),
            ]),

        // The posture three. One implement each, and the band drawer is off
        // — they are here so a stored routine still reads.
        Movement(
            id: "pull-apart",
            display: "Pull-apart",
            pattern: .pullHorizontal,
            position: .standing,
            muscles: "shoulders, back",
            form: MoveForm(
                setUp: "The band held in both hands at shoulder height, arms straight, hands shoulder width.",
                movement: "Pull the hands apart until the band touches the chest, squeeze the blades, and let it return slowly.",
                feel: "Between the shoulder blades.",
                wrong: "Shrugging; keep the shoulders down.",
                stopIf: "Shoulder pain."),
            variants: [
                Movement.Variant(
                    name: "Band pull-apart", equipment: .band, hold: .twoHands,
                    cue: "Arms straight at shoulder height, pull the band to your chest. Blades together, then let it close slowly."),
            ]),

        Movement(
            id: "face-pull",
            display: "Face pull",
            pattern: .pullHorizontal,
            position: .standing,
            muscles: "shoulders, back",
            form: MoveForm(
                setUp: "The band anchored or held in front at face height, hands together.",
                movement: "Pull toward the eyes with the elbows high and wide, thumbs turning back, then return slowly.",
                feel: "The back of the shoulders.",
                wrong: "Pulling to the chest instead of the face; keep the elbows high.",
                stopIf: "Shoulder pain."),
            variants: [
                Movement.Variant(
                    name: "Band face pull", equipment: .band, hold: .twoHands,
                    cue: "Pull the band toward your eyes, elbows high and wide, thumbs turning back. The shoulder blades finish it."),
            ]),

        Movement(
            id: "w-raise",
            display: "W raise",
            pattern: .pullHorizontal,
            position: .standing,
            muscles: "shoulders, back",
            form: MoveForm(
                setUp: "Elbows bent and tucked, the band between the hands, forearms making a W.",
                movement: "Draw the elbows down and back until the shoulder blades squeeze, then release.",
                feel: "Between and below the shoulder blades.",
                wrong: "Arching the low back to help; keep the ribs down.",
                stopIf: "Shoulder pain."),
            variants: [
                Movement.Variant(
                    name: "Band W raise", equipment: .band, hold: .twoHands,
                    cue: "Elbows bent to a W, band between the hands. Draw the elbows down and back until the blades meet."),
            ]),

        // MARK: - Pull, vertical

        Movement(
            id: "upright-row",
            display: "Upright row",
            pattern: .pullVertical,
            position: .standing,
            muscles: "shoulders, back",
            form: MoveForm(
                setUp: "Standing tall, dumbbells in front of the thighs, hands a little apart.",
                movement: "Lead with the elbows wide, lifting the weights no higher than the chest, then lower.",
                feel: "The tops of the shoulders.",
                wrong: "Lifting past the chest, which pinches the shoulder; stop at chest height.",
                stopIf: "Any pinch at the front or top of the shoulder — this move is not for everyone, and skipping it is fine."),
            variants: [
                Movement.Variant(
                    name: "Upright row", equipment: .dumbbells, hold: .pair, loadPounds: 2,
                    cue: "Hands apart, elbows lead wide, no higher than the chest. Stop before the shoulders shrug."),
            ]),

        Movement(
            id: "pullover",
            display: "Pullover",
            pattern: .pullVertical,
            position: .floor,
            muscles: "chest, back, core",
            form: MoveForm(
                setUp: "On your back, knees bent, one dumbbell held in both hands above the chest, arms straight but not locked.",
                movement: "Take the weight back past the head as far as the ribs stay down, then bring it back over the chest.",
                feel: "The back under the armpits and the chest stretching.",
                wrong: "Letting the ribs flare and the low back arch; keep the ribs down the whole way.",
                stopIf: "Shoulder pain at the bottom — shorten the range."),
            variants: [
                Movement.Variant(
                    name: "Pullover", equipment: .dumbbells, hold: .pair, loadPounds: 2,
                    cue: "On your back, one weight held in both hands, arms straight. Take it back past your head only as far as the ribs stay down."),
            ]),

        Movement(
            id: "wall-angel",
            display: "Wall angel",
            pattern: .pullVertical,
            position: .standing,
            muscles: "shoulders, back, core",
            form: MoveForm(
                setUp: "Back, head and arms flat against a wall, elbows bent to ninety degrees, feet a step out.",
                movement: "Slide the arms up the wall and back down, keeping wrists, elbows and the low back touching.",
                feel: "The muscles between the shoulder blades working, and the chest stretching.",
                wrong: "The ribs lifting off the wall to reach higher; go only as high as the back stays flat.",
                stopIf: "A sharp pinch in the shoulder."),
            variants: [
                Movement.Variant(
                    name: "Wall angel", equipment: .bodyweight, hold: .none,
                    cue: "Back, head and arms against the wall. Slide the arms up and down; ribs down, nothing leaves the wall."),
            ]),

        // MARK: - Press, overhead

        // Five implements, one movement. The pair's form is the movement's,
        // so the single — which aliased to it — inherits it unchanged.
        Movement(
            id: "overhead-press",
            display: "Press",
            pattern: .pushVertical,
            position: .standing,
            muscles: "shoulders, arms",
            form: MoveForm(
                setUp: "Standing tall, a dumbbell in each hand at the shoulders, palms forward, ribs down.",
                movement: "Press straight up until the arms are by the ears, then lower slowly to the shoulders.",
                feel: "The shoulders and the back of the arms.",
                wrong: "Arching the low back to push the weight up; brace the core and keep the ribs down.",
                stopIf: "A pinch at the top of the shoulder."),
            variants: [
                Movement.Variant(
                    name: "Beam overhead press", equipment: .beam, hold: .twoHands, loadPounds: 15,
                    cue: "From the collarbones to straight overhead. Ribs stay down as the arms go up.",
                    form: MoveForm(
                        setUp: "The beam across the collarbones, hands shoulder width, ribs down.",
                        movement: "Press straight up until the arms are by the ears, then lower to the collarbones.",
                        feel: "Shoulders and the back of the arms.",
                        wrong: "Pressing out in front rather than straight up; move the head back slightly and let the beam travel in a straight line.",
                        stopIf: "Shoulder pinch or the low back arching to help.")),
                Movement.Variant(
                    name: "Ring overhead press", equipment: .rings, hold: .twoHands, loadPounds: 5,
                    cue: "The 5 lb ring from the chest to straight overhead, slowly.",
                    form: MoveForm(
                        setUp: "The 5 lb ring held at the chest in both hands, feet hip width, ribs down.",
                        movement: "Press the ring straight overhead slowly, pause, and lower.",
                        feel: "The shoulders; the core keeps the ribs down.",
                        wrong: "Leaning back; stay stacked over the hips.",
                        stopIf: "A pinch at the top of the shoulder.")),
                Movement.Variant(
                    name: "Dumbbell press", equipment: .dumbbells, hold: .pair, loadPounds: 2,
                    cue: "Two pounds is enough when you go slowly."),
                Movement.Variant(
                    name: "Single-dumbbell overhead press", equipment: .singleDumbbell,
                    hold: .oneHand, loadPounds: 10, sided: .sides,
                    cue: "The dumbbell in one hand at the shoulder. Press straight up, ribs down; the free hand on the hip."),
                Movement.Variant(
                    name: "Band overhead press", equipment: .band, hold: .twoHands,
                    cue: "Stand on the middle of the band, an end in each hand at the shoulders. Press up against it, slower on the way down.",
                    form: MoveForm(
                        setUp: "Standing on the middle of the band, an end in each hand at the shoulders.",
                        movement: "Press up against the band until the arms are straight, then lower under control.",
                        feel: "Shoulders.",
                        wrong: "Leaning back against the tension; keep the ribs down.",
                        stopIf: "Shoulder pinch.")),
            ]),

        // The same press from the knees, and the knees are the point — it
        // is a core move as much as a shoulder one, which is why the
        // muscles read differently and it stands apart.
        Movement(
            id: "tall-kneeling-press",
            display: "Tall-kneeling press",
            pattern: .pushVertical,
            position: .kneeling,
            muscles: "shoulders, core, arms",
            form: MoveForm(
                setUp: "Kneeling tall on both knees, hips forward, the dumbbell in both hands at the chest.",
                movement: "Press it overhead with the ribs down and the glutes tight, then lower.",
                feel: "Shoulders, and the glutes and core holding you upright.",
                wrong: "Sitting back onto the heels or arching; squeeze the glutes and stay tall.",
                stopIf: "Knee discomfort on the floor — kneel on a folded towel."),
            variants: [
                Movement.Variant(
                    name: "Tall-kneeling press", equipment: .singleDumbbell, hold: .twoHands,
                    loadPounds: 10,
                    cue: "Kneeling tall, the dumbbell in both hands at the chest. Press it overhead; ribs down, hips under you."),
            ]),

        Movement(
            id: "arnold-press",
            display: "Arnold press",
            pattern: .pushVertical,
            position: .standing,
            muscles: "shoulders, arms",
            form: MoveForm(
                setUp: "Dumbbells at the chin, palms facing you, elbows in front.",
                movement: "Rotate the palms outward as you press overhead, then reverse on the way down.",
                feel: "All around the shoulders.",
                wrong: "Rushing the rotation; it happens through the whole press, not at the top.",
                stopIf: "Shoulder pinch."),
            variants: [
                Movement.Variant(
                    name: "Ring Arnold press", equipment: .rings, hold: .oneHand, loadPounds: 5,
                    sided: .sides,
                    cue: "The 5 lb ring at the chin, palm in. Rotate out as you press overhead.",
                    form: MoveForm(
                        setUp: "The 5 lb ring at the chin in one hand, palm facing you.",
                        movement: "Rotate the palm out as you press overhead, then reverse on the way down.",
                        feel: "All around that shoulder.",
                        wrong: "Arching the back on the one-arm version; brace as if both hands were loaded.",
                        stopIf: "Shoulder pinch.")),
                Movement.Variant(
                    name: "Arnold press", equipment: .dumbbells, hold: .pair, loadPounds: 2,
                    cue: "Palms in at the chin, rotate out as you press up."),
            ]),

        // MARK: - Push, horizontal

        Movement(
            id: "floor-press",
            display: "Floor press",
            pattern: .pushHorizontal,
            position: .floor,
            muscles: "chest, arms",
            form: MoveForm(
                setUp: "On your back, knees bent, a dumbbell in each hand, upper arms on the floor, forearms vertical.",
                movement: "Press straight up until the arms are long, then lower until the upper arms rest on the floor.",
                feel: "Chest and the back of the arms.",
                wrong: "Flaring the elbows straight out to the sides; keep them at about forty-five degrees.",
                stopIf: "A pinch in the front of the shoulder."),
            variants: [
                Movement.Variant(
                    name: "Beam floor press", equipment: .beam, hold: .twoHands, loadPounds: 15,
                    cue: "On your back, beam at the chest, press straight up. The floor stops your elbows.",
                    form: MoveForm(
                        setUp: "On your back, knees bent, the beam held over the chest with the upper arms on the floor.",
                        movement: "Press straight up, pause, and lower until the elbows meet the floor.",
                        feel: "Chest and the back of the arms.",
                        wrong: "Bouncing the elbows off the floor; touch and press.",
                        stopIf: "Shoulder pinch.")),
                Movement.Variant(
                    name: "Dumbbell floor press", equipment: .dumbbells, hold: .pair, loadPounds: 5,
                    cue: "On your back, a 5 lb dumbbell in each hand. Press straight up; the floor catches your elbows between reps."),
                Movement.Variant(
                    name: "Single-dumbbell floor press", equipment: .singleDumbbell, hold: .twoHands,
                    loadPounds: 10,
                    cue: "On your back, the dumbbell in both hands over the chest. Press straight up; the floor stops your elbows."),
            ]),

        Movement(
            id: "press-out",
            display: "Press-out",
            pattern: .pushHorizontal,
            position: .standing,
            muscles: "chest, shoulders, core",
            form: MoveForm(
                setUp: "The 8 lb ring held at the chest in both hands, feet hip width.",
                movement: "Press the ring straight out in front until the arms are long, hold a beat, and bring it back.",
                feel: "The chest and front of the shoulders, and the core resisting the pull forward.",
                wrong: "Leaning back to counterbalance; stay stacked.",
                stopIf: "Shoulder pain."),
            variants: [
                Movement.Variant(
                    name: "Ring press-out", equipment: .rings, hold: .twoHands, loadPounds: 8,
                    cue: "Hold the 8 lb ring at the chest and press straight out."),
            ]),

        Movement(
            id: "squeeze-press",
            display: "Squeeze press",
            pattern: .pushHorizontal,
            position: .standing,
            muscles: "chest, arms",
            form: MoveForm(
                setUp: "Standing or lying, two dumbbells pressed hard together at the chest, palms facing.",
                movement: "Keep squeezing them together while pressing away from the chest, then return without letting them part.",
                feel: "The inner chest.",
                wrong: "Letting the dumbbells separate; the squeeze is the move.",
                stopIf: "Shoulder or wrist pain."),
            variants: [
                Movement.Variant(
                    name: "Squeeze press", equipment: .dumbbells, hold: .pair, loadPounds: 3,
                    cue: "Press the two weights together hard at the chest, then press them to the ceiling without letting them part."),
            ]),

        Movement(
            id: "floor-fly",
            display: "Floor fly",
            pattern: .pushHorizontal,
            position: .floor,
            muscles: "chest",
            form: MoveForm(
                setUp: "On your back, knees bent, a light dumbbell in each hand above the chest, palms facing, elbows soft.",
                movement: "Open the arms wide until they touch the floor, then bring them back together over the chest.",
                feel: "A stretch across the chest, then the chest closing the arms.",
                wrong: "Bending the elbows to make it a press; the angle at the elbow does not change.",
                stopIf: "Shoulder pain at the bottom."),
            variants: [
                Movement.Variant(
                    name: "Floor fly", equipment: .dumbbells, hold: .pair, loadPounds: 2,
                    cue: "On your back, soft elbows, open until the arms touch the floor."),
            ]),

        Movement(
            id: "boxer-punches",
            display: "Boxer punches",
            pattern: .pushHorizontal,
            position: .standing,
            muscles: "shoulders, arms, core",
            form: MoveForm(
                setUp: "Standing, light dumbbells at the chest, knees soft, one foot slightly forward.",
                movement: "Punch one arm straight out at chest height and draw it back as the other goes, controlled, not fast.",
                feel: "The shoulders and chest; the core turning slightly with each punch.",
                wrong: "Locking the elbow at the end of the punch; stop just short.",
                stopIf: "Elbow or shoulder pain."),
            variants: [
                Movement.Variant(
                    name: "Boxer punches", equipment: .dumbbells, hold: .pair, loadPounds: 2,
                    cue: "Alternating, chest height, controlled. The shoulders do the work."),
            ]),

        // Standing, because the hands are on a counter — the position is
        // where the body is, not where the movement points.
        Movement(
            id: "push-up",
            display: "Push-up",
            pattern: .pushHorizontal,
            position: .standing,
            muscles: "chest, arms, core",
            form: MoveForm(
                setUp: "Hands on a counter or sturdy surface a little wider than the shoulders, body in one straight line from head to heels.",
                movement: "Lower the chest toward the surface with the elbows at about forty-five degrees, then press back up.",
                feel: "Chest and the back of the arms; the core holds the line.",
                wrong: "Hips sagging or piking up; squeeze the glutes and keep one straight line.",
                stopIf: "A pinch in the front of the shoulder or wrist pain — raise the hands higher."),
            variants: [
                Movement.Variant(
                    name: "Incline push-up", equipment: .bodyweight, hold: .none,
                    cue: "Hands on the counter. The higher the hands, the easier it is."),
            ]),
    ]
}
