import SwiftUI

/// Move plates: a movement drawn as a short strip of panels.
///
/// Two or three moments, side by side, separated by a hairline and standing on
/// one shared floor. The strip is the motion — there is no arrow, no dashed
/// arc, and no faint "start" figure behind the solid one. Those were the first
/// attempt and all three were off-brand: dashed strokes mean *projected*
/// elsewhere in this app, arrowheads mean *proceed*, and a 40%-alpha ghost sits
/// under the 3:1 floor `Palette` sets for non-text.
///
/// Three properties are load-bearing and easy to break:
///
/// 1. **The stroke is 1.5 points at every size.** The old plates scaled the
///    line with the frame and rendered anywhere from 0.73pt in a list row to
///    3.83pt in the sheet — the only mark in the app that changed weight when
///    it changed size. Nothing here multiplies `Ink.stroke` by anything.
/// 2. **One figure scale everywhere.** The head is always an eighth of panel
///    height. There is no per-strip bounding-box fit; a strip that needs more
///    room moves its `anchorX`, it does not zoom.
/// 3. **No opacity, in either register.** Every mark is the register's primary
///    colour or it is a rule. An alpha-blended stroke composites differently
///    against oat and against the field, and these are drawn twice — once in
///    each — with the timer's boundary cutting through both.

// MARK: - Anatomy

/// The figure, in panel units: `y` from 0 at the floor to 1 at the top, `x` in
/// the same units, so a 1:2 panel spans `x` in 0…0.5.
///
/// Everything derives from the head. 5.75 heads tall — which is not what a
/// first pass at the brief gives you: head 1 + torso 2 + thigh 1.5 + shin 1.5
/// is 6.00 heads with a neck of zero length. The quarter comes out of the
/// torso rather than the legs, because every squat, hinge, lunge and split in
/// the library is read from the thigh-shin angle and none of them from trunk
/// length.
enum Anatomy {
    /// Head diameter, and the unit everything else derives from.
    ///
    /// A twelfth of panel height rather than an eighth. The first pass drew a
    /// figure filling three quarters of its panel with an 8pt disc for a head
    /// at row size, which read as sturdy rather than as the small marginal
    /// drawing an almanac would set. Smaller leaves air around the figure and
    /// lets three panels sit beside a running clock without shouting.
    static let head = 0.105
    static let radius = head / 2

    static let floorY = 0.060
    static let thigh = 1.50 * head          // 0.1875
    static let shin = 1.50 * head           // 0.1875
    static let torso = 1.75 * head          // 0.21875
    static let upperArm = 1.25 * head       // 0.15625
    static let foreArm = 1.20 * head        // 0.15

    /// Standing landmarks: floor + thigh + shin, then the torso on top.
    static let hipStanding = floorY + thigh + shin      // 0.435
    /// How far up the torso the shoulder sits.
    static let shoulderRise = 0.88
    /// Half the shoulder width, front view.
    static let shoulderOffset = 0.45 * head
    /// Half the gap between the soles, front view.
    static let stanceDefault = 0.8
    /// The most a shoulder may rise, in head units. Beyond this it climbs past
    /// the head and the arms appear to sprout from the top of the skull.
    static let shrugCeiling = 0.62
    /// The drawn neck, between the top of the spine and the head disc.
    ///
    /// Zeroing this was a mistake in the first spec and the illustrator
    /// retracted it: with the disc tangent on the spine there is no shoulder
    /// landmark, so a shrug moves nothing visible and the head collides with
    /// any ink near it.
    static let neck = 0.20
    /// How much larger a figure on the floor is drawn. See `Pose.supine`.
    static let recumbent = 1.55

    /// Degrees from straight down, positive swinging forward (+x): 0 hangs at
    /// the side, 90 is horizontal, 180 is overhead. The one convention in this
    /// file, used absolutely and never relative to the torso.
    static func along(_ from: CGPoint, _ degrees: Double, _ length: Double,
                      mirrored: Bool = false) -> CGPoint {
        let radians = degrees * .pi / 180
        let dx = sin(radians) * length * (mirrored ? -1 : 1)
        return CGPoint(x: from.x + dx, y: from.y - cos(radians) * length)
    }

    /// The torso is measured from vertical instead, positive leaning forward.
    static func upward(_ from: CGPoint, _ degrees: Double, _ length: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: from.x + sin(radians) * length,
                       y: from.y + cos(radians) * length)
    }

    /// The knee, solved rather than placed.
    ///
    /// Exact two-bar inverse kinematics against equal thigh and shin. The first
    /// implementation put the knee at a displaced midpoint, which silently drew
    /// a short shin at the bottom of a squat — the leg visibly bent the wrong
    /// way and the figure read as a zigzag. Here the segment lengths are
    /// preserved in every pose and a straight leg falls out for free.
    static func joint(from hip: CGPoint, to foot: CGPoint,
                      segment: Double, ahead: Bool = true) -> CGPoint {
        // Pull an unreachable foot in to arm's length before solving. Clamping
        // the distance but keeping the far foot was the first version, and it
        // produced a knee that satisfied neither segment — thigh and shin both
        // came out 10% long on a wide split. A leg cannot be longer than it is;
        // if the pose asks for one, the sole moves, not the bone.
        var span = CGPoint(x: foot.x - hip.x, y: foot.y - hip.y)
        let asked = hypot(span.x, span.y)
        let reach = min(asked, segment * 2 - 0.0005)
        if asked > reach, asked > 0 {
            span = CGPoint(x: span.x * reach / asked, y: span.y * reach / asked)
        }
        let landed = CGPoint(x: hip.x + span.x, y: hip.y + span.y)
        let mid = CGPoint(x: (hip.x + landed.x) / 2, y: (hip.y + landed.y) / 2)
        let bulge = (segment * segment - reach * reach / 4).squareRoot()
        // Normal to the hip-foot line, taken so the knee travels forward.
        var normal = CGPoint(x: -span.y, y: span.x)
        let length = max(hypot(normal.x, normal.y), 0.0001)
        normal = CGPoint(x: normal.x / length, y: normal.y / length)
        if (normal.x < 0) == ahead { normal = CGPoint(x: -normal.x, y: -normal.y) }
        return CGPoint(x: mid.x + normal.x * bulge, y: mid.y + normal.y * bulge)
    }

    /// Where the second segment actually ends: along the line toward the
    /// asked-for point, at exactly its own length. This keeps a sole on the
    /// floor in every pose that can reach it, and honestly short in the ones
    /// that cannot, instead of stretching the bone to meet the ground.
    static func landing(from joint: CGPoint, toward target: CGPoint,
                        segment: Double) -> CGPoint {
        let span = CGPoint(x: target.x - joint.x, y: target.y - joint.y)
        let length = max(hypot(span.x, span.y), 0.0001)
        return CGPoint(x: joint.x + span.x / length * segment,
                       y: joint.y + span.y / length * segment)
    }
}

/// Which way the figure is seen, and therefore how wide its panel is.
///
/// A front-facing figure with both arms horizontal spans 6.2 head-widths — very
/// nearly its own height. It cannot share a 1:2 panel with a standing side view
/// at one figure scale, and shrinking the figure to fit reintroduces the spider
/// this rewrite exists to kill. So the aspect keys off the facing, which a
/// strip already declares and may never mix.
enum Facing: Sendable {
    case side, front
    var width: Double { self == .side ? 0.5 : 1.0 }
}

// MARK: - Pose

/// One drawn moment. Joints only — no colours, no sizes, nothing about screens.
struct Pose: Sendable {
    var hip: CGPoint
    var neck: CGPoint
    var head: CGPoint
    /// Polylines from shoulder through elbow to hand.
    var arms: [[CGPoint]] = []
    /// Polylines from hip through knee to sole.
    var legs: [[CGPoint]] = []
    /// Set only when the spine is a curve rather than a segment — cat cow and
    /// the spinal wave are *about* the curve.
    var spineCurve: Double?
    var props: [Prop] = []

    /// The near hand — the arm drawn last, on top. A far arm is added first so
    /// the near one lands over it, which means `first` is the wrong end.
    var hand: CGPoint { arms.last?.last ?? neck }
    var hands: [CGPoint] { arms.compactMap(\.last) }
    /// Where the near arm leaves the torso.
    var shoulder: CGPoint { arms.last?.first ?? neck }
    /// Mid-chest — where a racked bar rests. The shoulder itself sits inside
    /// the head disc's orbit, so a bar drawn there reads as held at the face.
    var chest: CGPoint {
        CGPoint(x: hip.x + (neck.x - hip.x) * 0.70,
                y: hip.y + (neck.y - hip.y) * 0.70)
    }

    /// Attaches kit positioned from this pose's own joints, so a beam is at the
    /// hands rather than at a number that has to be kept in step by hand.
    func holding(_ make: (Pose) -> [Prop]) -> Pose {
        var copy = self
        copy.props += make(self)
        return copy
    }
}

/// Kit, ground and furniture. Three weights only: held things are body weight,
/// supporting things are a firm rule, the floor is a plain rule.
enum Prop: Sendable {
    /// The beam: a bar two heads long with a tick at each end. The ticks are
    /// the whole difference between a beam and an arm and are never dropped.
    case beam(CGPoint, angle: Double = 0)
    /// One ring. Never three — they are used one at a time, and drawing all
    /// three would be drawing something that never happens.
    case ring(CGPoint)
    /// A dumbbell at each listed hand.
    case bells([CGPoint])
    /// The kettlebell: a body with a handle arched over it, hanging from the
    /// hand that grips it. Never the dumbbell's filled disc — eighteen pounds
    /// is not two, and the handle is the whole difference.
    case bell(CGPoint)
    /// The walking pad. `rise` lifts the far end.
    case pad(rise: Double)
    case wall(x: Double)
    /// A sofa edge or a counter — one prop, only the height differs.
    case ledge(x: Double, y: Double)
}

