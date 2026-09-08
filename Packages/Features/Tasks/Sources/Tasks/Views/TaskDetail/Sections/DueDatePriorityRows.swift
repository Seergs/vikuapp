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
                    title: "Due",
                    value: task.dueDate.map { DueDateFormatter.dueLabel($0) } ?? "Set due date",
                    valueColor: task.dueDate == nil
                        ? VikuColor.textTertiary
                        : (isOverdue(task) ? VikuColor.Semantic.dangerText : nil),
                    showsChevron: true,
                )
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(VikunjaTask.Priority.allCases.filter { $0 != .doNow }, id: \.self) { priority in
                    Button {
                        Task { await viewModel.setPriority(priority) }
                    } label: {
                        HStack {
                            Text(priorityMenuLabel(priority))
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
                    title: "Priority",
                    value: priorityDisplay(task.priority)?.label ?? "Set priority",
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
        switch priority {
        case .unset: nil
        case .low: PriorityDisplay(label: "Low", color: VikuColor.Priority.low)
        case .medium: PriorityDisplay(label: "Medium", color: VikuColor.Priority.medium)
        case .high: PriorityDisplay(label: "High", color: VikuColor.Priority.high)
        case .urgent, .doNow: PriorityDisplay(label: "Urgent", color: VikuColor.Priority.urgent)
        }
    }

    private func priorityMenuLabel(_ priority: VikunjaTask.Priority) -> String {
        priorityDisplay(priority)?.label ?? "None"
    }
}
