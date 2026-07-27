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
    /// Total completed sessions across the block.
    let marks: Int
    let weeks: Int
    let currentWeek: Int
    /// Sessions the plan asks for each week. Six closes a ring.
    var sessionsPerWeek: Int = 6

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = min(size.width, size.height) / 2 - 6
            let innerRadius = maxRadius * 0.16

            for week in 1...weeks {
                let t = Double(week - 1) / Double(max(weeks - 1, 1))
                let radius = innerRadius + (maxRadius - innerRadius) * t
                let lived = week <= currentWeek
                let path = ringPath(center: center, radius: radius, seed: week)

                context.stroke(
                    path,
                    with: .color(lived ? Palette.moss : Palette.sage.opacity(0.45)),
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
        .accessibilityLabel("Growth form. \(marks) sessions completed across \(currentWeek) of \(weeks) weeks.")
    }

    // MARK: - Geometry

    /// How many marks belong to a given week, filling earlier weeks first.
    private func marksIn(week: Int) -> Int {
        let before = (week - 1) * sessionsPerWeek
        return min(max(marks - before, 0), sessionsPerWeek)
    }

    /// A closed, slightly eccentric ring. The distortion is a sum of two low
    /// harmonics whose phase advances by the golden angle per week, which is
    /// what stops the rings from looking like concentric tree rings and starts
    /// them looking grown.
    private func ringPath(center: CGPoint, radius: Double, seed: Int) -> Path {
        let goldenAngle = 2.39996
        let phase = Double(seed) * goldenAngle
        let steps = 180

        var path = Path()
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let wobble =
                sin(angle * 2 + phase) * 0.035 +
                sin(angle * 3 - phase * 0.7) * 0.022
            let r = radius * (1 + wobble)
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
        let goldenAngle = 2.39996
        let phase = Double(seed) * goldenAngle

        for mark in 0..<count {
            let angle = -Double.pi / 2
                + (Double(mark) / Double(sessionsPerWeek)) * 2 * .pi
                + Double(seed) * 0.35
            let wobble =
                sin(angle * 2 + phase) * 0.035 +
                sin(angle * 3 - phase * 0.7) * 0.022
            let r = radius * (1 + wobble)

            let inner = CGPoint(x: center.x + cos(angle) * (r - 4.5),
                                y: center.y + sin(angle) * (r - 4.5))
            let outer = CGPoint(x: center.x + cos(angle) * (r + 4.5),
                                y: center.y + sin(angle) * (r + 4.5))

            var stroke = Path()
            stroke.move(to: inner)
            stroke.addLine(to: outer)

            // Only the most recent mark is saffron — today's, and only today's.
            let isLatest = isCurrent && mark == count - 1
            context.stroke(
                stroke,
                with: .color(isLatest ? Palette.saffron : Palette.moss),
                style: StrokeStyle(lineWidth: isLatest ? 2.2 : 1.6, lineCap: .round)
            )
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        GrowthForm(marks: 11, weeks: 12, currentWeek: 2)
            .frame(height: 150)
        GrowthForm(marks: 58, weeks: 12, currentWeek: 10)
            .frame(height: 150)
    }
    .padding(30)
    .background(Palette.oat)
}
