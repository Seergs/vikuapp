import SwiftUI
import Testing
@testable import VikuDesignSystem

#if os(macOS)
import AppKit
#endif

struct NativeSheetAppearanceTests {
    private static let palettes: [VikuPalette] = [
        .standard, .warm, .nord, .solarized, .forest, .cyberpunk, .terminal, .vaporwave,
    ]

    @Test(arguments: palettes)
    func `utility sheets retain the accent but share neutral surfaces and text`(theme: VikuPalette) {
        let sheet = theme.nativeSheet

        #expect(sheet.brand == theme.brand)
        #expect(sheet.brandForeground == theme.brandForeground)
        var neutralColors = sheet
        neutralColors.brand = VikuPalette.standard.brand
        neutralColors.brandForeground = VikuPalette.standard.brandForeground
        #expect(neutralColors == VikuPalette.standard.nativeSheet)
        #expect(sheet.pageBackground == Color.platformPageBackground)
        #expect(sheet.cardBackground == Color.platformCardBackground)
        #expect(sheet.fieldBackground == Color.platformFieldBackground)
        #expect(sheet.textPrimary == Color.platformTextPrimary)
        #expect(sheet.textSecondary == Color.platformNativeTextSecondary)
        #expect(sheet.textTertiary == Color.platformNativeTextTertiary)
    }

    @Test(arguments: palettes)
    func `nested sheets preserve their appearance`(theme: VikuPalette) {
        let sheet = theme.nativeSheet

        #expect(sheet.nativeSheet == sheet)
    }

    #if os(macOS)
    @Test @MainActor
    func `sheet scope reaches the root and descendants without recoloring siblings`() {
        let recorder = AppearanceRecorder()
        let host = NSHostingView(rootView: AppearanceHarness(theme: .vaporwave, scheme: .dark, recorder: recorder))
        _ = host.fittingSize

        #expect(recorder.values["outside"]?.palette == .vaporwave)
        #expect(recorder.values["root"]?.palette == VikuPalette.vaporwave.nativeSheet)
        #expect(recorder.values["nested"]?.palette == VikuPalette.vaporwave.nativeSheet)
        #expect(recorder.values["root"]?.scheme == .dark)

        // Changing theme/appearance while content is mounted must not leave a
        // cached sheet accent or force a color scheme of its own.
        host.rootView = AppearanceHarness(theme: .forest, scheme: .light, recorder: recorder)
        _ = host.fittingSize

        #expect(recorder.values["outside"]?.palette == .forest)
        #expect(recorder.values["root"]?.palette == VikuPalette.forest.nativeSheet)
        #expect(recorder.values["nested"]?.palette == VikuPalette.forest.nativeSheet)
        #expect(recorder.values["root"]?.scheme == .light)
    }
    #endif
}

#if os(macOS)
@MainActor
private final class AppearanceRecorder {
    struct Snapshot {
        let palette: VikuPalette
        let scheme: ColorScheme
    }

    var values: [String: Snapshot] = [:]
}

private struct AppearanceHarness: View {
    let theme: VikuPalette
    let scheme: ColorScheme
    let recorder: AppearanceRecorder

    var body: some View {
        HStack {
            AppearanceProbe(name: "outside", recorder: recorder)
            VStack {
                AppearanceProbe(name: "root", recorder: recorder)
                AppearanceProbe(name: "nested", recorder: recorder)
                    .vikuNativeSheetAppearance()
            }
            .vikuNativeSheetAppearance()
        }
        .environment(\.vikuPalette, theme)
        .environment(\.colorScheme, scheme)
    }
}

private struct AppearanceProbe: View {
    let name: String
    let recorder: AppearanceRecorder
    @Environment(\.vikuPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        recorder.values[name] = .init(palette: palette, scheme: scheme)
        return Color.clear.frame(width: 1, height: 1)
    }
}
#endif
