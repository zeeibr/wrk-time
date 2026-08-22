import SwiftData
import SwiftUI

/// What the plan is reading, and what it does about it.
///
/// The rule this screen is built to is HANDOFF's: **say what a signal is and
/// what the plan does with it, never what it means for your health.** Every
/// number here is paired with a consequence for the plan, or it is not shown.
/// A resting heart rate with a clinical gloss attached would be the app
/// practising medicine; a resting heart rate next to "the plan holds" is the
/// app explaining itself.
///
/// Missing data holds the plan. Nothing here fills a gap with a guess, and a
/// signal that is absent says so rather than reading as zero.
struct SignalsView: View {
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query(sort: \Block.startDate, order: .reverse) private var blocks: [Block]
    // Observed for the minutes ledger, so a session finished five minutes ago
    // is already counted when she opens this screen.
    @Query private var sessions: [PlannedSession]
    @Query private var runs: [RoutineRun]
    @Query private var practices: [MorningPractice]

    @State private var recovery = RecoverySnapshot()
    @State private var walks: [RecordedWalk] = []
    @State private var loaded = false
    @State private var loggingWeight = false
    @AppStorage(PlannerService.Memo.walkMinutes) private var walkTarget = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Masthead(context: "Signals")
                    .padding(.top, 4)

