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
    // One dumbbell, not a pair — held in both hands, bought for core work
    // (August 2026, Russian twists were the ask). Its own case so nothing
    // that says "two X lb dumbbells" about the pairs can ever say it about
    // this one.
    case singleDumbbell
    case kettlebell
    case band
    case walkingPad
    case bodyweight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .beam: "15 lb Bala Beam"
        case .rings: "Bala power rings · 5, 8, 10 lb"
        // Pairs, not singles — "two 3 lb dumbbells" is the unit she lifts.
        // The 2 lb Pelotons were the whole set until August 2026; the 3s and
        // 5s arrived when the 2s stopped being a challenge on the big levers.
        case .dumbbells: "Dumbbell pairs · 2, 3, 5 lb"
        // A single, and the label says so — next to the pairs above, a bare
        // "10 lb dumbbell" would read as one more pair.
        case .singleDumbbell: "Single dumbbells · 10, 15 lb"
        case .kettlebell: "Kettlebells · 9, 13, 18, 35 lb"
        // Bought for one job (August 2026), in her words: a routine "that
        // will get rid of my tech neck/slouch hump". The posture moves and
        // the seeded Posture reset routine are why it exists.
        case .band: "Resistance band"
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
        case .dumbbells: return "Two \(weight) lb dumbbells"
        // "One", where the pairs say "Two" — the same sentence shape making
        // the opposite promise about what to pick up.
        case .singleDumbbell: return "One \(weight) lb dumbbell"
        case .kettlebell: return "\(weight) lb kettlebell"
        case .band, .walkingPad, .bodyweight: return label
        }
    }

    /// Short form for tight rows.
    var shortLabel: String {
        switch self {
        case .beam: "Beam"
        case .rings: "Rings"
        case .dumbbells: "Dumbbells"
        case .singleDumbbell: "Single dumbbell"
        case .kettlebell: "Kettlebell"
        case .band: "Band"
        case .walkingPad: "Pad"
        case .bodyweight: "Bodyweight"
        }
    }

    var symbol: String {
        switch self {
        case .beam: "dumbbell"
        case .rings: "circle.circle"
        case .dumbbells: "dumbbell.fill"
        case .singleDumbbell: "dumbbell"
        case .kettlebell: "figure.strengthtraining.traditional"
        case .band: "figure.flexibility"
        case .walkingPad: "figure.walk.motion"
        case .bodyweight: "figure.strengthtraining.functional"
        }
    }

    /// What the planner is allowed to say this can load.
    var loadDescription: String {
        switch self {
        case .beam: "15 lb"
        case .rings: "5, 8 or 10 lb"
        case .dumbbells: "2, 3 or 5 lb pairs"
        case .singleDumbbell: "10 or 15 lb, one dumbbell held in both hands"
        case .kettlebell: "9, 13, 18 or 35 lb"
        case .band: "band tension, no set load"
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
    /// Kit that cannot be switched off. Her own body is not optional, and the
    /// pad carries no moves — only the weekly walking target, which lives on
    /// Signals and is not the planner's to withhold.
    static let alwaysOwned: Set<Equipment> = [.bodyweight, .walkingPad]

    /// Whether she actually has this to hand. The one predicate for it, so a
    /// rotation, a picker, the planner's schema and the reviewer cannot come
    /// to different conclusions about the same drawer.
    var isOwned: Bool { Tuning.ownedEquipment.contains(self) }

    /// The kit she has, in the enum's own order.
    static var owned: [Equipment] { allCases.filter(\.isOwned) }

    /// Everything that can honestly be switched off — what Settings lists.
    /// Bodyweight and the pad are excluded because they are not hers to lose.
    static var switchable: [Equipment] { allCases.filter { !alwaysOwned.contains($0) } }

    /// The loads this move may actually be set to: the equipment's ladder,
    /// less the one rule the brief makes about a specific bell. The 35 lb
    /// kettlebell is for the hinge until her counts say otherwise — and the
    /// app refuses it elsewhere whatever a prompt or a proposal says, so the
    /// rule is enforced here, where every load change passes, rather than
    /// trusted to prose. `docs/COACH-BRIEF.md` §10, §15.
    static func loads(for move: Move) -> [Double] {
        let ladder = move.equipment.availableLoadsPounds
        guard move.equipment == .kettlebell else { return ladder }
        let pattern = MoveTaxonomy.pattern(for: move.name)
        return pattern == .hinge ? ladder : ladder.filter { $0 < heavyBellPounds }
    }

    /// The bell the brief reserves for the hinge.
    static let heavyBellPounds: Double = 35

    var availableLoadsPounds: [Double] {
        switch self {
        case .beam: [15]
        case .rings: [5, 8, 10]
        case .dumbbells: [2, 3, 5]
        case .singleDumbbell: [10, 15]
        case .kettlebell: [9, 13, 18, 35]
        case .band: []
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
        // Cue rewritten on the August 2026 coach audit: placement is the
        // entire safety of a good morning, and the old cue never said it.
        Move(name: "Beam good morning", equipment: .beam,
             cue: "The beam rests across the back of the shoulders, never the neck. Soft knees, flat back, stop when your hamstrings say so.",
             loadPounds: 15),
        // Rewritten on the same audit: "shoulders on the sofa edge" was
        // furniture-as-equipment, and an edge that slides mid-set is exactly
        // the training-alone injury the library screens for.
        Move(name: "Beam hip thrust", equipment: .beam,
             cue: "On your back on the mat, beam across the hips. Press through the heels and hold a beat at the top.",
             loadPounds: 15),
        Move(name: "Beam overhead press", equipment: .beam,
             cue: "From the collarbones to straight overhead. Ribs stay down as the arms go up.",
             loadPounds: 15),
        Move(name: "Beam row", equipment: .beam,
             cue: "Hinge and hold it there. Pull the beam to your belly, elbows back not out.",
             loadPounds: 15),
        Move(name: "Beam reverse lunge", equipment: .beam,
             cue: "Beam across the chest. Step back, and the front knee stays over the ankle.",
             loadPounds: 15, sided: .sides),
        Move(name: "Beam floor press", equipment: .beam,
             cue: "On your back, beam at the chest, press straight up. The floor stops your elbows.",
             loadPounds: 15),
        // Core on the kit (August 2026, her ask): one loaded core pattern per
        // implement, so core work is not confined to the mat. Holds and slow
        // carries rather than loaded flexion — the honest way to load a core
        // that is still learning to brace. Drawings deferred like every
        // recent add. The band has none of these on purpose: band core work
        // is a Pallof press, and a Pallof press needs an anchor the kit does
        // not have.
        Move(name: "Beam overhead hold", equipment: .beam,
             cue: "The beam pressed overhead, arms by the ears. Ribs down over the hips, and hold.",
             loadPounds: 15),
        // The audit set (August 2026): a coach's pass over the whole catalog
        // found the gaps — pull volume trailing the presses, no lateral or
        // single-leg lower-body work, no calves, no grip, triceps stuck on
        // the 2 lb pairs — and these additions, across every implement, are
        // the answer. Every one is a recognised movement a trainer would
        // actually program; drawings deferred like every recent add.
        Move(name: "Beam curl", equipment: .beam,
             cue: "Both hands under the beam, elbows pinned to your sides. Curl to the collarbones, three counts down.",
             loadPounds: 15),
        Move(name: "Beam triceps extension", equipment: .beam,
             cue: "On your back, the beam pressed over the chest. Bend only the elbows, lower it toward your forehead, press back up.",
             loadPounds: 15),
        Move(name: "Beam lateral lunge", equipment: .beam,
             cue: "Beam across the collarbones. Step wide to one side, sit into that hip, and push back to standing.",
             loadPounds: 15, sided: .sides),
        Move(name: "Beam curtsy lunge", equipment: .beam,
             cue: "Beam across the collarbones. Step back and across, sink straight down; the front knee stays steady.",
             loadPounds: 15, sided: .sides),
        // Sided: the circles go one way, then the other, and each direction
        // gets its own full work interval.
        Move(name: "Ring halo", equipment: .rings,
             cue: "The 5 lb ring in both hands, slow circles around the head.",
             loadPounds: 5, sided: .directions),
        Move(name: "Ring press-out", equipment: .rings,
             cue: "Hold the 8 lb ring at the chest and press straight out.",
             loadPounds: 8),
        Move(name: "Ring deadlift", equipment: .rings,
             cue: "The 10 lb ring between the feet. Hinge, don't squat.",
             loadPounds: 10),
        Move(name: "Ring goblet squat", equipment: .rings,
             cue: "The 10 lb ring held at the chest. Sit down between the hips, chest tall.",
             loadPounds: 10),
        Move(name: "Ring row", equipment: .rings,
             cue: "Hinge, hold the 8 lb ring, pull it to your hip. The elbow goes back.",
             loadPounds: 8),
        Move(name: "Ring overhead press", equipment: .rings,
             cue: "The 5 lb ring from the chest to straight overhead, slowly.",
             loadPounds: 5),
        Move(name: "Ring front raise", equipment: .rings,
             cue: "The 5 lb ring in both hands, straight out to eye height.",
             loadPounds: 5),
        // Her additions to the defaults (August 2026), asked for by name. All
        // one arm at a time except the behind-back raise, which takes both
        // hands. Diagrams deliberately deferred — `MovePlates.deferred` keeps
        // the containment matcher from handing these the dumbbell drawings.
        Move(name: "Ring bicep curl", equipment: .rings,
             cue: "The 5 lb ring in one hand, elbow pinned to your side. Three counts down.",
             loadPounds: 5, sided: .sides),
        Move(name: "Ring hammer curl", equipment: .rings,
             cue: "One hand through the 5 lb ring, thumb up the whole way. The elbow stays pinned.",
             loadPounds: 5, sided: .sides),
        Move(name: "Ring Arnold press", equipment: .rings,
             cue: "The 5 lb ring at the chin, palm in. Rotate out as you press overhead.",
             loadPounds: 5, sided: .sides),
        Move(name: "Ring behind-back raise", equipment: .rings,
             cue: "Both hands on the 5 lb ring behind your back. Hinge, then lift it up and away.",
             loadPounds: 5),
        // Core on the kit — see the beam overhead hold.
        Move(name: "Ring half-kneeling overhead hold", equipment: .rings,
             cue: "Half kneeling, the 5 lb ring held straight overhead in one hand. Shoulders square, ribs stacked.",
             loadPounds: 5, sided: .sides),
        // The audit set — see the beam curl.
        Move(name: "Ring triceps extension", equipment: .rings,
             cue: "The 8 lb ring in both hands behind the head, elbows pointing at the ceiling. Only the forearms move.",
             loadPounds: 8),
        Move(name: "Ring bus driver", equipment: .rings,
             cue: "The 5 lb ring held straight out at shoulder height. Turn it like a steering wheel, left and right, slowly.",
             loadPounds: 5),
        Move(name: "Ring wrist curl", equipment: .rings,
             cue: "Seated, forearm resting along the thigh, the 5 lb ring in that hand. Curl just the wrist, slow both ways.",
             loadPounds: 5, sided: .sides),
        Move(name: "Ring bridge", equipment: .rings,
             cue: "On your back, the 10 lb ring resting on the hip bones. Press up through the heels and hold a beat at the top.",
             loadPounds: 10),
        Move(name: "Ring chop", equipment: .rings,
             cue: "Half kneeling, the 5 lb ring at the outside hip. Sweep it slowly up across to the far shoulder, and back down the same line.",
             loadPounds: 5, sided: .sides),
        Move(name: "Ring kickback", equipment: .rings,
             cue: "Hinge, the 5 lb ring in one hand, upper arm parallel to the floor. Straighten the elbow and hold a beat.",
             loadPounds: 5, sided: .sides),
        // The 18 lb kettlebell (August 2026) is the heaviest thing in the kit,
        // so it takes the patterns that want weight: hinges, squats, carries.
        // Deliberately no swing — a ballistic hinge is exactly the "needs a
        // coach's eye" line the move review draws, and the library holds
        // itself to the same rule. Diagrams deferred, like the late ring
        // moves; `MovePlates.deferred` keeps the containment matcher from
        // handing these the beam and ring strips.
        Move(name: "Kettlebell deadlift", equipment: .kettlebell,
             cue: "The bell between the feet. Hinge, flat back, stand all the way up.",
             loadPounds: 18),
        Move(name: "Kettlebell goblet squat", equipment: .kettlebell,
             cue: "Held by the horns at the chest. Sit between the hips, elbows inside the knees.",
             loadPounds: 18),
        Move(name: "Kettlebell carry", equipment: .kettlebell,
             cue: "One hand, ribs stacked over hips, shoulders level. Walk slowly and do not lean.",
             loadPounds: 18, sided: .sides),
        // Core on the kit — see the beam overhead hold.
        Move(name: "Kettlebell around the body", equipment: .kettlebell,
             cue: "Pass the bell around your waist, hand to hand. The hips stay still; only the arms travel.",
             loadPounds: 18, sided: .directions),
        // The audit set — see the beam curl. The audit's sharpest line: the
        // heaviest implement was not pointed at the biggest gap, the pull
        // side. The row fixes that.
        Move(name: "Kettlebell row", equipment: .kettlebell,
             cue: "Hinge, free hand braced on your thigh. Pull the bell to your hip; the elbow goes back, not out.",
             loadPounds: 18, sided: .sides),
        Move(name: "Kettlebell sumo squat", equipment: .kettlebell,
             cue: "Feet wide, toes out, the bell hanging in both hands. Sit straight down between the heels, chest tall.",
             loadPounds: 18),
        Move(name: "Kettlebell rack hold", equipment: .kettlebell,
             cue: "The bell resting on the forearm, fist at the collarbone, elbow tucked. Stand tall and breathe; ribs stay down.",
             loadPounds: 18, sided: .sides),
        Move(name: "Kickstand deadlift", equipment: .kettlebell,
             cue: "The bell inside the front foot, back toes down just for balance. Hinge over the front leg, flat back.",
             loadPounds: 18, sided: .sides),
        Move(name: "Kettlebell suitcase hold", equipment: .kettlebell,
             cue: "The bell in one hand at your side. Stand level — no lean — and let the grip do the work.",
             loadPounds: 18, sided: .sides),
        Move(name: "Kettlebell calf raise", equipment: .kettlebell,
             cue: "The bell in one hand, the other hand on the wall. Rise to the balls of the feet, pause, lower slowly.",
             loadPounds: 18),
        // Two pounds is a real load on a long lever held slowly, which is why
        // these are all shoulder and arm work. The weight never changes here —
        // tempo, range and rest do — so the library carries enough variety to
        // make a whole session out of them. Since August 2026 the pairs go up
        // to 5 lb, and the load bar in the library is how a move steps up.
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
        Move(name: "Dumbbell shrug", equipment: .dumbbells,
             cue: "Shoulders straight up toward the ears, hold a beat, then let them go.",
             loadPounds: 2),
        // Cue tightened on the audit: a narrow, high pull is the classic
        // novice-shoulder impingement recipe, and the old cue permitted it.
        Move(name: "Upright row", equipment: .dumbbells,
             cue: "Hands apart, elbows lead wide, no higher than the chest. Stop before the shoulders shrug.",
             loadPounds: 2),
        Move(name: "Overhead extension", equipment: .dumbbells,
             cue: "Both hands on one weight behind the head. Only the forearms move.",
             loadPounds: 2),
        // Audit: the shape wants one weight in both hands, and the old cue
        // never said how many to hold.
        Move(name: "Pullover", equipment: .dumbbells,
             cue: "On your back, one weight held in both hands, arms straight. Take it back past your head only as far as the ribs stay down.",
             loadPounds: 2),
        Move(name: "Boxer punches", equipment: .dumbbells,
             cue: "Alternating, chest height, controlled. The shoulders do the work.",
             loadPounds: 2),
        // Arm work she asked for by name (August 2026) — "raise the
        // platters", the barre serve-a-platter move, kept under her own name
        // for it, and a straight-arm press-back for the triceps. Framed as
        // arm strength, like everything here: no move decides where anything
        // comes off.
        Move(name: "Raise the platters", equipment: .dumbbells,
             cue: "Palms up at the waist, as if carrying two platters. Extend the arms forward, lift to shoulder height, and lower over three counts.",
             loadPounds: 2),
        Move(name: "Tricep press-back", equipment: .dumbbells,
             cue: "Arms straight at your sides, palms facing behind you. Press the weights back and up, and hold a beat at the top.",
             loadPounds: 2),
        // The audit set — see the beam curl. The 5s go where the audit
        // pointed them: at the chest and back work the 2s cannot load.
        Move(name: "Dumbbell floor press", equipment: .dumbbells,
             cue: "On your back, a 5 lb dumbbell in each hand. Press straight up; the floor catches your elbows between reps.",
             loadPounds: 5),
        Move(name: "Dumbbell row", equipment: .dumbbells,
             cue: "Hinge and hold it there. Pull both 5 lb dumbbells to your hips, blades together at the top.",
             loadPounds: 5),
        Move(name: "Zottman curl", equipment: .dumbbells,
             cue: "Curl palms up, turn palms down at the top, lower over three counts. The way down is the point.",
             loadPounds: 3),
        Move(name: "Scaption raise", equipment: .dumbbells,
             cue: "Straight arms, thumbs up, lifted halfway between front and side. To shoulder height and no higher.",
             loadPounds: 2),
        Move(name: "Squeeze press", equipment: .dumbbells,
             cue: "Press the two weights together hard at the chest, then press them to the ceiling without letting them part.",
             loadPounds: 3),
        // Core on the kit — see the beam overhead hold.
        Move(name: "Dumbbell dead bug press", equipment: .dumbbells,
             cue: "A dead bug with the dumbbells pressed to the ceiling. Low back flat, arms straight the whole time.",
             loadPounds: 2),
        // The single 10 lb dumbbell (August 2026), bought for core work by
        // name — Russian twists were the ask. One dumbbell in both hands,
        // never a pair; `Equipment.singleDumbbell` exists so nothing can
        // read it as one. Drawings deferred like every recent add.
        // Cue tightened on the audit: loaded rotation in a rounded seated
        // spine is the core move most often done badly alone, and "chest
        // lifted" is the one line that prevents it.
        Move(name: "Russian twist", equipment: .singleDumbbell,
             cue: "Seated tall, knees bent, the dumbbell in both hands. Turn from the ribs, side to side, slowly — the chest stays lifted the whole time.",
             loadPounds: 10),
        Move(name: "Standing side bend", equipment: .singleDumbbell,
             cue: "The dumbbell in one hand, slide it down the outside of the thigh and stand tall again.",
             loadPounds: 10, sided: .sides),
        // Core on the kit — see the beam overhead hold.
        Move(name: "Dumbbell march", equipment: .singleDumbbell,
             cue: "The dumbbell in both hands at your chest. March slowly; the ribs stay stacked over the hips.",
             loadPounds: 10),
        // The audit set — see the beam curl.
        Move(name: "Suitcase deadlift", equipment: .singleDumbbell,
             cue: "The dumbbell beside one foot. Hinge, take a firm grip, and stand tall — no lean toward the load.",
             loadPounds: 10, sided: .sides),
        Move(name: "Tall-kneeling press", equipment: .singleDumbbell,
             cue: "Kneeling tall, the dumbbell in both hands at the chest. Press it overhead; ribs down, hips under you.",
             loadPounds: 10),
        Move(name: "Plank pull-through", equipment: .singleDumbbell,
             cue: "From a high plank, drag the dumbbell under your chest to the other side, hand by hand. The hips stay quiet.",
             loadPounds: 10),
        // The posture set (August 2026). The band was bought for one job — her
        // words: a routine "that will get rid of my tech neck/slouch hump" —
        // and these six are the standard prescription for it: wake the deep
        // neck flexors, strengthen the upper back and rotator cuff, open the
        // chest. Strength, not flow, deliberately: they are sets and holds,
        // and keeping them out of `.flow` keeps them out of the morning
        // practice's qi gong pool. Drawings deferred like every recent add.
        Move(name: "Band pull-apart", equipment: .band,
             cue: "Arms straight at shoulder height, pull the band to your chest. Blades together, then let it close slowly."),
        Move(name: "Band face pull", equipment: .band,
             cue: "Pull the band toward your eyes, elbows high and wide, thumbs turning back. The shoulder blades finish it."),
        Move(name: "Band W raise", equipment: .band,
             cue: "Elbows bent to a W, band between the hands. Draw the elbows down and back until the blades meet."),
        Move(name: "Band external rotation", equipment: .band,
             cue: "Elbow pinned at your side, forearm swings out against the band. Slow out, slower back.",
             sided: .sides),
        // The audit set — see the beam curl. Only the moves a long band with
        // no anchor can honestly do: the audit also proposed lateral walks
        // and clamshells, which want a mini loop around the thighs, and they
        // were left out rather than adapted into something the kit is not.
        Move(name: "Band seated row", equipment: .band,
             cue: "Seated, legs long, the band looped around both feet. Pull to the ribs, blades together, let it return slowly."),
        Move(name: "Band overhead press", equipment: .band,
             cue: "Stand on the middle of the band, an end in each hand at the shoulders. Press up against it, slower on the way down."),
        Move(name: "Chin tuck", equipment: .bodyweight,
             cue: "Draw the chin straight back — yes, a double chin. Hold two counts, release. Eyes level the whole time."),
        Move(name: "Wall angel", equipment: .bodyweight,
             cue: "Back, head and arms against the wall. Slide the arms up and down; ribs down, nothing leaves the wall."),
        // Bodyweight is equipment. It needs no load and it is always to hand,
        // which makes it the one part of the kit that never runs out of
        // progressions — and the library had exactly one of them, so a
        // hand-built session could barely use it.
        Move(name: "Dead bug", equipment: .bodyweight,
             cue: "Ribs down, low back flat on the floor."),
        Move(name: "Incline push-up", equipment: .bodyweight,
             cue: "Hands on the counter. The higher the hands, the easier it is."),
        Move(name: "Reverse lunge", equipment: .bodyweight,
             cue: "Step back, not forward. The front knee stays over the ankle.",
             sided: .sides),
        Move(name: "Glute bridge", equipment: .bodyweight,
             cue: "Heels close, press through them, hold a beat at the top."),
        Move(name: "Split squat", equipment: .bodyweight,
             cue: "Back knee straight down. Most of the weight on the front foot.",
             sided: .sides),
        Move(name: "Bird dog", equipment: .bodyweight,
             cue: "Opposite arm and leg, slowly. The hips do not tip."),
        Move(name: "Wall sit", equipment: .bodyweight,
             cue: "Thighs parallel if you can, higher if you cannot. Breathe."),
        // The core set (August 2026). She asked for more core work, so these
        // five join the dead bug and bird dog already here: holds and slow
        // patterns a careful beginner can do alone on a mat. Framed as core
        // strength, which is what they are — nothing in this app claims a
        // move burns fat from anywhere in particular, because none does.
        // Drawings deferred like every recent add.
        Move(name: "Forearm plank", equipment: .bodyweight,
             cue: "Elbows under the shoulders, one straight line from head to heels. Breathe, don't sag."),
        Move(name: "Side plank", equipment: .bodyweight,
             cue: "On one forearm, feet stacked or staggered. Lift the hips and hold them still.",
             sided: .sides),
        Move(name: "Lying leg raise", equipment: .bodyweight,
             cue: "Low back pressed into the floor. Lower the legs only as far as it stays there."),
        Move(name: "Bicycle crunch", equipment: .bodyweight,
             cue: "Slow. Opposite elbow toward opposite knee, and the straight leg reaches long."),
        Move(name: "Plank shoulder tap", equipment: .bodyweight,
             cue: "From a high plank, tap the opposite shoulder. The hips stay square to the floor."),
        // The audit set — see the beam curl. The bodyweight half of the
        // answer to "every leg move is sagittal": abduction, single-leg
        // work, calves, and the posterior chain from the floor.
        Move(name: "Superman", equipment: .bodyweight,
             cue: "On your belly, arms reaching long. Float the arms and legs an inch off the mat and hold; keep looking down."),
        Move(name: "One-leg bridge", equipment: .bodyweight,
             cue: "One foot planted, the other leg held long or hugged in. Press through the heel; the hips stay level.",
             sided: .sides),
        Move(name: "Single-leg calf raise", equipment: .bodyweight,
             cue: "All your weight on one foot, fingertips on the wall. Rise to the ball of the foot, pause, lower with control.",
             sided: .sides),
        Move(name: "Side leg lift", equipment: .bodyweight,
             cue: "Side lying, bottom knee bent, top leg long. Lift to hip height, no higher, and lower slowly.",
             sided: .sides),
        Move(name: "Bear hold", equipment: .bodyweight,
             cue: "On all fours, toes tucked, knees hovering an inch off the mat. Flat back, and breathe."),
        Move(name: "Air squat", equipment: .bodyweight,
             cue: "Feet under the hips, sit down and back, chest tall. Stand all the way up every time."),
        Move(name: "Reverse tabletop hold", equipment: .bodyweight,
             cue: "Seated, hands behind you, fingers toward your heels. Press the hips up level with the knees and hold, chest broad."),

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
        Move(name: "Chest opener", equipment: .bodyweight, kind: .flow,
             cue: "Arms wide and back, chest lifting. Let the breath in do the opening."),
        Move(name: "Standing march", equipment: .bodyweight, kind: .flow,
             cue: "Knee to hip height, slowly. The foot goes down before the next one lifts."),
        Move(name: "Arm circles", equipment: .bodyweight, kind: .flow,
             cue: "Big and slow, both directions. The shoulder does the work, not the elbow."),
        Move(name: "Deep squat hold", equipment: .bodyweight, kind: .flow,
             cue: "Sit as low as is comfortable, heels down if they reach. Breathe there."),
        Move(name: "Ankle rocking", equipment: .bodyweight, kind: .flow,
             cue: "Rock forward onto the toes, then back onto the heels. Small and slow."),
        // From the reel's warm-up. Two of them — the corkscrew and the Allen
        // wrench — are drawn from her own description rather than guessed;
        // `MovePlates.strip(for:)` is a lookup and a plate of the wrong
        // movement is worse than none.
        //
        // "Cross body swings" and "trunk twists" are deliberately absent: they
        // are `Arm swings` and `Standing twist` under different names, and a
        // closed library with two names for one movement is how a rotation
        // starts repeating itself. Her call when asked.
        Move(name: "Corkscrew", equipment: .bodyweight, kind: .flow,
             cue: "Arms out to the sides at shoulder height. Twist them in place, palms turning over and back."),
        Move(name: "Allen wrench", equipment: .bodyweight, kind: .flow,
             cue: "Both elbows bent square — one arm up, one down. Rotate back and forth, swapping which is which."),
        Move(name: "Vertical arm swings", equipment: .bodyweight, kind: .flow,
             cue: "One arm swings up overhead as the other swings down past the hip. They alternate, long and loose."),
        Move(name: "Bent-over trunk twists", equipment: .bodyweight, kind: .flow,
             cue: "Hinge forward with a flat back, arms wide, and rotate one shoulder toward the floor and back."),
        Move(name: "Slam dunks", equipment: .bodyweight, kind: .flow,
             cue: "Both arms overhead, then drive them down past the hips together and with intent. The knees give a little."),
        Move(name: "Golf swings", equipment: .bodyweight, kind: .flow,
             cue: "Hands together, swing low across the body and up over the far shoulder. Both directions."),
        Move(name: "High knee circles", equipment: .bodyweight, kind: .flow,
             cue: "One knee up to hip height, then circle it out and away. Slow, and both legs."),
        // The audit's flow additions (August 2026): floor-based release work
        // the pool had none of — everything above is done standing.
        Move(name: "Thread the needle", equipment: .bodyweight, kind: .flow,
             cue: "On all fours, slide one arm beneath the other and let that shoulder rest toward the floor. Unwind slowly, then the other side."),
        Move(name: "Child's pose reach", equipment: .bodyweight, kind: .flow,
             cue: "Kneel back toward the heels, arms long on the mat. Walk the hands to one side, breathe there, then the other."),
        Move(name: "Knee sways", equipment: .bodyweight, kind: .flow,
             cue: "On your back, knees bent, feet a little wide. Let both knees fall to one side, then the other, at the pace of the breath."),
        Move(name: "Sun breath", equipment: .bodyweight, kind: .flow,
             cue: "Sweep the arms wide and overhead on the breath in, float them down on the breath out. Nothing to hurry."),
        Move(name: "Pelvic rocks", equipment: .bodyweight, kind: .flow,
             cue: "On your back, knees bent. Tip the pelvis toward you and away, small and slow; the low back presses and releases.")
    ]

    /// Every move by name, for the places that need the whole closed set:
    /// the planner's schema, the validator, and the plate lookup.
    /// The names the planner may put in a **rotation**, which is strength only.
    ///
    /// This was every move in the library, flow included, and the only place a
    /// generated move can land is the rotation — where `RoutineSchedule` makes
    /// it a work phase and counts it down with work cues and haptics. So a
    /// spinal wave could be programmed as a forty-second set, which is the one
    /// thing `MoveKind` exists to prevent. The flow movements reach a session
    /// through `WarmUp` and the morning practice, neither of which asks the
    /// model for anything.
    /// The strength names the planner may choose from — **her kit only**.
    ///
    /// Computed rather than stored, because it now depends on what she owns
    /// and she can change that from Settings while the app is running. It was
    /// a `let`, and a stored copy would have gone on offering the band the
    /// evening she switched it off.
    static var names: [String] { available.filter { $0.kind == .strength }.map(\.name) }

    /// Every move whose kit she actually has.
    ///
    /// The distinction this draws is the important one: `available` is what
    /// may be **offered or generated**, and `all` stays what things are
    /// **read back** against — drawings, the sidedness repair, a name in a
    /// stored routine. A week written when she had the band must still draw
    /// and still run; it simply will not be written again.
    static var available: [Move] { all.filter { $0.equipment.isOwned } }

    static func moves(for equipment: Equipment) -> [Move] {
        all.filter { $0.equipment == equipment && $0.kind == .strength }
    }

    /// The morning practice: qi gong and lymphatic movement, kept apart from
    /// the strength library so a flow never turns up inside a work interval.
    static var flow: [Move] { all.filter { $0.kind == .flow } }

    /// `count` strength moves from the library, honouring both refusals and
    /// what is already in hand.
    ///
    /// One builder, because there were two. `PlanRepair.resize` grew a rotation
    /// this way and `ExtraSession` needed the same thing — and the last time a
    /// question was spelled out separately in several places, the four spellings
    /// disagreed and the app offered her the incline push-up she was on record
    /// as disliking. So the two sets are named for what they are and matched
    /// differently on purpose:
    ///
    /// - `ruledOut` is matched by **containment** (`MovePreference.anyCovers`),
    ///   so "push-up" bars the incline and knee variants.
    /// - `used` is matched **exactly**, because a rotation holding "Beam row"
    ///   has not thereby used "Beam row to hip".
    ///
    /// `preferring` keeps a beam day from filling up with dumbbells; it is a
    /// sort, not a filter, so a short library still fills the rotation.
    /// `plus` is her own approved additions — the working library where the
    /// caller has a store to read them from.
    /// `holding` is what the session already has, when a rotation is being
    /// grown rather than written: the slots those moves cover are taken as
    /// covered, so a session with a hinge is not handed a second one. Only
    /// the new moves are returned.
    /// `varying` is which turn this is — a session's place in the week, a day
    /// index, whatever the caller has that ought to make one rotation differ
    /// from the next. Without it this took the **first** `count` moves of the
    /// library and did nothing else, so every offline session in every week
    /// was topped up with the same two movements, in the order they happen to
    /// be typed into this file. See `Rotation`, which is the same fix the
    /// morning practice needed.
    static func rotation(of count: Int,
                         preferring kit: Set<Equipment> = [],
                         avoiding ruledOut: Set<String> = [],
                         excluding used: Set<String> = [],
                         plus extras: [Move] = [],
                         holding inHand: [Move] = [],
                         varying turn: Int = 0) -> [Move] {
        // `available`, not `all`: this is the one builder for "pick N moves",
        // so filtering here is what keeps a rotation, an extra session and a
        // repaired week from ever reaching for kit she does not have.
        //
        // Filtered up front rather than while walking, because the walk needs
        // to know how big the pool actually is: a step is chosen to be coprime
        // with it, and skipping entries mid-walk would break the one property
        // that stops a rotation naming the same move twice.
        var taken = used
        var offered: [Move] = []
        for move in (available + extras) where move.kind == .strength {
            let key = MovePreference.key(move.name)
            guard !taken.contains(key), !MovePreference.anyCovers(ruledOut, move.name)
            else { continue }
            taken.insert(key)
            offered.append(move)
        }

        return Shape.fill(count, from: offered, preferring: kit,
                          holding: inHand, varying: turn)
    }

    /// Puts a rotation in the order a session runs: standing first, the floor
    /// block last, and inside each block the coach's order — hinge, squat or
    /// lunge, row, press or push, then carries and core, then accessory work.
    /// Stable for anything the table does not know (custom moves), which stay
    /// where they were relative to each other.
    ///
    /// Applied to every rotation the app writes and to every one the model
    /// writes (`PlanValidator`), so a week never opens on the mat, stands up
    /// for the beam, and lies back down. See `docs/COACH-BRIEF.md` §8–9.
    static func ordered(_ moves: [Move]) -> [Move] {
        moves.enumerated().sorted { a, b in
            let pa = MoveTaxonomy.position(for: a.element.name) ?? .standing
            let pb = MoveTaxonomy.position(for: b.element.name) ?? .standing
            if pa != pb { return pa < pb }
            let sa = Shape.order(of: a.element), sb = Shape.order(of: b.element)
            if sa != sb { return sa < sb }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Shrinks a rotation to `count` without losing a pattern it could keep:
    /// one move per pattern first, in running order, then whatever is left
    /// in running order. Trimming the ordered list from the end would keep
    /// two hinges and drop the squat.
    static func trimmed(_ moves: [Move], to count: Int) -> [Move] {
        let running = ordered(moves)
        var seen: Set<MovePattern> = []
        var kept: [Move] = []
        for move in running where kept.count < count {
            guard let pattern = MoveTaxonomy.pattern(for: move.name) else { kept.append(move); continue }
            if seen.insert(pattern).inserted { kept.append(move) }
        }
        for move in running where kept.count < count && !kept.contains(where: { $0.name == move.name }) {
            kept.append(move)
        }
        return ordered(kept)
    }

    /// The distinct implements a rotation asks her to fetch. Bodyweight is
    /// not one — it is what she is already holding.
    static func implements(in moves: [Move]) -> Set<Equipment> {
        Set(moves.map(\.equipment)).subtracting([.bodyweight])
    }

    /// The coach's session shape, from `docs/COACH-BRIEF.md` §9: one bell,
    /// standing — hinge, squat or lunge, row, press or push — then the floor
    /// to close. Built slot by slot so coverage is by construction, with the
    /// walk varying *which* hinge and *which* row rather than whether there
    /// is one.
    enum Shape {
        /// What a slot will take, in order of preference. The first predicate
        /// is the slot's own pattern; the later ones are what it settles for
        /// when the pool has nothing in the first.
        struct Slot {
            var wants: [(Move) -> Bool]
        }

        private static func family(_ f: MovePattern.Family) -> (Move) -> Bool {
            { MoveTaxonomy.pattern(for: $0.name)?.family == f }
        }
        private static func pattern(_ p: MovePattern) -> (Move) -> Bool {
            { MoveTaxonomy.pattern(for: $0.name) == p }
        }
        private static func patterns(_ ps: Set<MovePattern>) -> (Move) -> Bool {
            { MoveTaxonomy.pattern(for: $0.name).map(ps.contains) ?? false }
        }
        private static func floorCore(_ move: Move) -> Bool {
            MoveTaxonomy.pattern(for: move.name)?.family == .core
                && (MoveTaxonomy.position(for: move.name) ?? .standing) != .standing
        }
        private static func anything(_: Move) -> Bool { true }

        /// The slots for a rotation of `count`. Five is the shape as written;
        /// fewer drops from the end, more adds a carry or core and then
        /// accessory work. `turn` alternates the squat and the lunge, which
        /// the brief asks for on alternating sessions.
        static func slots(_ count: Int, turn: Int) -> [Slot] {
            let hinge = Slot(wants: [pattern(.hinge), family(.lower), anything])
            let kneeOrLunge = turn.isMultiple(of: 2)
                ? Slot(wants: [pattern(.squat), pattern(.lunge), family(.lower), anything])
                : Slot(wants: [pattern(.lunge), pattern(.squat), family(.lower), anything])
            let pull = Slot(wants: [pattern(.pullHorizontal), family(.pull), anything])
            let push = Slot(wants: [family(.push), anything])
            let core = Slot(wants: [floorCore, family(.core), anything])
            let carry = Slot(wants: [pattern(.carry), patterns([.coreAntiRotation]), anything])
            let accessory = Slot(wants: [pattern(.accessory), anything])
            let base = [hinge, kneeOrLunge, pull, push, core, carry, accessory]
            if count <= base.count { return Array(base.prefix(count)) }
            return base + Array(repeating: Slot(wants: [anything]), count: count - base.count)
        }

        /// Where a move sits inside its position block.
        static func order(of move: Move) -> Int {
            switch MoveTaxonomy.pattern(for: move.name) {
            case .hinge: 0
            case .squat, .lunge: 1
            case .pullHorizontal, .pullVertical: 2
            case .pushHorizontal, .pushVertical: 3
            case .carry, .coreAntiRotation, .coreFlexion, .coreExtension: 4
            case .accessory: 5
            case nil: 6
            }
        }

        /// Fills the slots from `pool`, then orders the result.
        ///
        /// Three preferences, all **sorts rather than filters** so a short
        /// pool still fills every slot:
        /// - the session's bell — the kit it was asked to prefer, and once a
        ///   loaded move is chosen, that implement — so a kettlebell day does
        ///   not reach for the beam when a bell move would do;
        /// - at most two implements: a third is taken only when nothing on
        ///   the first two fits the slot at all;
        /// - a move with a drawing ahead of one without, so a written week is
        ///   one she can look at. Her own approved additions never have
        ///   drawings, by decision, and still get reached.
        ///
        /// With `holding`, the slots those moves already satisfy are taken
        /// as covered and only the `count` new picks come back.
        static func fill(_ count: Int, from pool: [Move],
                         preferring kit: Set<Equipment>,
                         holding inHand: [Move] = [],
                         varying turn: Int) -> [Move] {
            var chosen = inHand
            var unassigned = inHand
            var picked: [Move] = []
            var held = kit.union(implements(in: inHand))
            for (index, slot) in slots(inHand.count + count, turn: turn).enumerated() {
                // A move already in hand that fits this slot's first wish
                // covers it; nothing new is fetched for it.
                if let covered = unassigned.firstIndex(where: slot.wants[0]) {
                    unassigned.remove(at: covered)
                    continue
                }
                guard picked.count < count else { break }
                let free = pool.filter { m in !chosen.contains { $0.name == m.name } }
                guard !free.isEmpty else { break }
                let fetched = implements(in: chosen)
                // The bell in hand first; then bodyweight, which costs no
                // fetch; then a second implement; a third only when nothing
                // else fits the slot at all.
                func rank(_ move: Move) -> Int {
                    let bell: Int
                    if held.contains(move.equipment) { bell = 0 }
                    else if move.equipment == .bodyweight { bell = 1 }
                    else if fetched.count < 2 { bell = 2 }
                    else { bell = 3 }
                    return bell * 2 + (MovePlates.strip(for: move) == nil ? 1 : 0)
                }
                var pick: Move?
                search: for want in slot.wants {
                    let fits = free.filter(want)
                    for group in 0...7 {
                        let tier = fits.filter { rank($0) == group }
                        if let move = Rotation.walk(tier, taking: 1, varying: turn + index).first {
                            pick = move
                            break search
                        }
                    }
                }
                guard let pick else { break }
                chosen.append(pick)
                picked.append(pick)
                if pick.equipment != .bodyweight { held.insert(pick.equipment) }
            }
            // Slots a held move did not cover in its first wish still count
            // the move: if the loop ran out of slots before `count` picks
            // (everything in hand was off-pattern), fill the remainder free.
            while picked.count < count {
                let free = pool.filter { m in !chosen.contains { $0.name == m.name } }
                guard let more = Rotation.walk(free, taking: 1, varying: turn + picked.count).first
                else { break }
                chosen.append(more)
                picked.append(more)
            }
            return ordered(picked)
        }
    }

    /// Another move using the same equipment, avoiding a set of names.
    ///
    /// The offline planner's templates are fixed, so without this a fallback
    /// week would hand back the exact move she had just rejected — which would
    /// read as the app not listening, and be right.
    static func substitute(for move: Move, avoiding excluded: Set<String>) -> Move? {
        // Nothing to swap to when the equipment itself is what she no longer
        // has — the caller then leaves the slot alone and says so, rather than
        // quietly offering the same kit under another name.
        guard move.equipment.isOwned else { return nil }
        return moves(for: move.equipment).first {
            // Containment, not equality — see `MovePreference.anyCovers`. This
            // line used to be `excluded.contains($0.name.lowercased())`, which
            // is why the first replacement offered for any bodyweight move was
            // the incline push-up she is on record as disliking.
            !MovePreference.anyCovers(excluded, $0.name)
                && MovePreference.key($0.name) != MovePreference.key(move.name)
        }
    }
}
