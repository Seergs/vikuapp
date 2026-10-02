import Foundation
import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The Labels section: the task's label pills, or an "Add labels…" prompt when
/// it has none. The header's "+ Edit" button and the empty-state prompt both
/// open the label picker sheet.
struct LabelsSection: View {
    let labels: [VikunjaCore.Label]
    let onEdit: () -> Void

    var body: some View {
        SectionBlock(
            title: String(localized: "Labels", bundle: .module),
            trailing: AnyView(SectionHeaderButton(
                title: String(localized: "Edit", bundle: .module),
                action: onEdit,
            )),
        ) {
            if labels.isEmpty {
                Button(String(localized: "Add labels…", bundle: .module), action: onEdit)
                    .buttonStyle(.plain)
                    .font(VikuFont.subheadline)
                    .foregroundStyle(VikuColor.textTertiary)
            } else {
                LabelsWrap(labels: labels)
            }
        }
    }
}
