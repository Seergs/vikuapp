import Foundation
import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The Due date and Priority rows on the task detail screen — two tappable
/// `InfoRow`s, the first opening the due-date sheet, the second a priority menu.
struct DueDatePriorityRows: View {
    @Bindable var viewModel: TaskDetailViewModel
    let onEditDueDate: () -> Void

    var body: some View {
        let task = viewModel.task

        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            Button(action: onEditDueDate) {
                InfoRow(
                    systemImage: "calendar",
                    iconColor: task.dueDate == nil ? VikuColor.textTertiary : VikuColor.textSecondary,
                    title: String(localized: "Due", bundle: .module),
                    value: task.dueDate.map { DueDateFormatter.dueLabel($0) }
                        ?? String(localized: "Set due date", bundle: .module),
                    valueColor: task.dueDate == nil
                        ? VikuColor.textTertiary
                        : (isOverdue(task) ? VikuColor.Semantic.dangerText : nil),
                    showsChevron: true,
                )
            }
            .buttonStyle(.plain)

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
                }
            } label: {
                InfoRow(
                    systemImage: "flag",
                    iconColor: priorityDisplay(task.priority)?.color ?? VikuColor.textTertiary,
                    title: String(localized: "Priority", bundle: .module),
                    value: priorityDisplay(task.priority)?.label ?? String(localized: "Set priority", bundle: .module),
                    valueColor: priorityDisplay(task.priority)?.color ?? VikuColor.textTertiary,
                    showsChevron: true,
                )
            }
            .buttonStyle(.plain)
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
