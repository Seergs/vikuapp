import SwiftUI
import VikuDesignSystem
import VikuNavigation

/// All guide metadata is bundled, so the index is immediately available offline.
struct DocumentationIndexView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.vikuPalette) private var palette

    var body: some View {
        List(DocumentationArticle.allCases) { article in
            Button {
                router.push(.documentationArticle(article.id))
            } label: {
                HStack(spacing: VikuSpacing.md) {
                    Image(systemName: article.systemImage)
                        .font(VikuFont.title3)
                        .foregroundStyle(palette.brand)
                        .frame(width: VikuSpacing.lg)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                        Text(verbatim: article.title)
                            .font(VikuFont.body)
                            .foregroundStyle(palette.textPrimary)
                        Text(verbatim: article.summary)
                            .font(VikuFont.footnote)
                            .foregroundStyle(palette.textSecondary)
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
            .buttonStyle(.plain)
            .listRowBackground(palette.cardBackground)
            .accessibilityElement(children: .combine)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.pageBackground)
        .navigationTitle("Guides & Documentation")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        DocumentationIndexView()
    }
    .environment(AppRouter())
}
