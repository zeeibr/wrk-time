import Foundation

/// How to do each move, for someone who has never been shown.
///
/// Her words, August 2026: *"im a beginner so i dont know much about form."*
/// The one-line `cue` on a move is what the timer says while she is in the
/// set; this is what she reads before the first one. Five lines, each one
/// sentence, in the app's voice:
///
/// - **set up** — where the feet, the hands and the implement are before
///   anything moves;
/// - **the movement** — what moves, in what order, how fast;
/// - **feel** — where the work should land, so she can tell a good rep from
///   a bad one without a mirror;
/// - **wrong** — the one or two mistakes a beginner actually makes on this
///   move, stated as what to do instead;
/// - **stop if** — the signal that means stop, as distinct from the signal
///   that means it is working. Pain is named by place; effort is never a
///   reason to stop.
///
/// A lookup beside the library, like `MoveMuscles` and `MoveTaxonomy`, so no
/// routine on disk changes shape. Custom moves carry their own notes from
/// the review. Educational, never medical: nothing here diagnoses, and
/// "stop if" points at a doctor only in the sense that any sharp pain does.
struct MoveForm: Equatable {
    var setUp: String
    var movement: String
    var feel: String
    var wrong: String
    var stopIf: String

    static func notes(for name: String) -> MoveForm? {
        if let (movement, variant) = MovementCatalog.byVariantName[MovePreference.key(name)] {
            return variant.form ?? movement.form
        }
        return table[MoveAliases.resolve(name)]
    }

    /// The line that is always true: effort is not the stop signal.
    static let effortIsNotPain = "Burning muscle and heavy breathing are the work. Sharp, pinching or joint pain is not — stop, rest, and come back lighter."

    // MARK: - The table

