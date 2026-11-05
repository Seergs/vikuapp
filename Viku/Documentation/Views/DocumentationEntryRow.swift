import SwiftUI
import VikuDesignSystem

/// An article's icon, title, and summary, shared by the index and the related
/// articles list. The caller supplies the tap target and surrounding chrome.
struct DocumentationEntryRow: View {
    enum Style {
        /// Bold title with its summary and a large icon.
        case regular
        /// Title only, with a lighter weight and a smaller icon.
        case compact
    }

    let entry: DocumentationEntry
    var style = Style.regular

    @Environment(\.vikuPalette) private var palette
    @ScaledMetric(relativeTo: .body) private var regularIconSize = VikuSpacing.xl + VikuSpacing.sm
    @ScaledMetric(relativeTo: .body) private var compactIconSize = VikuSpacing.lg + VikuSpacing.xs

    private var isCompact: Bool {
        style == .compact
    }

    var body: some View {
        HStack(spacing: VikuSpacing.md) {
            Image(systemName: entry.article.systemImage)
                .font(isCompact ? VikuFont.footnote.weight(.semibold) : VikuFont.title3.weight(.semibold))
                .foregroundStyle(entry.article.tint.color)
                .frame(
                    width: isCompact ? compactIconSize : regularIconSize,
                    height: isCompact ? compactIconSize : regularIconSize,
                )
                .background(
                    entry.article.tint.color.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                Text(verbatim: entry.title)
                    .font(isCompact ? VikuFont.body : VikuFont.body.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                if !isCompact, !entry.summary.isEmpty {
                    Text(verbatim: entry.summary)
                        .font(VikuFont.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(VikuFont.footnote)
                .foregroundStyle(palette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, VikuSpacing.xs)
        .contentShape(Rectangle())
    }
}
