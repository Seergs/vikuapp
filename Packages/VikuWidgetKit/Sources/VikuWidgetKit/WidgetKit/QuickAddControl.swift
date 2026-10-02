// Controls are an iOS Control Center / Lock Screen feature; `os(iOS)` keeps
// this out of the macOS build, where `ControlWidget` needs a far newer floor
// than the package's.
#if canImport(WidgetKit) && os(iOS)
import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center / Lock Screen / Action Button control that opens the app's
/// quick-add task sheet, via `QuickAddControlIntent`. Deliberately a plain SF
/// Symbol rather than `VikuGlyphMark` (the custom glyph `QuickAddWidget` draws
/// on the Lock Screen): a control's icon is rasterized into a template image
/// the system tints/inverts per render context (a dark Control Center tile,
/// the Action Button assignment sheet, always-on display, ...), and a custom
/// SwiftUI view built from `GeometryReader` + blend modes can't be captured
/// that way — it renders as a "?" placeholder instead. Add `QuickAddControl()`
/// to the widget extension's `WidgetBundle` (behind an iOS 18 availability
/// check, since the package floor is iOS 17).
@available(iOS 18.0, *)
public struct QuickAddControl: ControlWidget {
    public init() {}

    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: VikuWidgetConfig.quickAddControlKind) {
            ControlWidgetButton(action: QuickAddControlIntent()) {
                Label {
                    Text("Add Task", bundle: .module)
                } icon: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .displayName("Add Task")
        .description("Open Viku's quick-add sheet.")
    }
}
#endif
