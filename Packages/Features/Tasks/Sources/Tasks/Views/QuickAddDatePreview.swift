import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// Bounded, scrollable diagnostic presentation. The raw title and task due date remain untouched.
struct QuickAddDatePreview: View {
    static let height = VikuSpacing.xxl * 3

    let result: NaturalLanguageDateParser.Result
    let timeZone: TimeZone

    @Environment(\.vikuPalette) private var palette
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                Text("Date preview", bundle: .module)
                    .font(VikuFont.footnote.weight(.semibold))
                Text("Preview only. Dates are not applied.", bundle: .module)
                    .font(VikuFont.caption)
                Text(verbatim: timeZone.identifier)
                    .font(VikuFont.caption2)

                if result.expressions.isEmpty {
                    Text("No date recognized", bundle: .module)
                } else {
                    if result.expressions.count > 1 {
                        Text("Multiple date interpretations", bundle: .module)
                    }
                    ForEach(Array(result.expressions.enumerated()), id: \.offset) { _, expression in
                        VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                            Text(verbatim: expression.text)
                                .font(VikuFont.footnote.weight(.medium))
                            outcome(expression.outcome)
                        }
                    }
                }
            }
            .font(VikuFont.footnote)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VikuSpacing.sm)
        }
        .frame(height: Self.height)
        .background(palette.fieldBackground, in: RoundedRectangle(cornerRadius: VikuRadius.sm))
    }

    @ViewBuilder
    private func outcome(_ outcome: NaturalLanguageDateParser.Outcome) -> some View {
        switch outcome {
        case let .resolved(value):
            date(value.date)
        case let .ambiguous(_, alternatives):
            Text("Needs clarification", bundle: .module)
            ForEach(Array(alternatives.enumerated()), id: \.offset) { _, alternative in
                date(alternative.date)
            }
        case .invalid:
            Text("Invalid date or time", bundle: .module)
        case .incomplete:
            Text("Keep typing…", bundle: .module)
        case .unsupported:
            Text("Unsupported expression", bundle: .module)
        }
    }

    private func date(_ value: Date) -> some View {
        Text(value, format: Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: timeZone))
            // Text's date presentation also reads SwiftUI's environment time zone.
            .environment(\.timeZone, timeZone)
            .font(VikuFont.footnote.monospacedDigit())
    }
}
