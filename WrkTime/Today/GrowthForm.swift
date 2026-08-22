import SwiftUI

/// Twelve nesting rings, one per week of the block.
///
/// The shape is generative but deterministic: every ring is the same base
/// circle pushed around by a fixed distortion field, so the form is stable
/// across launches and devices — you are looking at *your* season, not a new
/// doodle each time. A week you have lived is drawn in moss; a week still ahead
/// is a sage hairline — the futures sharing one wobble phase so they nest
/// rather than tangle, taking their own shape only once lived. One mark is one
/// finished session: a moss dot set on its week's ring, the latest in
/// saffron-ink with a fine halo. A workout of her own that was real work is a
/// thin tick hanging inward from the ring — present, and unmistakably not a
/// mark. Her vocabulary, chosen off the mark review's comparison sheet.
struct GrowthForm: View {
    /// Finished sessions per week, index 0 being week one.
    ///
    /// Per week, not a total. A total had to be spread across the rings by
    /// filling earlier weeks first, which meant the form could never show a
    /// gap — a session done in week three after a quiet week two would draw on
    /// ring two. A season document that cannot show a quiet week is not a
    /// document. Nothing is said about the gap; it is simply the truth.
    let marksByWeek: [Int]
    let weeks: Int
    let currentWeek: Int

    /// Her own workouts per week — extra sessions and routines she ran that
    /// were long enough to be real work (`RoutineRuns.substantialSeconds`) —
    /// as **positions**, not counts. Each tick sits just past the dot of the
    /// session it was performed after, in dot-slot units from
    /// `tickPositions`, so the ring reads chronologically: a Tuesday double
    /// day is a dot with its tick beside it, not a pile of ticks at the end
    /// of the week. Never a mark — nothing counts them.
    var minorsByWeek: [[Double]] = []

    /// Total finished sessions across the block.
    var marks: Int { marksByWeek.reduce(0, +) }
    /// Sessions the plan asks for each week. Six closes a ring.
    var sessionsPerWeek: Int = 6
    /// Seeds the distortion field for this block.
    ///
    /// Without it the phase came from the week index alone, which meant week
    /// three of your first block, week three of your second, and week three of
    /// anyone else's were the identical curve. The determinism was right; the
    /// identity was missing. This is what makes the drawing a portrait rather
    /// than a decoration — and what makes a finished season worth keeping.
    var blockSeed: UInt64 = 0
    /// Draw only the weeks lived so far, spread across the whole canvas — the
    /// thumbnail treatment. At 84pt on Today, twelve rings and their future
    /// hairlines read as a cramped thicket; the shape of the season to come is
    /// Season's business, so the thumbnail keeps just the season so far.
    var livedWeeksOnly = false

    /// Which day of the current week today is, 0–6, or nil on a form with no
    /// live week to speak of (a finished season, a preview). Today's seventh
    /// of the current ring is stroked in saffron — the one place on the
    /// drawing that means *now* rather than *done*, which is exactly what
    /// saffron is for.
    var dayOfWeek: Int? = nil

    /// The distortion phase for a week. One definition — the ring and the marks
    /// laid on it must agree exactly.
    private func phase(forWeek week: Int) -> Double {
        let goldenAngle = 2.39996
        return Double((blockSeed &+ UInt64(week)) % 997) * goldenAngle
    }

