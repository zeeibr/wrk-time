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

    /// Every library move to its drawing, resolved once at launch. The library
    /// is fixed, so the longest-key-wins rule that makes "split squat" beat
    /// "squat" runs here rather than on every lookup.
    private static let byName: [String: Strip] = {
        var table: [String: Strip] = [:]
        for move in MoveLibrary.all {
            let key = MovePreference.key(move.name)
            if let strip = sorted.first(where: { key.contains($0.key) }) {
                table[key] = strip
            }
        }
        return table
    }()


    private static let sorted: [Strip] = all.sorted { $0.key.count > $1.key.count }

    static let all: [Strip] = beam + rings + dumbbells + bodyweight + pad + flow

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

        Strip(key: "hip thrust", equipment: .beam, facing: .front, panels: [
            .supine(width: 1.0, hipLift: 0, shoulderLift: 1.15, kneeUp: 1.15, armAngle: 92)
                .holding { [.beam($0.hip), .ledge(x: 0.34, y: Anatomy.floorY + 0.30 * Anatomy.head + 1.15 * Anatomy.head)] },
            .supine(width: 1.0, hipLift: 1.15, shoulderLift: 1.15, kneeUp: 1.15, armAngle: 92)
                .holding { [.beam($0.hip), .ledge(x: 0.34, y: Anatomy.floorY + 0.30 * Anatomy.head + 1.15 * Anatomy.head)] }
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

        Strip(key: "ring deadlift", equipment: .rings, facing: .side, panels: [
            .side(sink: 0.86, lean: 34, shoulder: 6, elbow: 4).holding { [.ring($0.hand)] },
            .side(sink: 0.74, lean: 70, shoulder: 4, elbow: 4).holding { [.ring($0.hand)] }
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

        Strip(key: "punch", equipment: .dumbbells, facing: .side, panels: [
            .side(anchorX: 0.16, shoulder: 58, elbow: 102, farArm: (56, 106))
                .holding { [.bells($0.hands)] },
            .side(anchorX: 0.16, shoulder: 86, elbow: 4, farArm: (56, 106))
                .holding { [.bells($0.hands)] }
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

    private static let pad: [Strip] = [
        Strip(key: "incline walk", equipment: .walkingPad, facing: .side, panels: [
            .side(sink: 0.98, lean: 8, shoulder: 44, elbow: 14, split: 2.3, groundY: incline)
                .holding { _ in [.pad(rise: 0.9)] },
            .side(sink: 0.99, lean: 8, shoulder: 4, elbow: 8, split: 0.15, groundY: incline)
                .holding { _ in [.pad(rise: 0.9)] },
            .side(sink: 0.98, lean: 8, shoulder: -34, elbow: 12, split: 2.3, groundY: incline)
                .holding { _ in [.pad(rise: 0.9)] }
        ], signature: 0),

        Strip(key: "walk", equipment: .walkingPad, facing: .side, panels: [
            .side(sink: 0.99, shoulder: 42, elbow: 14, split: 2.3).holding { _ in [.pad(rise: 0)] },
            .side(sink: 1.00, shoulder: 4, elbow: 8, split: 0.15).holding { _ in [.pad(rise: 0)] },
            .side(sink: 0.99, shoulder: -34, elbow: 12, split: 2.3).holding { _ in [.pad(rise: 0)] }
        ], signature: 0)
    ]

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

        Strip(key: "fold", facing: .side, panels: [
            .side(sink: 1.00, lean: 0, shoulder: 14, elbow: 8),
            .side(sink: 0.98, lean: 50, shoulder: 8, elbow: 6),
            .side(sink: 0.90, lean: 88, shoulder: 4, elbow: 4)
        ], signature: 2)
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
