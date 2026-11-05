import SwiftUI
import VikuDesignSystem
import VikuUI

/// Links to other guides, shown after the article body as a native grouped
/// list. The article scrolls as a whole, so the list never scrolls itself and
/// is sized to its content.
struct DocumentationRelatedArticlesView: View {
    let entries: [DocumentationEntry]
    let onSelect: (String) -> Void

    @Environment(\.vikuPalette) private var palette
    @ScaledMetric(relativeTo: .body) private var estimatedRowHeight = VikuSpacing.xxl + VikuSpacing.sm
    @State private var contentHeight: CGFloat?

    var body: some View {
        List {
            Section {
                ForEach(entries) { entry in
                    Button {
                        onSelect(entry.id)
                    } label: {
                        DocumentationEntryRow(entry: entry, style: .compact)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(palette.cardBackground)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Related Articles")
                    .vikuSectionHeader()
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .listStyle(.insetGrouped)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, height in
            contentHeight = height
        }
        // Until the list reports its size, reserve a close estimate so the
        // article doesn't jump when the real height arrives.
        .frame(height: contentHeight ?? estimatedRowHeight * CGFloat(entries.count + 1))
    }
}