    /// The phase a week actually *draws* with. Weeks still ahead all share the
    /// block's own phase: rings wobbling in unison at proportional radii
    /// cannot cross, so the future nests instead of tangling — the review
    /// called the old independent phases "scribble", and it was right. A week
    /// takes on its own shape when she starts living it.
    private func drawPhase(forWeek week: Int) -> Double {
        phase(forWeek: week <= currentWeek ? week : 0)
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            // The wobble pushes a ring up to `maxWobble` beyond its nominal
            // radius, so the outermost ring has to be drawn that much smaller
            // or it leaves the canvas. It did: at 84pt on Today the overflow
            // was about four points and invisible, but at full width on Season
            // the same 11% clipped the form flat on both sides.
            let inset = min(size.width, size.height) / 2 - 6
            let maxRadius = inset / (1 + Self.maxWobble)
            let innerRadius = maxRadius * 0.16

            let shown = livedWeeksOnly ? min(max(currentWeek, 1), weeks) : weeks

            // Marks scale with the **ring spacing** — the one number that
            // says how much room this rendering of the form actually has.
            // Absolute sizes were wrong twice over: hero-sized dots on the
            // 84pt thumbnail, then, scaled by canvas alone, seed-sized dots
            // on the lived-only hero whose three rings had half the screen
            // between them. Spacing gets both right, and every other case,
            // from one definition.
            let spacing = livedWeeksOnly
                ? maxRadius / Double(shown)
                : (maxRadius - innerRadius) / Double(max(shown - 1, 1))
            // Every ring's nominal radius, resolved before anything is drawn,
            // so a mark can ask how much room it has before it reaches the
            // ring on either side of its own.
            let radii: [Double] = (1...shown).map { week in
                if livedWeeksOnly {
                    // Spread from the centre so the newest ring always sits at
                    // the rim — a one-week season is one full-size ring, not a
                    // dot lost in blank canvas.
                    return maxRadius * Double(week) / Double(shown)
                }
                let t = Double(week - 1) / Double(max(weeks - 1, 1))
                return innerRadius + (maxRadius - innerRadius) * t
            }

            for week in 1...shown {
                let radius = radii[week - 1]
                let inward = week > 1 ? radii[week - 2] : nil
                let outward = week < shown ? radii[week] : nil
                let lived = week <= currentWeek
                let path = ringPath(center: center, radius: radius, seed: week)

                context.stroke(
                    path,
                    // A week still ahead was drawn at sage 45% — 1.34:1 on oat,
                    // which is not faint, it is absent. Raised until the shape
                    // of the season to come is actually visible.
                    with: .color(lived ? Palette.moss : Palette.sage.opacity(0.85)),
                    lineWidth: lived ? 1.3 : 0.8
                )

                // Today, on the ring being lived: its seventh of the current
                // week's circumference, over the moss, slightly heavier. The
                // same angular origin as the marks, so the segment and the
                // dots tell one story about where the week is.
                if week == currentWeek, let day = dayOfWeek, (0..<7).contains(day) {
                    let start = -Double.pi / 2 + Double(day) / 7 * 2 * .pi
                    context.stroke(
                        ringSegment(center: center, radius: radius, seed: week,
                                    from: start, to: start + 2 * .pi / 7),
                        with: .color(Palette.saffron),
                        lineWidth: 1.8
                    )
                }

                let marksThisWeek = marksIn(week: week)
                let minors = minorsIn(week: week)
                // The divisor grows with what the week actually holds, so a
                // heavy week spreads rather than stacking.
                let slots = max(sessionsPerWeek, marksThisWeek)

                // Ticks first, dots over them: a dot's knockout may sit on a
                // tick's end, never the other way round — a mark is the thing
                // that must never be diminished.
                if !minors.isEmpty {
                    drawMinorMarks(context: context, center: center, radius: radius,
                                   seed: week, positions: minors, slots: slots,
                                   inward: inward, outward: outward,
                                   spacing: spacing)
                }

                if marksThisWeek > 0 {
                    drawMarks(context: context, center: center, radius: radius,
                              seed: week, count: marksThisWeek, slots: slots,
                              isCurrent: week == currentWeek,
                              inward: inward, outward: outward,
                              spacing: spacing)
                }
            }

            // The seed at the middle — day one, still there.
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)),
                with: .color(Palette.ink)
            )
        }
        // A `Canvas` is not an accessibility element on its own, so the label
        // had nothing to attach to. The value carries what the drawing actually
        // encodes — this week's progress toward six — which the old label left
        // out entirely.
        .accessibilityElement()
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel("Season growth form")
        .accessibilityValue({
            var base = marks == 0
                ? "No marks yet. Week \(currentWeek) of \(weeks)."
                : "\(marks.marksPhrase). Week \(currentWeek) of \(weeks), \(marksIn(week: currentWeek)) of \(sessionsPerWeek) this week."
            if let dayOfWeek { base += " Day \(dayOfWeek + 1) of the week." }
            let minor = minorsByWeek.reduce(0) { $0 + $1.count }
            guard minor > 0 else { return base }
            return base + " Plus \(minor) \(minor == 1 ? "workout" : "workouts") of your own."
        }())
    }

    // MARK: - Geometry

    /// How many marks belong to a given week — the week it actually happened in.
    ///
    /// Uncapped, at her ask: a week where she picked up a missed session or
    /// took the next one early really did finish six, and the count says 6 of
    /// 5. The drawing was already built for it — `slots` below grows with the
    /// week — but a `min` here flattened every heavy week back to the target
    /// before the slots could spread.
    private func marksIn(week: Int) -> Int {
        guard week >= 1, week <= marksByWeek.count else { return 0 }
        return marksByWeek[week - 1]
    }

    /// One tick per extra she did, not one tick meaning "some". Bounded only
    /// by sanity — past a dozen the ring is a necklace and the count belongs
    /// in the rows, not the drawing.
    private func minorsIn(week: Int) -> [Double] {
        guard week >= 1, week <= minorsByWeek.count else { return [] }
        return Array(minorsByWeek[week - 1].prefix(12))
    }

    /// Where a week's ticks sit, in dot-slot units, from when things happened.
    ///
    /// An extra follows the session it was performed after: its position is
    /// just past that session's dot. Extras from the same day cluster close;
    /// a different day after the same session steps wider — her spec, almost
    /// word for word. One done before any session that week hangs just before
    /// the first dot. Everything is clamped inside the gap so a heavy day
    /// cannot run its ticks into the next session's dot.
    ///
    /// Static and pure, because three facts have to keep agreeing: what the
    /// views bin, what this places, and what the tests assert. `nonisolated`
    /// is the honest declaration of that purity — living on a View, it would
    /// otherwise inherit `@MainActor`, which the app never noticed (views call
    /// it on the main actor) and the tests crashed on (they do not). An
    /// executor assertion inside a geometry function is the isolation system
    /// pointing out that the function never needed an actor at all.
    nonisolated static func tickPositions(sessions: [Date], extras: [Date],
                                          calendar: Calendar = .current) -> [Double] {
        let ordered = sessions.sorted()
        var dayOrder: [Int: [Date]] = [:]
        var withinDay: [Int: [Date: Int]] = [:]

        return extras.sorted().map { time in
            let after = ordered.filter { $0 <= time }.count
            let day = calendar.startOfDay(for: time)

            var days = dayOrder[after] ?? []
            if !days.contains(day) { days.append(day) }
            dayOrder[after] = days
            let dayIndex = days.firstIndex(of: day) ?? 0

            let inDay = withinDay[after]?[day] ?? 0
            withinDay[after, default: [:]][day] = inDay + 1

            let spread = Double(dayIndex) * 0.30 + Double(inDay) * 0.14
            guard after > 0 else {
                // Before the week's first session: tucked ahead of its dot.
                return -0.55 + min(spread, 0.38)
            }
            return Double(after - 1) + 0.40 + min(spread, 0.45)
        }
    }

    /// The radius of a week's ring at a given angle.
    ///
    /// One definition, used by both the ring and the marks laid on it — they
    /// have to agree exactly or the marks float off the line.
    ///
    /// The amplitudes carry the whole character. At the original 0.035/0.022
    /// the eccentricity only read while most rings were nearly invisible; once
    /// every week was drawn at legible contrast, twelve faintly-wobbling rings
    /// nested together went back to reading as concentric tree rings. Pushed
    /// until each ring is its own shape even in a dense stack.
    /// The two wobble amplitudes, and the most they can add when both peak
    /// together. Named so the canvas can reserve exactly that much room —
    /// hard-coding the sum in two places is how the clipping got in.
    private static let wobbleA = 0.068
    private static let wobbleB = 0.042
    static let maxWobble = wobbleA + wobbleB

    private func ringRadius(_ radius: Double, at angle: Double, phase: Double) -> Double {
        let wobble =
            sin(angle * 2 + phase) * Self.wobbleA +
            sin(angle * 3 - phase * 0.7) * Self.wobbleB
        return radius * (1 + wobble)
    }

    private func ringPath(center: CGPoint, radius: Double, seed: Int) -> Path {
        let phase = drawPhase(forWeek: seed)
        let steps = 180

        var path = Path()
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let r = ringRadius(radius, at: angle, phase: phase)
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// A stretch of a ring between two angles, on the same wobble as the ring
    /// itself — the today segment must sit exactly on the week it highlights,
    /// or it reads as a second ring starting.
    private func ringSegment(center: CGPoint, radius: Double, seed: Int,
                             from start: Double, to end: Double) -> Path {
        let phase = drawPhase(forWeek: seed)
        let steps = 26
        var path = Path()
        for step in 0...steps {
            let angle = start + (end - start) * Double(step) / Double(steps)
            let r = ringRadius(radius, at: angle, phase: phase)
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// How far a mark may reach either side of its own ring before it starts
    /// touching the ring inside or outside it.
    ///
    /// Measured at the mark's **own angle**, not from the nominal radii: every
    /// ring wobbles on its own phase, so two rings a comfortable twelve points
    /// apart on average pass much closer than that somewhere, and a
    /// fixed-length notch drawn right there bridged the two. A mark belongs to
    /// one week; touching two rings makes it ambiguous which.
    ///
    /// Each ring claims at most `neighbourShare` of the gap, so even two marks
    /// facing each other across the narrowest point leave daylight between.
    private static let markReach = 4.5
    private static let neighbourShare = 0.4
    /// Below this a mark stops reading as a mark at all, so a very tight stack
    /// gets a short notch rather than none.
    private static let markFloor = 1.2

    private func reach(at angle: Double, radius: Double, seed: Int,
                       inward: Double?, outward: Double?) -> Double {
        let r = ringRadius(radius, at: angle, phase: drawPhase(forWeek: seed))
        var limit = Self.markReach
        if let inward {
            let neighbour = ringRadius(inward, at: angle, phase: drawPhase(forWeek: seed - 1))
            limit = min(limit, (r - neighbour) * Self.neighbourShare)
        }
        if let outward {
            let neighbour = ringRadius(outward, at: angle, phase: drawPhase(forWeek: seed + 1))
            limit = min(limit, (neighbour - r) * Self.neighbourShare)
        }
        return max(limit, Self.markFloor)
    }

    /// Marks sit at even intervals around their ring, starting from the top and
    /// rotating with the week so they never stack into a straight spoke.
    ///
    /// A mark is a **dot set on the ring** — her choice from the mark review's
    /// comparison sheet. The crossing notch had two faults the mocks made
    /// undeniable: four sessions at even slots around the centre dot drew a
    /// crosshair, and the vocabulary needed a size fight with the extras'
    /// ticks that it was losing at 84pt. A dot cannot form a reticle, and it
    /// outweighs a thin tick at any size without trying.
    private func drawMarks(context: GraphicsContext, center: CGPoint, radius: Double,
                           seed: Int, count: Int, slots: Int, isCurrent: Bool,
                           inward: Double?, outward: Double?, spacing: Double) {
        let phase = drawPhase(forWeek: seed)

        for mark in 0..<count {
            let angle = -Double.pi / 2
                + (Double(mark) / Double(slots)) * 2 * .pi
                + Double(seed) * 0.35
            let r = ringRadius(radius, at: angle, phase: phase)
            let room = reach(at: angle, radius: radius, seed: seed,
                             inward: inward, outward: outward)
            let point = CGPoint(x: center.x + cos(angle) * r,
                                y: center.y + sin(angle) * r)

            let isLatest = isCurrent && mark == count - 1
            // Sized off the ring spacing, then held back by the per-angle
            // room so a tight passage still shrinks what sits in it.
            let wanted = spacing * (isLatest ? 0.21 : 0.19)
            let dot = max(0.9, min(min(wanted, isLatest ? 4.6 : 4.2), room * 1.1))
            let pad = max(0.6, min(spacing * 0.08, 1.7))

            // Knocked out of the ring, so the dot is a seed on the line and
            // not a thickening of it.
            context.fill(Path(ellipseIn: CGRect(x: point.x - dot - pad, y: point.y - dot - pad,
                                                width: (dot + pad) * 2, height: (dot + pad) * 2)),
                         with: .color(Palette.oat))
            // The most recent mark in saffron-ink — ink, not plain saffron,
            // which was 1.82:1 on oat: the least visible mark on the form when
            // it wants to be the most findable — with a fine halo ring, so it
            // is told apart by form as well as colour.
            context.fill(Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot,
                                                width: dot * 2, height: dot * 2)),
                         with: .color(isLatest ? Palette.saffronInk : Palette.moss))
            if isLatest {
                let gap = max(0.9, min(spacing * 0.12, 2.4))
                let halo = min(dot + gap, max(room, dot + 0.8))
                context.stroke(
                    Path(ellipseIn: CGRect(x: point.x - halo, y: point.y - halo,
                                           width: halo * 2, height: halo * 2)),
                    with: .color(Palette.saffronInk),
                    lineWidth: max(0.6, min(spacing * 0.065, 1.2))
                )
            }
        }
    }

    /// Her own workouts, told apart from marks by *form*: a small bead sitting
    /// **on** the ring, half a slot along from where the marks sit.
    ///
    /// Her own workouts are **thin ticks hanging inward from the ring** — her
    /// choice, paired with the dots: sessions are seeds set on the line, her
    /// own work is a fine tally beneath it. Subordinate by shape and by
    /// weight, so it can never win the size fight the old bead was winning at
    /// 84pt; one-sided and half-slot offset, so no arrangement of them can
    /// form a crosshair.
    private func drawMinorMarks(context: GraphicsContext, center: CGPoint, radius: Double,
                                seed: Int, positions: [Double], slots: Int,
                                inward: Double?, outward: Double?, spacing: Double) {
        let phase = drawPhase(forWeek: seed)

        for position in positions {
            // Positions are in dot-slot units from `tickPositions`: a tick
            // sits just past the session it followed, same-day extras close
            // together, so the ring reads as the week actually went.
            let angle = -Double.pi / 2
                + (position / Double(slots)) * 2 * .pi
                + Double(seed) * 0.35
            let r = ringRadius(radius, at: angle, phase: phase)
            let room = reach(at: angle, radius: radius, seed: seed,
                             inward: inward, outward: outward)
            let length = max(0.9, min(min(spacing * 0.24, 5.0), room * 0.8))

            var stroke = Path()
            stroke.move(to: CGPoint(x: center.x + cos(angle) * r,
                                    y: center.y + sin(angle) * r))
            stroke.addLine(to: CGPoint(x: center.x + cos(angle) * (r - length),
                                       y: center.y + sin(angle) * (r - length)))
            context.stroke(stroke, with: .color(Palette.moss),
                           style: StrokeStyle(lineWidth: max(0.6, min(spacing * 0.07, 1.3)),
                                              lineCap: .round))
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        // Week two, mid-week, with two workouts of her own alongside.
        GrowthForm(marksByWeek: [6, 5] + Array(repeating: 0, count: 10),
                   weeks: 12, currentWeek: 2,
                   minorsByWeek: [[0.42, 0.56], [1.4]] + Array(repeating: [], count: 10),
                   blockSeed: 4816)
            .frame(height: 150)
        // A season with a quiet week three in it — the case the old model
        // could not represent at all — and a heavy fortnight of extras, which
        // is the case the marker had to stop crowding.
        GrowthForm(marksByWeek: [6, 6, 0, 5, 6, 6, 4, 6, 6, 3] + [0, 0],
                   weeks: 12, currentWeek: 10,
                   minorsByWeek: [[0.4], [], [0.4, 0.54, 1.7], [2.4, 2.54], [], [0.4],
                                  [1.4, 1.54, 3.4], [0.4, 2.7], [1.4], [0.4, 0.54]] + [[], []],
                   blockSeed: 90210)
            .frame(height: 150)
        // The thumbnail, where the crowding showed first.
        GrowthForm(marksByWeek: [4, 3], weeks: 12, currentWeek: 2,
                   minorsByWeek: [[0.4, 0.54, 1.7], [0.4, 1.4]], sessionsPerWeek: 4,
                   blockSeed: 4816, livedWeeksOnly: true)
            .frame(width: 84, height: 84)
    }
    .padding(30)
    .background(Palette.oat)
}
