import SwiftData
import SwiftUI

/// The only screen that asks about her body, and it asks once.
///
/// It exists because the alternative was worse: the app previously opened a
/// block with a starting weight and a goal already filled in — numbers nobody
/// had entered, presented as hers. An almanac records what happened; inventing
/// the first two entries is the one thing it must not do.
///
/// Two rules hold here. Nothing is prefilled that she did not type or that
/// Health did not measure, and the target date is a request rather than an
/// instruction — `Projection` will move the date before it moves the rate.
struct BlockSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// The most recent reading, if Health or a previous block left one. Offered
    /// as a starting point, never written in without her seeing it.
    var knownWeight: Double?
    var onFinish: (Block) -> Void

    @State private var current = ""
    @State private var goal = ""
    @State private var hasTargetDate = false
    @State private var targetDate = Date.now.addingTimeInterval(84 * 86_400)
    @State private var pace: Pace = .building

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Masthead(context: "New block")
                        .padding(.top, 4)

                    Text("Twelve weeks. The plan is written a week at a time, and revised from what you actually did.")
                        .font(.almanacBody)
                        .foregroundStyle(Palette.mute)
                        .fixedSize(horizontal: false, vertical: true)

                    IndexedSection(number: "01", label: "Weight") {
                        SectionHead(title: "Where you are")
                            .padding(.bottom, 10)

                        WeightField(label: "Today", text: $current)
                        WeightField(label: "Goal", text: $goal)

                        Text("Both optional. Leave them empty and the block still runs — the plan does not need a goal weight to program a week, and it never trains you differently because of one.")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }

                    if projection != nil {
                        IndexedSection(number: "02", label: "Date") {
                            SectionHead(title: "When", note: projection?.summary)
                                .padding(.bottom, 10)

                            CheckRow(title: "Aim for a date",
                                     note: hasTargetDate ? nil : "Otherwise the plan sets the pace.",
                                     selected: hasTargetDate) {
                                hasTargetDate.toggle()
                            }

                            if hasTargetDate {
                                DatePicker("Target date",
                                           selection: $targetDate,
                                           in: Date.now...,
                                           displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .font(.almanacBody)
                                    .tint(Palette.moss)
                                    .padding(.top, 8)
                            }

                            if let note = projection?.cappedNote {
                                Text(note)
                                    .font(.almanacBodySmall)
                                    .foregroundStyle(Palette.saffronInk)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 12)
                            }
                        }
                    }

                    IndexedSection(number: projection == nil ? "02" : "03", label: "Pace") {
                        SectionHead(title: "How hard", note: "\(pace.sessionsPerWeek)×/wk")
                            .padding(.bottom, 6)

                        ForEach(Pace.allCases) { option in
                            CheckRow(title: option.label, note: option.note,
                                     selected: pace == option) { pace = option }
                        }
                        Rule()

                        Text(pace.expectation)
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                    }

                    PrimaryButton(title: "Begin the block",
                                  subtitle: "12 weeks · \(pace.sessionsPerWeek) sessions a week") {
                        begin()
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Palette.oat.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
        }
        .task {
            if let knownWeight, current.isEmpty {
                current = String(format: "%.1f", knownWeight)
            }
        }
    }

    // MARK: - Derived

    private var currentPounds: Double? { Double(current.replacingOccurrences(of: ",", with: ".")) }
    private var goalPounds: Double? { Double(goal.replacingOccurrences(of: ",", with: ".")) }

    private var projection: Projection? {
        guard let currentPounds, let goalPounds else { return nil }
        return Projections.project(current: currentPounds,
                                   goal: goalPounds,
                                   requestedArrival: hasTargetDate ? targetDate : nil)
    }

    private func begin() {
        let block = Block(goalWeightPounds: goalPounds ?? 0,
                          startingWeightPounds: currentPounds ?? 0,
                          pace: pace)
        context.insert(block)

        // A weight she typed is a real reading and belongs in the record, so
        // the trend has something to average from day one.
        if let currentPounds {
            context.insert(WeightEntry(date: .now, pounds: currentPounds, source: .manual))
        }

        onFinish(block)
        dismiss()
    }
}

// MARK: - Parts

/// A number entry that stays in the register: mono, tabular, right-aligned, so
/// the two weights line up on the decimal the way they would on a page.
private struct WeightField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.almanacBody)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 12)
                TextField("—", text: $text)
                    .font(Face.mono(17))
                    .tabular()
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: 90)
                Text("lb").almanacLabel(Palette.mute, small: true)
            }
            .padding(.vertical, 12)
            Rule()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) weight in pounds")
    }
}

