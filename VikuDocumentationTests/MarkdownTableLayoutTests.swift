import SwiftUI
import Testing
import Textual
import UIKit
import VikuDesignSystem

@Suite(.serialized)
@MainActor
struct MarkdownTableLayoutTests {
    @Test(arguments: [CGFloat(320), 768], [DynamicTypeSize.large, .accessibility3])
    func `short tables expand their actual columns to the article width`(
        width: CGFloat, typeSize: DynamicTypeSize,
    ) async throws {
        let layout = try await measure("""
        | A | B |
        | --- | --- |
        | One | Two |
        """, width: width, typeSize: typeSize)

        #expect(abs(layout.bounds.width - (width - 2 * VikuSpacing.xxs)) < 1)
        #expect(layout.numberOfColumns == 2)
        #expect(layout.cellBounds(row: 1, column: 0).width > 100)
        #expect(layout.cellBounds(row: 1, column: 1).width > 100)
    }

    @Test
    func `long descriptions wrap within the article`() async throws {
        let layout = try await measure("""
        | Feature | Description |
        | --- | --- |
        | Projects | Organize related work into projects and keep all your tasks together. |
        """, width: 320)

        #expect(abs(layout.bounds.width - (320 - 2 * VikuSpacing.xxs)) < 1)
        #expect(layout.rowBounds(1).height > layout.rowBounds(0).height)
    }

    @Test
    func `wide tables retain their full column extent for scrolling`() async throws {
        let columns = Array(repeating: "Column", count: 24).joined(separator: " | ")
        let separator = Array(repeating: "---", count: 24).joined(separator: " | ")
        let layout = try await measure("| \(columns) |\n| \(separator) |\n| \(columns) |", width: 320)

        #expect(layout.numberOfColumns == 24)
        #expect(layout.bounds.width > 320)
        #expect(layout.cellBounds(row: 1, column: 23).maxX > 320)
    }

    private func measure(
        _ markdown: String, width: CGFloat, typeSize: DynamicTypeSize = .large,
    ) async throws -> StructuredText.TableLayout {
        let probe = TableLayoutProbe()
        let content = ScrollView {
            StructuredText(markdown: markdown)
                .textual.structuredTextStyle(VikuMarkdownStyle(palette: .standard))
                .textual.tableOverlay { layout in
                    Color.clear
                        .onChange(of: layout, initial: true) { _, value in
                            probe.layout = value
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environment(\.dynamicTypeSize, typeSize)
        let controller = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 1000))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds

        // Overflow learns its viewport width after its first layout pass.
        // Allow geometry and cell-bound preferences to settle before measuring.
        for _ in 0 ..< 20 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        let layout = try #require(probe.layout)
        #expect(layout.numberOfRows == 2)
        return layout
    }
}

@MainActor
private final class TableLayoutProbe {
    var layout: StructuredText.TableLayout?
}
