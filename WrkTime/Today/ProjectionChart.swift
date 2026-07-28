import SwiftUI

/// Weight so far, and where the current plan says it is going.
///
/// Drawn from the approved mockup (`docs/design/lane-g-almanac-approved.html`,
/// `.lg-chart`): readings as a solid ink line over a filled area, the
/// projection as a moss dash reaching a saffron goal line, and a widening band
/// around the projection.
///
/// **The band is the honest part.** A single projected line implies the app
/// knows what the scale will read in October. It does not. The band widens with
/// distance because the uncertainty does, and it is labelled with the number it
/// represents rather than left as decoration.
///
/// Everything is derived from real readings. With too few to draw a trend the
/// chart says so and draws nothing, rather than inventing a slope.
struct ProjectionChart: View {
    let entries: [WeightEntry]
    let goal: Double
    /// Where the plan says she arrives, from `Projections`.
    let projection: Projection?

    /// Below this there is no line worth drawing.
    static let minimumReadings = 2

    private var readings: [WeightEntry] {
        entries.sorted { $0.date < $1.date }.suffix(60)
    }

    var body: some View {
        if readings.count < Self.minimumReadings {
            Text("Two weigh-ins draw the line. One is a number; two is a direction.")
                .font(.almanacBodySmall)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            chart
        }
    }

    private var chart: some View {
        Canvas { context, size in
            let plot = Plot(size: size, readings: readings, goal: goal, projection: projection)

            drawGrid(context, plot)
            drawBand(context, plot)
            drawGoalLine(context, plot)
            drawArea(context, plot)
            drawProjection(context, plot)
            drawActual(context, plot)
            drawNow(context, plot)
            drawGoalLabel(context, plot)
            drawAxis(context, plot)
        }
        .frame(height: 168)
        .accessibilityElement()
        .accessibilityLabel("Weight trend and projection")
        .accessibilityValue(summary)
    }

    private var summary: String {
        guard let latest = readings.last else { return "No readings." }
        let now = String(format: "%.1f", latest.pounds)
        guard let projection, !projection.isComplete else {
            return "\(now) pounds today. At goal."
        }
        return "\(now) pounds today, projected to reach \(Int(goal.rounded())) pounds around \(projection.arrival.formatted(.dateTime.month(.wide).day()))."
    }

