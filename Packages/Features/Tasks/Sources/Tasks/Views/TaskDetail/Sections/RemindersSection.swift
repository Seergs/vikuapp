import Foundation
import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

/// The Reminders section: every `TaskReminder` on the task as its own row
/// (tap to edit, "x" to remove), or a placeholder when there are none.
/// Mirrors `RelationsSection`'s row layout — same card, same leading
/// icon+label/trailing "x" shape.
struct RemindersSection: View {
    let reminders: [TaskReminder]
    let onAdd: () -> Void
    let onEdit: (Int) -> Void
    let onRemove: (Int) -> Void

    var body: some View {
        SectionBlock(
            title: String(localized: "Reminders", bundle: .module),
            trailing: AnyView(SectionHeaderButton(
                title: String(localized: "Add", bundle: .module),
                action: onAdd,
            )),
        ) {
            if reminders.isEmpty {
                Text("No reminders set.", bundle: .module)
                    .font(VikuFont.subheadline)
                    .foregroundStyle(VikuColor.textTertiary)
            } else {
                VStack(spacing: VikuSpacing.sm) {
                    ForEach(Array(reminders.enumerated()), id: \.offset) { index, reminder in
                        ReminderRow(
                            label: ReminderFormatter.label(for: reminder),
                            onTap: { onEdit(index) },
                            onRemove: { onRemove(index) },
                        )
                    }
                }
            }
        }
    }
}

private struct ReminderRow: View {
    let label: String
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: VikuSpacing.sm) {
            Button(action: onTap) {
                HStack(spacing: VikuSpacing.sm) {
                    Image(systemName: "bell")
                        .font(.system(size: 13))
                        .foregroundStyle(VikuColor.brandPrimary)
                    Text(verbatim: label)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(VikuColor.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(VikuColor.Surface.field, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.sm)
        .background(VikuColor.Surface.card, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
    }
}