// MARK: - Builders

extension Pose {
    /// Seen from the side, facing +x. One arm and one leg — the near ones —
    /// unless a split stance or a second arm is asked for.
    ///
    /// - Parameters:
    ///   - sink: 1 standing tall, 0 a deep squat one thigh-length down.
    ///   - lean: torso tilt forward from vertical, degrees.
    ///   - shoulder: near upper arm, absolute per `Anatomy.along`.
    ///   - elbow: added to `shoulder` for the forearm's absolute angle.
    ///   - split: sole separation in head units. Non-zero draws the far leg.
    static func side(anchorX: Double = 0.25,
                     sink: Double = 1,
                     lean: Double = 0,
                     shoulder: Double = 16,
                     elbow: Double = 8,
                     farArm: (Double, Double)? = nil,
                     split: Double = 0,
                     footAhead: Double = 0,
                     footLift: Double = 0,
                     groundY: (Double) -> Double = { _ in Anatomy.floorY }) -> Pose {
        let h = Anatomy.head
        let hipY = Anatomy.hipStanding - Anatomy.thigh * (1 - sink)
        // The hips travel back as you sit and as you fold. This one line is
        // what stops a squat reading as a chair and a hinge reading as a bow.
        let hipX = anchorX - h * (0.9 * (1 - sink) + sin(lean * .pi / 180))
        let hip = CGPoint(x: hipX, y: hipY)

        let neck = Anatomy.upward(hip, lean, Anatomy.torso)
        let head = Anatomy.upward(neck, lean, Anatomy.radius)
        let shoulderPoint = Anatomy.upward(hip, lean, Anatomy.torso * Anatomy.shoulderRise)

        func arm(_ upper: Double, _ fore: Double) -> [CGPoint] {
            let elbowPoint = Anatomy.along(shoulderPoint, upper, Anatomy.upperArm)
            return [shoulderPoint, elbowPoint,
                    Anatomy.along(elbowPoint, upper + fore, Anatomy.foreArm)]
        }

        func leg(soleX: Double, lift: Double) -> [CGPoint] {
            let asked = CGPoint(x: soleX, y: groundY(soleX) + lift * h)
            let knee = Anatomy.joint(from: hip, to: asked, segment: Anatomy.thigh)
            return [hip, knee, Anatomy.landing(from: knee, toward: asked,
                                               segment: Anatomy.shin)]
        }

        let frontSole = anchorX + (0.30 * split + footAhead) * h
        var legs = [leg(soleX: frontSole, lift: footLift)]
        if split != 0 { legs.append(leg(soleX: frontSole - split * h, lift: 0)) }

        // The far arm is drawn first so the near one lands on top of it.
        var arms: [[CGPoint]] = []
        if let farArm { arms.append(arm(farArm.0, farArm.1)) }
        arms.append(arm(shoulder, elbow))

        return Pose(hip: hip, neck: neck, head: head, arms: arms, legs: legs)
    }

    /// Seen from the front. Two arms and two legs, mirrored about the spine —
    /// what a raise, a halo, a sweep or a tilt needs, because side-on collapses
    /// all four to a single foreshortened line.
    static func front(sink: Double = 1,
                      spread: Double = 14,
                      elbow: Double = 8,
                      stance: Double = Anatomy.stanceDefault,
                      tilt: Double = 0,
                      shift: Double = 0,
                      shrug: Double = 0,
                      footLift: Double = 0) -> Pose {
        let h = Anatomy.head
        let spine = 0.5
        let hipY = Anatomy.hipStanding - Anatomy.thigh * (1 - sink)
        // The neck stays on the spine while the hips travel, so the trunk
        // becomes a slant — which is the whole of a hip circle.
        let hip = CGPoint(x: spine + shift * h, y: hipY)
        let neck = CGPoint(x: spine, y: hipY + Anatomy.torso)
        let reach = Anatomy.radius + Anatomy.neck * Anatomy.head
        let head = CGPoint(x: neck.x + sin(tilt * .pi / 180) * reach,
                           y: neck.y + cos(tilt * .pi / 180) * reach)

        func arm(_ side: Bool) -> [CGPoint] {
            let lift = min(shrug, Anatomy.shrugCeiling)
            let shoulder = CGPoint(
                x: spine + (Anatomy.shoulderOffset - 0.22 * lift * h) * (side ? 1 : -1),
                y: hipY + Anatomy.torso * Anatomy.shoulderRise + lift * h)
            let elbowPoint = Anatomy.along(shoulder, spread, Anatomy.upperArm, mirrored: !side)
            return [shoulder, elbowPoint,
                    Anatomy.along(elbowPoint, spread + elbow, Anatomy.foreArm, mirrored: !side)]
        }

        func leg(_ side: Bool, lift: Double) -> [CGPoint] {
            let asked = CGPoint(x: spine + stance * h / 2 * (side ? 1 : -1),
                                y: Anatomy.floorY + lift * h)
            let knee = Anatomy.joint(from: hip, to: asked, segment: Anatomy.thigh,
                                     ahead: side)
            return [hip, knee, Anatomy.landing(from: knee, toward: asked,
                                               segment: Anatomy.shin)]
        }

        return Pose(hip: hip, neck: neck, head: head,
                    arms: [arm(true), arm(false)],
                    legs: [leg(true, lift: footLift), leg(false, lift: 0)])
    }

    /// On the back, head to +x. Knees are placed rather than solved here — a
    /// supine leg is foreshortened, and inverse kinematics would draw it at
    /// full length lying flat.
    ///
    /// Lying poses draw at `Anatomy.recumbent` rather than at the standing
    /// scale. This is the one deliberate exception to one-scale-everywhere, and
    /// it is not a cheat: the rule exists so a figure does not appear to zoom
    /// between one *standing* move and the next, and a body on the floor has no
    /// vertical extent to trade against a portrait panel. Drawn at the standing
    /// scale it occupied the bottom fifth of the frame and read as a smudge.
    static func supine(width: Double = 0.5,
                       hipLift: Double = 0,
                       shoulderLift: Double = 0,
                       kneeUp: Double = 1.2,
                       armAngle: Double = 0,
                       armBend: Double = 16) -> Pose {
        let h = Anatomy.head * Anatomy.recumbent
        let deck = Anatomy.floorY + 0.62 * h
        // Laid out across the panel rather than huddled at its centre. The
        // first version spanned a quarter of the frame and read as a smudge at
        // row size — a lying figure is as long as a standing one is tall.
        let centre = width / 2
        let hipX = centre - 0.55 * h
        let hip = CGPoint(x: hipX, y: deck + hipLift * h)
        let neck = CGPoint(x: hipX + 1.75 * h, y: deck + shoulderLift * h + 0.18 * h)
        let head = CGPoint(x: neck.x + Anatomy.radius * Anatomy.recumbent, y: neck.y)
        let shoulder = CGPoint(x: hipX + 1.50 * h, y: deck + shoulderLift * h + 0.15 * h)

        // Measured from straight up, positive rotating toward the feet.
        let radians = armAngle * .pi / 180
        let direction = CGPoint(x: -sin(radians), y: cos(radians))
        let upper = Anatomy.upperArm * Anatomy.recumbent
        let fore = Anatomy.foreArm * Anatomy.recumbent
        let elbow = CGPoint(x: shoulder.x + direction.x * upper,
                            y: shoulder.y + direction.y * upper)
        let bent = (armAngle + armBend) * .pi / 180
        let hand = CGPoint(x: elbow.x - sin(bent) * fore,
                           y: elbow.y + cos(bent) * fore)

        let knee = CGPoint(x: hipX - 0.9 * h, y: Anatomy.floorY + kneeUp * h)
        let sole = CGPoint(x: hipX - 2.1 * h, y: Anatomy.floorY)

        return Pose(hip: hip, neck: neck, head: head,
                    arms: [[shoulder, elbow, hand]], legs: [[hip, knee, sole]])
    }

    /// On all fours, head to +x. `curve` is negative for the arched shape and
    /// positive for the rounded one; `reach` puts the opposite arm and leg out
    /// level with the spine.
    static func quadruped(width: Double = 0.5,
                          curve: Double = 0,
                          headDrop: Double = 0,
                          reach: Bool = false) -> Pose {
        let h = Anatomy.head * Anatomy.recumbent
        let spineY = Anatomy.floorY + 2.4 * h
        let hipX = width / 2 - 1.3 * h
        let neckX = hipX + 2.6 * h
        let hip = CGPoint(x: hipX, y: spineY)
        let neck = CGPoint(x: neckX, y: spineY)
        let head = CGPoint(x: neckX + Anatomy.radius * Anatomy.recumbent - 0.3 * headDrop * h,
                           y: spineY - headDrop * h)

        // Placed rather than solved. The supporting limbs are near-vertical and
        // shorter than two segments, so inverse kinematics bulges the joint
        // most of a head sideways — straight out of the panel.
        let handDown = CGPoint(x: neckX + 0.1 * h, y: Anatomy.floorY)
        let soleDown = CGPoint(x: hipX - 0.15 * h, y: Anatomy.floorY)
        var arms = [[neck, CGPoint(x: neckX + 0.34 * h, y: (spineY + Anatomy.floorY) / 2),
                     handDown]]
        var legs = [[hip, CGPoint(x: hipX - 0.42 * h, y: (spineY + Anatomy.floorY) / 2),
                     soleDown]]

        if reach {
            arms.insert([neck, CGPoint(x: neckX + 0.72 * h, y: spineY + 0.22 * h),
                         CGPoint(x: neckX + 1.60 * h, y: spineY + 0.40 * h)], at: 0)
            legs.insert([hip, CGPoint(x: hipX - 0.72 * h, y: spineY + 0.22 * h),
                         CGPoint(x: hipX - 1.60 * h, y: spineY + 0.40 * h)], at: 0)
        }

        var pose = Pose(hip: hip, neck: neck, head: head, arms: arms, legs: legs)
        pose.spineCurve = curve
        return pose
    }
}

