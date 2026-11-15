import SwiftUI

/// Keeps scroll-position updates local instead of reevaluating the board's columns.
struct KanbanHorizontalScroll<Content: View>: View {
    @State private var position: Int?
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal) {
            content
        }
        // Keep the visible bucket anchored as card content changes during a drag.
        .scrollPosition(id: $position)
        .scrollIndicators(.hidden)
    }
}
