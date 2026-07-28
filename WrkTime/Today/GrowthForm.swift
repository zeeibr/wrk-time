import SwiftUI

/// Twelve nesting rings, one per week of the block.
///
/// The shape is generative but deterministic: every ring is the same base
/// circle pushed around by a fixed distortion field, so the form is stable
/// across launches and devices — you are looking at *your* season, not a new
/// doodle each time. A week you have lived is drawn in moss; a week still ahead
/// is a sage hairline, so the shape you are growing into is visible from day
/// one. One mark is one finished session: a short radial notch crossing its own
/// week's ring.
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

    /// The distortion phase for a week. One definition — the ring and the marks
    /// laid on it must agree exactly.
    private func phase(forWeek week: Int) -> Double {
        let goldenAngle = 2.39996
        return Double((blockSeed &+ UInt64(week)) % 997) * goldenAngle
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

            for week in 1...weeks {
                let t = Double(week - 1) / Double(max(weeks - 1, 1))
                let radius = innerRadius + (maxRadius - innerRadius) * t
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

                let marksThisWeek = marksIn(week: week)
                if marksThisWeek > 0 {
                    drawMarks(context: context, center: center, radius: radius,
                              seed: week, count: marksThisWeek,
                              isCurrent: week == currentWeek)
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
        .accessibilityValue(
            marks == 0
                ? "No marks yet. Week \(currentWeek) of \(weeks)."
                : "\(marks.marksPhrase). Week \(currentWeek) of \(weeks), \(marksIn(week: currentWeek)) of \(sessionsPerWeek) this week."
        )
    }

    // MARK: - Geometry

    /// How many marks belong to a given week — the week it actually happened in.
    private func marksIn(week: Int) -> Int {
        guard week >= 1, week <= marksByWeek.count else { return 0 }
        return min(marksByWeek[week - 1], sessionsPerWeek)
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
        let phase = phase(forWeek: seed)
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

    /// Marks sit at even intervals around their ring, starting from the top and
    /// rotating with the week so they never stack into a straight spoke.
    private func drawMarks(context: GraphicsContext, center: CGPoint, radius: Double,
                           seed: Int, count: Int, isCurrent: Bool) {
        let phase = phase(forWeek: seed)

        for mark in 0..<count {
            let angle = -Double.pi / 2
                + (Double(mark) / Double(sessionsPerWeek)) * 2 * .pi
                + Double(seed) * 0.35
            let r = ringRadius(radius, at: angle, phase: phase)

            let inner = CGPoint(x: center.x + cos(angle) * (r - 4.5),
                                y: center.y + sin(angle) * (r - 4.5))
            let outer = CGPoint(x: center.x + cos(angle) * (r + 4.5),
                                y: center.y + sin(angle) * (r + 4.5))

            var stroke = Path()
            stroke.move(to: inner)
            stroke.addLine(to: outer)

            // The most recent mark, told apart by *form* as well as colour: a
            // longer notch with a terminal dot, so it reads as a pin rather
            // than a tick. It used to be plain saffron, which was both 1.82:1
            // on oat — the least visible mark on the form, when it wants to be
            // the most findable — and a quiet contradiction of the rule that
            // saffron means live. A finished session is not live.
            let isLatest = isCurrent && mark == count - 1
            context.stroke(
                stroke,
                with: .color(isLatest ? Palette.saffronInk : Palette.moss),
                style: StrokeStyle(lineWidth: isLatest ? 2.4 : 1.6, lineCap: .round)
            )
            if isLatest {
                let dot = CGRect(x: outer.x - 2.5, y: outer.y - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: dot), with: .color(Palette.saffronInk))
            }
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        // Week two, mid-week.
        GrowthForm(marksByWeek: [6, 5] + Array(repeating: 0, count: 10),
                   weeks: 12, currentWeek: 2, blockSeed: 4816)
            .frame(height: 150)
        // A season with a quiet week three in it — the case the old model
        // could not represent at all.
        GrowthForm(marksByWeek: [6, 6, 0, 5, 6, 6, 4, 6, 6, 3] + [0, 0],
                   weeks: 12, currentWeek: 10, blockSeed: 90210)
            .frame(height: 150)
    }
    .padding(30)
    .background(Palette.oat)
}