// MARK: - Strips

/// One move as two or three moments.
struct Strip: Sendable {
    /// Matched by containment against a move's name, lowercased.
    let key: String
    /// The kit this drawing has in its hands, or nil when the strip is a bare
    /// pattern that suits any of it. A strip is never handed to a move with
    /// different kit: the planner invents names freely, and "Beam goblet squat"
    /// matching the bodyweight `squat` drew a woman squatting with nothing in
    /// her hands under a label reading 15 LB BALA BEAM.
    var equipment: Equipment?
    let facing: Facing
    let panels: [Pose]
    /// The one frame that most distinguishes this move from its neighbours —
    /// for a squat, the bottom rather than the finish. A list row shows this
    /// and nothing else.
    var signature: Int

    /// Panel 0 and the signature. For a squat drawn stand / bottom / stand,
    /// "first and last" would be the same drawing twice.
    var pair: [Pose] {
        signature == 0 ? Array(panels.prefix(2)) : [panels[0], panels[signature]]
    }
}

enum MovePlates {
    /// The strip for a move.
    ///
    /// A plain lookup, because the library is closed: `MoveLibrary.names` is an
    /// enum in the planner's response schema, so a move that reaches this app
    /// is one of the thirty-seven and has a drawing.
    ///
    /// This used to be three passes of fuzzy matching — the longest key
    /// contained in the name, then a shared word within the same equipment,
    /// then a bare pattern for bodyweight moves — and all of it existed to
    /// guess what an invented name meant. It guessed wrong: "Ring goblet squat"
    /// shares the word "ring" with the ring deadlift and was drawn as a hinge.
    /// Closing the library deleted the guessing rather than adding a fourth
    /// rule to it.
    ///
    /// Still Optional. A hand-built routine, or a session stored before the
    /// library closed, can name something that is no longer there — and a
    /// missing drawing is a gap in a row, not a crash.
    static func strip(for move: Move) -> Strip? { byName[MovePreference.key(move.name)] }

    /// By name alone, for callers with no `Move` to hand.
    static func strip(for name: String) -> Strip? { byName[MovePreference.key(name)] }

    /// Moves whose drawings are deliberately not made yet. Without this the
    /// containment matcher hands "Ring bicep curl" the dumbbell curl strip —
    /// the right body, the wrong implement in its hands — and a drawing of the
    /// wrong thing is worse than none. Remove a name from here when its own
    /// strip is drawn. Internal so the coverage test can hold the whole
    /// library to account *except* exactly these.
    /// Grouped by *why*, because the reasons are different and only one of
    /// them is "nobody has drawn it yet". Anything here that a builder could
    /// reach is a to-do; anything below the second heading is a decision.
    ///
    /// "Air squat" is deliberately absent from this set: the bare `squat`
    /// strip is the plain bodyweight squat and nothing else claims it — every
    /// other squat in the library is taken by a longer key (front, goblet,
    /// split, deep) — so the ordinary longest-match rule hands it over, which
    /// is the whole reason keys are matched by containment.
    static let deferred: Set<String> = [
        // NOT YET DRAWN. Reachable with the builders that exist.
        "russian twist", "tall-kneeling press", "plank pull-through",

        // NO PROP FOR IT. The band is a line between the hands under tension,
        // and it genuinely changes the silhouette — `Prop` has no case for it,
        // and inventing one is a drawing decision rather than geometry.
        "band pull-apart", "band face pull", "band w raise",
        "band external rotation", "band seated row", "band overhead press",

        // NO BUILDER FOR THE SHAPE. There is no prone, side-lying, seated or
        // kneel-back pose, and `supine` places one arm, one leg and a pinned
        // sole. Each of these needs a builder before it can be drawn at all.
        "forearm plank", "side plank", "lying leg raise", "bicycle crunch",
        "plank shoulder tap", "superman", "one-leg bridge", "side leg lift",
        "reverse tabletop hold", "child's pose reach", "thread the needle",
        "wall angel",

        // THE MOVEMENT IS SMALLER THAN THE PANEL RULE. Consecutive panels must
        // differ by a head diameter to read as a change; a chin tuck moves an
        // inch, a wrist curl less, and a bear hold's knees hover. Drawing any
        // of these to clear the bar would be drawing a movement she is not
        // doing — the same call that dropped "Shaking" from the library.
        "chin tuck", "ring wrist curl", "bear hold", "single-leg calf raise",
        "pelvic rocks", "knee sways", "kettlebell calf raise",
        // A static hold has one frame. Two panels can only differ by inventing
        // an entry the move does not contain — a clean, in these two cases.
        "kettlebell rack hold", "kettlebell suitcase hold",

        // THE DISTINGUISHING FACT IS INVISIBLE IN BOTH PROJECTIONS. A grip
        // rotation, a wheel turn, a step that goes back *and* across, a chop
        // across the body: side-on collapses the across, front-on mirrors
        // what it draws, and neither can hold the thing that names the move.
        "ring hammer curl", "ring bus driver", "ring chop", "beam curtsy lunge",
        // The Zottman turns the forearm over and the scaption lifts in the
        // plane halfway between front and side: front-on the scaption is the
        // lateral raise, side-on it is the front raise, and the Zottman is the
        // bicep curl either way.
        "zottman curl", "scaption raise"
    ]

    /// Every library move to its drawing, resolved once at launch. The library
    /// is fixed, so the longest-key-wins rule that makes "split squat" beat
    /// "squat" runs here rather than on every lookup.
    private static let byName: [String: Strip] = {
        var table: [String: Strip] = [:]
        for move in MoveLibrary.all {
            let key = MovePreference.key(move.name)
            guard !deferred.contains(key) else { continue }
            if let strip = sorted.first(where: { key.contains($0.key) }) {
                table[key] = strip
            }
        }
        return table
    }()


    private static let sorted: [Strip] = all.sorted { $0.key.count > $1.key.count }

    static let all: [Strip] = beam + rings + dumbbells + singleDumbbell
        + kettlebell + bodyweight + flow

    // MARK: Beam
    //
    // The rack sits at mid-chest, not at the collarbones the cue names: a bar
    // two heads long drawn any higher runs straight through the head disc.

    private static let beam: [Strip] = [
        Strip(key: "front squat", equipment: .beam, facing: .side, panels: [
            .side(anchorX: 0.21, sink: 1.00, lean: 0, shoulder: 88, elbow: 176)
                .holding { [.beam($0.chest)] },
            .side(anchorX: 0.21, sink: 0.34, lean: 26, shoulder: 84, elbow: 176)
                .holding { [.beam($0.chest)] }
        ], signature: 1),

        Strip(key: "deadlift", equipment: .beam, facing: .side, panels: [
            .side(sink: 0.92, lean: 26, shoulder: 6, elbow: 4).holding { [.beam($0.hand)] },
            .side(sink: 0.84, lean: 68, shoulder: 4, elbow: 4).holding { [.beam($0.hand)] }
        ], signature: 1),

        Strip(key: "good morning", equipment: .beam, facing: .side, panels: [
            .side(sink: 1.00, lean: 0, shoulder: 96, elbow: 176)
                .holding { [.beam($0.neck)] },
            .side(sink: 0.94, lean: 62, shoulder: 96, elbow: 176)
                .holding { [.beam($0.neck)] }
        ], signature: 1),

        // Front-facing, so the bar draws in full with its end ticks — an
        // overhead press is the one beam move where the bar is the point, and
        // side-on it would be a dot above her head.
        Strip(key: "overhead press", equipment: .beam, facing: .front, panels: [
            .front(spread: 34, elbow: 128).holding { [.beam(midpoint($0.hands))] },
            .front(spread: 172, elbow: 6).holding { [.beam(midpoint($0.hands))] }
        ], signature: 1),

        Strip(key: "beam row", equipment: .beam, facing: .side, panels: [
            .side(anchorX: 0.22, sink: 0.92, lean: 58, shoulder: 4, elbow: 4)
                .holding { [.beam($0.hand)] },
            .side(anchorX: 0.22, sink: 0.92, lean: 58, shoulder: 2, elbow: 132)
                .holding { [.beam($0.hand)] }
        ], signature: 1),

        Strip(key: "beam reverse lunge", equipment: .beam, facing: .side, panels: [
            .side(sink: 1.00, shoulder: 88, elbow: 176, split: 0.2)
                .holding { [.beam($0.chest)] },
            .side(sink: 0.52, shoulder: 84, elbow: 176, split: 2.6)
                .holding { [.beam($0.chest)] }
        ], signature: 1),

        Strip(key: "floor press", equipment: .beam, facing: .front, panels: [
            .supine(width: 1.0, kneeUp: 1.15, armAngle: 62)
                .holding { [.beam($0.hand, angle: 90)] },
            .supine(width: 1.0, kneeUp: 1.15, armAngle: 0)
                .holding { [.beam($0.hand, angle: 90)] }
        ], signature: 1),

        Strip(key: "hip thrust", equipment: .beam, facing: .front, panels: [
            .supine(width: 1.0, hipLift: 0, shoulderLift: 1.15, kneeUp: 1.15, armAngle: 92)
                .holding { [.beam($0.hip), .ledge(x: 0.34, y: Anatomy.floorY + 0.30 * Anatomy.head + 1.15 * Anatomy.head)] },
            .supine(width: 1.0, hipLift: 1.15, shoulderLift: 1.15, kneeUp: 1.15, armAngle: 92)
                .holding { [.beam($0.hip), .ledge(x: 0.34, y: Anatomy.floorY + 0.30 * Anatomy.head + 1.15 * Anatomy.head)] }
        ], signature: 1),

        // A hold has one position, so the strip shows the way into it: racked,
        // then locked out with the arms by the ears. Side-on rather than
        // front-on like the overhead press — the hold is the stacked line,
        // wrist over shoulder over hip, which is a sagittal fact.
        Strip(key: "beam overhead hold", equipment: .beam, facing: .side, panels: [
            .side(sink: 1.00, shoulder: 88, elbow: 176).holding { [.beam($0.chest)] },
            .side(sink: 1.00, shoulder: 172, elbow: 4).holding { [.beam($0.hand)] }
        ], signature: 1),

        // Front-on: both hands on one bar is the whole difference from the
        // dumbbell curl, and side-on the two drawings would differ only by the
        // mark at the hand. The elbows hold still in both panels — that is the
        // cue — and the travel is carried by the hands.
        Strip(key: "beam curl", equipment: .beam, facing: .front, panels: [
            .front(spread: 8, elbow: 4).holding { [.beam(midpoint($0.hands))] },
            .front(spread: 8, elbow: 160).holding { [.beam(midpoint($0.hands))] }
        ], signature: 1),

        // Panel 0 is the beam floor press's lockout, honestly, because that is
        // where this move starts. So the signature is the lowered frame, or a
        // list row would show the two moves as the same drawing.
        Strip(key: "beam triceps extension", equipment: .beam, facing: .front, panels: [
            .supine(width: 1.0, kneeUp: 1.15, armAngle: 0)
                .holding { [.beam($0.hand, angle: 90)] },
            .supine(width: 1.0, kneeUp: 1.15, armAngle: 0, armBend: -100)
                .holding { [.beam($0.hand, angle: 90)] }
        ], signature: 1),

        // Front-on, because the step is sideways and side-on it collapses to a
        // foreshortened line. `shift` is what makes it the move rather than a
        // wide squat: the hips travel over one foot, so that knee bends and the
        // far leg comes out straight on its own.
        Strip(key: "beam lateral lunge", equipment: .beam, facing: .front, panels: [
            .front(spread: 34, elbow: 128).holding { [.beam(midpoint($0.hands))] },
            .front(sink: 0.35, spread: 34, elbow: 128, stance: 3.1, shift: 0.55)
                .holding { [.beam(midpoint($0.hands))] }
        ], signature: 1)
    ]

