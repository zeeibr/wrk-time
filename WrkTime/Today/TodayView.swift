import SwiftUI
import SwiftData

/// The document register.
///
/// Reading order is deliberate: what today is, what it asks of you, the control
/// that starts it, then the supporting figures. Fasting appears once, as a cell
/// beside weight — it is an input to the plan, not the point of the app.
struct TodayView: View {
    @Query(sort: \PlannedSession.scheduledFor) private var sessions: [PlannedSession]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query private var fastWindows: [FastWindow]

    @State private var runningRoutine: IntervalRoutine?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                masthead

                if let session = todaysSession, let routine = session.routine {
                    IndexedSection(number: "01", label: "Session") {
                        SectionHead(title: session.title,
                                    note: routine.totalDuration.durationString)
                            .padding(.bottom, 10)

                        counters(for: routine)
                            .padding(.bottom, 12)

                        ForEach(Array(routine.moves.enumerated()), id: \.element.id) { index, move in
                            BlockRow(
                                index: index + 1,
                                symbol: move.symbol,
                                name: move.name,
                                equipment: move.equipmentLabel,
                                measure: "\(Int(routine.clampedWork))s ×\(routine.rounds / max(routine.moves.count, 1))"
                            )
                        }
                        Rule()

                        PrimaryButton(title: "Begin session",
                                      subtitle: "\(routine.rounds) rounds · \(routine.totalDuration.durationString)") {
                            runningRoutine = routine
                        }
                        .padding(.top, 14)
                    }
                } else {
                    restDayNote
                }

                IndexedSection(number: "02", label: "Season") {
                    SectionHead(title: "The season so far", note: seasonNote)
                        .padding(.bottom, 12)
                    GrowthForm(marks: completedCount, weeks: 12, currentWeek: currentWeek)
                        .frame(height: 128)
                        .frame(maxWidth: .infinity)
                }

                IndexedSection(number: "03", label: "Signals") {
                    Rule(firm: true)
                    HStack(alignment: .top, spacing: 14) {
                        StatCell(label: "Weight",
                                 value: latestWeightString,
                                 unit: "lb")
                        StatCell(label: "Fasting",
                                 value: fastingString,
                                 emphasis: Palette.moss)
                    }
                    .padding(.top, 12)

                    Text(fastingFootnote)
                        .font(.almanacBodySmall)
                        .foregroundStyle(Palette.mute)
                        .padding(.top, 10)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.oat.ignoresSafeArea())
        .fullScreenCover(item: $runningRoutine) { routine in
            WorkoutTimerView(routine: routine)
        }
    }

    // MARK: - Pieces

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(mastheadLabel).almanacLabel()
            Text(greeting)
                .font(.almanacTitle)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func counters(for routine: IntervalRoutine) -> some View {
        HStack(spacing: 0) {
            counter(routine.totalDuration.durationString, "Minutes")
            divider
            counter("\(routine.rounds)", "Rounds")
            divider
            counter("\(Int(routine.clampedWork))/\(Int(routine.rest))", "Work / rest")
        }
        .overlay(alignment: .top) { Rule() }
        .overlay(alignment: .bottom) { Rule() }
        .padding(.vertical, 10)
    }

    private func counter(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(Face.ui(24))
                .tabular()
                .foregroundStyle(Palette.ink)
            Text(label).almanacLabel(small: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(Palette.rule).frame(width: 1 / displayScale, height: 34)
    }

    private var restDayNote: some View {
        IndexedSection(number: "01", label: "Session") {
            SectionHead(title: "Nothing scheduled", note: "Rest")
                .padding(.bottom, 10)
            Text("A rest day is part of the plan, not a gap in it. If you want to move anyway, a walk on the pad is free.")
                .font(.almanacBody)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Derived copy

    private var todaysSession: PlannedSession? {
        sessions.first { Calendar.current.isDateInToday($0.scheduledFor) && !$0.isComplete }
    }

    private var completedCount: Int { sessions.filter(\.isComplete).count }

    private var currentWeek: Int { max(1, (completedCount / 6) + 1) }

    private var seasonNote: String { "\(completedCount) marks" }

    private var mastheadLabel: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()
    }

    /// Warm, specific, and never exclamatory — the voice this lane inherited
    /// from Season.
    private var greeting: String {
        let streak = completedCount
        if streak == 0 { return "Day one. Start small." }
        if todaysSession == nil { return "Rest day. That counts too." }
        return "\(streak) sessions in.\nToday is a steady one."
    }

    private var latestWeightString: String {
        guard let latest = weights.first else { return "—" }
        return String(format: "%.1f", latest.pounds)
    }

    private var fastingString: String {
        fastWindows.first?.summaryLine ?? "Not tracking"
    }

    private var fastingFootnote: String {
        "Your eating window is one of three inputs to the projected rate, alongside session volume and sleep."
    }
}
