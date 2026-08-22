import SwiftData
import SwiftUI

/// The block at full size.
///
/// Today shows the growth form as a thumbnail because Today is about the next
/// thirteen minutes. This screen is the opposite: it is the document you open
/// when you want to know how the season is actually going, so the drawing gets
/// the fold and the numbers sit under it.
///
/// It states quiet weeks plainly. A week with no marks draws an empty ring and
/// gets a row reading "—", and nothing anywhere apologises for it or nudges
/// about it. A season document that cannot show a gap is not a document.
struct SeasonView: View {
    @Environment(\.modelContext) private var context
    /// Observed so the fortnight redraws the moment a practice is recorded.
    @Query private var practices: [MorningPractice]
    /// Observed for the same reason: "Your own" was a manual fetch through the
    /// context, so a run recorded on the timer did not appear until something
    /// unrelated redrew this screen — which read as the run never being
    /// recorded at all.
    @Query(sort: \RoutineRun.finishedAt, order: .reverse) private var runs: [RoutineRun]

    @Query(sort: \Block.startDate, order: .reverse) private var blocks: [Block]
    @Query(sort: \PlannedSession.scheduledFor) private var sessions: [PlannedSession]

    /// A past run being done again from this screen.
    struct Rerun: Identifiable {
        let routine: IntervalRoutine
        let saved: SavedRoutine?
        var id: UUID { routine.id }
    }
    @State private var rerunning: Rerun?
    /// The week whose days are open under its row. One at a time — the rows
    /// are a summary, and the expansion is a look inside one of them.
    @State private var expandedWeek: Int?
    /// Whether the hero hides the weeks still ahead. Her ask — sometimes the
    /// season so far is the picture she wants, without the ripples of what is
    /// coming. A tap on the drawing flips it; not persisted, because the full
    /// form is the screen's statement and each visit starts from it.
    @State private var livedOnly = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Masthead(context: "Season")
                    .padding(.top, 4)