    // MARK: Rings

    private static let rings: [Strip] = [
        Strip(key: "halo", equipment: .rings, facing: .front, panels: [
            .front(spread: 96, elbow: 62).holding { [.ring(midpoint($0.hands))] },
            .front(spread: 176, elbow: 4).holding { [.ring(midpoint($0.hands))] }
        ], signature: 1),

        Strip(key: "press-out", equipment: .rings, facing: .side, panels: [
            .side(anchorX: 0.13, shoulder: 30, elbow: 116).holding { [.ring($0.hand)] },
            .side(anchorX: 0.13, shoulder: 88, elbow: 2).holding { [.ring($0.hand)] }
        ], signature: 1),

        Strip(key: "goblet squat", equipment: .rings, facing: .side, panels: [
            .side(anchorX: 0.21, sink: 1.00, shoulder: 26, elbow: 118)
                .holding { [.ring($0.hand)] },
            .side(anchorX: 0.21, sink: 0.34, lean: 26, shoulder: 22, elbow: 118)
                .holding { [.ring($0.hand)] }
        ], signature: 1),

        Strip(key: "ring row", equipment: .rings, facing: .side, panels: [
            .side(anchorX: 0.22, sink: 0.88, lean: 60, shoulder: 4, elbow: 4)
                .holding { [.ring($0.hand)] },
            .side(anchorX: 0.22, sink: 0.88, lean: 60, shoulder: 2, elbow: 128)
                .holding { [.ring($0.hand)] }
        ], signature: 1),

        Strip(key: "ring overhead press", equipment: .rings, facing: .front, panels: [
            .front(spread: 30, elbow: 132).holding { [.ring(midpoint($0.hands))] },
            .front(spread: 174, elbow: 4).holding { [.ring(midpoint($0.hands))] }
        ], signature: 1),

        Strip(key: "ring front raise", equipment: .rings, facing: .side, panels: [
            .side(anchorX: 0.16, shoulder: 22, elbow: 20).holding { [.ring($0.hand)] },
            .side(anchorX: 0.16, shoulder: 84, elbow: 6).holding { [.ring($0.hand)] }
        ], signature: 1),

        Strip(key: "ring deadlift", equipment: .rings, facing: .side, panels: [
            .side(sink: 0.86, lean: 34, shoulder: 6, elbow: 4).holding { [.ring($0.hand)] },
            .side(sink: 0.74, lean: 70, shoulder: 4, elbow: 4).holding { [.ring($0.hand)] }
        ], signature: 1),

        // One arm, elbow pinned: the upper arm holds still in both panels and
        // only the forearm sweeps. The far arm hangs throughout, which is what
        // makes this read as one arm at a time rather than as the dumbbell
        // curl with a ring drawn on it. It must stay in both panels.
        Strip(key: "ring bicep curl", equipment: .rings, facing: .side, panels: [
            .side(shoulder: 6, elbow: 34, farArm: (6, 4)).holding { [.ring($0.hand)] },
            .side(shoulder: 6, elbow: 140, farArm: (6, 4)).holding { [.ring($0.hand)] }
        ], signature: 1),

        // Side-on rather than front-on like the dumbbell Arnold press, because
        // this one is a single arm and `front` mirrors what it draws. Panel 0
        // is the ring at the chin with the elbow tucked; the rotation itself is
        // not drawable and is not attempted.
        Strip(key: "ring arnold press", equipment: .rings, facing: .side, panels: [
            .side(anchorX: 0.24, shoulder: -6, elbow: 160, farArm: (6, 4))
                .holding { [.ring($0.hand)] },
            .side(anchorX: 0.24, shoulder: 172, elbow: 4, farArm: (6, 4))
                .holding { [.ring($0.hand)] }
        ], signature: 1),

        // The hinge is held across both panels so the arm is the only thing
        // that moves — the difference between this and the ring row, where the
        // elbow folds and the arm stays under the shoulder.
        Strip(key: "ring behind-back raise", equipment: .rings, facing: .side, panels: [
            .side(anchorX: 0.26, sink: 0.90, lean: 55, shoulder: -35, elbow: -4)
                .holding { [.ring($0.hand)] },
            .side(anchorX: 0.26, sink: 0.90, lean: 55, shoulder: -85, elbow: -6)
                .holding { [.ring($0.hand)] }
        ], signature: 1),

        // A hold, so the travel is the entry — the wall sit's answer. The ring
        // is overhead in both panels because it never leaves there; what
        // changes is the body under it.
        Strip(key: "ring half-kneeling overhead hold", equipment: .rings, facing: .side, panels: [
            .side(anchorX: 0.25, sink: 1.00, shoulder: 178, elbow: 2, split: 0.2)
                .holding { [.ring($0.hand)] },
            .side(anchorX: 0.25, sink: 0.12, shoulder: 178, elbow: 2, split: 2.5)
                .holding { [.ring($0.hand)] }
        ], signature: 1),

        // The elbow is identical in both panels and only the forearm moves,
        // which is the cue read literally. Signature 0 — the ring behind the
        // head is what names this move; the finish is a figure with an arm up,
        // like four others in the library.
        Strip(key: "ring triceps extension", equipment: .rings, facing: .side, panels: [
            .side(anchorX: 0.20, shoulder: 172, elbow: -232).holding { [.ring($0.hand)] },
            .side(anchorX: 0.20, shoulder: 172, elbow: 4).holding { [.ring($0.hand)] }
        ], signature: 0),

        // The glute bridge with the ring on the hip bones, drawn the way the
        // beam hip thrust is — the ring rides at `hip` so it travels with her
        // rather than sitting at a number kept in step by hand.
        Strip(key: "ring bridge", equipment: .rings, facing: .front, panels: [
            .supine(width: 1.0, hipLift: 0, kneeUp: 1.15, armAngle: 92)
                .holding { [.ring($0.hip)] },
            .supine(width: 1.0, hipLift: 1.05, kneeUp: 1.15, armAngle: 92)
                .holding { [.ring($0.hip)] }
        ], signature: 1),

        // The dumbbell kickback's hinge and pinned upper arm — the same
        // movement, and the kit is what the strip draws.
        Strip(key: "ring kickback", equipment: .rings, facing: .side, panels: [
            .side(anchorX: 0.20, sink: 0.94, lean: 46, shoulder: -50, elbow: 94)
                .holding { [.ring($0.hand)] },
            .side(anchorX: 0.20, sink: 0.94, lean: 46, shoulder: -50, elbow: 2)
                .holding { [.ring($0.hand)] }
        ], signature: 1)
    ]

    // MARK: Dumbbells

