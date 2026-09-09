import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore
import VikuUI

/// The Calendar screen: every project's dated tasks laid out on a month grid,
/// with the tapped day's tasks listed below. Tasks with no due date never
/// appear here — only inside their own project (same rule as Today).
struct CalendarView: View {
    @Bindable var viewModel: CalendarViewModel
    let router: Router<CalendarRoute>

    private let calendar = Calendar.current
    @State private var monthAnchor: Date = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        content
            .background(VikuColor.Surface.page)
            .navigationTitle("Calendar")
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failure(message):
            VikuStatusView(
                systemImage: "exclamationmark.triangle.fill",
                title: "Couldn't load your tasks",
                message: message,
            ) {
                Task { await viewModel.load() }
            }
        case .loaded:
            loadedContent
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: VikuRadius.lg, style: .continuous)
    }

    private var month: CalendarMonth {
        CalendarMonth(containing: monthAnchor, tasks: viewModel.tasks, calendar: calendar)
    }

    private var selectedTasks: [VikunjaTask] {
        CalendarMonth.tasks(on: selectedDay, from: viewModel.tasks, calendar: calendar)
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VikuSpacing.md) {
                monthHeader
                MonthGrid(
                    month: month,
                    selectedDay: selectedDay,
                    projectsByID: viewModel.projectsByID,
                    onSelect: { selectedDay = $0 },
                )
                .padding(VikuSpacing.md)
                .background(VikuColor.Surface.card, in: cardShape)
                .padding(.horizontal, VikuSpacing.md)

                selectedDaySection
            }
            .padding(.vertical, VikuSpacing.md)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VikuColor.textSecondary)
                    .frame(width: 32, height: 32)
            }

            Spacer()

            Text(month.title)
                .font(VikuFont.headline)
                .foregroundStyle(Color.primary)

            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VikuColor.textSecondary)
                    .frame(width: 32, height: 32)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, VikuSpacing.md)
    }

    @ViewBuilder
    private var selectedDaySection: some View {
        HStack(spacing: VikuSpacing.xs) {
            Text(selectedDayTitle)
                .fontWeight(.bold)
            if !selectedTasks.isEmpty {
                Text("\(selectedTasks.count)")
                    .fontWeight(.regular)
            }
        }
        .font(VikuFont.footnote)
        .foregroundStyle(VikuColor.textSecondary)
        .textCase(.uppercase)
        .kerning(0.3)
        .padding(.horizontal, VikuSpacing.md)
        .padding(.top, VikuSpacing.xs)

        if selectedTasks.isEmpty {
            Text("No tasks this day.")
                .font(VikuFont.subheadline)
                .foregroundStyle(VikuColor.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, VikuSpacing.lg)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(selectedTasks.enumerated()), id: \.element.id) { index, task in
                    CalendarTaskRow(
                        task: task,
                        project: viewModel.projectsByID[task.projectID],
                        onToggle: { Task { await viewModel.toggleDone(task) } },
                        onOpen: { open(task) },
                    )
                    .padding(.horizontal, VikuSpacing.md)
                    .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
                    if index < selectedTasks.count - 1 {
                        Divider().padding(.leading, VikuSpacing.md)
                    }
                }
            }
            .background(VikuColor.Surface.card, in: cardShape)
            .padding(.horizontal, VikuSpacing.md)
        }
    }

    private var selectedDayTitle: String {
        if calendar.isDateInToday(selectedDay) {
            return "Today"
        }
        return selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func shiftMonth(by delta: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        monthAnchor = shifted
    }

    private func open(_ task: VikunjaTask) {
        guard let project = viewModel.projectsByID[task.projectID] else { return }
        router.push(.taskDetail(task, project))
    }
}

/// The 7-column month grid: weekday header row plus one row per week, each day
/// a tappable cell with a selection/today ring and up to three project dots.
private struct MonthGrid: View {
    let month: CalendarMonth
    let selectedDay: Date
    let projectsByID: [Int: Project]
    let onSelect: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let calendar = Calendar.current

