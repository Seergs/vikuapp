import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// A chip for the one shortcut outcome that isn't self-evident from the
/// title's own inline tint: a label that will be created on save. An
/// unmatched/ambiguous project or label needs no chip of its own — like
/// Todoist and Fantastical, the title's tint (or lack of one, for text that
/// matched nothing) is the only signal; piling a second, separate "error"
/// element on top of that tint read as an alarm for something that isn't
/// actually a failure (the text is simply kept literal). Applied projects,
/// priorities and existing labels need no chip either, for the same reason.
///
/// Inserts/removes itself (`QuickAddSheetView.detentHeight` grows the sheet
/// to match, by the same `height` reused there) rather than reserving a
/// permanent slot: a slot that's always there, even empty, left dead space
/// either between the title and project fields (while sized to fit no chip)
/// or below the priority row (while sized to always fit one). Pops in
/// un-animated on purpose — see `QuickAddSheetView`'s comment on why.
struct QuickAddShortcutChips: View {
    /// `QuickAddSheetView.detentHeight` grows the sheet by exactly this much
    /// whenever `hasChip(in:)` is true for the current tokens, so the row's
    /// own appearance and the sheet's resize move by the same amount.
    static let height: CGFloat = 20

    let input: String
    let tokens: [QuickAddParser.ResolvedToken]

    static func hasChip(in tokens: [QuickAddParser.ResolvedToken]) -> Bool {
        tokens.contains {
            if case .newLabel = $0.resolution {
                true
            } else {
                false
            }
        }
    }

    private var newLabelTokens: [QuickAddParser.ResolvedToken] {
        tokens.filter {
            if case .newLabel = $0.resolution {
                true
            } else {
                false
            }
        }
    }

    var body: some View {
        if !newLabelTokens.isEmpty {
            HStack(spacing: VikuSpacing.sm) {
                ForEach(Array(newLabelTokens.enumerated()), id: \.offset) { _, item in
                    chip(for: item)
                }
            }
            .frame(height: Self.height, alignment: .leading)
        }
    }

    @ViewBuilder
    private func chip(for item: QuickAddParser.ResolvedToken) -> some View {
        switch item.resolution {
        case .newLabel:
            ChipLabel(
                icon: "plus.circle.fill",
                title: String(localized: "New label", bundle: .module),
                value: rawText(item),
                iconTint: VikuColor.brandPrimary,
            )
        case .unmatchedProject, .ambiguousProject, .ambiguousLabel, .label, .project, .priority, .superseded:
            EmptyView()
        }
    }

    private func rawText(_ item: QuickAddParser.ResolvedToken) -> String {
        String(input[item.token.range])
    }
}

/// Plain icon + text, no badge background: a colored icon carries the
/// accent, the text stays in the normal secondary color, so this reads as a
/// quiet hint rather than an error (the title field already tints the
/// offending text in place).
private struct ChipLabel: View {
    let icon: String
    let title: String
    let value: String
    let iconTint: Color

    var body: some View {
        HStack(spacing: VikuSpacing.xs) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(iconTint)
            Text(verbatim: title)
                .font(VikuFont.footnote.weight(.semibold))
            Text(verbatim: value)
                .font(VikuFont.footnote)
        }
        .foregroundStyle(VikuColor.textSecondary)
    }
}