    private static let dumbbells: [Strip] = [
        Strip(key: "arnold press", equipment: .dumbbells, facing: .front, panels: [
            .front(spread: 8, elbow: 158).holding { [.bells($0.hands)] },
            .front(spread: 170, elbow: 6).holding { [.bells($0.hands)] }
        ], signature: 1),

        Strip(key: "press", equipment: .dumbbells, facing: .front, panels: [
            .front(spread: 32, elbow: 118).holding { [.bells($0.hands)] },
            .front(spread: 172, elbow: 6).holding { [.bells($0.hands)] }
        ], signature: 1),

        Strip(key: "lateral raise", equipment: .dumbbells, facing: .front, panels: [
            .front(spread: 6, elbow: 5).holding { [.bells($0.hands)] },
            .front(spread: 82, elbow: 12).holding { [.bells($0.hands)] }
        ], signature: 1),

        Strip(key: "front raise", equipment: .dumbbells, facing: .side, panels: [
            .side(anchorX: 0.16, shoulder: 26, elbow: 24).holding { [.bells([$0.hand])] },
            .side(anchorX: 0.16, shoulder: 88, elbow: 8).holding { [.bells([$0.hand])] }
        ], signature: 1),

        Strip(key: "rear delt fly", equipment: .dumbbells, facing: .front, panels: [
            .front(sink: 0.92, spread: 10, elbow: 14).holding { [.bells($0.hands)] },
            .front(sink: 0.92, spread: 90, elbow: 10).holding { [.bells($0.hands)] }
        ], signature: 1),

        Strip(key: "curl", equipment: .dumbbells, facing: .side, panels: [
            .side(shoulder: 6, elbow: 34).holding { [.bells([$0.hand])] },
            .side(shoulder: 6, elbow: 140).holding { [.bells([$0.hand])] }
        ], signature: 1),

        Strip(key: "kickback", equipment: .dumbbells, facing: .side, panels: [
            .side(anchorX: 0.20, sink: 0.94, lean: 46, shoulder: -50, elbow: 94)
                .holding { [.bells([$0.hand])] },
            .side(anchorX: 0.20, sink: 0.94, lean: 46, shoulder: -50, elbow: 2)
                .holding { [.bells([$0.hand])] }
        ], signature: 1),

        Strip(key: "floor fly", equipment: .dumbbells, facing: .front, panels: [
            .supine(width: 1.0, kneeUp: 1.15, armAngle: 0).holding { [.bells([$0.hand])] },
            .supine(width: 1.0, kneeUp: 1.15, armAngle: -36).holding { [.bells([$0.hand])] }
        ], signature: 1),

        Strip(key: "around the world", equipment: .dumbbells, facing: .front, panels: [
            .front(spread: 88, elbow: 10).holding { [.bells($0.hands)] },
            .front(spread: 168, elbow: 8).holding { [.bells($0.hands)] }
        ], signature: 1),

        Strip(key: "shrug", equipment: .dumbbells, facing: .front, panels: [
            .front(spread: 22, elbow: 14, shrug: 0).holding { [.bells($0.hands)] },
            .front(spread: 4, elbow: 2, shrug: 0.62).holding { [.bells($0.hands)] }
        ], signature: 1),

        Strip(key: "upright row", equipment: .dumbbells, facing: .front, panels: [
            .front(spread: 8, elbow: 6).holding { [.bells($0.hands)] },
            .front(spread: 62, elbow: -78).holding { [.bells($0.hands)] }
        ], signature: 1),

        Strip(key: "extension", equipment: .dumbbells, facing: .side, panels: [
            .side(anchorX: 0.18, shoulder: 168, elbow: -128).holding { [.bells([$0.hand])] },
            .side(anchorX: 0.18, shoulder: 172, elbow: -8).holding { [.bells([$0.hand])] }
        ], signature: 0),

        Strip(key: "pullover", equipment: .dumbbells, facing: .front, panels: [
            .supine(width: 1.0, kneeUp: 1.15, armAngle: 0).holding { [.bells([$0.hand])] },
            .supine(width: 1.0, kneeUp: 1.15, armAngle: -54).holding { [.bells([$0.hand])] }
        ], signature: 1),

        Strip(key: "punch", equipment: .dumbbells, facing: .side, panels: [
            .side(anchorX: 0.16, shoulder: 58, elbow: 102, farArm: (56, 106))
                .holding { [.bells($0.hands)] },
            .side(anchorX: 0.16, shoulder: 86, elbow: 4, farArm: (56, 106))
                .holding { [.bells($0.hands)] }
        ], signature: 1),

        // Her own name for the barre move: forearms out level at the waist,
        // then straight arms to shoulder height. Signature 0 — panel 1 is the
        // front raise's finish almost exactly, and the platter carry is what
        // names the move.
        Strip(key: "platters", equipment: .dumbbells, facing: .side, panels: [
            .side(anchorX: 0.16, shoulder: 6, elbow: 84).holding { [.bells([$0.hand])] },
            .side(anchorX: 0.16, shoulder: 88, elbow: 4).holding { [.bells([$0.hand])] }
        ], signature: 0),

        // Standing tall, straight arms sweeping back and up. Upright, which is
        // the whole distinction from the kickback: same triceps, no hinge.
        Strip(key: "press-back", equipment: .dumbbells, facing: .side, panels: [
            .side(anchorX: 0.28, shoulder: -4, elbow: -2).holding { [.bells([$0.hand])] },
            .side(anchorX: 0.28, shoulder: -46, elbow: -4).holding { [.bells([$0.hand])] }
        ], signature: 1),

        // The arms hold still and the leg travels — "arms straight the whole
        // time" is the cue, so `armBend` is 6 rather than the builder's 16.
        // The bell is what separates this row from the bodyweight dead bug.
        Strip(key: "dead bug press", equipment: .dumbbells, facing: .front, panels: [
            .supine(width: 1.0, kneeUp: 1.30, armAngle: 0, armBend: 6)
                .holding { [.bells([$0.hand])] },
            .supine(width: 1.0, kneeUp: 0.35, armAngle: 0, armBend: 6)
                .holding { [.bells([$0.hand])] }
        ], signature: 1),

        // Elbow down on the deck with the forearm vertical, then pressed
        // straight up. Signature 0: the beam floor press already owns the
        // pressed-up frame, and the elbow on the floor names this one.
        Strip(key: "dumbbell floor press", equipment: .dumbbells, facing: .front, panels: [
            .supine(width: 1.0, kneeUp: 1.15, armAngle: 90, armBend: -76)
                .holding { [.bells([$0.hand])] },
            .supine(width: 1.0, kneeUp: 1.15, armAngle: 0, armBend: 4)
                .holding { [.bells([$0.hand])] }
        ], signature: 0),

        // Hinged and held there. The elbow drives back past the ribs and the
        // forearm hangs, so the weight finishes at the hip — the beam and ring
        // rows keep the upper arm still and swing the forearm forward instead,
        // because they pull to an implement rather than to the hip.
        Strip(key: "dumbbell row", equipment: .dumbbells, facing: .side, panels: [
            .side(anchorX: 0.29, sink: 0.92, lean: 52, shoulder: 8, elbow: 6)
                .holding { [.bells([$0.hand])] },
            .side(anchorX: 0.29, sink: 0.92, lean: 52, shoulder: -42, elbow: 48)
                .holding { [.bells([$0.hand])] }
        ], signature: 1),

        // Both hands meet on the spine, so the two bells land on the same point
        // and draw as one disc — which is what two weights pressed together
        // look like.
        Strip(key: "squeeze press", equipment: .dumbbells, facing: .front, panels: [
            .front(spread: 20, elbow: -153).holding { [.bells($0.hands)] },
            .front(spread: 190, elbow: 1).holding { [.bells($0.hands)] }
        ], signature: 0)
    ]

    // MARK: Kettlebell
    //
    // The bell hangs below the hand it is drawn at, so every pose here is
    // chosen with that in mind: at the bottom of a hinge the body sits on the
    // floor line, and nowhere does it cross a shin. That is why the hinges
    // carry a small negative `footAhead` — a bell drawn over the near shin is
    // a smudge, not a kettlebell.
    //
    // Every key is the full move name, because "deadlift", "goblet squat" and
    // "squat" already exist and would win by containment otherwise.

