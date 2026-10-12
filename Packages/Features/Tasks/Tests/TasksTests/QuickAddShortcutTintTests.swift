@testable import Tasks
import Testing
import VikuDesignSystem
import VikunjaCore

struct QuickAddShortcutTintTests {
    @Test
    func `a project resolution tints with the given palette's brand color`() {
        let project = QuickAddParser.Resolution.project(Project(id: 1, title: "Compras"))

        #expect(project.tint(in: .standard) == VikuPalette.standard.brand)
        #expect(project.tint(in: .warm) == VikuPalette.warm.brand)
    }

    @Test
    func `a new label resolution tints with the given palette's brand color`() {
        let newLabel = QuickAddParser.Resolution.newLabel("urgente")

        #expect(newLabel.tint(in: .standard) == VikuPalette.standard.brand)
        #expect(newLabel.tint(in: .warm) == VikuPalette.warm.brand)
    }

    @Test
    func `an unmatched project resolution tints with the given palette's danger text color`() {
        let unmatched = QuickAddParser.Resolution.unmatchedProject

        #expect(unmatched.tint(in: .standard) == VikuPalette.standard.semanticDangerText)
        #expect(unmatched.tint(in: .warm) == VikuPalette.warm.semanticDangerText)
    }

    @Test
    func `a superseded resolution has no tint regardless of palette`() {
        #expect(QuickAddParser.Resolution.superseded.tint(in: .standard) == nil)
        #expect(QuickAddParser.Resolution.superseded.tint(in: .warm) == nil)
    }
}
