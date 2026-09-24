import SwiftUI
import Testing
@testable import VikuDesignSystem

struct ColorHexTests {
    @Test
    func `hex initializer matches components`() {
        let color = Color(hex: 0x196AFF)

        let expected = Color(.sRGB, red: 0x19 / 255, green: 0x6A / 255, blue: 0xFF / 255)
        #expect(color.resolve(in: .init()) == expected.resolve(in: .init()))
    }

    @Test
    func `viku hex parses with or without leading hash`() {
        #expect(Color(vikuHex: "196AFF")?.resolve(in: .init()) == Color(hex: 0x196AFF).resolve(in: .init()))
        #expect(Color(vikuHex: "#196AFF")?.resolve(in: .init()) == Color(hex: 0x196AFF).resolve(in: .init()))
    }

    @Test
    func `viku hex returns nil for empty or malformed input`() {
        #expect(Color(vikuHex: "") == nil)
        #expect(Color(vikuHex: "not-a-color") == nil)
        #expect(Color(vikuHex: "FF") == nil)
    }

    @Test
    func `viku muted hex keeps hue but clamps saturation and lightness`() {
        // HSL(0°, 38%, 46%) worked out by hand: chroma = (1 - |2×0.46-1|) ×
        // 0.38 ≈ 0.3496, max = L + chroma/2 ≈ 0.635 (≈ 0xA2), min = L -
        // chroma/2 ≈ 0.285 (≈ 0x49) — i.e. roughly #A24949. Compared with a
        // tolerance rather than `Color(vikuHex: "A24949")` exactly: rounding
        // a hex string to the nearest byte and this HSL formula's raw
        // doubles land a hair apart even when both mean the same color.
        guard let muted = Color(vikuMutedHex: "EF4444")?.resolve(in: .init()) else {
            Issue.record("expected a color")
            return
        }
        #expect(abs(muted.red - 0.635) < 0.01)
        #expect(abs(muted.green - 0.285) < 0.01)
        #expect(abs(muted.blue - 0.285) < 0.01)
    }

    @Test
    func `viku muted hex ignores the input's own saturation and lightness`() {
        // Only the hue is kept — a saturated red and a dark, washed-out red
        // land on the same muted color. This is what makes re-muting an
        // already-muted swatch (`VikuColor.SwatchPalette`) a no-op rather
        // than a second darkening pass.
        let fromSaturated = Color(vikuMutedHex: "EF4444")
        let fromMuted = Color(vikuMutedHex: "802020")
        #expect(fromSaturated?.resolve(in: .init()) == fromMuted?.resolve(in: .init()))
    }

    @Test
    func `viku muted hex returns nil for empty or malformed input`() {
        #expect(Color(vikuMutedHex: "") == nil)
        #expect(Color(vikuMutedHex: "not-a-color") == nil)
        #expect(Color(vikuMutedHex: "FF") == nil)
    }
}
