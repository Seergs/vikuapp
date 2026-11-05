import SwiftUI
import VikuDesignSystem

/// Shared chrome for the article's overview cards: surface, rounded outline.
private struct DocumentationCardModifier: ViewModifier {
    @Environment(\.vikuPalette) private var palette

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous)
                    .strokeBorder(palette.textTertiary.opacity(0.35))
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func documentationCard() -> some View {
        modifier(DocumentationCardModifier())
    }
}

/// Hairline that matches the card outline at any display scale.
struct DocumentationCardSeparator: View {
    @Environment(\.vikuPalette) private var palette
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(palette.textTertiary.opacity(0.35))
            .frame(height: 1 / displayScale)
    }
}

/// The small uppercase title that opens a card.
struct DocumentationCardHeader: View {
    let title: LocalizedStringKey

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(VikuFont.caption.weight(.bold))
            .foregroundStyle(palette.textSecondary)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VikuSpacing.md)
    }
}
