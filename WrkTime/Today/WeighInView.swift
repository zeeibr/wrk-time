import SwiftData
import SwiftUI

/// Records a weigh-in by hand.
///
/// Health is the usual source, but it cannot be the only one: the scale may not
/// write to Health, Health access may be declined, and the whole weight trend —
/// the headline figure, the projection, the chart — had no way to receive a
/// number without it. The block setup screen took one reading and then there
/// was no second door.
///
/// The date is editable because a weigh-in remembered at lunchtime still
/// belongs to the morning it happened.
struct WeighInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var pounds = ""
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Masthead(context: "Weigh-in")
                        .padding(.top, 4)

                    IndexedSection(number: "01", label: "Reading") {
                        SectionHead(title: "What it said")
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            HStack {
                                Text("Weight")
                                    .font(.almanacBody)
                                    .foregroundStyle(Palette.ink)
                                Spacer(minLength: 12)
                                TextField("—", text: $pounds)
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

                        DatePicker("When", selection: $date, in: ...Date.now,
                                   displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .font(.almanacBody)
                            .tint(Palette.moss)
                            .padding(.vertical, 10)
                        Rule()

                        Text("One reading is a number; the trend is what the app reads from. A single heavy morning moves the line very little, which is the point of averaging it.")
                            .font(.almanacBodySmall)
                            .foregroundStyle(Palette.mute)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                    }

                    PrimaryButton(title: "Record it", subtitle: nil) { save() }
                        .disabled(value == nil)
                        .opacity(value == nil ? 0.4 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Palette.oat.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.mute)
                }
            }
        }
    }

    private var value: Double? {
        Double(pounds.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil }
    }

    private func save() {
        guard let value else { return }
        // Marked `.manual` rather than `.health`, because where a number came
        // from is worth keeping — a typed reading and a scale reading deserve
        // different trust when projecting from them.
        context.insert(WeightEntry(date: date, pounds: value, source: .manual))
        dismiss()
    }
}