    private static let kettlebell: [Strip] = [
        Strip(key: "kettlebell deadlift", equipment: .kettlebell, facing: .side, panels: [
            .side(anchorX: 0.24, sink: 1.00, shoulder: 16, elbow: 4, footAhead: -0.4)
                .holding { [.bell($0.hand)] },
            .side(anchorX: 0.24, sink: 0.82, lean: 70, shoulder: 14, elbow: 4, footAhead: -0.4)
                .holding { [.bell($0.hand)] }
        ], signature: 1),

        // Elbows down and the bell in front of the chest. The arm folds tight
        // rather than reaching, which is the difference between a goblet hold
        // and the ring's press-out.
        Strip(key: "kettlebell goblet squat", equipment: .kettlebell, facing: .side, panels: [
            .side(anchorX: 0.21, sink: 1.00, shoulder: 20, elbow: 142)
                .holding { [.bell($0.hand)] },
            .side(anchorX: 0.21, sink: 0.34, lean: 26, shoulder: 10, elbow: 150)
                .holding { [.bell($0.hand)] }
        ], signature: 1),

        // A walk, so the stride and the free arm carry the change. The loaded
        // arm hangs plumb in both panels — that is the move, and swinging it
        // would draw a different one.
        Strip(key: "kettlebell carry", equipment: .kettlebell, facing: .side, panels: [
            .side(anchorX: 0.24, sink: 0.90, shoulder: 2, elbow: 2, farArm: (28, 10), split: 1.5)
                .holding { [.bell($0.hand)] },
            .side(anchorX: 0.24, sink: 0.84, shoulder: 2, elbow: 2, farArm: (-28, 10), split: 2.2)
                .holding { [.bell($0.hand)] }
        ], signature: 1),

        // Side-on, because the pass reads as front-then-behind: a front view
        // puts half the circle out of sight behind the back. The hips do not
        // move between the panels — only the arms — which is the cue.
        Strip(key: "kettlebell around the body", equipment: .kettlebell, facing: .side, panels: [
            .side(anchorX: 0.24, shoulder: 34, elbow: 52, farArm: (-30, -24))
                .holding { [.bell($0.hand)] },
            .side(anchorX: 0.24, shoulder: -30, elbow: -24, farArm: (34, 52))
                .holding { [.bell($0.hand)] }
        ], signature: 0),

        // The elbow goes back, not out: the upper arm draws back above the ribs
        // and the forearm hangs plumb, so the bell finishes behind the thigh
        // rather than on top of it.
        Strip(key: "kettlebell row", equipment: .kettlebell, facing: .side, panels: [
            .side(anchorX: 0.22, sink: 0.90, lean: 58, shoulder: 4, elbow: 4)
                .holding { [.bell($0.hand)] },
            .side(anchorX: 0.22, sink: 0.90, lean: 58, shoulder: -84, elbow: 68)
                .holding { [.bell($0.hand)] }
        ], signature: 1),

        // Front-on: wide feet and a bell hanging between them is the whole
        // shape, and side-on it collapses to the goblet squat. The arms angle
        // in so both hands meet on one handle.
        Strip(key: "kettlebell sumo squat", equipment: .kettlebell, facing: .front, panels: [
            .front(sink: 0.92, spread: -8, elbow: -4, stance: 2.2)
                .holding { [.bell(midpoint($0.hands))] },
            .front(sink: 0.16, spread: -8, elbow: -4, stance: 2.2)
                .holding { [.bell(midpoint($0.hands))] }
        ], signature: 1),

        // No "kettlebell" in the name and still the kettlebell's move. The back
        // foot is a little over a head behind and stays down: the builder has
        // no heel to raise, and a lifted back foot would draw a one-leg
        // deadlift.
        Strip(key: "kickstand deadlift", equipment: .kettlebell, facing: .side, panels: [
            .side(anchorX: 0.24, sink: 0.96, lean: 8, shoulder: 16, elbow: 4,
                  split: 1.3, footAhead: -0.3)
                .holding { [.bell($0.hand)] },
            .side(anchorX: 0.24, sink: 0.86, lean: 70, shoulder: 14, elbow: 4,
                  split: 1.3, footAhead: -0.3)
                .holding { [.bell($0.hand)] }
        ], signature: 1)
    ]

    // MARK: Single 10 lb dumbbell
    //
    // One dumbbell, held in both hands or one — never a pair. `Prop.bells`
    // takes a list of hands, so a single is one hand and the pairs are two.

    private static let singleDumbbell: [Strip] = [
        // The hips travel one way and the trunk slants the other, with the head
        // carrying it further — the same device the hip circle uses, which is
        // all `front` has for a lateral bend.
        Strip(key: "side bend", equipment: .singleDumbbell, facing: .front, panels: [
            .front(spread: 6, elbow: 4).holding { [.bells([$0.hand])] },
            .front(sink: 0.92, spread: 6, elbow: 4, tilt: -34, shift: 1.15)
                .holding { [.bells([$0.hand])] }
        ], signature: 1),

        // One dumbbell in both hands: the hands meet on the spine, so a single
        // bell draws at the meeting point. The arms are identical in both
        // panels because only the knee moves — the ribs stay stacked.
        Strip(key: "dumbbell march", equipment: .singleDumbbell, facing: .front, panels: [
            .front(spread: 20, elbow: -153).holding { [.bells([$0.hand])] },
            .front(spread: 20, elbow: -153, footLift: 1.7).holding { [.bells([$0.hand])] }
        ], signature: 1),

        // Deeper than the beam deadlift on purpose: a 10 lb dumbbell standing
        // on the floor is a short lever, and the hand has to get down to it.
        // The bell lands beside the foot, which is the cue.
        Strip(key: "suitcase deadlift", equipment: .singleDumbbell, facing: .side, panels: [
            .side(anchorX: 0.26, sink: 1.00, lean: 4, shoulder: 2, elbow: 2)
                .holding { [.bells([$0.hand])] },
            .side(anchorX: 0.26, sink: 0.45, lean: 58, shoulder: 2, elbow: 2)
                .holding { [.bells([$0.hand])] }
        ], signature: 1)
    ]

    // MARK: Bodyweight

    private static let bodyweight: [Strip] = [
        Strip(key: "dead bug", facing: .front, panels: [
            .supine(width: 1.0, kneeUp: 1.30, armAngle: 0),
            .supine(width: 1.0, kneeUp: 0.35, armAngle: -22)
        ], signature: 1),

        // A body angled from the floor to a counter is a wide, low shape, so
        // it takes the square panel for the same reason the quadruped does.
        Strip(key: "push-up", facing: .front, panels: [
            .side(anchorX: 0.42, sink: 0.96, lean: 38, shoulder: 62, elbow: 2)
                .holding { [.ledge(x: $0.hand.x - 0.02, y: $0.hand.y)] },
            .side(anchorX: 0.42, sink: 0.94, lean: 68, shoulder: 54, elbow: 66)
                .holding { [.ledge(x: $0.hand.x - 0.02, y: $0.hand.y + 0.05)] }
        ], signature: 1),

        Strip(key: "lunge", facing: .side, panels: [
            .side(sink: 1.00, shoulder: 62, elbow: 18, split: 0.2),
            .side(sink: 0.52, shoulder: 68, elbow: 20, split: 2.6)
        ], signature: 1),

        Strip(key: "glute bridge", facing: .front, panels: [
            .supine(width: 1.0, hipLift: 0, kneeUp: 1.15, armAngle: 92),
            .supine(width: 1.0, hipLift: 1.05, kneeUp: 1.15, armAngle: 92)
        ], signature: 1),

        Strip(key: "split squat", facing: .side, panels: [
            .side(sink: 0.98, shoulder: 20, elbow: -170, split: 2.2),
            .side(sink: 0.30, shoulder: 20, elbow: -170, split: 2.2)
        ], signature: 1),

        // A quadruped is wide and low. It gets the square panel for the same
        // reason a lateral raise does — the portrait frame cannot hold it at the
        // one figure scale, and shrinking the figure is the thing we are not
        // allowed to do.
        Strip(key: "bird dog", facing: .front, panels: [
            .quadruped(width: 1.0),
            .quadruped(width: 1.0, reach: true)
        ], signature: 1),

        Strip(key: "wall sit", facing: .side, panels: [
            .side(anchorX: 0.30, sink: 1.00).holding { _ in [.wall(x: 0.07)] },
            .side(anchorX: 0.30, sink: 0.15, footAhead: 1.1).holding { _ in [.wall(x: 0.07)] }
        ], signature: 1),

        Strip(key: "squat", facing: .side, panels: [
            .side(anchorX: 0.21, sink: 1.00, shoulder: 8, elbow: 6),
            .side(anchorX: 0.21, sink: 0.34, lean: 26, shoulder: 74, elbow: 16)
        ], signature: 1)
    ]

    // MARK: Walking pad
    //
    // Three panels because walking is a cycle: stride, pass, opposite stride.


    private static func incline(_ x: Double) -> Double {
        Anatomy.floorY + 0.9 * Anatomy.head * (x / 0.5)
    }

    // MARK: Flow

