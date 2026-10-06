import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// One chip per shortcut that needs attention or will do something on save: a
/// project or label that matched nothing useful, and a label that will be created.
/// Applied projects, priorities and existing labels need no chip, since the
/// title tints them in place.
struct QuickAddShortcutChips: View {
    let input: String
    let tokens: [QuickAddParser.ResolvedToken]

    var body: some View {
        if !tokens.isEmpty {
            HStack(spacing: VikuSpacing.sm) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, item in
                    chip(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(for item: QuickAddParser.ResolvedToken) -> some View {
        switch item.resolution {
        case .unmatchedProject:
            ChipLabel(
                title: String(localized: "Unknown project", bundle: .module),
                value: rawText(item),
                tint: VikuColor.Semantic.dangerText,
            )
        case .ambiguousProject:
            ChipLabel(
                title: String(localized: "Several projects match", bundle: .module),
                value: rawText(item),
                tint: VikuColor.Semantic.dangerText,
            )
        case .newLabel:
            ChipLabel(
                title: String(localized: "New label", bundle: .module),
                value: rawText(item),
                tint: VikuColor.brandPrimary,
            )
        case .ambiguousLabel:
            ChipLabel(
                title: String(localized: "Several labels match", bundle: .module),
                value: rawText(item),
                tint: VikuColor.Semantic.dangerText,
            )
        case .label, .project, .priority, .superseded:
            EmptyView()
        }
    }

    private func rawText(_ item: QuickAddParser.ResolvedToken) -> String {
        String(input[item.token.range])
    }
}

private struct ChipLabel: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: VikuSpacing.xs) {
            Text(verbatim: title)
                .font(VikuFont.footnote.weight(.semibold))
            Text(verbatim: value)
                .font(VikuFont.footnote)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xs)
        .padding(.vertical, VikuSpacing.xs)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}
