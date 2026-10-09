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
    let deliveryWarning: ReminderDeliveryWarning?
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
                            preciseLabel: ReminderFormatter.preciseLabel(for: reminder),
                            onTap: { onEdit(index) },
                            onRemove: { onRemove(index) },
                        )
                    }
                    if let deliveryWarning {
                        ReminderDeliveryWarningBanner(warning: deliveryWarning)
                    }
                }
            }
        }
    }
}

private struct ReminderDeliveryWarningBanner: View {
    let warning: ReminderDeliveryWarning

    private var message: String {
        switch warning {
        case .pushDisabled:
            String(
                localized: "Won't ring on this iPhone: push notifications are off. Turn them on in Settings.",
                bundle: .module,
            )
        case .eventNotSubscribed:
            String(
                localized: "Won't ring on this iPhone: reminders are off for this project. Turn them on in Settings.",
                bundle: .module,
            )
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(VikuColor.Semantic.dangerText)
            Text(verbatim: message)
                .font(VikuFont.footnote)
                .foregroundStyle(VikuColor.Semantic.dangerText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.sm)
        .background(
            VikuColor.Semantic.danger.opacity(0.12),
            in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
        )
    }
}

private struct ReminderRow: View {
    let label: String
    /// The reminder's resolved date/time, always shown below `label` in a
    /// smaller, subtler style — most useful for a relative reminder, whose
    /// `label` ("5 weeks after due date") never shows a clock time at all.
    let preciseLabel: String
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: VikuSpacing.sm) {
            Button(action: onTap) {
                HStack(spacing: VikuSpacing.sm) {
                    Image(systemName: "bell")
                        .font(.system(size: 13))
                        .foregroundStyle(VikuColor.brandPrimary)
                    VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                        Text(verbatim: label)
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundStyle(Color.primary)
                        Text(verbatim: preciseLabel)
                            .font(VikuFont.caption2)
                            .foregroundStyle(VikuColor.textTertiary)
                    }
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