    private static let flow: [Strip] = [
        Strip(key: "bounce", facing: .front, panels: [
            .front(sink: 0.80, spread: 8, elbow: 34),
            .front(sink: 1.06, spread: 66, elbow: 10, footLift: 0.34)
        ], signature: 1),

        Strip(key: "arm swing", facing: .front, panels: [
            .front(spread: 80, elbow: 6),
            .front(spread: -16, elbow: 74)
        ], signature: 1),

        Strip(key: "shoulder roll", facing: .front, panels: [
            .front(spread: 40, elbow: 22, shrug: 0),
            .front(spread: 4, elbow: 2, shrug: 0.62)
        ], signature: 1),

        Strip(key: "neck release", facing: .front, panels: [
            .front(spread: 26, elbow: 16, tilt: 0),
            .front(spread: 6, elbow: 4, tilt: 62, shrug: 0.62)
        ], signature: 1),

        Strip(key: "spinal wave", facing: .side, panels: [
            .side(sink: 0.92, lean: 76, shoulder: 4, elbow: 4),
            .side(sink: 1.00, lean: -6, shoulder: 14, elbow: 8)
        ], signature: 0),

        Strip(key: "hip circle", facing: .front, panels: [
            .front(spread: 16, elbow: -184, shift: -0.85),
            .front(spread: 16, elbow: -184, shift: 0.85)
        ], signature: 0),

        Strip(key: "cat cow", facing: .front, panels: [
            .quadruped(width: 1.0, curve: -0.55, headDrop: -0.30),
            .quadruped(width: 1.0, curve: 0.55, headDrop: 0.55)
        ], signature: 0),

        Strip(key: "tapping", facing: .front, panels: [
            .front(spread: 44, elbow: 166),
            .front(spread: 14, elbow: 22)
        ], signature: 0),

        Strip(key: "twist", facing: .front, panels: [
            .front(spread: 62, elbow: 34, shift: -0.60),
            .front(spread: 62, elbow: -34, shift: 0.60)
        ], signature: 0),

        Strip(key: "circles", facing: .side, panels: [
            .side(anchorX: 0.13, shoulder: 38, elbow: 108, split: 0.7, footLift: 0.60),
            .side(anchorX: 0.13, shoulder: 104, elbow: -34, split: 0.7, footLift: 0.60)
        ], signature: 0),

        Strip(key: "chest opener", facing: .front, panels: [
            .front(spread: 44, elbow: 34),
            .front(spread: 104, elbow: -16)
        ], signature: 1),

        // The reel's warm-up.
        //
        // Every key here is *longer* than the existing key it would otherwise
        // collide with, because `byName` matches by containment against a list
        // sorted longest-first. "vertical arm swing" beats "arm swing";
        // "high knee circle" beats "circles"; "bent-over trunk twist" beats
        // "twist". Get that wrong and the move silently inherits a plate of a
        // different movement — which is worse than no plate, and is exactly
        // what closing the library was meant to end.

        // Arms out at shoulder height, rotating in place. The rotation itself is
        // not drawable — this figure has no forearm roll — so the forearms carry
        // it, angling up and then down through the same shoulder line.
        Strip(key: "corkscrew", facing: .front, panels: [
            .front(spread: 90, elbow: 28),
            .front(spread: 90, elbow: -28)
        ], signature: 0),

        // Both elbows square, one arm up and one down, swapping. `front` mirrors
        // its arms about the spine, so it cannot draw an asymmetric pair at all —
        // this is the one flow move that has to be side-on, where `farArm` gives
        // the second arm its own angles.
        Strip(key: "allen wrench", facing: .side, panels: [
            .side(anchorX: 0.24, shoulder: 158, elbow: -80, farArm: (24, 80)),
            .side(anchorX: 0.24, shoulder: 24, elbow: 80, farArm: (158, -80))
        ], signature: 0),

        // One arm at a time, which is the whole distinction from a slam dunk —
        // her correction. `front` mirrors its arms about the spine and so cannot
        // draw an asymmetric pair at all, which forces side-on, where `farArm`
        // gets its own angles. Straight arms here against the Allen wrench's
        // bent squares, so the two side-on flow plates stay distinguishable.
        //
        // It was also drawn symmetric *and* overhead first, which made its
        // signature identical to `arm circles` in the library list.
        Strip(key: "vertical arm swing", facing: .side, panels: [
            .side(anchorX: 0.24, shoulder: 172, elbow: 4, farArm: (10, 4)),
            .side(anchorX: 0.24, shoulder: 10, elbow: 4, farArm: (172, 4))
        ], signature: 0),

        // Hinged and rotating. The hinge is what separates this from the
        // standing twist, so both panels keep the lean and only the shoulders
        // turn.
        Strip(key: "bent-over trunk twist", facing: .front, panels: [
            .front(spread: 96, elbow: 8, shift: -0.55),
            .front(spread: 96, elbow: 8, shift: 0.55)
        ], signature: 0),

        // Both arms together and with intent — her words, and the reason this is
        // front-on where the vertical swing is side-on. The knee bend on the
        // second panel is the intensity: nobody drives down hard standing tall.
        Strip(key: "slam dunk", facing: .front, panels: [
            .front(sink: 1.0, spread: 170, elbow: 4),
            .front(sink: 0.78, spread: -16, elbow: 8)
        ], signature: 0),

        // Hands together through the whole arc, so the arms read as one lever
        // rather than two. Low across the body, then up over the far shoulder.
        Strip(key: "golf swing", facing: .front, panels: [
            .front(sink: 0.90, spread: 30, elbow: -18, shift: -0.45),
            .front(sink: 1.0, spread: 148, elbow: 14, shift: 0.40)
        ], signature: 1),

        // The two panels have to be *seen* to differ — a guard in the suite
        // measures the travel between consecutive panels against a head width,
        // and the first version of this moved the knee barely a tenth of one.
        // Knee up in front, then swung out and away, with the hip following.
        // Standing, then the knee up and the hip swung out after it. Two guards
        // in the suite shaped this: widening the stance lifted both feet clear
        // of the floor, and a large `shift` with a foot already raised put the
        // planted leg out of reach of the ground — the solver lands it short.
        // Half a head of shift is what a lifted leg leaves room for.
        Strip(key: "high knee circle", facing: .front, panels: [
            .front(spread: 20, elbow: 16),
            .front(spread: 20, elbow: 16, shift: 0.5, footLift: 1.7)
        ], signature: 0),

        Strip(key: "standing march", facing: .front, panels: [
            .front(spread: 14, elbow: 22),
            .front(spread: 26, elbow: 14, footLift: 1.7)
        ], signature: 1),

        Strip(key: "arm circles", facing: .front, panels: [
            .front(spread: 18, elbow: 8),
            .front(spread: 168, elbow: 6)
        ], signature: 1),

        Strip(key: "deep squat", facing: .side, panels: [
            .side(anchorX: 0.21, sink: 1.00, shoulder: 10, elbow: 8),
            .side(anchorX: 0.21, sink: 0.34, lean: 28, shoulder: 40, elbow: 96)
        ], signature: 1),

        Strip(key: "ankle rocking", facing: .side, panels: [
            .side(anchorX: 0.24, lean: -18, shoulder: 2, elbow: 4),
            .side(anchorX: 0.24, lean: 24, shoulder: 38, elbow: 18)
        ], signature: 1),

        Strip(key: "fold", facing: .side, panels: [
            .side(sink: 1.00, lean: 0, shoulder: 14, elbow: 8),
            .side(sink: 0.98, lean: 50, shoulder: 8, elbow: 6),
            .side(sink: 0.90, lean: 88, shoulder: 4, elbow: 4)
        ], signature: 2),

        // The sweep is frontal and both arms do the same thing, which is what
        // `front` draws. Three panels because the arc is the movement. The wide
        // panel is the signature rather than the overhead one: overhead at this
        // scale is `arm circles` drawn a second time.
        Strip(key: "sun breath", facing: .front, panels: [
            .front(spread: 6, elbow: 6),
            .front(spread: 88, elbow: 6),
            .front(spread: 172, elbow: 6)
        ], signature: 1)
    ]

    private static func midpoint(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / Double(points.count), y: sum.y / Double(points.count))
    }
}

// MARK: - The view

/// A move drawn as a strip of panels.
///
/// Takes its colours rather than reading `Palette`, because it is drawn inside
/// the timer's knockout — the same strip renders once in ink and once in oat,
/// in identical layout, and the boundary cuts through both.
struct MoveStrip: View {
    enum Style {
        /// One panel — the signature. A list row only has to answer *which
        /// move is this*.
        case signature
        /// Panel one and the signature.
        case pair
        /// Every panel, unnumbered. The timer wants the whole movement, but a
        /// row of mono numerals beside a running count is a second thing
        /// ticking on a screen that already has one.
        case strip
        /// Every panel, numbered. The size where the strip is studied.
        case full
    }

    let move: Move
    var style: Style = .signature
    var line: Color = Palette.ink
    var rule: Color = Palette.rule
    var label: Color = Palette.mute

    @Environment(\.displayScale) private var displayScale

    private var strip: Strip? { MovePlates.strip(for: move) }

    /// Whether this move has a strip at all, so a caller can leave the space
    /// out rather than reserving a box for a fallback glyph.
    static func exists(for move: Move) -> Bool { MovePlates.strip(for: move) != nil }

    /// Gutter, hairline, gutter — the mockup's answer for adjacent cells.
    static let gutter: CGFloat = 10
    /// Fixed at every size — the single most important number in this file. A
    /// hair under the icon weight (1.4pt) so the figure reads as lighter than
    /// the furniture around it rather than competing with it.
    static let stroke: CGFloat = 1.1
    /// Reserved under the panels for `01 02 03` in `.full`.
    private static let numeralBand: CGFloat = 16

    private var poses: [Pose] {
        guard let strip else { return [] }
        switch style {
        case .signature: return [strip.panels[strip.signature]]
        case .pair: return strip.pair
        case .strip, .full: return strip.panels
        }
    }

