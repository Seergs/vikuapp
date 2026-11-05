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
            Section {
                if viewModel.entries.isEmpty {
                    ContentUnavailableView.search(text: viewModel.query)
                        .listRowBackground(palette.pageBackground)
                } else {
                    ForEach(viewModel.entries) { entry in
                        articleRow(entry)
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
            viewModel.load(preferredLanguages: [locale.identifier])
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