    /// The mockup's `.lg-c__plate`: an oat card behind a label so it reads over
    /// grid lines and the projection rather than tangling with them.
    private func plate(_ context: GraphicsContext, at point: CGPoint, size: CGSize) {
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                          width: size.width, height: size.height)
        context.fill(Path(roundedRect: rect, cornerRadius: 2),
                     with: .color(Palette.oat.opacity(0.92)))
    }

    // MARK: - Layers

    private func drawGrid(_ context: GraphicsContext, _ plot: Plot) {
        for pounds in plot.gridValues {
            let y = plot.y(for: pounds)
            var line = Path()
            line.move(to: CGPoint(x: plot.left, y: y))
            line.addLine(to: CGPoint(x: plot.right, y: y))
            context.stroke(line, with: .color(Palette.rule), lineWidth: 1)

            context.draw(
                Text("\(Int(pounds))")
                    .font(Face.mono(10))
                    .foregroundStyle(Palette.mute),
                at: CGPoint(x: plot.left - 8, y: y),
                anchor: .trailing
            )
        }
    }

    /// The range around the projection, widening with distance because that is
    /// what actually happens to a forecast.
    private func drawBand(_ context: GraphicsContext, _ plot: Plot) {
        guard let end = plot.projectedEnd else { return }
        let spread = plot.bandSpread

        var band = Path()
        band.move(to: plot.nowPoint)
        band.addLine(to: CGPoint(x: end.x, y: end.y - spread))
        band.addLine(to: CGPoint(x: end.x, y: end.y + spread))
        band.closeSubpath()
        context.fill(band, with: .color(Palette.moss.opacity(0.13)))

        // Inside the band, not under the axis, where it collided with the
        // date labels.
        let midX = (plot.nowPoint.x + end.x) / 2
        let midY = (plot.nowPoint.y + end.y) / 2
        plate(context, at: CGPoint(x: midX, y: midY + spread * 0.55),
              size: CGSize(width: 96, height: 13))
        context.draw(
            Text("RANGE ±\(String(format: "%.1f", plot.bandPounds)) LB")
                .font(Face.mono(9))
                .tracking(0.8)
                .foregroundStyle(Palette.mute),
            at: CGPoint(x: midX, y: midY + spread * 0.55),
            anchor: .center
        )
    }

    private func drawGoalLine(_ context: GraphicsContext, _ plot: Plot) {
        guard goal > 0 else { return }
        let y = plot.y(for: goal)
        var line = Path()
        line.move(to: CGPoint(x: plot.left, y: y))
        line.addLine(to: CGPoint(x: plot.right, y: y))
        context.stroke(line, with: .color(Palette.saffron),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [1.5, 3.5]))

    }

    /// Drawn last, so the projection dashes cannot cross the label. Order is
    /// the whole fix: the plate is only opaque to what was painted before it.
    private func drawGoalLabel(_ context: GraphicsContext, _ plot: Plot) {
        guard goal > 0 else { return }
        let centre = CGPoint(x: plot.right - 36, y: plot.y(for: goal) - 11)
        plate(context, at: centre, size: CGSize(width: 78, height: 14))
        context.draw(
            Text("GOAL \(String(format: "%.1f", goal))")
                .font(Face.mono(9, weight: .semibold))
                .tracking(0.6)
                // saffronInk, because this one has to be read on oat.
                .foregroundStyle(Palette.saffronInk),
            at: centre,
            anchor: .center
        )
    }

    private func drawArea(_ context: GraphicsContext, _ plot: Plot) {
        guard let first = plot.points.first, let last = plot.points.last else { return }
        var area = Path()
        area.move(to: first)
        for point in plot.points.dropFirst() { area.addLine(to: point) }
        area.addLine(to: CGPoint(x: last.x, y: plot.bottom))
        area.addLine(to: CGPoint(x: first.x, y: plot.bottom))
        area.closeSubpath()
        context.fill(area, with: .color(Palette.moss.opacity(0.12)))
    }

    private func drawProjection(_ context: GraphicsContext, _ plot: Plot) {
        guard let end = plot.projectedEnd else { return }
        var line = Path()
        line.move(to: plot.nowPoint)
        line.addLine(to: end)
        context.stroke(line, with: .color(Palette.moss),
                       style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [4, 3.4]))

        context.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)),
                     with: .color(Palette.saffron))
    }

    private func drawActual(_ context: GraphicsContext, _ plot: Plot) {
        var line = Path()
        guard let first = plot.points.first else { return }
        line.move(to: first)
        for point in plot.points.dropFirst() { line.addLine(to: point) }
        context.stroke(line, with: .color(Palette.ink),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

        // The reading you are standing on, haloed so it reads over the area.
        let now = plot.nowPoint
        context.fill(Path(ellipseIn: CGRect(x: now.x - 4.8, y: now.y - 4.8, width: 9.6, height: 9.6)),
                     with: .color(Palette.oat))
        context.fill(Path(ellipseIn: CGRect(x: now.x - 2.6, y: now.y - 2.6, width: 5.2, height: 5.2)),
                     with: .color(Palette.ink))
    }

    private func drawNow(_ context: GraphicsContext, _ plot: Plot) {
        var line = Path()
        line.move(to: CGPoint(x: plot.nowPoint.x, y: plot.nowPoint.y + 7))
        line.addLine(to: CGPoint(x: plot.nowPoint.x, y: plot.bottom))
        context.stroke(line, with: .color(Palette.sage),
                       style: StrokeStyle(lineWidth: 1, dash: [1.5, 3]))

        guard let latest = readings.last else { return }
        // Sits to the right of the marker, clamped so a late-block reading
        // cannot push it off the canvas.
        let anchorX = min(plot.nowPoint.x + 10, plot.right - 96)
        plate(context, at: CGPoint(x: anchorX + 44, y: plot.nowPoint.y + 2),
              size: CGSize(width: 92, height: 30))
        context.draw(
            Text(String(format: "%.1f", latest.pounds))
                .font(.almanacHeading)
                .foregroundStyle(Palette.ink),
            at: CGPoint(x: anchorX, y: plot.nowPoint.y - 2),
            anchor: .bottomLeading
        )
        context.draw(
            Text("LB · TODAY")
                .font(Face.mono(9))
                .tracking(0.9)
                .foregroundStyle(Palette.mute),
            at: CGPoint(x: anchorX, y: plot.nowPoint.y + 12),
            anchor: .bottomLeading
        )
    }

    private func drawAxis(_ context: GraphicsContext, _ plot: Plot) {
        var axis = Path()
        axis.move(to: CGPoint(x: plot.left, y: plot.bottom))
        axis.addLine(to: CGPoint(x: plot.right, y: plot.bottom))
        context.stroke(axis, with: .color(Palette.ink), lineWidth: 1.2)

        let format = Date.FormatStyle.dateTime.day().month(.abbreviated)
        if let first = readings.first {
            context.draw(
                Text(first.date.formatted(format).uppercased())
                    .font(Face.mono(9)).tracking(1).foregroundStyle(Palette.mute),
                at: CGPoint(x: plot.left, y: plot.bottom + 12), anchor: .leading
            )
        }
        if let arrival = projection?.arrival {
            context.draw(
                Text(arrival.formatted(format).uppercased())
                    .font(Face.mono(9)).tracking(1).foregroundStyle(Palette.mute),
                at: CGPoint(x: plot.right, y: plot.bottom + 12), anchor: .trailing
            )
        }
    }
}

