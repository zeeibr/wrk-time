import Foundation

/// The core and the carries: everything the taxonomy calls a carry, an
/// anti-rotation, a flexion or an extension of the trunk.
///
/// Two things decided the grouping. A movement holds one set of muscles and
/// one position, so where those differ the movement is a different movement
/// however alike the names read: the dead bug and the dumbbell dead bug
/// press work different things ("core" against "core, shoulders"), and the
/// overhead hold standing with the beam is not the half-kneeling one with a
/// ring. And a variant's name must contain the movement's noun, which is
/// why the beam hip thrust stands apart from the bridge rather than joining
/// it — the same shape on the mat under a name that says otherwise.
extension MovementCatalog {
    static let coreAndCarry: [Movement] = [

        // MARK: - Carries and holds

        Movement(
            id: "overhead-hold",
            display: "Overhead hold",
            pattern: .carry,
            position: .standing,
            muscles: "core, shoulders",
            form: MoveForm(
                setUp: "The beam pressed overhead, arms long beside the ears, ribs down.",
                movement: "Hold it still and breathe.",
                feel: "The shoulders and the core keeping the ribs down.",
                wrong: "The low back arching as the arms tire; lower the beam before that happens.",
                stopIf: "Shoulder pinch or any arching."),
            variants: [
                .init(name: "Beam overhead hold", equipment: .beam, hold: .twoHands,
                      loadPounds: 15,
                      cue: "The beam pressed overhead, arms by the ears. Ribs down over the hips, and hold."),
            ]),

        Movement(
            id: "half-kneeling-overhead-hold",
            display: "Half-kneeling overhead hold",
            pattern: .carry,
            position: .kneeling,
            muscles: "core, shoulders",
            form: MoveForm(
                setUp: "Half kneeling, one knee down, the 5 lb ring held straight overhead in the hand on the same side as the down knee.",
                movement: "Hold still and breathe, shoulders square, ribs down.",
                feel: "The shoulder, and the core and the glute of the down leg keeping you upright.",
                wrong: "Leaning away from the ring; stack the ribs over the hips.",
                stopIf: "Shoulder pinch."),
            variants: [
                .init(name: "Ring half-kneeling overhead hold", equipment: .rings, hold: .oneHand,
                      loadPounds: 5, sided: .sides,
                      cue: "Half kneeling, the 5 lb ring held straight overhead in one hand. Shoulders square, ribs stacked."),
            ]),

        Movement(
            id: "carry",
            display: "Carry",
            pattern: .carry,
            position: .standing,
            muscles: "core, back, arms",
            form: MoveForm(
                setUp: "The bell in one hand at the side, standing tall, shoulders level.",
                movement: "Walk slowly in a straight line, then switch hands; the free arm hangs naturally.",
                feel: "The side of the trunk opposite the bell working to keep you level, and the grip.",
                wrong: "Leaning away from the bell; stand as if carrying nothing.",
                stopIf: "The grip fails before the interval — set it down, shake out, and pick it up again."),
            variants: [
                .init(name: "Kettlebell carry", equipment: .kettlebell, hold: .oneHand,
                      loadPounds: 18, sided: .sides,
                      cue: "One hand, ribs stacked over hips, shoulders level. Walk slowly and do not lean."),
            ]),

        Movement(
            id: "rack-hold",
            display: "Rack hold",
            pattern: .carry,
            position: .standing,
            muscles: "core, arms, shoulders",
            form: MoveForm(
                setUp: "The bell resting on the forearm with the fist at the collarbone, elbow tucked to the ribs.",
                movement: "Stand tall and breathe; the bell does not move.",
                feel: "The core holding you upright against the weight on one side.",
                wrong: "The elbow winging out so the bell hangs on the wrist; keep it tucked.",
                stopIf: "Wrist pain — adjust the bell deeper into the hand."),
            variants: [
                .init(name: "Kettlebell rack hold", equipment: .kettlebell, hold: .oneHand,
                      loadPounds: 18, sided: .sides,
                      cue: "The bell resting on the forearm, fist at the collarbone, elbow tucked. Stand tall and breathe; ribs stay down."),
            ]),

        Movement(
            id: "suitcase-hold",
            display: "Suitcase hold",
            pattern: .carry,
            position: .standing,
            muscles: "core, arms",
            form: MoveForm(
                setUp: "The bell in one hand at the side, feet hip width.",
                movement: "Stand perfectly level and breathe; nothing moves.",
                feel: "The side of the trunk opposite the bell, and the grip.",
                wrong: "A lean toward or away from the weight; check that the shoulders are level.",
                stopIf: "Grip failure; set it down and rest."),
            variants: [
                .init(name: "Kettlebell suitcase hold", equipment: .kettlebell, hold: .oneHand,
                      loadPounds: 18, sided: .sides,
                      cue: "The bell in one hand at your side. Stand level — no lean — and let the grip do the work."),
            ]),

        Movement(
            id: "march",
            display: "March",
            pattern: .carry,
            position: .standing,
            muscles: "core",
            form: MoveForm(
                setUp: "The dumbbell in both hands at the chest, standing tall.",
                movement: "March slowly, lifting each knee to hip height, ribs stacked over the hips.",
                feel: "The core holding you still while the legs move.",
                wrong: "Leaning back to lift the knee; stay tall.",
                stopIf: "Low back ache."),
            variants: [
                .init(name: "Dumbbell march", equipment: .singleDumbbell, hold: .twoHands,
                      loadPounds: 10,
                      cue: "The dumbbell in both hands at your chest. March slowly; the ribs stay stacked over the hips."),
            ]),

        // MARK: - Bracing against rotation

        Movement(
            id: "halo",
            display: "Halo",
            pattern: .coreAntiRotation,
            position: .standing,
            muscles: "shoulders, arms, core",
            form: MoveForm(
                setUp: "The 5 lb ring held in both hands in front of the face, feet hip width, ribs down.",
                movement: "Circle the ring slowly around the head, close to it, one way and then the other.",
                feel: "The shoulders, and the core keeping you from swaying.",
                wrong: "Bending the neck to get the ring round; the head stays still and the arms travel.",
                stopIf: "Shoulder pinch."),
            variants: [
                .init(name: "Ring halo", equipment: .rings, hold: .twoHands,
                      loadPounds: 5, sided: .directions,
                      cue: "The 5 lb ring in both hands, slow circles around the head."),
            ]),

        Movement(
            id: "bus-driver",
            display: "Bus driver",
            pattern: .coreAntiRotation,
            position: .standing,
            muscles: "shoulders, arms",
            form: MoveForm(
                setUp: "The 5 lb ring held straight out at shoulder height in both hands.",
                movement: "Turn it like a steering wheel, left and right, slowly.",
                feel: "The shoulders and the core.",
                wrong: "Letting the arms drop as they tire; lower the weight before the arms do.",
                stopIf: "Shoulder pain."),
            variants: [
                .init(name: "Ring bus driver", equipment: .rings, hold: .twoHands,
                      loadPounds: 5,
                      cue: "The 5 lb ring held straight out at shoulder height. Turn it like a steering wheel, left and right, slowly."),
            ]),

        Movement(
            id: "chop",
            display: "Chop",
            pattern: .coreAntiRotation,
            position: .kneeling,
            muscles: "core, shoulders",
            form: MoveForm(
                setUp: "Half kneeling, the 5 lb ring in both hands at the outside hip of the down knee.",
                movement: "Sweep it slowly up and across to the far shoulder, then back down the same line.",
                feel: "The core turning the trunk against a still pelvis.",
                wrong: "The hips rotating with the ring; they face forward the whole time.",
                stopIf: "Low back pain."),
            variants: [
                .init(name: "Ring chop", equipment: .rings, hold: .twoHands,
                      loadPounds: 5, sided: .sides,
                      cue: "Half kneeling, the 5 lb ring at the outside hip. Sweep it slowly up across to the far shoulder, and back down the same line."),
            ]),

        Movement(
            id: "around-the-body",
            display: "Around the body",
            pattern: .coreAntiRotation,
            position: .standing,
            muscles: "core",
            form: MoveForm(
                setUp: "Standing tall, the bell in one hand at the front.",
                movement: "Pass it around the waist hand to hand in a slow circle, then reverse.",
                feel: "The core keeping the hips still while the bell travels.",
                wrong: "The hips swaying to meet the bell; only the arms move.",
                stopIf: "You cannot pass it without the back twisting — lighten the bell."),
            variants: [
                .init(name: "Kettlebell around the body", equipment: .kettlebell, hold: .oneHand,
                      loadPounds: 18, sided: .directions,
                      cue: "Pass the bell around your waist, hand to hand. The hips stay still; only the arms travel."),
            ]),

        // The dead bug and the pressed version are two movements, not one:
        // the arms holding a pair over the chest make it shoulders as well as
        // core, and a movement carries one answer to that question.
        Movement(
            id: "dead-bug",
            display: "Dead bug",
            pattern: .coreAntiRotation,
            position: .floor,
            muscles: "core",
            form: MoveForm(
                setUp: "On your back, arms straight up over the chest, knees over the hips at ninety degrees, low back pressed into the floor.",
                movement: "Lower one arm overhead and the opposite leg toward the floor, slowly, then return and switch.",
                feel: "The deep abdominals working to keep the low back flat.",
                wrong: "The low back arching off the floor; go only as far as it stays pressed down.",
                stopIf: "The back lifts on every rep — shorten the range or move one limb at a time."),
            variants: [
                .init(name: "Dead bug", equipment: .bodyweight, hold: .none,
                      cue: "Ribs down, low back flat on the floor."),
            ]),

        Movement(
            id: "dead-bug-press",
            display: "Dead bug press",
            pattern: .coreAntiRotation,
            position: .floor,
            muscles: "core, shoulders",
            form: MoveForm(
                setUp: "As the dead bug, with a light dumbbell in each hand pressed to the ceiling.",
                movement: "Lower one leg slowly while the arms stay pressed up and still, then switch.",
                feel: "The deep abdominals and the shoulders holding the weights steady.",
                wrong: "The arms drifting overhead as the leg lowers; they stay over the chest.",
                stopIf: "The low back lifts off the floor."),
            variants: [
                .init(name: "Dumbbell dead bug press", equipment: .dumbbells, hold: .pair,
                      loadPounds: 2,
                      cue: "A dead bug with the dumbbells pressed to the ceiling. Low back flat, arms straight the whole time."),
            ]),

        Movement(
            id: "plank-pull-through",
            display: "Plank pull-through",
            pattern: .coreAntiRotation,
            position: .floor,
            muscles: "core, shoulders",
            form: MoveForm(
                setUp: "A high plank with the dumbbell on the floor just outside one hand, feet wide.",
                movement: "Reach under the chest with the far hand, drag the weight across to the other side, and repeat the other way.",
                feel: "The core holding the hips square as one hand leaves the floor.",
                wrong: "The hips twisting toward the ceiling; keep them level.",
                stopIf: "Wrist or low back pain."),
            variants: [
                .init(name: "Plank pull-through", equipment: .singleDumbbell, hold: .oneHand,
                      loadPounds: 10,
                      cue: "From a high plank, drag the dumbbell under your chest to the other side, hand by hand. The hips stay quiet."),
            ]),

        Movement(
            id: "bird-dog",
            display: "Bird dog",
            pattern: .coreAntiRotation,
            position: .floor,
            muscles: "core, back",
            form: MoveForm(
                setUp: "On all fours, hands under the shoulders, knees under the hips, back flat.",
                movement: "Reach one arm forward and the opposite leg back until both are long and level, pause, and return.",
                feel: "The core holding the hips still; the glute of the reaching leg.",
                wrong: "The hips tipping as the leg lifts; keep them square to the floor.",
                stopIf: "Low back or wrist pain."),
            variants: [
                .init(name: "Bird dog", equipment: .bodyweight, hold: .none,
                      cue: "Opposite arm and leg, slowly. The hips do not tip."),
            ]),

        Movement(
            id: "forearm-plank",
            display: "Forearm plank",
            pattern: .coreAntiRotation,
            position: .floor,
            muscles: "core",
            form: MoveForm(
                setUp: "Forearms on the floor, elbows under the shoulders, toes tucked, one straight line from head to heels.",
                movement: "Hold and breathe normally; nothing moves.",
                feel: "The whole front of the trunk, and the glutes if you squeeze them.",
                wrong: "Hips sagging or lifting; squeeze the glutes to find the line.",
                stopIf: "Low back ache — lower the knees to the floor and hold from there."),
            variants: [
                .init(name: "Forearm plank", equipment: .bodyweight, hold: .none,
                      cue: "Elbows under the shoulders, one straight line from head to heels. Breathe, don't sag."),
            ]),

        Movement(
            id: "side-plank",
            display: "Side plank",
            pattern: .coreAntiRotation,
            position: .floor,
            muscles: "core",
            form: MoveForm(
                setUp: "On one forearm, elbow under the shoulder, feet stacked or the top foot in front, body in a line.",
                movement: "Lift the hips until the body is straight and hold still.",
                feel: "The side of the trunk nearest the floor.",
                wrong: "The hips dropping back or sagging; think of being pressed between two panes of glass.",
                stopIf: "Shoulder pain — drop to the knee version."),
            variants: [
                .init(name: "Side plank", equipment: .bodyweight, hold: .none,
                      sided: .sides,
                      cue: "On one forearm, feet stacked or staggered. Lift the hips and hold them still."),
            ]),

        Movement(
            id: "plank-shoulder-tap",
            display: "Plank shoulder tap",
            pattern: .coreAntiRotation,
            position: .floor,
            muscles: "core, shoulders",
            form: MoveForm(
                setUp: "A high plank on the hands, feet a little wider than the hips for balance.",
                movement: "Lift one hand and tap the opposite shoulder, set it down, and switch, slowly.",
                feel: "The core working to keep the hips from rocking.",
                wrong: "The hips swinging side to side; go slower and widen the feet.",
                stopIf: "Wrist pain — turn the hands out slightly or make fists."),
            variants: [
                .init(name: "Plank shoulder tap", equipment: .bodyweight, hold: .none,
                      cue: "From a high plank, tap the opposite shoulder. The hips stay square to the floor."),
            ]),

        Movement(
            id: "bear-hold",
            display: "Bear hold",
            pattern: .coreAntiRotation,
            position: .floor,
            muscles: "core, shoulders",
            form: MoveForm(
                setUp: "On all fours, toes tucked, hands under the shoulders.",
                movement: "Lift the knees an inch off the floor and hold, back flat, breathing.",
                feel: "The whole core and the front of the thighs.",
                wrong: "The back rounding or the hips rising; keep the knees low and the back flat.",
                stopIf: "Wrist pain."),
            variants: [
                .init(name: "Bear hold", equipment: .bodyweight, hold: .none,
                      cue: "On all fours, toes tucked, knees hovering an inch off the mat. Flat back, and breathe."),
            ]),

        // MARK: - Bending the trunk

        Movement(
            id: "russian-twist",
            display: "Russian twist",
            pattern: .coreFlexion,
            position: .floor,
            muscles: "core",
            form: MoveForm(
                setUp: "Seated, knees bent, heels on the floor, leaning back slightly with a tall spine, the dumbbell in both hands at the chest.",
                movement: "Turn from the ribs to one side, then the other, slowly; the weight follows the chest.",
                feel: "The sides of the trunk.",
                wrong: "Swinging the arms while the chest stays facing forward; the ribs turn and the arms go along.",
                stopIf: "Low back pain — sit taller and reduce the lean."),
            variants: [
                .init(name: "Russian twist", equipment: .singleDumbbell, hold: .twoHands,
                      loadPounds: 10,
                      cue: "Seated tall, knees bent, the dumbbell in both hands. Turn from the ribs, side to side, slowly — the chest stays lifted the whole time."),
            ]),

        Movement(
            id: "standing-side-bend",
            display: "Standing side bend",
            pattern: .coreFlexion,
            position: .standing,
            muscles: "core",
            form: MoveForm(
                setUp: "Standing tall, the dumbbell in one hand at the side, feet hip width.",
                movement: "Slide the weight down the outside of the thigh, bending only sideways, then stand tall.",
                feel: "The side of the trunk opposite the weight pulling you back up.",
                wrong: "Leaning forward or back; the movement is in one plane, straight to the side.",
                stopIf: "Low back pain."),
            variants: [
                .init(name: "Standing side bend", equipment: .singleDumbbell, hold: .oneHand,
                      loadPounds: 10, sided: .sides,
                      cue: "The dumbbell in one hand, slide it down the outside of the thigh and stand tall again."),
            ]),

        Movement(
            id: "lying-leg-raise",
            display: "Lying leg raise",
            pattern: .coreFlexion,
            position: .floor,
            muscles: "core",
            form: MoveForm(
                setUp: "On your back, legs long, hands under the hips or by the sides, low back pressed into the floor.",
                movement: "Lift the legs to vertical and lower them only as far as the low back stays down.",
                feel: "The lower abdominals.",
                wrong: "Lowering past the point the back arches; bend the knees to shorten the lever.",
                stopIf: "Low back pain on the way down."),
            variants: [
                .init(name: "Lying leg raise", equipment: .bodyweight, hold: .none,
                      cue: "Low back pressed into the floor. Lower the legs only as far as it stays there."),
            ]),

        Movement(
            id: "bicycle-crunch",
            display: "Bicycle crunch",
            pattern: .coreFlexion,
            position: .floor,
            muscles: "core",
            form: MoveForm(
                setUp: "On your back, hands lightly behind the head, knees up.",
                movement: "Bring one elbow toward the opposite knee while the other leg reaches long, then switch, slowly.",
                feel: "The abdominals, especially the sides.",
                wrong: "Pulling on the neck; the hands only rest there, and the elbows stay wide.",
                stopIf: "Neck strain."),
            variants: [
                .init(name: "Bicycle crunch", equipment: .bodyweight, hold: .none,
                      cue: "Slow. Opposite elbow toward opposite knee, and the straight leg reaches long."),
            ]),

        // MARK: - Extending the trunk

        // One movement, two implements: the ring simply rests where the hands
        // would be. The beam's version is named a hip thrust and so stands on
        // its own, and the one-leg bridge works the legs as well.
        Movement(
            id: "bridge",
            display: "Bridge",
            pattern: .coreExtension,
            position: .floor,
            muscles: "glutes",
            form: MoveForm(
                setUp: "On your back, knees bent, heels close to the hips, arms by the sides.",
                movement: "Press through the heels to lift the hips until the body is a straight line from knees to shoulders, hold, and lower slowly.",
                feel: "The glutes, with a little hamstring.",
                wrong: "Arching the low back to go higher; stop where the glutes are doing it.",
                stopIf: "Hamstring cramp — walk the heels a little further away."),
            variants: [
                .init(name: "Glute bridge", equipment: .bodyweight, hold: .none,
                      cue: "Heels close, press through them, hold a beat at the top."),
                .init(name: "Ring bridge", equipment: .rings, hold: .twoHands,
                      loadPounds: 10,
                      cue: "On your back, the 10 lb ring resting on the hip bones. Press up through the heels and hold a beat at the top.",
                      form: MoveForm(
                        setUp: "On your back, knees bent, the 10 lb ring resting on the hip bones held in both hands.",
                        movement: "Press through the heels, lift the hips, hold, and lower.",
                        feel: "The glutes.",
                        wrong: "The knees falling out or in; keep them over the feet.",
                        stopIf: "Low back pain.")),
            ]),

        Movement(
            id: "hip-thrust",
            display: "Hip thrust",
            pattern: .coreExtension,
            position: .floor,
            muscles: "glutes",
            form: MoveForm(
                setUp: "On your back on the mat, knees bent, the beam across the hips held in both hands.",
                movement: "Drive through the heels to lift the hips, hold a beat at the top, and lower slowly.",
                feel: "The glutes.",
                wrong: "Arching the back at the top; tuck the ribs and let the glutes finish.",
                stopIf: "Low back pain."),
            variants: [
                .init(name: "Beam hip thrust", equipment: .beam, hold: .twoHands,
                      loadPounds: 15,
                      cue: "On your back on the mat, beam across the hips. Press through the heels and hold a beat at the top."),
            ]),

        Movement(
            id: "one-leg-bridge",
            display: "One-leg bridge",
            pattern: .coreExtension,
            position: .floor,
            muscles: "glutes, legs",
            form: MoveForm(
                setUp: "As the glute bridge, with one foot planted and the other leg held long or hugged in.",
                movement: "Press through the planted heel and lift the hips level, then lower.",
                feel: "The glute of the planted leg.",
                wrong: "The hips tipping toward the lifted leg; keep them level.",
                stopIf: "Hamstring cramp or low back pain."),
            variants: [
                .init(name: "One-leg bridge", equipment: .bodyweight, hold: .none,
                      sided: .sides,
                      cue: "One foot planted, the other leg held long or hugged in. Press through the heel; the hips stay level."),
            ]),

        Movement(
            id: "superman",
            display: "Superman",
            pattern: .coreExtension,
            position: .floor,
            muscles: "back, glutes, core",
            form: MoveForm(
                setUp: "On your belly, arms reaching long in front, legs long behind, forehead toward the floor.",
                movement: "Float the arms and legs an inch off the mat, hold, and lower.",
                feel: "The whole back of the body working gently.",
                wrong: "Lifting high and craning the neck; keep it small and the gaze down.",
                stopIf: "Low back pain rather than muscle work."),
            variants: [
                .init(name: "Superman", equipment: .bodyweight, hold: .none,
                      cue: "On your belly, arms reaching long. Float the arms and legs an inch off the mat and hold; keep looking down."),
            ]),

        Movement(
            id: "reverse-tabletop-hold",
            display: "Reverse tabletop hold",
            pattern: .coreExtension,
            position: .floor,
            muscles: "arms, shoulders, glutes",
            form: MoveForm(
                setUp: "Seated, hands behind you with the fingers pointing toward the heels, feet flat.",
                movement: "Press the hips up until level with the knees and hold, chest open.",
                feel: "The glutes, the back of the shoulders and the back of the arms.",
                wrong: "The hips sagging; press them up and squeeze the glutes.",
                stopIf: "Wrist or shoulder pain."),
            variants: [
                .init(name: "Reverse tabletop hold", equipment: .bodyweight, hold: .none,
                      cue: "Seated, hands behind you, fingers toward your heels. Press the hips up level with the knees and hold, chest broad."),
            ]),
    ]
}
