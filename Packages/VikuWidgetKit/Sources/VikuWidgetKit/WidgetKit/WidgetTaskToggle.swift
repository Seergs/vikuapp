#if canImport(WidgetKit)
import SwiftUI
import VikuDesignSystem
import WidgetKit

/// WidgetKit optimistically updates a Toggle's isOn while its intent runs.
/// The style must draw from configuration.isOn, not the archived task value.
struct WidgetTaskToggle: View {
    let taskID: Int
    let accountID: String
    let sourceKind: String
    let title: String
    let isDone: Bool
    let color: Color

    var body: some View {
        #if os(iOS)
        Toggle(isOn: isDone, intent: ToggleTaskDoneIntent(
            taskID: taskID, accountID: accountID, isDone: !isDone, sourceKind: sourceKind,
        )) {
            Text(verbatim: title)
        }
        .toggleStyle(WidgetCompletionToggleStyle(color: color, title: title))
        #else
        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(color)
            .font(VikuFont.caption)
        #endif
    }
}

private struct WidgetCompletionToggleStyle: ToggleStyle {
    let color: Color
    let title: String

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Circle()
                .strokeBorder(configuration.isOn ? Color.clear : color, lineWidth: 1.5)
                .background(Circle().fill(configuration.isOn ? color : Color.clear))
                .frame(width: VikuSpacing.md - VikuSpacing.xxs, height: VikuSpacing.md - VikuSpacing.xxs)
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(VikuFont.caption2)
                            .imageScale(.small)
                            .foregroundStyle(VikuColor.textOnBrand)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(configuration.isOn
            ? Text("Completed", bundle: .module)
            : Text("Not completed", bundle: .module))
    }
}
#endif