                if let block {
                    form(for: block)
                    weekByWeek(for: block)
                    practiceRecord
                    details(for: block)
                } else {
                    Text("No block yet. The season starts when you begin one.")
                        .font(.almanacBody)
                        .foregroundStyle(Palette.mute)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.oat.ignoresSafeArea())
        // The recording itself happens in `WorkoutTimerView.report`, presenter
        // be damned — this closure only owes the saved routine its timestamp.
        .fullScreenCover(item: $rerunning) { rerun in
            WorkoutTimerView(routine: rerun.routine, subject: .routine) { outcome in
                guard case .completed = outcome else { return }
                rerun.saved?.lastRunAt = .now
                try? context.save()
            }
        }
    }

    private var block: Block? { blocks.first }

    // MARK: - The drawing

    private func form(for block: Block) -> some View {
        IndexedSection(number: "01", label: "Form") {
            SectionHead(title: "The season", note: seasonNote(for: block))
                .padding(.bottom, 16)

            GrowthForm(marksByWeek: marksByWeek(for: block),
                       weeks: block.weekCount,
                       currentWeek: block.currentWeek,
                       minorsByWeek: minorsByWeek(for: block),
                       sessionsPerWeek: block.pace.sessionsPerWeek,
                       blockSeed: block.formSeed,
                       livedWeeksOnly: livedOnly,
                       dayOfWeek: dayOfBlockWeek(for: block))
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    livedOnly.toggle()
                    Haptics.transport()
                }
                // The drawing is the whole point of this screen and unreadable
                // to a screen reader, so it says in words what it shows.
                .accessibilityElement()
                .accessibilityLabel("Growth form")
                .accessibilityValue(formDescription(for: block))
                .accessibilityHint(livedOnly ? "Shows the weeks still ahead"
                                             : "Hides the weeks still ahead")
                .accessibilityAddTraits(.isButton)

            Text("One ring is one week; one dot set on the ring is one finished session, the newest ringed in saffron. The saffron stretch of the current ring is today. A small tick under the ring is a workout of your own, seven minutes or more — real work, never a mark. Weeks still ahead are hairlines that take their own shape once you are in them. Tap the drawing to see the season so far on its own.")
                .font(.almanacBodySmall)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
    }

    // MARK: - Week by week

    private func weekByWeek(for block: Block) -> some View {
        IndexedSection(number: "02", label: "Weeks") {
            SectionHead(title: "Week by week", note: "\(block.pace.label) · \(block.pace.sessionsPerWeek)×")
                .padding(.bottom, 4)

            let marks = marksByWeek(for: block)
            let target = block.pace.sessionsPerWeek

            ForEach(0..<block.weekCount, id: \.self) { index in
                let week = index + 1
                let state = state(ofWeek: week, in: block)
                WeekRow(week: week,
                        dates: span(ofWeek: week, in: block),
                        marks: marks.indices.contains(index) ? marks[index] : 0,
                        target: target,
                        state: state,
                        expanded: expandedWeek == week)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // A week still ahead has no days to show.
                        guard state != .ahead else { return }
                        expandedWeek = expandedWeek == week ? nil : week
                        Haptics.transport()
                    }

                if expandedWeek == week, state != .ahead {
                    let days = dayBreakdown(ofWeek: week, in: block)
                    if days.isEmpty {
                        Text("Nothing recorded this week.")
                            .almanacLabel(Palette.mute, small: true)
                            .padding(.leading, 24)
                            .padding(.vertical, 7)
                    } else {
                        ForEach(days, id: \.day) { entry in
                            DayRow(day: entry.day, sessions: entry.sessions,
                                   extras: entry.extras)
                        }
                    }
                }
            }
            Rule()
        }
    }

    /// What each day of a week actually held — finished sessions by the day
    /// they were completed (the same fact the week's count states), her own
    /// substantial workouts by the day they were run (the same ones the ring
    /// draws as ticks). Only days with something in them get an entry; the
    /// app keeps no ledger of absences.
    private func dayBreakdown(ofWeek week: Int, in block: Block)
        -> [(day: Date, sessions: Int, extras: Int)] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: (week - 1) * 7,
                                  to: calendar.startOfDay(for: block.startDate)) ?? block.startDate
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start)
            else { return nil }
            let done = sessions.count {
                guard let at = $0.completedAt else { return false }
                return calendar.isDate(at, inSameDayAs: day)
            }
            let extras = runs.count {
                $0.isSubstantial && calendar.isDate($0.finishedAt, inSameDayAs: day)
            }
            guard done + extras > 0 else { return nil }
            return (day, done, extras)
        }
    }

    private func state(ofWeek week: Int, in block: Block) -> WeekRow.State {
        if week < block.currentWeek { .past }
        else if week == block.currentWeek { .current }
        else { .ahead }
    }

    /// The days a week actually runs — "Aug 3–9", or "Aug 31–Sep 6" across a
    /// month boundary. Weeks are counted from the block's start date, the same
    /// arithmetic `marksByWeek` bins by, so the row and its marks agree.
    private func span(ofWeek week: Int, in block: Block) -> String {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: (week - 1) * 7,
                                  to: calendar.startOfDay(for: block.startDate)) ?? block.startDate
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let opening = start.formatted(.dateTime.month(.abbreviated).day())
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        let closing = sameMonth
            ? end.formatted(.dateTime.day())
            : end.formatted(.dateTime.month(.abbreviated).day())
        return "\(opening)–\(closing)"
    }

    // MARK: - The morning practice

    /// The practice's own record, kept apart from the growth form.
    ///
    /// It is deliberately not a mark and deliberately not on the form: one mark
    /// is one finished planned session, and a daily thing drawn there would
    /// swamp the weekly one and change what the form means. But "every day" is
    /// the whole point of the practice, so it needs somewhere its own history
    /// is visible — this is that place.
    ///
    /// A fortnight of days, filled where it was done and open where it was not.
    /// Reading the gaps is possible and that is fine; what the app does not do
    /// is keep a row for a day she missed, or call it a failure.
    private var practiceRecord: some View {
        IndexedSection(number: "03", label: "Morning") {
            SectionHead(title: "The practice", note: practiceNote)
                .padding(.bottom, 12)

            HStack(spacing: 5) {
                ForEach(fortnight, id: \.day) { entry in
                    Rectangle()
                        .fill(entry.done ? Palette.moss : Color.clear)
                        .frame(height: 22)
                        .overlay(Rectangle().strokeBorder(Palette.ruleFirm, lineWidth: 1))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Morning practice, last fourteen days")
            .accessibilityValue("\(fortnight.filter(\.done).count) of 14 done")

            Text("The last fortnight, most recent on the right.")
                .almanacLabel(Palette.mute, small: true)
                .padding(.top, 8)

            // Her own workouts, beside the practice rather than on the growth
            // form. Both are real work that earns no mark, and this section is
            // already where the app keeps that category — so the distinction is
            // carried by *where* it appears rather than by a second notch
            // vocabulary on the form.
            Spacer(minLength: 20)
            SectionHead(title: "Your own", note: runNote)
                .padding(.bottom, 8)

            if recentRuns.isEmpty {
                Text("Routines you build and extra sessions you take appear here. They are volume the planner reads — they are not marks, because a mark is a session the plan asked for.")
                    .font(.almanacBodySmall)
                    .foregroundStyle(Palette.mute)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Each row is a way back in, not just a ledger line: tapping
                // reopens the routine to do again. Rows from before runs
                // carried their routine stay plain.
                ForEach(recentRuns) { run in
                    let reopen = RoutineRuns.reopen(run, in: context)
                    let row = VStack(spacing: 0) {
                        Rule()
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(run.name).font(.almanacBody).foregroundStyle(Palette.ink)
                                Text(run.source.label).almanacLabel(Palette.mute, small: true)
                            }
                            Spacer(minLength: 8)
                            Text(runDetail(run))
                                .almanacLabel(Palette.mute, small: true)
                                .tabular()
                            if reopen != nil {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Palette.mute)
                                    .padding(.top, 3)
                            }
                        }
                        .padding(.vertical, 11)
                    }

                    // A plain row when there is nothing to reopen — a disabled
                    // button dims its label, and a ledger line from before
                    // runs carried their routine is a fact, not a failure.
                    if let reopen {
                        Button {
                            rerunning = Rerun(routine: reopen.routine, saved: reopen.saved)
                        } label: {
                            row.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(run.name)
                        .accessibilityValue("\(run.source.label), \(runDetail(run))")
                        .accessibilityHint("Runs this routine again")
                    } else {
                        row
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(run.name)
                            .accessibilityValue("\(run.source.label), \(runDetail(run))")
                    }
                }
                Rule()
            }
        }
    }

    /// The last fortnight of her own work, newest first. Bounded because this is
    /// a record to glance at, not a log to scroll.
    private var recentRuns: [RoutineRun] {
        let since = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        return Array(runs.filter { $0.finishedAt >= since }.prefix(10))
    }

    private var runNote: String {
        let count = recentRuns.count
        guard count > 0 else { return "Nothing yet" }
        return count == 1 ? "1 in a fortnight" : "\(count) in a fortnight"
    }

    private func runDetail(_ run: RoutineRun) -> String {
        let day = run.finishedAt.formatted(.dateTime.weekday(.abbreviated))
        return run.roundsCompleted > 0
            ? "\(day) · \(run.roundsCompleted) × \(run.seconds.durationString)"
            : "\(day) · \(run.seconds.durationString)"
    }

    private var practiceNote: String {
        let run = MorningPractices.run(in: context)
        // Sized to the section head's measure — a header meta must never
        // ellipsize.
        guard run > 0 else { return "\(Practice.count) × \(Int(Practice.seconds))s" }
        return run == 1 ? "1 day" : "\(run) days in a row"
    }

    private var fortnight: [(day: Date, done: Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let done = Set(MorningPractices.all(in: context).map { calendar.startOfDay(for: $0.day) })
        return (0..<14).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return (day, done.contains(day))
        }
    }

    // MARK: - The block itself

    private func details(for block: Block) -> some View {
        IndexedSection(number: "04", label: "Block") {
            SectionHead(title: "This block", note: "\(block.currentWeek) of \(block.weekCount)")
                .padding(.bottom, 4)

            DetailRow(label: "Started", value: block.startDate.formatted(.dateTime.month(.wide).day()))
            DetailRow(label: "Ends", value: block.endDate.formatted(.dateTime.month(.wide).day()))
            DetailRow(label: "Pace", value: "\(block.pace.label) · \(block.pace.sessionsPerWeek) a week")

            if block.hasGoal {
                DetailRow(label: "Started at", value: "\(Int(block.startingWeightPounds.rounded())) lb")
                DetailRow(label: "Goal", value: "\(Int(block.goalWeightPounds.rounded())) lb")
            }
            Rule()

            Text(block.pace.expectation)
                .font(.almanacBodySmall)
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    // MARK: - Derived

    /// Finished sessions binned by the week they were actually finished in.
    private func marksByWeek(for block: Block) -> [Int] {
        var counts = Array(repeating: 0, count: block.weekCount)
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: block.startDate)
        for session in sessions {
            guard let done = session.completedAt else { continue }
            let days = calendar.dateComponents([.day], from: first,
                                               to: calendar.startOfDay(for: done)).day ?? 0
            // Integer division truncates toward zero, so the six days *before*
            // a block began all mapped to week 0 — and nothing prunes a
            // previous block's sessions from the query. A new block therefore
            // opened with the last week of the old one already drawn on it.
            guard days >= 0 else { continue }
            let week = days / 7
            if counts.indices.contains(week) { counts[week] += 1 }
        }
        return counts
    }

    /// Same binning as `marksByWeek`, then placed by `tickPositions` so each
    /// tick follows the session it came after — see `TodayView.minorsByWeek`.
    private func minorsByWeek(for block: Block) -> [[Double]] {
        let weekCount = block.weekCount
        var sessionTimes = Array(repeating: [Date](), count: weekCount)
        var extraTimes = Array(repeating: [Date](), count: weekCount)
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: block.startDate)
        func week(of date: Date) -> Int? {
            let days = calendar.dateComponents([.day], from: first,
                                               to: calendar.startOfDay(for: date)).day ?? 0
            guard days >= 0 else { return nil }
            let bin = days / 7
            return bin < weekCount ? bin : nil
        }
        for session in sessions {
            guard let done = session.completedAt, let bin = week(of: done) else { continue }
            sessionTimes[bin].append(done)
        }
        for run in runs where run.isSubstantial {
            guard let bin = week(of: run.finishedAt) else { continue }
            extraTimes[bin].append(run.finishedAt)
        }
        return (0..<weekCount).map {
            GrowthForm.tickPositions(sessions: sessionTimes[$0], extras: extraTimes[$0])
        }
    }

    /// Which day of the block's week today is — same arithmetic as the bins,
    /// see `TodayView.dayOfBlockWeek`.
    private func dayOfBlockWeek(for block: Block) -> Int? {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: block.startDate),
                                           to: calendar.startOfDay(for: .now)).day ?? 0
        return days >= 0 ? days % 7 : nil
    }

    private func seasonNote(for block: Block) -> String {
        let total = marksByWeek(for: block).reduce(0, +)
        return total == 0 ? "Not yet drawn" : total.marksPhrase
    }

    private func formDescription(for block: Block) -> String {
        let marks = marksByWeek(for: block)
        let total = marks.reduce(0, +)
        let done = marks.prefix(block.currentWeek).filter { $0 > 0 }.count
        return "\(total) finished sessions across \(done) of \(block.currentWeek) weeks so far."
    }
}

