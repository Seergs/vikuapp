#if canImport(WidgetKit)
import Foundation
import SwiftUI
import VikuDesignSystem
import VikunjaCore
import WidgetKit

/// Root view for `CalendarWidget` (`.systemLarge` only). Branches on the
/// timeline state, then lays out the month grid over today's task list.
struct CalendarWidgetView: View {
    let entry: CalendarEntry

    private let contentInset = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)

    var body: some View {
        content
            .padding(contentInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(VikuColor.Surface.page, for: .widget)
            .widgetURL(URL(string: "\(VikuWidgetConfig.urlScheme)://calendar"))
    }

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .notConnected:
            CalendarWidgetMessage(
                systemImage: "link.circle",
                title: String(localized: "Not connected", bundle: .module),
                message: String(localized: "Open Viku to add your instance.", bundle: .module),
            )
        case .needsAuth:
            CalendarWidgetMessage(
                systemImage: "lock.circle",
                title: String(localized: "Sign in again", bundle: .module),
                message: String(
                    localized: "Your token was rejected. Re-add the connection in Settings.",
                    bundle: .module,
                ),
            )
        case .unavailable:
            CalendarWidgetMessage(
                systemImage: "wifi.slash",
                title: String(localized: "Couldn't refresh", bundle: .module),
                message: String(localized: "No connection and nothing saved yet.", bundle: .module),
            )
        case let .content(content):
            CalendarWidgetBody(content: content)
        }
    }
}

// MARK: - Loaded body

private struct CalendarWidgetBody: View {
    let content: CalendarWidgetContent

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xs) {
            header
            MonthGrid(content: content)
            Divider()
            todaySection
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: VikuSpacing.xs) {
            Text(verbatim: content.monthTitle)
                .font(VikuFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            if content.isStale {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(VikuColor.textTertiary)
                    .accessibilityLabel(Text("Showing saved data", bundle: .module))
            }
            if let url = URL(string: "\(VikuWidgetConfig.urlScheme)://quick-add") {
                Link(destination: url) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(VikuColor.brandPrimary)
                }
                .accessibilityLabel(Text("Add task", bundle: .module))
            }
        }
    }

    @ViewBuilder
    private var todaySection: some View {
        HStack(spacing: VikuSpacing.xs) {
            Text(verbatim: content.selectedDayLabel)
                .fontWeight(.bold)
            if content.todayTaskCount > 0 {
                Text(verbatim: "\(content.todayTaskCount)")
            }
        }
        .font(VikuFont.caption2)
        .textCase(.uppercase)
        .kerning(0.3)
        .foregroundStyle(VikuColor.textSecondary)

        if content.todayTasks.isEmpty {
            Text("Nothing due today.", bundle: .module)
                .font(VikuFont.caption)
                .foregroundStyle(VikuColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 1)
        } else {
            VStack(spacing: VikuSpacing.xs) {
                ForEach(content.todayTasks) { task in
                    CalendarWidgetTaskRow(task: task)
                }
            }
            let hidden = content.todayTaskCount - content.todayTasks.count
            if hidden > 0 {
                Text(String(localized: "+\(hidden) more", bundle: .module))
                    .font(VikuFont.caption2)
                    .foregroundStyle(VikuColor.textTertiary)
            }
        }
    }
}

// MARK: - Month grid

private struct MonthGrid: View {
    let content: CalendarWidgetContent

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: VikuSpacing.xxs) {
            ForEach(Array(content.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(verbatim: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(VikuColor.textTertiary)
                    .frame(maxWidth: .infinity)
            }
            ForEach(content.weeks.flatMap(\.self)) { day in
                DayCell(day: day)
            }
        }
    }
}

private struct DayCell: View {
    let day: CalendarWidgetDay

    private var numberColor: Color {
        if day.hasOverduePending {
            return VikuColor.Priority.urgent
        }
        if !day.isInMonth {
            return VikuColor.textTertiary
        }
        return .primary
    }

    var body: some View {
        VStack(spacing: 1.5) {
            ZStack {
                if day.isToday {
                    Circle().fill(VikuColor.brandPrimary.opacity(0.16))
                }
                Text(verbatim: "\(day.dayNumber)")
                    .font(.system(size: 12, weight: day.isToday ? .bold : .medium))
                    .foregroundStyle(day.isToday ? VikuColor.brandPrimary : numberColor)
            }
            .frame(width: 22, height: 22)

            HStack(spacing: 2) {
                ForEach(Array(day.dotColorHexes.enumerated()), id: \.offset) { _, hex in
                    Circle()
                        .fill(Color(vikuHex: hex) ?? VikuColor.brandPrimary)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Task row

private struct CalendarWidgetTaskRow: View {
    let task: CalendarWidgetTask

    private var projectColor: Color {
        Color(vikuHex: task.projectColorHex) ?? VikuColor.brandPrimary
    }

    var body: some View {
        HStack(spacing: VikuSpacing.xs + VikuSpacing.xxs) {
            toggle

            Text(verbatim: task.title)
                .font(VikuFont.caption)
                .fontWeight(.medium)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? VikuColor.textTertiary : Color.primary)
                .lineLimit(1)

            Spacer(minLength: VikuSpacing.xs)

            if task.isOverdue {
                Text("Overdue", bundle: .module)
                    .font(VikuFont.caption2)
                    .foregroundStyle(VikuColor.Semantic.dangerText)
            } else if !task.projectName.isEmpty {
                Text(verbatim: task.projectName)
                    .font(VikuFont.caption2)
                    .foregroundStyle(VikuColor.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
    }

    @ViewBuilder
    private var toggle: some View {
        let circle = Circle()
            .strokeBorder(task.isDone ? Color.clear : projectColor, lineWidth: 1.5)
            .background(Circle().fill(task.isDone ? projectColor : Color.clear))
            .frame(width: 14, height: 14)
            .overlay {
                if task.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

        #if os(iOS)
        Button(intent: ToggleTaskDoneIntent(taskID: task.id)) { circle }
            .buttonStyle(.plain)
        #else
        circle
        #endif
    }
}

// MARK: - Message

private struct CalendarWidgetMessage: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: VikuSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(VikuColor.textTertiary)
            Text(verbatim: title)
                .font(VikuFont.caption)
                .fontWeight(.semibold)
            Text(verbatim: message)
                .font(VikuFont.caption2)
                .foregroundStyle(VikuColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
