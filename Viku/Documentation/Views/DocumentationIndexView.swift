import SwiftUI
import VikuDesignSystem
import VikuNavigation

/// The index and search content are bundled and available without connectivity.
struct DocumentationIndexView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.vikuPalette) private var palette
    @Environment(\.locale) private var locale
    @State private var viewModel = DocumentationIndexViewModel()
    @ScaledMetric(relativeTo: .body) private var iconSize = VikuSpacing.xl + VikuSpacing.sm

    var body: some View {
        List {
            Section {
                if viewModel.articles.isEmpty {
                    ContentUnavailableView.search(text: viewModel.query)
                        .listRowBackground(palette.pageBackground)
                } else {
                    ForEach(viewModel.articles) { article in
                        articleRow(article)
                    }
                }
            } footer: {
                supportFooter
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.pageBackground)
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $viewModel.query,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text("Search Help"),
        )
        .task(id: locale.identifier) {
            viewModel.loadSearchIndex(preferredLanguages: [locale.identifier])
        }
    }

    private func articleRow(_ article: DocumentationArticle) -> some View {
        Button {
            router.push(.documentationArticle(article.id))
        } label: {
            HStack(spacing: VikuSpacing.md) {
                Image(systemName: article.systemImage)
                    .font(VikuFont.title3.weight(.semibold))
                    .foregroundStyle(article.tint.color)
                    .frame(width: iconSize, height: iconSize)
                    .background(
                        article.tint.color.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                    Text(verbatim: article.title)
                        .font(VikuFont.body.weight(.bold))
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

    private var supportFooter: some View {
        VStack(spacing: VikuSpacing.xs) {
            Text("Can't find what you're looking for?")
                .foregroundStyle(palette.textSecondary)
            if let url = URL(string: "https://github.com/Seergs/vikuapp/issues/new") {
                Link("Contact Support", destination: url)
                    .fontWeight(.bold)
                    .foregroundStyle(palette.brand)
            }
        }
        .font(VikuFont.footnote)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, VikuSpacing.lg)
        .textCase(nil)
    }
}

#Preview {
    NavigationStack {
        DocumentationIndexView()
    }
    .environment(AppRouter())
}