// MARK: - Geometry

/// Maps pounds and dates onto the canvas. Kept apart from the drawing so the
/// scale is decided once and every layer agrees with it.
private struct Plot {
    let left: CGFloat = 34
    let right: CGFloat
    let top: CGFloat = 14
    let bottom: CGFloat

    let points: [CGPoint]
    let nowPoint: CGPoint
    let projectedEnd: CGPoint?
    let gridValues: [Double]
    let bandPounds: Double
    let bandSpread: CGFloat

    private let low: Double
    private let high: Double

    init(size: CGSize, readings: [WeightEntry], goal: Double, projection: Projection?) {
        let leftEdge: CGFloat = 34
        let rightEdge = size.width - 6
        let topEdge: CGFloat = 14
        let bottomEdge = size.height - 22
        right = rightEdge
        bottom = bottomEdge

        // The scale has to hold every reading and the goal, or the goal line
        // sits off-canvas and the chart quietly stops being about the goal.
        let weights = readings.map(\.pounds)
        let candidates = goal > 0 ? weights + [goal] : weights
        let lo = (candidates.min() ?? 0) - 2
        let hi = max((candidates.max() ?? 1) + 2, lo + 1)
        low = lo
        high = hi

        let start = readings.first?.date ?? .now
        let last = readings.last?.date ?? .now
        let end = projection?.arrival ?? last
        let span = max(end.timeIntervalSince(start), 1)

        // Local and pure: reading `self.low` here would be touching a property
        // before the initialiser has finished setting it.
        func px(_ date: Date) -> CGFloat {
            leftEdge + (rightEdge - leftEdge) * CGFloat(date.timeIntervalSince(start) / span)
        }
        func py(_ pounds: Double) -> CGFloat {
            topEdge + (bottomEdge - topEdge) * CGFloat((hi - pounds) / (hi - lo))
        }

        let plotted = readings.map { CGPoint(x: px($0.date), y: py($0.pounds)) }
        points = plotted
        nowPoint = plotted.last ?? CGPoint(x: leftEdge, y: py(weights.last ?? 0))

        if let projection, !projection.isComplete, goal > 0 {
            projectedEnd = CGPoint(x: px(projection.arrival), y: py(goal))
        } else {
            projectedEnd = nil
        }

        // Three pounds at the far end, the mockup's figure, scaled to the axis.
        bandPounds = 3
        bandSpread = (bottomEdge - topEdge) * CGFloat(3 / (hi - lo))

        // Grid every ten pounds, on round numbers inside the range.
        let firstLine = (lo / 10).rounded(.up) * 10
        gridValues = stride(from: firstLine, through: hi, by: 10).map { $0 }
    }

    func y(for pounds: Double) -> CGFloat {
        let height = bottom - top
        return top + height * CGFloat((high - pounds) / (high - low))
    }
}