    var body: some View {
        Group {
            if let strip, !poses.isEmpty {
                Canvas { context, size in
                    draw(strip, poses: poses, in: &context, size: size)
                }
            } else {
                // Nothing honest to draw of the movement — but the kit is still
                // a fact, and a hole in an aligned column is worse than a glyph
                // that claims nothing about shape.
                Image(systemName: move.symbol)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(label)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ strip: Strip, poses: [Pose],
                      in context: inout GraphicsContext, size: CGSize) {
        let count = poses.count
        let band = style == .full ? Self.numeralBand : 0
        let dividers = CGFloat(count - 1) * (Self.gutter * 2 + 1 / displayScale)

        // Height is the size class; width follows from the facing. Fit to
        // whichever runs out first, so a three-panel front strip shrinks rather
        // than spilling out of its row.
        let byHeight = size.height - band
        let byWidth = (size.width - dividers) / (CGFloat(count) * strip.facing.width)
        let panelHeight = max(min(byHeight, byWidth), 1)
        let panelWidth = panelHeight * strip.facing.width
        let total = panelWidth * CGFloat(count) + dividers
        // The timer stacks the strip above the move's name and cue, so it hangs
        // off the same left margin as the type. The sheet centres it, because
        // there it is a plate on its own rather than the top line of a block.
        let originX = style == .strip ? 0 : (size.width - total) / 2
        let originY = (size.height - band - panelHeight) / 2

        let hairline = 1 / displayScale

        for (index, pose) in poses.enumerated() {
            let left = originX + CGFloat(index) * (panelWidth + Self.gutter * 2 + hairline)
            let frame = CGRect(x: left, y: originY, width: panelWidth, height: panelHeight)

            if index > 0 {
                var divider = Path()
                let x = left - Self.gutter - hairline / 2
                divider.move(to: CGPoint(x: x, y: originY))
                divider.addLine(to: CGPoint(x: x, y: originY + panelHeight))
                context.stroke(divider, with: .color(rule), lineWidth: hairline)
            }

            drawPanel(pose, facing: strip.facing, in: &context, frame: frame,
                      hairline: hairline)

            if style == .full {
                let numeral = Text(String(format: "%02d", index + 1))
                    .font(Face.mono(10))
                    .tracking(1.5)
                    .foregroundStyle(label)
                context.draw(numeral, at: CGPoint(x: frame.midX,
                                                  y: frame.maxY + band / 2), anchor: .center)
            }
        }
    }

    private func drawPanel(_ pose: Pose, facing: Facing,
                           in context: inout GraphicsContext,
                           frame: CGRect, hairline: CGFloat) {
        // Panel units are square: a side panel spans x in 0…0.5 and y in 0…1,
        // and its frame is half as wide as it is tall, so one unit is the same
        // length on both axes.
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: frame.minX + p.x / facing.width * frame.width,
                    y: frame.maxY - p.y * frame.height)
        }

        let body = StrokeStyle(lineWidth: Self.stroke, lineCap: .round, lineJoin: .round)
        let firm = StrokeStyle(lineWidth: max(hairline * 2, 1), lineCap: .butt)

        // The floor runs panel edge to panel edge, never clipped to the figure.
        // Three drawings standing on one line is what makes a strip a strip.
        var hasPad = false
        for prop in pose.props { if case .pad = prop { hasPad = true } }
        if !hasPad {
            var floor = Path()
            floor.move(to: point(CGPoint(x: 0, y: Anatomy.floorY)))
            floor.addLine(to: point(CGPoint(x: facing.width, y: Anatomy.floorY)))
            context.stroke(floor, with: .color(rule), lineWidth: hairline)
        }

        for prop in pose.props {
            switch prop {
            case .beam(let centre, let angle):
                // Side-on, a bar across the body points at the reader: it is a
                // short mark at the hands, not a bar. Drawn full length it lay
                // along a horizontal upper arm and the two merged into one pole
                // jutting out of the chest.
                guard facing == .front else {
                    // Side-on, a bar across the body lies **on** the silhouette
                    // — it is not a thing floating in front of her. Drawn as an
                    // upright cross-section it read as a stray capital I beside
                    // the ear; drawn as a short horizontal with an end tick,
                    // centred on the place it is actually held, it reads as a
                    // bar resting across her.
                    let h = Anatomy.head
                    let half = 0.40 * h
                    let tick = 0.30 * h
                    var mark = Path()
                    mark.move(to: point(CGPoint(x: centre.x - half, y: centre.y)))
                    mark.addLine(to: point(CGPoint(x: centre.x + half, y: centre.y)))
                    for end in [centre.x - half, centre.x + half] {
                        mark.move(to: point(CGPoint(x: end, y: centre.y - tick / 2)))
                        mark.addLine(to: point(CGPoint(x: end, y: centre.y + tick / 2)))
                    }
                    context.stroke(mark, with: .color(line), style: body)
                    continue
                }
                let radians = angle * .pi / 180
                let half = Anatomy.head            // 2 heads long, so 1 each way
                let axis = CGPoint(x: cos(radians) * half, y: sin(radians) * half)
                let a = CGPoint(x: centre.x - axis.x, y: centre.y - axis.y)
                let b = CGPoint(x: centre.x + axis.x, y: centre.y + axis.y)
                var bar = Path()
                bar.move(to: point(a))
                bar.addLine(to: point(b))
                // The ticks are the whole difference between a beam and an arm.
                let tick = CGPoint(x: -sin(radians) * 0.35 * Anatomy.head / 2,
                                   y: cos(radians) * 0.35 * Anatomy.head / 2)
                for end in [a, b] {
                    bar.move(to: point(CGPoint(x: end.x - tick.x, y: end.y - tick.y)))
                    bar.addLine(to: point(CGPoint(x: end.x + tick.x, y: end.y + tick.y)))
                }
                context.stroke(bar, with: .color(line), style: body)

            case .ring(let centre):
                let c = point(centre)
                // Side-on a ring is edge-on, so it narrows rather than staying
                // a circle. Same reasoning as the beam.
                let r = (facing == .front ? 0.375 : 0.26)
                        * Anatomy.head / facing.width * frame.width
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                      width: r * 2, height: r * 2)),
                               with: .color(line), style: body)

            case .bells(let hands):
                let r = 0.2 * Anatomy.head / facing.width * frame.width
                for hand in hands {
                    let c = point(hand)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                        width: r * 2, height: r * 2)),
                                 with: .color(line))
                }

            case .bell(let grip):
                // The grip is the hand; the weight hangs under it. Stroked, not
                // filled: at this size a bell is head-sized, and a disc that big
                // reads as a hole punched in the panel rather than as iron.
                let h = Anatomy.head
                let seat = CGPoint(x: grip.x, y: grip.y - 0.62 * h)
                let c = point(seat)
                let r = 0.30 * h / facing.width * frame.width
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                      width: r * 2, height: r * 2)),
                               with: .color(line), style: body)
                // Both ends sit on the body's rim and the arch passes through
                // the hand, so she is holding the handle rather than hovering
                // above it. Same weight as the body — this is held kit, not
                // furniture.
                var handle = Path()
                handle.move(to: point(CGPoint(x: seat.x - 0.22 * h, y: seat.y + 0.20 * h)))
                handle.addQuadCurve(
                    to: point(CGPoint(x: seat.x + 0.22 * h, y: seat.y + 0.20 * h)),
                    control: point(CGPoint(x: seat.x, y: grip.y + 0.42 * h)))
                context.stroke(handle, with: .color(line), style: body)

            case .pad(let rise):
                var deck = Path()
                deck.move(to: point(CGPoint(x: 0, y: Anatomy.floorY)))
                deck.addLine(to: point(CGPoint(x: facing.width,
                                               y: Anatomy.floorY + rise * Anatomy.head)))
                let tickEnd = CGPoint(x: 0.35 * Anatomy.head, y: Anatomy.floorY - 0.35 * Anatomy.head)
                deck.move(to: point(CGPoint(x: 0, y: Anatomy.floorY)))
                deck.addLine(to: point(tickEnd))
                context.stroke(deck, with: .color(rule), style: firm)

            case .wall(let x):
                var wall = Path()
                wall.move(to: point(CGPoint(x: x, y: Anatomy.floorY)))
                wall.addLine(to: point(CGPoint(x: x, y: 0.95)))
                context.stroke(wall, with: .color(rule), style: firm)

            case .ledge(let x, let y):
                // A counter edge, not a crate: a short top and a short return.
                let run = min(0.9 * Anatomy.head, facing.width - x)
                var ledge = Path()
                ledge.move(to: point(CGPoint(x: x + run, y: y)))
                ledge.addLine(to: point(CGPoint(x: x, y: y)))
                ledge.addLine(to: point(CGPoint(x: x, y: max(y - 1.1 * Anatomy.head,
                                                            Anatomy.floorY))))
                context.stroke(ledge, with: .color(rule), style: firm)
            }
        }

        var figure = Path()
        if let curve = pose.spineCurve, curve != 0 {
            let hip = point(pose.hip), neck = point(pose.neck)
            let mid = CGPoint(x: (hip.x + neck.x) / 2,
                              y: (hip.y + neck.y) / 2
                                 - CGFloat(curve) * CGFloat(Anatomy.head) * frame.height)
            figure.move(to: hip)
            figure.addQuadCurve(to: neck, control: mid)
        } else {
            figure.move(to: point(pose.hip))
            figure.addLine(to: point(pose.neck))
        }
        for limb in pose.arms + pose.legs {
            guard let first = limb.first else { continue }
            figure.move(to: point(first))
            for joint in limb.dropFirst() { figure.addLine(to: point(joint)) }
        }

        // A foot at every sole. Without one a figure floats above its own floor
        // line, and two legs seen from the front are a single stroke.
        let toe = 0.42 * Anatomy.head
        for leg in pose.legs {
            guard let sole = leg.last else { continue }
            // Side-on the figure faces +x and so does every toe, always.
            //
            // The first version pointed the toe away from the knee, to make a
            // split stance read as one foot forward and one back. That is wrong
            // in every pose where the knee travels ahead of the foot — a squat,
            // a hinge, a lunge, a walking stride — which is most of the library,
            // and it drew the feet on backwards.
            let forward: Double = facing == .front
                ? (sole.x >= pose.hip.x ? 1 : -1)
                : 1
            figure.move(to: point(sole))
            figure.addLine(to: point(CGPoint(x: sole.x + toe * forward,
                                             y: sole.y + toe * 0.42)))
        }
        context.stroke(figure, with: .color(line), style: body)

        // A filled disc, not a stroked circle: at row size a stroked head fills
        // in optically anyway, and filled it gives the eye one solid anchor to
        // land on while scanning a list.
        let centre = point(pose.head)
        let r = Anatomy.radius / facing.width * frame.width
        context.fill(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r,
                                            width: r * 2, height: r * 2)),
                     with: .color(line))
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MoveLibrary.all) { move in
                HStack(spacing: 12) {
                    MoveStrip(move: move, style: .pair)
                        .frame(width: 120, height: 76)
                    Text(move.name).font(.almanacBody).foregroundStyle(Palette.ink)
                    Spacer()
                }
                Rule()
            }
        }
        .padding(20)
    }
    .background(Palette.oat)
}
