import SwiftUI
import VikuDesignSystem
import VikuNavigation

/// The index and search content are bundled and available without connectivity.
struct DocumentationIndexView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.vikuPalette) private var palette
    @Environment(\.locale) private var locale
    @State private var viewModel = DocumentationIndexViewModel()

    var body: some View {
        List {
            if viewModel.entries.isEmpty {
                Section {
                    ContentUnavailableView.search(text: viewModel.query)
                        .listRowBackground(palette.pageBackground)
                } footer: {
                    supportFooter
                }
            } else {
                ForEach(sections, id: \.category) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            articleRow(entry)
                        }
                    } header: {
                        if let category = section.category {
                            Text(verbatim: category.title)
                        }
                    } footer: {
                        if section.category == sections.last?.category {
                            supportFooter
                        }
                    }
                }
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
            viewModel.load(preferredLanguages: [locale.identifier])
        }
    }

    /// Keep catalog order within each category and omit empty search sections.
    /// Articles with missing or unknown categories remain visible at the end.
    private var sections: [(category: DocumentationCategory?, entries: [DocumentationEntry])] {
        let entries = viewModel.entries
        let categories = DocumentationCategory.allCases.map(Optional.some) + [nil]
        return categories.compactMap { category in
            let matches = entries.filter { $0.category == category }
            return matches.isEmpty ? nil : (category: category, entries: matches)
        }
    }

    private func articleRow(_ entry: DocumentationEntry) -> some View {
        Button {
            router.push(.documentationArticle(entry.id))
        } label: {
            DocumentationEntryRow(entry: entry)
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
