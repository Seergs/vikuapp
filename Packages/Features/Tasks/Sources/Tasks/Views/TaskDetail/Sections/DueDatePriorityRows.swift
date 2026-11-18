import Foundation
import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The Due date and Priority rows on the task detail screen — two tappable
/// `InfoRow`s, the first opening the due-date sheet, the second a priority menu.
struct DueDatePriorityRows: View {
    @Bindable var viewModel: TaskDetailViewModel
    let onEditDueDate: () -> Void

    @Environment(\.vikuPalette) private var palette

    private var dueDateValue: String {
        viewModel.task.dueDate.map { DueDateFormatter.dueLabel($0) }
            ?? String(localized: "Set due date", bundle: .module)
    }

    private var priorityValue: String {
        priorityDisplay(viewModel.task.priority)?.label ?? String(localized: "Set priority", bundle: .module)
    }

    var body: some View {
        let task = viewModel.task

        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            Button(action: onEditDueDate) {
                InfoRow(
                    systemImage: "calendar",
                    iconColor: task.dueDate == nil ? palette.textTertiary : palette.textSecondary,
                    title: String(localized: "Due", bundle: .module),
                    value: dueDateValue,
                    valueColor: task.dueDate == nil
                        ? palette.textTertiary
                        : (isOverdue(task) ? palette.semanticDangerText : nil),
                    showsChevron: true,
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("taskDetail.dueDate")
            .accessibilityLabel(Text("Due", bundle: .module))
            .accessibilityValue(Text(verbatim: dueDateValue))

            Menu {
                ForEach(VikunjaTask.Priority.selectable, id: \.self) { priority in
                    Button {
                        Task { await viewModel.setPriority(priority) }
                    } label: {
                        HStack {
                            Text(verbatim: priority.localizedMenuLabel)
                            if task.priority == priority {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .accessibilityIdentifier("taskDetail.priority.\(priority.rawValue)")
                }
            } label: {
                InfoRow(
                    systemImage: "flag",
                    iconColor: priorityDisplay(task.priority)?.color ?? palette.textTertiary,
                    title: String(localized: "Priority", bundle: .module),
                    value: priorityValue,
                    valueColor: priorityDisplay(task.priority)?.color ?? palette.textTertiary,
                    showsChevron: true,
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("taskDetail.priority")
            .accessibilityLabel(Text("Priority", bundle: .module))
            .accessibilityValue(Text(verbatim: priorityValue))
        }
        .padding(.top, VikuSpacing.lg)
    }

    private func isOverdue(_ task: VikunjaTask) -> Bool {
        guard let dueDate = task.dueDate, !task.isDone else { return false }
        return dueDate < Date()
    }

    private struct PriorityDisplay {
        let label: String
        let color: Color
    }

    private func priorityDisplay(_ priority: VikunjaTask.Priority) -> PriorityDisplay? {
        guard let color = VikuColor.Priority.dot(for: priority) else { return nil }
        return PriorityDisplay(label: priority.localizedMenuLabel, color: color)
    }
}

extension VikunjaTask.Priority {
    /// `displayName` (`VikunjaCore`) is plain English; this feature's priority
    /// menus need a localized label, so it owns its own translation here
    /// rather than reaching into Core, mirroring `PriorityOption.all` in
    /// `VikuDesignSystem`'s `TaskFormControls.swift` and `Home`/`Projects`'
    /// own `TodayView`/`ProjectOverviewView`. Internal (not `private`): also
    /// used by `TaskDetailView`'s own priority menu.
    var localizedMenuLabel: String {
        switch self {
        case .unset: String(localized: "None", bundle: .module)
        case .low: String(localized: "Low", bundle: .module)
        case .medium: String(localized: "Medium", bundle: .module)
        case .high: String(localized: "High", bundle: .module)
        case .urgent, .doNow: String(localized: "Urgent", bundle: .module)
        }
    }
}
