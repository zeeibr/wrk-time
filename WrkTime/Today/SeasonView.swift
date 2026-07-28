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

    @Query(sort: \Block.startDate, order: .reverse) private var blocks: [Block]
    @Query(sort: \PlannedSession.scheduledFor) private var sessions: [PlannedSession]

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
                       sessionsPerWeek: block.pace.sessionsPerWeek,
                       blockSeed: block.formSeed)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 8)
                // The drawing is the whole point of this screen and unreadable
                // to a screen reader, so it says in words what it shows.
                .accessibilityElement()
                .accessibilityLabel("Growth form")
                .accessibilityValue(formDescription(for: block))

            Text("One ring is one week; one notch is one finished session. Weeks still ahead are drawn as hairlines, so the shape you are growing into is visible from the first day.")
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
                WeekRow(week: index + 1,
                        marks: marks.indices.contains(index) ? marks[index] : 0,
                        target: target,
                        state: state(ofWeek: index + 1, in: block))
            }
            Rule()
        }
    }

    private func state(ofWeek week: Int, in block: Block) -> WeekRow.State {
        if week < block.currentWeek { .past }
        else if week == block.currentWeek { .current }
        else { .ahead }
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
        }
    }

    private var practiceNote: String {
        let run = MorningPractices.run(in: context)
        guard run > 0 else { return "\(Practice.count) movements · \(Int(Practice.seconds))s each" }
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

    private func seasonNote(for block: Block) -> String {
        let total = marksByWeek(for: block).reduce(0, +)
        return total == 0 ? "Not yet drawn" : "\(total) marks"
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
    let marks: Int
    let target: Int
    let state: State

    var body: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(spacing: 10) {
                Text(String(format: "%02d", week))
                    .almanacLabel(state == .current ? Palette.saffronInk : Palette.mute, small: true)
                    .tabular()

                HStack(spacing: 3) {
                    ForEach(0..<max(target, 1), id: \.self) { index in
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
            }
            .padding(.vertical, 9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Week \(week)")
        .accessibilityValue(state == .ahead ? "Still ahead"
                            : "\(marks) of \(target) sessions finished")
    }

    /// A week you have lived is moss; today's week is saffron, which is the one
    /// place on this screen saffron is allowed.
    private var fill: Color { state == .current ? Palette.saffron : Palette.moss }

    private var measure: String {
        switch state {
        case .ahead: "—"
        default: "\(marks)/\(target)"
        }
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