    private static let table: [String: MoveForm] = [

        // MARK: Hinges

        "kettlebell deadlift": MoveForm(
            setUp: "Feet under the hips, the bell on the floor between the arches, toes pointing slightly out.",
            movement: "Push the hips back until the hands reach the handle, grip, then stand by driving the floor away — hips and shoulders rise together.",
            feel: "The back of the thighs stretch on the way down and the glutes finish the stand.",
            wrong: "Bending the knees first turns it into a squat; lead with the hips and keep the shins nearly vertical.",
            stopIf: "The low back rounds or aches rather than the hamstrings working — lighten the bell and hinge less deep."),
        "kickstand deadlift": MoveForm(
            setUp: "The bell inside the front foot; the back foot a step behind with only the toes down, like a kickstand.",
            movement: "Hinge over the front leg, hips back, reach the bell, and stand through the front heel.",
            feel: "The front hamstring and glute do nearly all of it; the back foot only balances.",
            wrong: "Loading the back foot makes it a split squat; keep nine tenths of your weight on the front leg.",
            stopIf: "The front knee caves inward or the low back takes the load."),
        "suitcase deadlift": MoveForm(
            setUp: "The dumbbell on the floor beside one foot, feet hip width, shoulders level.",
            movement: "Hinge, grip, and stand tall without leaning toward the weight; then lower it the same way.",
            feel: "The hamstrings on the way down, and the side of the trunk opposite the weight holding you level.",
            wrong: "Tipping sideways toward the load; the whole point is to stay square.",
            stopIf: "You cannot stay level without the low back twisting."),
        "ring deadlift": MoveForm(
            setUp: "The 10 lb ring flat on the floor between the feet, feet hip width.",
            movement: "Hips back, flat back, reach the ring with both hands, and stand by driving through the heels.",
            feel: "Hamstrings stretch on the way down; glutes squeeze at the top.",
            wrong: "Squatting down to it; push the hips back and keep the shins still.",
            stopIf: "The low back rounds or aches."),
        "beam deadlift": MoveForm(
            setUp: "The beam on the floor against the shins, feet hip width, hands just outside the legs.",
            movement: "Push the hips back, take the beam, and stand up tall keeping it close to the legs the whole way.",
            feel: "Hamstrings load on the way down; standing up is the glutes.",
            wrong: "Letting the beam drift forward away from the shins, which pulls on the low back.",
            stopIf: "The back rounds or you feel it in the spine rather than the legs."),
        "beam good morning": MoveForm(
            setUp: "The beam across the back of the shoulders, never on the neck, feet hip width, knees soft.",
            movement: "Hinge forward from the hips with a flat back until the hamstrings stop you, then stand.",
            feel: "A stretch down the back of the thighs; the glutes bring you back up.",
            wrong: "Rounding the back to go lower; the range is whatever your hamstrings allow with a flat back.",
            stopIf: "Any pinch in the low back — this move has no business there."),

        // MARK: Squats

        "kettlebell goblet squat": MoveForm(
            setUp: "The bell held by the horns at the chest, elbows down, feet a little wider than the hips, toes slightly out.",
            movement: "Sit straight down between the heels, elbows inside the knees, chest tall, then stand.",
            feel: "The thighs and glutes doing the work; the bell only asks the core to stay tall.",
            wrong: "The heels lifting or the knees caving in; push the knees out toward the little toes.",
            stopIf: "Sharp knee pain on the way down, as opposed to thighs burning."),
        "kettlebell sumo squat": MoveForm(
            setUp: "Feet wide, toes turned out, the bell hanging in both hands between the legs.",
            movement: "Sit straight down between the heels, chest up, then drive through the feet to stand.",
            feel: "The inner thighs and glutes.",
            wrong: "Leaning forward so the bell swings; keep the torso tall and the bell hanging straight down.",
            stopIf: "Knee or groin pain that is sharp, not a stretch."),
        "ring goblet squat": MoveForm(
            setUp: "The 10 lb ring held at the chest in both hands, feet a little wider than the hips.",
            movement: "Sit down between the hips, chest tall, pause at the bottom, and stand.",
            feel: "Thighs and glutes.",
            wrong: "Knees falling inward; think about spreading the floor apart.",
            stopIf: "Sharp knee pain."),
        "beam front squat": MoveForm(
            setUp: "The beam across the collarbones, resting on the front of the shoulders, elbows lifted, feet a little wider than the hips.",
            movement: "Sit down over three counts with the chest tall, then stand in one.",
            feel: "Thighs and glutes; the upper back works to keep the beam up.",
            wrong: "Letting the elbows drop so the beam rolls forward; keep the elbows up and the chest proud.",
            stopIf: "Sharp knee pain or a wrist that cannot tolerate the beam's position."),
        "air squat": MoveForm(
            setUp: "Feet under the hips or a little wider, toes slightly out, arms out in front for balance.",
            movement: "Sit down and back as if to a chair, chest tall, as low as your heels stay down, then stand all the way up.",
            feel: "Thighs and glutes.",
            wrong: "Heels rising or knees caving; slow down and let the knees track over the toes.",
            stopIf: "Sharp knee pain."),
        "wall sit": MoveForm(
            setUp: "Back flat against the wall, feet a step out, hip width.",
            movement: "Slide down until the thighs are parallel to the floor, or higher if they cannot be, and hold.",
            feel: "The front of the thighs burning; that is the whole move.",
            wrong: "Hands on the thighs; they rest by your sides or across the chest.",
            stopIf: "Knee pain behind the kneecap rather than thigh burn."),

        // MARK: Lunges

        "reverse lunge": MoveForm(
            setUp: "Standing tall, feet under the hips, hands on the hips or at the chest.",
            movement: "Step one foot back, lower until the back knee nearly touches the floor, and push through the front heel to return.",
            feel: "The front thigh and glute; the back leg only steadies you.",
            wrong: "Stepping forward instead, which loads the knee; step back, and keep the front knee over the ankle.",
            stopIf: "Sharp pain in the front knee."),
        "split squat": MoveForm(
            setUp: "One foot forward, one back, a long stride apart, most of your weight on the front foot.",
            movement: "Lower the back knee straight down toward the floor, then stand; the feet stay where they are.",
            feel: "Front thigh and glute.",
            wrong: "Leaning forward over the front knee; keep the torso upright and the hips square.",
            stopIf: "Sharp knee pain."),
        "beam reverse lunge": MoveForm(
            setUp: "The beam across the chest or the front of the shoulders, feet under the hips.",
            movement: "Step back, lower the back knee toward the floor, and drive through the front heel to stand.",
            feel: "Front thigh and glute; the core holds the beam still.",
            wrong: "The front knee drifting past the toes; keep it over the ankle.",
            stopIf: "Sharp knee pain or balance so poor the beam is moving."),
        "beam lateral lunge": MoveForm(
            setUp: "The beam across the collarbones, feet together.",
            movement: "Step wide to one side, sit back into that hip with the other leg straight, then push back to standing.",
            feel: "The glute and inner thigh of the bent leg.",
            wrong: "The bent knee falling inward; keep it over the foot and the chest up.",
            stopIf: "Sharp knee or groin pain."),
        "beam curtsy lunge": MoveForm(
            setUp: "The beam across the collarbones, feet under the hips.",
            movement: "Step one foot back and across behind the other, sink straight down, and stand.",
            feel: "The outer glute of the front leg.",
            wrong: "Twisting the hips; they stay square to the front.",
            stopIf: "Any knee pain on the front leg."),

        // MARK: Rows and pulls

        "kettlebell row": MoveForm(
            setUp: "Hinge forward with a flat back, the free hand braced on the thigh, the bell hanging under the shoulder.",
            movement: "Pull the bell to the hip, elbow going back not out, pause, then lower slowly.",
            feel: "The muscles beside the shoulder blade; the arm is just the handle.",
            wrong: "Shrugging the shoulder toward the ear; keep it down and pull with the back.",
            stopIf: "The low back aches from holding the hinge — rest it, then hinge less deep."),
        "beam row": MoveForm(
            setUp: "Hinge forward with a flat back, the beam hanging at arm's length, hands shoulder width.",
            movement: "Pull the beam to the belly, elbows back, squeeze the shoulder blades, lower slowly.",
            feel: "Between and below the shoulder blades.",
            wrong: "Standing up to meet the beam; the torso stays still and the beam comes to you.",
            stopIf: "Low back pain rather than upper back work."),
        "dumbbell row": MoveForm(
            setUp: "Hinge forward with a flat back, a dumbbell in each hand hanging under the shoulders.",
            movement: "Pull both to the hips, blades together at the top, and lower over three counts.",
            feel: "Between the shoulder blades.",
            wrong: "Elbows flaring wide; they go back, close to the body.",
            stopIf: "Low back pain."),
        "ring row": MoveForm(
            setUp: "Hinge forward with a flat back, the 8 lb ring in one hand hanging under the shoulder.",
            movement: "Pull the ring to the hip, elbow going back, pause, then lower.",
            feel: "Beside the shoulder blade on that side.",
            wrong: "Twisting the torso to lift; the shoulders stay square to the floor.",
            stopIf: "Low back pain."),
        "rear delt fly": MoveForm(
            setUp: "Hinge forward with a flat back, a light dumbbell in each hand hanging below the chest, palms facing each other.",
            movement: "Open the arms wide with soft elbows until they are level with the shoulders, squeeze, and lower.",
            feel: "The back of the shoulders and between the blades.",
            wrong: "Swinging the weights up; they should be light enough to move slowly.",
            stopIf: "A pinch in the front of the shoulder."),
        "upright row": MoveForm(
            setUp: "Standing tall, dumbbells in front of the thighs, hands a little apart.",
            movement: "Lead with the elbows wide, lifting the weights no higher than the chest, then lower.",
            feel: "The tops of the shoulders.",
            wrong: "Lifting past the chest, which pinches the shoulder; stop at chest height.",
            stopIf: "Any pinch at the front or top of the shoulder — this move is not for everyone, and skipping it is fine."),
        "pullover": MoveForm(
            setUp: "On your back, knees bent, one dumbbell held in both hands above the chest, arms straight but not locked.",
            movement: "Take the weight back past the head as far as the ribs stay down, then bring it back over the chest.",
            feel: "The back under the armpits and the chest stretching.",
            wrong: "Letting the ribs flare and the low back arch; keep the ribs down the whole way.",
            stopIf: "Shoulder pain at the bottom — shorten the range."),
        "wall angel": MoveForm(
            setUp: "Back, head and arms flat against a wall, elbows bent to ninety degrees, feet a step out.",
            movement: "Slide the arms up the wall and back down, keeping wrists, elbows and the low back touching.",
            feel: "The muscles between the shoulder blades working, and the chest stretching.",
            wrong: "The ribs lifting off the wall to reach higher; go only as high as the back stays flat.",
            stopIf: "A sharp pinch in the shoulder."),
        "band pull-apart": MoveForm(
            setUp: "The band held in both hands at shoulder height, arms straight, hands shoulder width.",
            movement: "Pull the hands apart until the band touches the chest, squeeze the blades, and let it return slowly.",
            feel: "Between the shoulder blades.",
            wrong: "Shrugging; keep the shoulders down.",
            stopIf: "Shoulder pain."),
        "band face pull": MoveForm(
            setUp: "The band anchored or held in front at face height, hands together.",
            movement: "Pull toward the eyes with the elbows high and wide, thumbs turning back, then return slowly.",
            feel: "The back of the shoulders.",
            wrong: "Pulling to the chest instead of the face; keep the elbows high.",
            stopIf: "Shoulder pain."),
        "band w raise": MoveForm(
            setUp: "Elbows bent and tucked, the band between the hands, forearms making a W.",
            movement: "Draw the elbows down and back until the shoulder blades squeeze, then release.",
            feel: "Between and below the shoulder blades.",
            wrong: "Arching the low back to help; keep the ribs down.",
            stopIf: "Shoulder pain."),
        "band seated row": MoveForm(
            setUp: "Seated on the floor, legs long, the band looped around both feet, handles in the hands.",
            movement: "Pull to the ribs with the elbows close, blades together, then let the arms out slowly.",
            feel: "Between the shoulder blades.",
            wrong: "Rounding the back as the arms go out; sit tall the whole way.",
            stopIf: "Low back pain."),

        // MARK: Presses and pushes

        "incline push-up": MoveForm(
            setUp: "Hands on a counter or sturdy surface a little wider than the shoulders, body in one straight line from head to heels.",
            movement: "Lower the chest toward the surface with the elbows at about forty-five degrees, then press back up.",
            feel: "Chest and the back of the arms; the core holds the line.",
            wrong: "Hips sagging or piking up; squeeze the glutes and keep one straight line.",
            stopIf: "A pinch in the front of the shoulder or wrist pain — raise the hands higher."),
        "dumbbell press": MoveForm(
            setUp: "Standing tall, a dumbbell in each hand at the shoulders, palms forward, ribs down.",
            movement: "Press straight up until the arms are by the ears, then lower slowly to the shoulders.",
            feel: "The shoulders and the back of the arms.",
            wrong: "Arching the low back to push the weight up; brace the core and keep the ribs down.",
            stopIf: "A pinch at the top of the shoulder."),
        "arnold press": MoveForm(
            setUp: "Dumbbells at the chin, palms facing you, elbows in front.",
            movement: "Rotate the palms outward as you press overhead, then reverse on the way down.",
            feel: "All around the shoulders.",
            wrong: "Rushing the rotation; it happens through the whole press, not at the top.",
            stopIf: "Shoulder pinch."),
        "ring overhead press": MoveForm(
            setUp: "The 5 lb ring held at the chest in both hands, feet hip width, ribs down.",
            movement: "Press the ring straight overhead slowly, pause, and lower.",
            feel: "The shoulders; the core keeps the ribs down.",
            wrong: "Leaning back; stay stacked over the hips.",
            stopIf: "A pinch at the top of the shoulder."),
        "ring arnold press": MoveForm(
            setUp: "The 5 lb ring at the chin in one hand, palm facing you.",
            movement: "Rotate the palm out as you press overhead, then reverse on the way down.",
            feel: "All around that shoulder.",
            wrong: "Arching the back on the one-arm version; brace as if both hands were loaded.",
            stopIf: "Shoulder pinch."),
        "beam overhead press": MoveForm(
            setUp: "The beam across the collarbones, hands shoulder width, ribs down.",
            movement: "Press straight up until the arms are by the ears, then lower to the collarbones.",
            feel: "Shoulders and the back of the arms.",
            wrong: "Pressing out in front rather than straight up; move the head back slightly and let the beam travel in a straight line.",
            stopIf: "Shoulder pinch or the low back arching to help."),
        "tall-kneeling press": MoveForm(
            setUp: "Kneeling tall on both knees, hips forward, the dumbbell in both hands at the chest.",
            movement: "Press it overhead with the ribs down and the glutes tight, then lower.",
            feel: "Shoulders, and the glutes and core holding you upright.",
            wrong: "Sitting back onto the heels or arching; squeeze the glutes and stay tall.",
            stopIf: "Knee discomfort on the floor — kneel on a folded towel."),
        "band overhead press": MoveForm(
            setUp: "Standing on the middle of the band, an end in each hand at the shoulders.",
            movement: "Press up against the band until the arms are straight, then lower under control.",
            feel: "Shoulders.",
            wrong: "Leaning back against the tension; keep the ribs down.",
            stopIf: "Shoulder pinch."),
        "ring press-out": MoveForm(
            setUp: "The 8 lb ring held at the chest in both hands, feet hip width.",
            movement: "Press the ring straight out in front until the arms are long, hold a beat, and bring it back.",
            feel: "The chest and front of the shoulders, and the core resisting the pull forward.",
            wrong: "Leaning back to counterbalance; stay stacked.",
            stopIf: "Shoulder pain."),
        "squeeze press": MoveForm(
            setUp: "Standing or lying, two dumbbells pressed hard together at the chest, palms facing.",
            movement: "Keep squeezing them together while pressing away from the chest, then return without letting them part.",
            feel: "The inner chest.",
            wrong: "Letting the dumbbells separate; the squeeze is the move.",
            stopIf: "Shoulder or wrist pain."),
        "dumbbell floor press": MoveForm(
            setUp: "On your back, knees bent, a dumbbell in each hand, upper arms on the floor, forearms vertical.",
            movement: "Press straight up until the arms are long, then lower until the upper arms rest on the floor.",
            feel: "Chest and the back of the arms.",
            wrong: "Flaring the elbows straight out to the sides; keep them at about forty-five degrees.",
            stopIf: "A pinch in the front of the shoulder."),
        "beam floor press": MoveForm(
            setUp: "On your back, knees bent, the beam held over the chest with the upper arms on the floor.",
            movement: "Press straight up, pause, and lower until the elbows meet the floor.",
            feel: "Chest and the back of the arms.",
            wrong: "Bouncing the elbows off the floor; touch and press.",
            stopIf: "Shoulder pinch."),
        "floor fly": MoveForm(
            setUp: "On your back, knees bent, a light dumbbell in each hand above the chest, palms facing, elbows soft.",
            movement: "Open the arms wide until they touch the floor, then bring them back together over the chest.",
            feel: "A stretch across the chest, then the chest closing the arms.",
            wrong: "Bending the elbows to make it a press; the angle at the elbow does not change.",
            stopIf: "Shoulder pain at the bottom."),
        "boxer punches": MoveForm(
            setUp: "Standing, light dumbbells at the chest, knees soft, one foot slightly forward.",
            movement: "Punch one arm straight out at chest height and draw it back as the other goes, controlled, not fast.",
            feel: "The shoulders and chest; the core turning slightly with each punch.",
            wrong: "Locking the elbow at the end of the punch; stop just short.",
            stopIf: "Elbow or shoulder pain."),

        // MARK: Carries and holds

        "kettlebell carry": MoveForm(
            setUp: "The bell in one hand at the side, standing tall, shoulders level.",
            movement: "Walk slowly in a straight line, then switch hands; the free arm hangs naturally.",
            feel: "The side of the trunk opposite the bell working to keep you level, and the grip.",
            wrong: "Leaning away from the bell; stand as if carrying nothing.",
            stopIf: "The grip fails before the interval — set it down, shake out, and pick it up again."),
        "kettlebell suitcase hold": MoveForm(
            setUp: "The bell in one hand at the side, feet hip width.",
            movement: "Stand perfectly level and breathe; nothing moves.",
            feel: "The side of the trunk opposite the bell, and the grip.",
            wrong: "A lean toward or away from the weight; check that the shoulders are level.",
            stopIf: "Grip failure; set it down and rest."),
        "kettlebell rack hold": MoveForm(
            setUp: "The bell resting on the forearm with the fist at the collarbone, elbow tucked to the ribs.",
            movement: "Stand tall and breathe; the bell does not move.",
            feel: "The core holding you upright against the weight on one side.",
            wrong: "The elbow winging out so the bell hangs on the wrist; keep it tucked.",
            stopIf: "Wrist pain — adjust the bell deeper into the hand."),
        "beam overhead hold": MoveForm(
            setUp: "The beam pressed overhead, arms long beside the ears, ribs down.",
            movement: "Hold it still and breathe.",
            feel: "The shoulders and the core keeping the ribs down.",
            wrong: "The low back arching as the arms tire; lower the beam before that happens.",
            stopIf: "Shoulder pinch or any arching."),
        "ring half-kneeling overhead hold": MoveForm(
            setUp: "Half kneeling, one knee down, the 5 lb ring held straight overhead in the hand on the same side as the down knee.",
            movement: "Hold still and breathe, shoulders square, ribs down.",
            feel: "The shoulder, and the core and the glute of the down leg keeping you upright.",
            wrong: "Leaning away from the ring; stack the ribs over the hips.",
            stopIf: "Shoulder pinch."),
        "dumbbell march": MoveForm(
            setUp: "The dumbbell in both hands at the chest, standing tall.",
            movement: "March slowly, lifting each knee to hip height, ribs stacked over the hips.",
            feel: "The core holding you still while the legs move.",
            wrong: "Leaning back to lift the knee; stay tall.",
            stopIf: "Low back ache."),

        // MARK: Core — brace

        "dead bug": MoveForm(
            setUp: "On your back, arms straight up over the chest, knees over the hips at ninety degrees, low back pressed into the floor.",
            movement: "Lower one arm overhead and the opposite leg toward the floor, slowly, then return and switch.",
            feel: "The deep abdominals working to keep the low back flat.",
            wrong: "The low back arching off the floor; go only as far as it stays pressed down.",
            stopIf: "The back lifts on every rep — shorten the range or move one limb at a time."),
        "dumbbell dead bug press": MoveForm(
            setUp: "As the dead bug, with a light dumbbell in each hand pressed to the ceiling.",
            movement: "Lower one leg slowly while the arms stay pressed up and still, then switch.",
            feel: "The deep abdominals and the shoulders holding the weights steady.",
            wrong: "The arms drifting overhead as the leg lowers; they stay over the chest.",
            stopIf: "The low back lifts off the floor."),
        "bird dog": MoveForm(
            setUp: "On all fours, hands under the shoulders, knees under the hips, back flat.",
            movement: "Reach one arm forward and the opposite leg back until both are long and level, pause, and return.",
            feel: "The core holding the hips still; the glute of the reaching leg.",
            wrong: "The hips tipping as the leg lifts; keep them square to the floor.",
            stopIf: "Low back or wrist pain."),
        "forearm plank": MoveForm(
            setUp: "Forearms on the floor, elbows under the shoulders, toes tucked, one straight line from head to heels.",
            movement: "Hold and breathe normally; nothing moves.",
            feel: "The whole front of the trunk, and the glutes if you squeeze them.",
            wrong: "Hips sagging or lifting; squeeze the glutes to find the line.",
            stopIf: "Low back ache — lower the knees to the floor and hold from there."),
        "side plank": MoveForm(
            setUp: "On one forearm, elbow under the shoulder, feet stacked or the top foot in front, body in a line.",
            movement: "Lift the hips until the body is straight and hold still.",
            feel: "The side of the trunk nearest the floor.",
            wrong: "The hips dropping back or sagging; think of being pressed between two panes of glass.",
            stopIf: "Shoulder pain — drop to the knee version."),
        "plank shoulder tap": MoveForm(
            setUp: "A high plank on the hands, feet a little wider than the hips for balance.",
            movement: "Lift one hand and tap the opposite shoulder, set it down, and switch, slowly.",
            feel: "The core working to keep the hips from rocking.",
            wrong: "The hips swinging side to side; go slower and widen the feet.",
            stopIf: "Wrist pain — turn the hands out slightly or make fists."),
        "bear hold": MoveForm(
            setUp: "On all fours, toes tucked, hands under the shoulders.",
            movement: "Lift the knees an inch off the floor and hold, back flat, breathing.",
            feel: "The whole core and the front of the thighs.",
            wrong: "The back rounding or the hips rising; keep the knees low and the back flat.",
            stopIf: "Wrist pain."),
        "plank pull-through": MoveForm(
            setUp: "A high plank with the dumbbell on the floor just outside one hand, feet wide.",
            movement: "Reach under the chest with the far hand, drag the weight across to the other side, and repeat the other way.",
            feel: "The core holding the hips square as one hand leaves the floor.",
            wrong: "The hips twisting toward the ceiling; keep them level.",
            stopIf: "Wrist or low back pain."),
        "ring halo": MoveForm(
            setUp: "The 5 lb ring held in both hands in front of the face, feet hip width, ribs down.",
            movement: "Circle the ring slowly around the head, close to it, one way and then the other.",
            feel: "The shoulders, and the core keeping you from swaying.",
            wrong: "Bending the neck to get the ring round; the head stays still and the arms travel.",
            stopIf: "Shoulder pinch."),
        "ring bus driver": MoveForm(
            setUp: "The 5 lb ring held straight out at shoulder height in both hands.",
            movement: "Turn it like a steering wheel, left and right, slowly.",
            feel: "The shoulders and the core.",
            wrong: "Letting the arms drop as they tire; lower the weight before the arms do.",
            stopIf: "Shoulder pain."),
        "ring chop": MoveForm(
            setUp: "Half kneeling, the 5 lb ring in both hands at the outside hip of the down knee.",
            movement: "Sweep it slowly up and across to the far shoulder, then back down the same line.",
            feel: "The core turning the trunk against a still pelvis.",
            wrong: "The hips rotating with the ring; they face forward the whole time.",
            stopIf: "Low back pain."),
        "kettlebell around the body": MoveForm(
            setUp: "Standing tall, the bell in one hand at the front.",
            movement: "Pass it around the waist hand to hand in a slow circle, then reverse.",
            feel: "The core keeping the hips still while the bell travels.",
            wrong: "The hips swaying to meet the bell; only the arms move.",
            stopIf: "You cannot pass it without the back twisting — lighten the bell."),

        // MARK: Core — flex and extend

        "russian twist": MoveForm(
            setUp: "Seated, knees bent, heels on the floor, leaning back slightly with a tall spine, the dumbbell in both hands at the chest.",
            movement: "Turn from the ribs to one side, then the other, slowly; the weight follows the chest.",
            feel: "The sides of the trunk.",
            wrong: "Swinging the arms while the chest stays facing forward; the ribs turn and the arms go along.",
            stopIf: "Low back pain — sit taller and reduce the lean."),
        "standing side bend": MoveForm(
            setUp: "Standing tall, the dumbbell in one hand at the side, feet hip width.",
            movement: "Slide the weight down the outside of the thigh, bending only sideways, then stand tall.",
            feel: "The side of the trunk opposite the weight pulling you back up.",
            wrong: "Leaning forward or back; the movement is in one plane, straight to the side.",
            stopIf: "Low back pain."),
        "lying leg raise": MoveForm(
            setUp: "On your back, legs long, hands under the hips or by the sides, low back pressed into the floor.",
            movement: "Lift the legs to vertical and lower them only as far as the low back stays down.",
            feel: "The lower abdominals.",
            wrong: "Lowering past the point the back arches; bend the knees to shorten the lever.",
            stopIf: "Low back pain on the way down."),
        "bicycle crunch": MoveForm(
            setUp: "On your back, hands lightly behind the head, knees up.",
            movement: "Bring one elbow toward the opposite knee while the other leg reaches long, then switch, slowly.",
            feel: "The abdominals, especially the sides.",
            wrong: "Pulling on the neck; the hands only rest there, and the elbows stay wide.",
            stopIf: "Neck strain."),
        "glute bridge": MoveForm(
            setUp: "On your back, knees bent, heels close to the hips, arms by the sides.",
            movement: "Press through the heels to lift the hips until the body is a straight line from knees to shoulders, hold, and lower slowly.",
            feel: "The glutes, with a little hamstring.",
            wrong: "Arching the low back to go higher; stop where the glutes are doing it.",
            stopIf: "Hamstring cramp — walk the heels a little further away."),
        "one-leg bridge": MoveForm(
            setUp: "As the glute bridge, with one foot planted and the other leg held long or hugged in.",
            movement: "Press through the planted heel and lift the hips level, then lower.",
            feel: "The glute of the planted leg.",
            wrong: "The hips tipping toward the lifted leg; keep them level.",
            stopIf: "Hamstring cramp or low back pain."),
        "beam hip thrust": MoveForm(
            setUp: "On your back on the mat, knees bent, the beam across the hips held in both hands.",
            movement: "Drive through the heels to lift the hips, hold a beat at the top, and lower slowly.",
            feel: "The glutes.",
            wrong: "Arching the back at the top; tuck the ribs and let the glutes finish.",
            stopIf: "Low back pain."),
        "ring bridge": MoveForm(
            setUp: "On your back, knees bent, the 10 lb ring resting on the hip bones held in both hands.",
            movement: "Press through the heels, lift the hips, hold, and lower.",
            feel: "The glutes.",
            wrong: "The knees falling out or in; keep them over the feet.",
            stopIf: "Low back pain."),
        "superman": MoveForm(
            setUp: "On your belly, arms reaching long in front, legs long behind, forehead toward the floor.",
            movement: "Float the arms and legs an inch off the mat, hold, and lower.",
            feel: "The whole back of the body working gently.",
            wrong: "Lifting high and craning the neck; keep it small and the gaze down.",
            stopIf: "Low back pain rather than muscle work."),
        "reverse tabletop hold": MoveForm(
            setUp: "Seated, hands behind you with the fingers pointing toward the heels, feet flat.",
            movement: "Press the hips up until level with the knees and hold, chest open.",
            feel: "The glutes, the back of the shoulders and the back of the arms.",
            wrong: "The hips sagging; press them up and squeeze the glutes.",
            stopIf: "Wrist or shoulder pain."),

        // MARK: Accessory — arms and shoulders

        "bicep curl": MoveForm(
            setUp: "Standing tall, a dumbbell in each hand, elbows pinned to the sides.",
            movement: "Curl to the shoulders and lower over three counts; only the forearms move.",
            feel: "The front of the upper arms.",
            wrong: "Swinging the body or the elbows drifting forward; pin them.",
            stopIf: "Elbow pain."),
        "zottman curl": MoveForm(
            setUp: "Standing tall, dumbbells at the sides, palms forward.",
            movement: "Curl up palms up, turn the palms down at the top, and lower slowly over three counts.",
            feel: "The front of the arms up, the forearms down.",
            wrong: "Rushing the lowering; the way down is the point.",
            stopIf: "Wrist or elbow pain."),
        "beam curl": MoveForm(
            setUp: "Standing tall, both hands under the beam, elbows pinned to the sides.",
            movement: "Curl to the collarbones and lower over three counts.",
            feel: "The front of the upper arms.",
            wrong: "Leaning back to lift; stay tall.",
            stopIf: "Elbow or wrist pain."),
        "ring bicep curl": MoveForm(
            setUp: "The 5 lb ring in one hand, elbow pinned to the side.",
            movement: "Curl to the shoulder and lower over three counts.",
            feel: "The front of that upper arm.",
            wrong: "The elbow drifting forward; pin it.",
            stopIf: "Elbow pain."),
        "ring hammer curl": MoveForm(
            setUp: "One hand through the 5 lb ring, thumb up, elbow pinned.",
            movement: "Curl with the thumb up the whole way and lower slowly.",
            feel: "The front and outer upper arm and the forearm.",
            wrong: "Turning the palm; it stays thumb-up.",
            stopIf: "Elbow pain."),
        "ring wrist curl": MoveForm(
            setUp: "Seated, the forearm resting along the thigh with the hand past the knee, the 5 lb ring in that hand.",
            movement: "Curl only the wrist up, pause, and lower.",
            feel: "The forearm.",
            wrong: "Lifting the forearm off the thigh; only the wrist moves.",
            stopIf: "Wrist pain rather than forearm work."),
        "tricep kickback": MoveForm(
            setUp: "Hinge forward with a flat back, a dumbbell in each hand, upper arms parallel to the floor.",
            movement: "Straighten the elbows until the arms are long, squeeze, and bend again; the upper arm stays still.",
            feel: "The back of the upper arms.",
            wrong: "The upper arm swinging to help; it does not move.",
            stopIf: "Elbow pain."),
        "ring kickback": MoveForm(
            setUp: "Hinge forward with a flat back, the 5 lb ring in one hand, upper arm parallel to the floor.",
            movement: "Straighten the elbow, hold a beat, and bend.",
            feel: "The back of that upper arm.",
            wrong: "Dropping the upper arm; keep it level.",
            stopIf: "Elbow pain."),
        "tricep press-back": MoveForm(
            setUp: "Standing tall, dumbbells at the sides, palms facing behind you, arms straight.",
            movement: "Press the weights back and up, hold a beat, and return.",
            feel: "The back of the upper arms and the back of the shoulders.",
            wrong: "Leaning forward to swing them higher; stay tall and keep it small.",
            stopIf: "Shoulder pinch."),
        "overhead extension": MoveForm(
            setUp: "Standing tall, both hands on one dumbbell held behind the head, elbows pointing at the ceiling.",
            movement: "Straighten the elbows to press it overhead, then lower slowly behind the head.",
            feel: "The back of the upper arms.",
            wrong: "The elbows flaring wide; keep them pointing up and close to the head.",
            stopIf: "Elbow or shoulder pain."),
        "ring triceps extension": MoveForm(
            setUp: "The 8 lb ring in both hands behind the head, elbows pointing at the ceiling.",
            movement: "Straighten the elbows, pause, and lower.",
            feel: "The back of the upper arms.",
            wrong: "Elbows drifting out; keep them close.",
            stopIf: "Elbow or shoulder pain."),
        "beam triceps extension": MoveForm(
            setUp: "On your back, the beam pressed over the chest, hands shoulder width.",
            movement: "Bend only the elbows to lower it toward the forehead, then straighten.",
            feel: "The back of the upper arms.",
            wrong: "The upper arms moving; they stay vertical.",
            stopIf: "Elbow pain."),
        "lateral raise": MoveForm(
            setUp: "Standing tall, light dumbbells at the sides, elbows very slightly bent.",
            movement: "Raise the arms out to the sides to shoulder height, lead with the elbows, and lower over three counts.",
            feel: "The tops of the shoulders.",
            wrong: "Shrugging or swinging; if you need to swing, the weight is too heavy.",
            stopIf: "A pinch at the top of the shoulder — stop a little below shoulder height."),
        "front raise": MoveForm(
            setUp: "Standing tall, dumbbells in front of the thighs, arms straight.",
            movement: "Raise the arms straight out in front to eye height and lower slowly.",
            feel: "The front of the shoulders.",
            wrong: "Swinging the body; stop before the shoulders shrug.",
            stopIf: "Shoulder pinch."),
        "ring front raise": MoveForm(
            setUp: "The 5 lb ring held in both hands in front of the thighs.",
            movement: "Raise it straight out to eye height and lower slowly.",
            feel: "The front of the shoulders.",
            wrong: "Leaning back; stay tall.",
            stopIf: "Shoulder pinch."),
        "scaption raise": MoveForm(
            setUp: "Standing tall, dumbbells at the sides, thumbs up.",
            movement: "Raise the straight arms halfway between front and side to shoulder height, and lower.",
            feel: "The shoulders and the muscles around the blade.",
            wrong: "Going above shoulder height; stop there.",
            stopIf: "Shoulder pinch."),
        "around the world": MoveForm(
            setUp: "Standing tall, light dumbbells at the sides, palms forward.",
            movement: "Sweep the straight arms out and up until they meet overhead, then back down the same path.",
            feel: "The shoulders all the way around.",
            wrong: "Bending the elbows or arching the back; keep both long and the ribs down.",
            stopIf: "Shoulder pinch — it is fine to stop the sweep below the top."),
        "dumbbell shrug": MoveForm(
            setUp: "Standing tall, dumbbells at the sides.",
            movement: "Lift the shoulders straight up toward the ears, hold a beat, and let them down.",
            feel: "The top of the shoulders and neck.",
            wrong: "Rolling the shoulders in a circle; straight up and down only.",
            stopIf: "Neck pain."),
        "raise the platters": MoveForm(
            setUp: "Standing tall, dumbbells at the waist, palms up as if carrying two platters.",
            movement: "Extend the arms forward, lift to shoulder height, and bring them back the same way.",
            feel: "The front of the shoulders and the biceps.",
            wrong: "Letting the palms turn in; they stay up.",
            stopIf: "Shoulder pinch."),
        "ring behind-back raise": MoveForm(
            setUp: "Standing, both hands on the 5 lb ring behind the back, arms long.",
            movement: "Hinge slightly forward, lift the ring up and away from the body, and lower.",
            feel: "The back of the shoulders and the chest opening.",
            wrong: "Rounding the shoulders forward; keep the chest open.",
            stopIf: "Shoulder pinch."),
        "band external rotation": MoveForm(
            setUp: "Elbow pinned to the side at ninety degrees, the band held across the body.",
            movement: "Swing the forearm outward against the band, slowly, and slower back.",
            feel: "The back of the shoulder, deep.",
            wrong: "The elbow leaving the side; pin it.",
            stopIf: "Shoulder pain."),
        "chin tuck": MoveForm(
            setUp: "Sitting or standing tall, eyes level, shoulders relaxed.",
            movement: "Draw the chin straight back as if making a double chin, hold two counts, and release.",
            feel: "The front of the neck working and the back of the neck lengthening.",
            wrong: "Tipping the head down; the eyes stay level and the head glides back.",
            stopIf: "Dizziness or sharp neck pain."),

        // MARK: Accessory — legs

        "kettlebell calf raise": MoveForm(
            setUp: "Standing tall, the bell in one hand, the other hand on a wall for balance.",
            movement: "Rise onto the balls of the feet, pause at the top, and lower slowly.",
            feel: "The calves.",
            wrong: "Bouncing; pause at the top and lower over two counts.",
            stopIf: "Achilles pain."),
        "single-leg calf raise": MoveForm(
            setUp: "All your weight on one foot, fingertips on a wall.",
            movement: "Rise onto the ball of that foot, pause, and lower slowly.",
            feel: "That calf.",
            wrong: "Rolling onto the outside of the foot; rise through the big toe.",
            stopIf: "Achilles pain."),
        "side leg lift": MoveForm(
            setUp: "Lying on one side, bottom knee bent for balance, top leg long, hips stacked.",
            movement: "Lift the top leg to hip height, no higher, and lower slowly.",
            feel: "The outer hip of the top leg.",
            wrong: "Rolling the hip back so the leg comes forward; keep the hips stacked and the toes pointing forward.",
            stopIf: "Hip pinch."),
    ]
}
