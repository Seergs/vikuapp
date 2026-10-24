import Testing
@testable import VikuDesignSystem

struct AccentTintTests {
    @Test
    func `a recognized name resolves to its token`() {
        #expect(VikuColor.AccentTint.named("purple") == .purple)
        #expect(VikuColor.AccentTint.named("teal") == .teal)
    }

    @Test
    func `an unrecognized name falls back to blue`() {
        #expect(VikuColor.AccentTint.named("magenta") == .blue)
        #expect(VikuColor.AccentTint.named("") == .blue)
    }
}
