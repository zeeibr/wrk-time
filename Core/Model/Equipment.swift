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

    /// How a thing is held. The first axis of the library that is not the
    /// implement: a row is the same movement with a pair, one hand on a
    /// bell, or one hand on the single. `oneHand` implies sided.
    enum Hold: String, Codable, Sendable { case pair, oneHand, twoHands, none }

    /// The holds this implement allows. A pair is only ever a pair; the
    /// single, the rings and the bell are one hand or two; the beam is two.
    var holds: Set<Hold> {
        switch self {
        case .dumbbells: [.pair]
        case .singleDumbbell, .rings, .kettlebell: [.oneHand, .twoHands]
        case .beam: [.twoHands]
        case .band: [.twoHands, .oneHand]
        case .walkingPad, .bodyweight: [.none]
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
    /// The library: every strength movement's variants from the catalog,
    /// then the flow movements. The catalog is the one place a strength
    /// move is written; the flow list stays a list because a flow movement
    /// has no implement to vary by.
    static let all: [Move] = MovementCatalog.all.flatMap(\.moves) + literals

    /// The flow movements — qi gong, mobility, lymphatic. Not a strength
    /// move among them: those live in `MovementCatalog`.
    static let literals: [Move] = [

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
            // Inside a rank, keep one pattern together — rows before vertical
            // pulls rather than interleaved — so the library's sub-heads
            // read as groups.
            let ka = MoveTaxonomy.pattern(for: a.element.name).map { MovePattern.allCases.firstIndex(of: $0) ?? 99 } ?? 99
            let kb = MoveTaxonomy.pattern(for: b.element.name).map { MovePattern.allCases.firstIndex(of: $0) ?? 99 } ?? 99
            if ka != kb { return ka < kb }
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