// MARK: - Parts

/// One week: its number, its marks drawn as squares, and the count.
///
/// The squares are the same vocabulary as the notches on the form, so a row
/// and the drawing above it are legible as the same fact stated twice.
private struct WeekRow: View {
    enum State { case past, current, ahead }

    let week: Int
    /// The days this week runs, e.g. "Aug 3–9".
    let dates: String
    let marks: Int
    let target: Int
    let state: State
    /// Whether the row is open, its days listed beneath it. Weeks still
    /// ahead have no days to show and never open.
    var expanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(spacing: 10) {
                // Ink, not saffron: a calendar position is neither a running
                // round nor today's mark. The current week's pips already
                // carry the accent.
                Text(String(format: "%02d", week))
                    .almanacLabel(state == .current ? Palette.ink : Palette.mute, small: true)
                    .tabular()

                HStack(spacing: 3) {
                    // A heavy week grows extra squares rather than capping at
                    // the target — six finished on a five-session week is
                    // 6/5, and every mark earns its pip.
                    ForEach(0..<max(max(target, marks), 1), id: \.self) { index in
                        Rectangle()
                            .fill(index < marks ? fill : Color.clear)
                            .frame(width: 7, height: 7)
                            .overlay {
                                Rectangle().strokeBorder(Palette.moss.opacity(index < marks ? 0 : 0.30),
                                                         lineWidth: 1)
                            }
                    }
                }
                Spacer(minLength: 8)
                Text(measure)
                    .almanacLabel(Palette.mute, small: true)
                    .tabular()
                if state != .ahead {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Palette.mute)
                }
            }
            .padding(.vertical, 9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Week \(week), \(dates)")
        .accessibilityValue(state == .ahead ? "Still ahead"
                            : "\(marks) of \(target) sessions finished")
        .accessibilityHint(state == .ahead ? ""
                           : expanded ? "Hides the days" : "Shows each day")
        .accessibilityAddTraits(state == .ahead ? [] : .isButton)
    }

    /// A week you have lived is moss; today's week is saffron, which is the one
    /// place on this screen saffron is allowed.
    private var fill: Color { state == .current ? Palette.saffron : Palette.moss }

    private var measure: String {
        switch state {
        case .ahead: "\(dates) · —"
        default: "\(dates) · \(marks)/\(target)"
        }
    }
}

/// One day inside an expanded week: when, and what it held. Sessions are the
/// week's marks placed on their day; extras are the ring's ticks named. Only
/// days with something get a row, so a quiet Tuesday is simply not mentioned.
private struct DayRow: View {
    let day: Date
    let sessions: Int
    let extras: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .almanacLabel(Palette.ink, small: true)
                .tabular()
            Text(day.formatted(.dateTime.month(.abbreviated).day()))
                .almanacLabel(Palette.mute, small: true)
            Spacer(minLength: 8)
            Text(measure)
                .almanacLabel(Palette.mute, small: true)
                .tabular()
        }
        .padding(.vertical, 6)
        .padding(.leading, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(measure)
    }

    private var measure: String {
        var parts: [String] = []
        if sessions > 0 { parts.append(sessions == 1 ? "1 session" : "\(sessions) sessions") }
        if extras > 0 { parts.append(extras == 1 ? "1 extra" : "\(extras) extras") }
        return parts.joined(separator: " · ")
    }
}

private struct DetailRow: View {
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
                Text(value)
                    .almanacLabel(Palette.mute)
                    .tabular()
            }
            .padding(.vertical, 11)
        }
        .accessibilityElement(children: .combine)
    }
}
