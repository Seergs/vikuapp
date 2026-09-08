import SwiftUI
import VikunjaCore

/// The compact task row shared by every screen that lists tasks (Today,
/// a project's overview, Search). A circular completion checkbox, a
/// strikethrough-on-done title, a one-line metadata row (project dot + name,
/// due date or an "Overdue" label, a link glyph when the task has relations),
/// up to two label pills plus a "+N" overflow pill, and a trailing priority
/// dot.
///
/// The whole row is tappable (`onOpen`); the checkbox handles its own tap so
/// it never bubbles up. Callers supply the long-press menu via
/// `contextMenu` — its contents differ per screen (Search has no "Move",
/// etc.).
public struct VikuTaskRow<Menu: View>: View {
    /// The number of label pills shown inline before collapsing the rest into
    /// a "+N" pill.
    public static var labelDisplayLimit: Int {
        2
    }

    private let task: VikunjaTask
    private let project: Project?
    private let showsProjectBadge: Bool
    private let onToggle: () -> Void
    private let onOpen: () -> Void
    @ViewBuilder private let contextMenu: () -> Menu

    /// - Parameters:
    ///   - task: the task to render.
    ///   - project: the task's project. Drives the checkbox tint and, when
    ///     `showsProjectBadge` is `true`, the metadata row's dot + name.
    ///   - showsProjectBadge: whether to show the project dot + name in the
    ///     metadata row. A project's own overview passes `false` (the project
    ///     is already the screen title); everywhere else leaves it `true`.
    ///   - onToggle: completion checkbox tapped.
    ///   - onOpen: the row (anywhere but the checkbox) tapped.
    ///   - contextMenu: the long-press menu contents for this screen.
    public init(
        task: VikunjaTask,
        project: Project?,
        showsProjectBadge: Bool = true,
        onToggle: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        @ViewBuilder contextMenu: @escaping () -> Menu,
    ) {
        self.task = task
        self.project = project
        self.showsProjectBadge = showsProjectBadge
        self.onToggle = onToggle
        self.onOpen = onOpen
        self.contextMenu = contextMenu
    }

    private var checkboxColor: Color {
        project.flatMap { Color(vikuHex: $0.hexColor) } ?? VikuColor.brandPrimary
    }

    private var isOverdue: Bool {
        guard let dueDate = task.dueDate, !task.isDone else { return false }
        return dueDate < Date()
    }

    private var badge: (title: String, color: Color)? {
        guard showsProjectBadge, let project else { return nil }
        return (project.title, checkboxColor)
    }

    /// Whether the metadata row has anything to show besides the link glyph.
    /// When it doesn't (a project overview task with no due date), the glyph
    /// would sit alone on its own line, so it moves up next to the title.
    private var hasMetadataLine: Bool {
        badge != nil || isOverdue || task.dueDate != nil
    }

    public var body: some View {
        HStack(alignment: .top, spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            checkbox
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: VikuSpacing.xs + VikuSpacing.xxs) {
                HStack(spacing: VikuSpacing.xs) {
                    Text(task.title)
                        .font(VikuFont.body)
                        .fontWeight(.medium)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? VikuColor.textTertiary : Color.primary)

                    if !hasMetadataLine, task.hasRelations {
                        linkGlyph
                    }
                }

                if hasMetadataLine {
                    metadataRow
                }

                if !task.labels.isEmpty {
                    labelRow
                }
            }

            Spacer(minLength: VikuSpacing.sm)

            if let priorityColor = VikuColor.Priority.dot(for: task.priority) {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, VikuSpacing.xs)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu(menuItems: contextMenu)
    }

    private var checkbox: some View {
        Button(action: onToggle) {
            Circle()
                .strokeBorder(task.isDone ? Color.clear : checkboxColor, lineWidth: 2)
                .background(Circle().fill(task.isDone ? checkboxColor : Color.clear))
                .frame(width: 24, height: 24)
                .overlay {
                    if task.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var metadataRow: some View {
        HStack(spacing: VikuSpacing.xs + VikuSpacing.xxs) {
            if let badge {
                HStack(spacing: VikuSpacing.xs) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(badge.color)
                        .frame(width: 6, height: 6)
                    Text(badge.title)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(VikuColor.textSecondary)
                        .truncationMode(.tail)
                }
            }

            if badge != nil, isOverdue || task.dueDate != nil {
                Text("·")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VikuColor.textSecondary)
            }

            // The due date / "Overdue" label and the relations glyph stay at
            // their natural width so a long project name is what truncates,
            // keeping the row to one line.
            Group {
                if isOverdue {
                    Text("Overdue")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(VikuColor.Semantic.dangerText)
                } else if let dueDate = task.dueDate {
                    Text(DueDateFormatter.compact(dueDate))
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(VikuColor.textSecondary)
                }

                if task.hasRelations {
                    linkGlyph
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .lineLimit(1)
    }

    private var linkGlyph: some View {
        Image(systemName: "link")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(VikuColor.textTertiary)
    }

    private var labelRow: some View {
        HStack(spacing: VikuSpacing.xs + VikuSpacing.xxs) {
            ForEach(task.labels.prefix(Self.labelDisplayLimit)) { label in
                TaskRowLabelPill(label: label)
            }

            let remaining = task.labels.count - Self.labelDisplayLimit
            if remaining > 0 {
                TaskRowExtraLabelsPill(count: remaining)
            }
        }
    }
}

private struct TaskRowLabelPill: View {
    let label: VikunjaCore.Label

    private var color: Color {
        Color(vikuHex: label.hexColor) ?? VikuColor.textSecondary
    }

    var body: some View {
        Text(label.title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.xxs)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

private struct TaskRowExtraLabelsPill: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(VikuColor.textTertiary)
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.xxs)
            .background(Capsule().fill(VikuColor.textSecondary.opacity(0.14)))
    }
}
