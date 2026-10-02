#if canImport(WidgetKit)
import Foundation
import SwiftUI
import VikuDesignSystem
import VikunjaCore
import WidgetKit

/// Root view for every `TodayWidget` family. Branches on the timeline state,
/// then on `widgetFamily` for the content layout.
struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    /// System content margins are disabled on the configuration; this is the
    /// inset every family gets instead, kept generous so text never reaches
    /// the widget edge.
    private var contentInset: EdgeInsets {
        family == .systemSmall
            ? EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
            : EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18)
    }

    var body: some View {
        content
            .padding(contentInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(VikuColor.Surface.page, for: .widget)
            .widgetURL(URL(string: "\(VikuWidgetConfig.urlScheme)://today"))
    }

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .notConnected:
            TodayWidgetMessage(
                systemImage: "link.circle",
                title: String(localized: "Not connected", bundle: .module),
                message: String(localized: "Open Vikunja to add your instance.", bundle: .module),
            )
        case .needsAuth:
            TodayWidgetMessage(
                systemImage: "lock.circle",
                title: String(localized: "Sign in again", bundle: .module),
                message: String(
                    localized: "Your token was rejected. Re-add the connection in Settings.",
                    bundle: .module,
                ),
            )
        case .unavailable:
            TodayWidgetMessage(
                systemImage: "wifi.slash",
                title: String(localized: "Couldn't refresh", bundle: .module),
                message: String(localized: "No connection and nothing saved yet.", bundle: .module),
            )
        case let .content(content):
            loadedContent(content)
        }
    }

    @ViewBuilder
    private func loadedContent(_ content: TodayWidgetContent) -> some View {
        switch family {
        case .systemSmall:
            TodaySmallView(content: content)
        case .systemMedium:
            TodayListView(content: content, rowLimit: 3)
        default:
            TodayListView(content: content, rowLimit: VikuWidgetConfig.taskLimit)
        }
    }
}

// MARK: - Small

private struct TodaySmallView: View {
    let content: TodayWidgetContent

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
            TodayWidgetHeader(content: content)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: VikuSpacing.xxs) {
                Text(verbatim: "\(content.pendingCount)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
                Text(pendingWord)
                    .font(VikuFont.caption)
                    .foregroundStyle(VikuColor.textSecondary)
            }

            Text(pendingBreakdown)
                .font(VikuFont.caption2)
                .foregroundStyle(VikuColor.textSecondary)
        }
    }

    /// The count renders in its own bold `Text` above, so this only needs the
    /// trailing word ("task"/"tasks"). The plural variable needs the count
    /// embedded to pick the right form, so it's resolved as one phrase and
    /// the leading digits are dropped rather than duplicating the number.
    private var pendingWord: String {
        let phrase = String(localized: "\(content.pendingCount) tasks", bundle: .module)
        guard let spaceIndex = phrase.firstIndex(of: " ") else { return phrase }
        return String(phrase[phrase.index(after: spaceIndex)...])
    }

    private var pendingBreakdown: String {
        if content.overdueCount > 0 {
            return String(
                localized: "\(content.overdueCount) overdue · \(content.todayCount) today",
                bundle: .module,
            )
        }
        return String(
            localized: "\(content.todayCount) today · \(content.upcomingCount) upcoming",
            bundle: .module,
        )
    }
}

// MARK: - Medium / Large

private struct TodayListView: View {
    let content: TodayWidgetContent
    let rowLimit: Int

    private var rows: [TodayWidgetTask] {
        Array(content.tasks.prefix(rowLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xs) {
            TodayWidgetHeader(content: content)

            if rows.isEmpty {
                Spacer(minLength: 0)
                Text("Nothing due. Enjoy it.", bundle: .module)
                    .font(VikuFont.caption)
                    .foregroundStyle(VikuColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: VikuSpacing.xs) {
                    ForEach(rows) { task in
                        TodayWidgetRow(task: task)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct TodayWidgetRow: View {
    let task: TodayWidgetTask

    private var projectColor: Color {
        Color(vikuHex: task.projectColorHex) ?? VikuColor.brandPrimary
    }

    var body: some View {
        HStack(spacing: VikuSpacing.xs + VikuSpacing.xxs) {
            toggle

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: task.title)
                    .font(VikuFont.caption)
                    .fontWeight(.medium)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? VikuColor.textTertiary : Color.primary)
                    .lineLimit(1)

                HStack(spacing: VikuSpacing.xs) {
                    if !task.projectName.isEmpty {
                        Circle().fill(projectColor).frame(width: 4, height: 4)
                        Text(verbatim: task.projectName)
                            .foregroundStyle(VikuColor.textSecondary)
                    }
                    if let due = dueLabel {
                        Text(verbatim: "· \(due)")
                            .foregroundStyle(
                                task.bucket == .overdue ? VikuColor.Semantic.dangerText : VikuColor.textSecondary,
                            )
                    }
                }
                .font(VikuFont.caption2)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
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

    private var dueLabel: String? {
        guard let dueDate = task.dueDate else { return nil }
        switch task.bucket {
        case .overdue: return String(localized: "Overdue", bundle: .module)
        case .today: return String(localized: "Today", bundle: .module)
        case .upcoming:
            return DueDateFormatter.compact(dueDate)
        }
    }
}

// MARK: - Shared pieces

private struct TodayWidgetHeader: View {
    @Environment(\.widgetFamily) private var family
    let content: TodayWidgetContent

    var body: some View {
        HStack(spacing: VikuSpacing.xs) {
            Text("Today", bundle: .module)
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(VikuColor.textSecondary)
            Spacer(minLength: 0)
            if content.isStale {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(VikuColor.textTertiary)
                    .accessibilityLabel(Text("Showing saved data", bundle: .module))
            }
            quickAddButton
        }
    }

    @ViewBuilder
    private var quickAddButton: some View {
        if family == .systemSmall {
            // `Link` only claims one tap target per `.systemSmall` widget,
            // already spoken for by `.widgetURL` on the whole card. An
            // App Intent-backed `Button` opens its own tap region instead, so
            // it works here too — and with the extra room this size has, the
            // glyph can afford to be bigger than the `Link` version below.
            #if os(iOS)
            Button(intent: QuickAddControlIntent()) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(VikuColor.brandPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Add task", bundle: .module))
            #endif
        } else if let url = quickAddURL {
            Link(destination: url) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VikuColor.brandPrimary)
            }
            .accessibilityLabel(Text("Add task", bundle: .module))
        }
    }

    private var quickAddURL: URL? {
        URL(string: "\(VikuWidgetConfig.urlScheme)://quick-add")
    }
}

private struct TodayWidgetMessage: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: VikuSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
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