                recoverySection
                weightSection
                movementSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.oat.ignoresSafeArea())
        .sheet(isPresented: $loggingWeight) { WeighInView() }
        .task {
            let health = HealthKitService()
            _ = await health.requestAuthorization()
            recovery = await health.recoverySnapshot()
            walks = await health.walks(since: Date.now.addingTimeInterval(-14 * 86_400))
            loaded = true
        }
    }

    // MARK: - Recovery

    private var recoverySection: some View {
        IndexedSection(number: "01", label: "Recovery") {
            SectionHead(title: "Last night", note: guidanceNote)
                .padding(.bottom, 10)

            if let explanation = recovery.explanation {
                Text(explanation)
                    .font(.almanacBody)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
            }

            HStack(alignment: .top, spacing: 14) {
                StatCell(label: "Sleep",
                         value: recovery.sleepHours.map { String(format: "%.1f", $0) } ?? "—",
                         unit: recovery.sleepHours == nil ? nil : "h")
                StatCell(label: "Variability",
                         value: recovery.hrv.map { "\(Int($0.rounded()))" } ?? "—",
                         unit: recovery.hrv == nil ? nil : "ms")
                StatCell(label: "Resting",
                         value: recovery.restingHeartRate.map { "\(Int($0.rounded()))" } ?? "—",
                         unit: recovery.restingHeartRate == nil ? nil : "bpm")
            }

            if let baselines = baselineNote {
                Text(baselines)
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.mute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            if loaded, recovery.sleepHours == nil, recovery.hrv == nil {
                Text("Nothing came through from Health. The plan holds as written — a missing signal is never read as a bad one.")
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.mute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    /// What the numbers did, not what the plan will do about it.
    ///
    /// "Ease off" and "Room to push" read as instructions the plan has issued,
    /// and the plan issues nothing — recovery never reaches the planner. These
    /// describe the reading and leave the decision with her. With no readings
    /// at all it says so rather than claiming the plan stands on evidence it
    /// does not have.
    private var guidanceNote: String {
        guard recovery.explanation != nil else { return "No readings" }
        return switch recovery.guidance {
        case .ease: "Down on your usual"
        case .push: "Up on your usual"
        case .hold: "As usual"
        }
    }

    /// Baselines are stated because the comparison is against you, not against
    /// a population — which is the only reason the numbers mean anything.
    private var baselineNote: String? {
        var parts: [String] = []
        if let baseline = recovery.hrvBaseline {
            parts.append("variability usually around \(Int(baseline.rounded())) ms")
        }
        if let baseline = recovery.restingHeartRateBaseline {
            parts.append("resting heart rate around \(Int(baseline.rounded())) bpm")
        }
        guard !parts.isEmpty else { return nil }
        return "Compared against your own recent average — \(parts.joined(separator: ", ")). Not against anyone else's."
    }

    // MARK: - Weight

    private var weightSection: some View {
        IndexedSection(number: "02", label: "Weight") {
            SectionHead(title: "The trend", note: trendNote)
                .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 14) {
                StatCell(label: "Mean",
                         value: trend.sevenDayMean.map { String(format: "%.1f", $0) } ?? "—",
                         unit: trend.sevenDayMean == nil ? nil : "lb")
                StatCell(label: "Weekly change",
                         value: weeklyRateValue,
                         unit: trend.weeklyRate == nil ? nil : "lb")
                if let goal = blocks.first?.goalWeightPounds, goal > 0 {
                    StatCell(label: "Goal", value: "\(Int(goal.rounded()))", unit: "lb")
                }
            }

            Button { loggingWeight = true } label: {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Record a weigh-in")
                        .font(.almanacBody)
                    Spacer()
                }
                .foregroundStyle(Palette.moss)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            Rule()

            ProjectionChart(entries: weights,
                            goal: blocks.first?.goalWeightPounds ?? 0,
                            projection: projection)
                .padding(.top, 16)

            Text(weightNote)
                .font(.almanacBodySmall)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    private var trend: WeightTrend { WeightTrend(entries: weights) }

    /// Drawn from the seven-day mean, never the last reading, for the same
    /// reason the headline number is.
    private var projection: Projection? {
        guard let block = blocks.first, block.hasGoal,
              let mean = trend.sevenDayMean else { return nil }
        return Projections.project(current: mean, goal: block.goalWeightPounds)
    }

    /// "7-day mean" is a claim about method. With one or two readings on the
    /// board it reads as a claim about the data, so the count is stated until
    /// there is enough of it for the method to be the interesting part.
    private var trendNote: String {
        let recent = weights.filter { $0.date > Date.now.addingTimeInterval(-7 * 86_400) }.count
        switch recent {
        case 0: return "No readings"
        case 1: return "1 reading"
        case 2: return "2 readings"
        default: return "7-day mean"
        }
    }

    private var weeklyRateValue: String {
        guard let rate = trend.weeklyRate else { return "—" }
        return String(format: "%+.1f", rate)
    }

    /// Two things get said here and nothing else: what the number is measured
    /// over, and what the plan does with it. The plan does nothing with it —
    /// which is worth stating, because a weight tracker that silently trains
    /// you harder for a bad week is the thing this app is built not to be.
    private var weightNote: String {
        guard trend.sevenDayMean != nil else {
            return "No readings yet. Weight is an input the plan records and does not train from — the sessions stay the same either way."
        }
        var lines = ["Averaged over seven readings, because a single morning is mostly water and can swing further than a week of real change."]

        if let block = blocks.first, block.hasGoal {
            if let projected = trend.projectedDate(toGoal: block.goalWeightPounds) {
                lines.append("At the current trend that reaches \(Int(block.goalWeightPounds.rounded())) lb around \(projected.formatted(.dateTime.month(.wide).day())).")
            } else if trend.weeklyRate == nil {
                // Two different silences, and conflating them was a lie: with
                // one reading there is no rate at all, and saying "the trend is
                // not heading toward the goal" would be a direction claim made
                // from no direction.
                lines.append("Two weeks of readings are needed before there is a rate to project from.")
            } else {
                // `projectedDate` returns nil on a flat or rising trend rather
                // than inventing a date, and this is where that shows.
                lines.append("The trend is not currently heading toward the goal, so there is no date to project. That is the arithmetic, not a verdict.")
            }
        }
        return lines.joined(separator: " ")
    }

    // MARK: - Movement

    private var movementSection: some View {
        // One section for the week's movement, walking first because it is
        // the number with a target. It was two sections — 03 WALKING and 04
        // MINUTES, both headed "This week", with the walking minutes stated
        // in each — which was the screen asking one question twice and
        // filing the answers apart.
        IndexedSection(number: "03", label: "Movement") {
            SectionHead(title: "This week", note: walkTarget > 0 ? "\(walkedThisWeek)/\(walkTarget) min" : "\(walkedThisWeek + strengthMinutes + flowMinutes) min moved")
                .padding(.bottom, 10)

            if walkTarget > 0 {
                WalkBar(done: walkedThisWeek, target: walkTarget)
                    .padding(.bottom, 10)

                // The number she can act on today. The planner thinks in weeks
                // because that is the unit a plan is written in, but nobody
                // decides on a Tuesday morning how to spend a weekly total —
                // the useful sentence is how long to be out for today, and how
                // much of the week is still owed.
                Text(dailyWalkNote)
                    .font(.almanacBody)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)

                Text(walkNote)
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.mute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
            }

            DetailLine(label: "Walking", value: "\(walkedThisWeek) min")
            DetailLine(label: "Strength", value: "\(strengthMinutes) min")
            DetailLine(label: "Qi gong", value: "\(flowMinutes) min")
            Rule()

            Text("Strength counts finished sessions and workouts of your own; qi gong counts the morning practice and the flow that opens each session. Walking comes from Health, so a walk the phone missed is missing here too.")
                .font(.almanacBodySmall)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.bottom, 14)

            // An eyebrow, not a second section head — this list belongs to
            // the movement section, and a full-size title here read as an
            // unnumbered peer breaking the margin's rhythm.
            HStack(alignment: .firstTextBaseline) {
                Text("Off the plan")
                    .almanacLabel(Palette.mute, small: true)
                Spacer(minLength: 8)
                Text(walks.isEmpty ? "Nothing logged" : "\(walks.count) walks")
                    .almanacLabel(Palette.mute, small: true)
                    .tabular()
            }
            .padding(.bottom, walks.isEmpty ? 10 : 4)

            if walks.isEmpty {
                Text("Walks recorded by Whoop, a Watch or your phone appear here. They are context for the plan, never marks — a mark is a finished session you planned.")
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.mute)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(walks.prefix(10).enumerated()), id: \.offset) { _, walk in
                    VStack(spacing: 0) {
                        Rule()
                        HStack(alignment: .firstTextBaseline) {
                            Text(walk.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                .font(.almanacBody)
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 8)
                            // Named, never guessed at.
                            Text(walk.source).almanacLabel(Palette.mute, small: true)
                            Text("\(Int(walk.minutes.rounded())) min")
                                .almanacLabel(Palette.mute)
                                .tabular()
                        }
                        .padding(.vertical, 9)
                    }
                    .accessibilityElement(children: .combine)
                }
                Rule()
            }
        }
    }

    /// Minutes walked since the start of this calendar week.
    private var walkedThisWeek: Int {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return Int(walks.filter { $0.date >= weekStart }
            .reduce(0) { $0 + $1.minutes }.rounded())
    }

    /// The one place the app says out loud which lever moves the scale.
    ///
    /// It is stated here rather than beside the weight, because this is the
    /// number she can act on. It names walking and stops there — the app does
    /// not tell anyone what to eat.
    /// "About 26 minutes a day", and what today still owes.
    ///
    /// Spread across the days **left in the week**, not across seven. A target
    /// divided by seven on a Friday is a number that was already impossible on
    /// Wednesday, and quietly reports a shortfall as a daily requirement. If
    /// the week is already done it says so and asks for nothing.
    private var dailyWalkNote: String {
        let remaining = max(walkTarget - walkedThisWeek, 0)
        guard remaining > 0 else { return "This week's walking is done." }

        let calendar = Calendar.current
        let weekEnd = calendar.dateInterval(of: .weekOfYear, for: .now)?.end ?? .now
        // Today counts as one of them, so the last day of the week asks for
        // what is left rather than dividing it by nothing.
        let daysLeft = max(calendar.dateComponents([.day],
                                                   from: calendar.startOfDay(for: .now),
                                                   to: weekEnd).day ?? 1, 1)
        let perDay = Int((Double(remaining) / Double(daysLeft)).rounded())

        guard daysLeft > 1 else { return "\(remaining) minutes today finishes the week." }
        return "About \(perDay) minutes a day for the rest of the week — \(remaining) minutes still to go."
    }

    private var walkNote: String {
        let base = "The sessions build and keep muscle; they are too short to move the scale. Walking is the part of the plan that does."
        guard walkedThisWeek < walkTarget else {
            return "That is this week's walking done. " + base
        }
        return base
    }

    // MARK: - This week's minutes

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    }

    /// Split by the routine's own schedule: a finished session's flow opener
    /// goes under qi gong, the rounds under strength. Runs recorded before the
    /// split existed count wholly as strength — the only honest reading of a
    /// row that never said.
    private var strengthMinutes: Int {
        let fromSessions = sessions
            .filter { ($0.completedAt ?? .distantPast) >= weekStart }
            .compactMap(\.routine)
            .reduce(0.0) { $0 + $1.schedule.total - flowPortion($1) }
        let fromRuns = runs
            .filter { $0.finishedAt >= weekStart }
            .reduce(0.0) { $0 + max($1.seconds - min($1.flowSeconds ?? 0, $1.seconds), 0) }
        return Int(((fromSessions + fromRuns) / 60).rounded())
    }

    private var flowMinutes: Int {
        let fromPractices = practices
            .filter { ($0.completedAt ?? .distantPast) >= weekStart }
            .reduce(0.0) { $0 + Double($1.moveNames.count) * Practice.seconds }
        let fromSessions = sessions
            .filter { ($0.completedAt ?? .distantPast) >= weekStart }
            .compactMap(\.routine)
            .reduce(0.0) { $0 + flowPortion($1) }
        let fromRuns = runs
            .filter { $0.finishedAt >= weekStart }
            .reduce(0.0) { $0 + min($1.flowSeconds ?? 0, $1.seconds) }
        return Int(((fromPractices + fromSessions + fromRuns) / 60).rounded())
    }

    private func flowPortion(_ routine: IntervalRoutine) -> TimeInterval {
        Double(routine.warmUp.count) * routine.warmUpSeconds
    }
}

/// Walking progress as a filled bar rather than a ring — walking is volume
/// accumulating toward a number, and the rings on the growth form mean
/// something else entirely.
private struct WalkBar: View {
    let done: Int
    let target: Int

    private var fraction: Double {
        guard target > 0 else { return 0 }
        return min(Double(done) / Double(target), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Palette.moss.opacity(0.16))
                    Rectangle()
                        .fill(Palette.moss)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 8)

            Text(done >= target
                 ? "\(done) minutes — target met"
                 : "\(done) of \(target) minutes")
                .almanacLabel(Palette.mute, small: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Walking this week")
        .accessibilityValue("\(done) of \(target) minutes")
    }
}

private struct DetailLine: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            Rule()
            HStack {
                Text(label)
                    .font(.almanacBody)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text(value).almanacLabel(Palette.mute).tabular()
            }
            .padding(.vertical, 11)
        }
        .accessibilityElement(children: .combine)
    }
}
