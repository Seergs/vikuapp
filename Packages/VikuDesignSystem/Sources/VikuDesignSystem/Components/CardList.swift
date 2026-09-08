import SwiftUI

public extension View {
    /// The "grouped card" recipe for one row in a run of rows inside a `.plain`
    /// `List`: inner padding, a card background, a hand-drawn divider between
    /// adjacent rows (`List`'s own separators stay hidden), and per-position
    /// corner rounding so the run reads as a single rounded card. Also strips
    /// the list row's own insets/separator/background.
    ///
    /// Each task is kept as its own `List` row (rather than all of them packed
    /// into one row as a real card) so a long-press highlight and `.contextMenu`
    /// only ever target the row under the finger — packed into a shared row,
    /// `List` highlights every row in the section at once.
    ///
    /// - Parameters:
    ///   - index: this row's position within the run.
    ///   - count: the number of rows in the run.
    func vikuCardRow(index: Int, count: Int) -> some View {
        modifier(VikuCardRowModifier(index: index, count: count))
    }
}

private struct VikuCardRowModifier: ViewModifier {
    let index: Int
    let count: Int

    private var isFirst: Bool {
        index == 0
    }

    private var isLast: Bool {
        index == count - 1
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, VikuSpacing.md)
            .padding(.vertical, VikuSpacing.sm)
            .background(VikuColor.Surface.card)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Divider().padding(.leading, VikuSpacing.md)
                }
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: isFirst ? VikuRadius.lg : 0,
                    bottomLeadingRadius: isLast ? VikuRadius.lg : 0,
                    bottomTrailingRadius: isLast ? VikuRadius.lg : 0,
                    topTrailingRadius: isFirst ? VikuRadius.lg : 0,
                    style: .continuous,
                ),
            )
            // Only the card itself gets breathing room from the screen edges —
            // any section label above it stays flush with the navigation title.
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xs)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