    var body: some View {
        LazyVGrid(columns: columns, spacing: VikuSpacing.xs) {
            ForEach(month.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(VikuColor.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, VikuSpacing.xs)
            }

            ForEach(month.weeks.flatMap(\.self)) { day in
                DayCell(
                    day: day,
                    isSelected: calendar.isDate(day.date, inSameDayAs: selectedDay),
                    dotColors: day.dotProjectIDs.map { projectColor(for: $0) },
                    onTap: { onSelect(day.date) },
                )
            }
        }
    }

    private func projectColor(for projectID: Int) -> Color {
        projectsByID[projectID].flatMap { Color(vikuHex: $0.hexColor) } ?? VikuColor.brandPrimary
    }
}

private struct DayCell: View {
    let day: CalendarMonth.Day
    let isSelected: Bool
    let dotColors: [Color]
    let onTap: () -> Void

    private var numberColor: Color {
        if isSelected {
            return .white
        }
        if day.hasOverduePending {
            return VikuColor.Priority.urgent
        }
        if !day.isInMonth {
            return VikuColor.textTertiary
        }
        return .primary
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: VikuSpacing.xs) {
                ZStack {
                    if isSelected {
                        Circle().fill(VikuColor.brandPrimary)
                    } else if day.isToday {
                        Circle().strokeBorder(VikuColor.brandPrimary, lineWidth: 1.5)
                    }
                    Text("\(day.dayNumber)")
                        .font(.system(size: 14.5, weight: day.isToday || isSelected ? .bold : .medium))
                        .foregroundStyle(numberColor)
                }
                .frame(width: 32, height: 32)

                HStack(spacing: 2.5) {
                    ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(isSelected ? Color.white : color)
                            .frame(width: 4.5, height: 4.5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Compact task row for the selected day's list. A local copy of Home's
/// `TodayTaskRow` recipe, trimmed to what this screen needs (no move/delete
/// context menu) — the shared feature rows are still per-feature today.
private struct CalendarTaskRow: View {
    static let labelDisplayLimit = 2

    let task: VikunjaTask
    let project: Project?
    let onToggle: () -> Void
    let onOpen: () -> Void

    private var projectColor: Color {
        project.flatMap { Color(vikuHex: $0.hexColor) } ?? VikuColor.brandPrimary
    }

    private var isOverdue: Bool {
        guard let dueDate = task.dueDate, !task.isDone else { return false }
        return dueDate < Date()
    }

    private var priorityColor: Color? {
        switch task.priority {
        case .unset: nil
        case .low: VikuColor.Priority.low
        case .medium: VikuColor.Priority.medium
        case .high: VikuColor.Priority.high
        case .urgent, .doNow: VikuColor.Priority.urgent
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            Button(action: onToggle) {
                Circle()
                    .strokeBorder(task.isDone ? Color.clear : projectColor, lineWidth: 2)
                    .background(Circle().fill(task.isDone ? projectColor : Color.clear))
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
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: VikuSpacing.xs + VikuSpacing.xxs) {
                Text(task.title)
                    .font(VikuFont.body)
                    .fontWeight(.medium)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? VikuColor.textTertiary : Color.primary)

                HStack(spacing: VikuSpacing.xs + VikuSpacing.xxs) {
                    if let project {
                        HStack(spacing: VikuSpacing.xs) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(projectColor)
                                .frame(width: 6, height: 6)
                            Text(project.title)
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundStyle(VikuColor.textSecondary)
                                .truncationMode(.tail)
                        }
                    }

                    if project != nil, task.dueDate != nil {
                        Text("·")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(VikuColor.textSecondary)
                    }

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
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(VikuColor.textTertiary)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .lineLimit(1)

                if !task.labels.isEmpty {
                    HStack(spacing: VikuSpacing.xs + VikuSpacing.xxs) {
                        ForEach(task.labels.prefix(Self.labelDisplayLimit)) { label in
                            CalendarLabelPill(label: label)
                        }
                        let remaining = task.labels.count - Self.labelDisplayLimit
                        if remaining > 0 {
                            Text("+\(remaining)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(VikuColor.textTertiary)
                                .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
                                .padding(.vertical, VikuSpacing.xxs)
                                .background(Capsule().fill(VikuColor.textSecondary.opacity(0.14)))
                        }
                    }
                }
            }

            Spacer(minLength: VikuSpacing.sm)

            if let priorityColor {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, VikuSpacing.xs)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

private struct CalendarLabelPill: View {
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
