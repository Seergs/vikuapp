import Foundation
import VikunjaCore

/// A flattened, display-ready task for the Today widget. Deliberately a thin
/// value type — not a `VikunjaTask` — so the cached JSON payload and the
/// extension's memory stay small.
public struct TodayWidgetTask: Sendable, Hashable, Codable, Identifiable {
    public let id: Int
    public let title: String
    public let isDone: Bool
    public let dueDate: Date?
    public let bucket: TaskDueBucket
    public let projectName: String
    /// Raw `hex_color` off the task's project, or `""` when unset — the view
    /// resolves it through `Color(vikuHex:)` with a token fallback.
    public let projectColorHex: String

    public init(
        id: Int,
        title: String,
        isDone: Bool,
        dueDate: Date?,
        bucket: TaskDueBucket,
        projectName: String,
        projectColorHex: String,
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.dueDate = dueDate
        self.bucket = bucket
        self.projectName = projectName
        self.projectColorHex = projectColorHex
    }
}

/// The Today widget's data for one render: bucket counts plus a capped list of
/// tasks. Persisted to the App Group container so a failed refresh can fall
/// back to the last good render (`isStale == true`).
public struct TodayWidgetContent: Sendable, Hashable, Codable {
    public let accountName: String
    public let generatedAt: Date
    public var isStale: Bool
    public let overdueCount: Int
    public let todayCount: Int
    public let upcomingCount: Int
    /// Ordered overdue → today → upcoming, capped at `VikuWidgetConfig.taskLimit`.
    public let tasks: [TodayWidgetTask]

    public init(
        accountName: String,
        generatedAt: Date,
        isStale: Bool = false,
        overdueCount: Int,
        todayCount: Int,
        upcomingCount: Int,
        tasks: [TodayWidgetTask],
    ) {
        self.accountName = accountName
        self.generatedAt = generatedAt
        self.isStale = isStale
        self.overdueCount = overdueCount
        self.todayCount = todayCount
        self.upcomingCount = upcomingCount
        self.tasks = tasks
    }

    public var pendingCount: Int {
        overdueCount + todayCount
    }

    public func tasks(in bucket: TaskDueBucket) -> [TodayWidgetTask] {
        tasks.filter { $0.bucket == bucket }
    }

    /// Builds the content from a `TodayDigest` and a project lookup, keeping
    /// the same overdue → today → upcoming order the Home screen shows.
    public static func make(
        digest: TodayDigest,
        projectsByID: [Int: Project],
        accountName: String,
        now: Date,
        taskLimit: Int = VikuWidgetConfig.taskLimit,
    ) -> TodayWidgetContent {
        func widgetTask(_ task: VikunjaTask, _ bucket: TaskDueBucket) -> TodayWidgetTask {
            let project = task.projectID.remoteValue.flatMap { projectsByID[$0] }
            return TodayWidgetTask(
                id: task.id.remoteValue ?? -1,
                title: task.title,
                isDone: task.isDone,
                dueDate: task.dueDate,
                bucket: bucket,
                projectName: project?.title ?? "",
                projectColorHex: project?.hexColor ?? "",
            )
        }

        let ordered =
            digest.overdue.map { widgetTask($0, .overdue) }
                + digest.today.map { widgetTask($0, .today) }
                + digest.upcoming.map { widgetTask($0, .upcoming) }

        return TodayWidgetContent(
            accountName: accountName,
            generatedAt: now,
            overdueCount: digest.overdue.count,
            todayCount: digest.today.count,
            upcomingCount: digest.upcoming.count,
            tasks: Array(ordered.prefix(taskLimit)),
        )
    }
}

/// What the widget should render. `.content` covers both a fresh load and a
/// stale fallback — the view keys off `content.isStale` for the badge.
public enum TodayWidgetState: Sendable, Hashable {
    /// No active account configured — the user hasn't finished onboarding, or
    /// deleted their last connection.
    case notConnected
    /// The server rejected the stored token (401). The user needs to re-add
    /// the connection in Settings.
    case needsAuth
    /// The refresh failed and there's no cached snapshot to fall back on.
    case unavailable
    case content(TodayWidgetContent)
}

public extension TodayWidgetContent {
    /// Sample data for the widget gallery and SwiftUI previews.
    static let placeholder = TodayWidgetContent(
        accountName: "Viku",
        generatedAt: Date(),
        overdueCount: 2,
        todayCount: 3,
        upcomingCount: 4,
        tasks: [
            TodayWidgetTask(
                id: 1, title: "Reply to the hosting invoice", isDone: false, dueDate: Date(),
                bucket: .overdue, projectName: "Admin", projectColorHex: "#E85E00",
            ),
            TodayWidgetTask(
                id: 2, title: "Draft the release notes", isDone: false, dueDate: Date(),
                bucket: .today, projectName: "Vikunja iOS", projectColorHex: "#196AFF",
            ),
            TodayWidgetTask(
                id: 3, title: "Water the plants", isDone: false, dueDate: Date(),
                bucket: .today, projectName: "Home", projectColorHex: "#1FA669",
            ),
            TodayWidgetTask(
                id: 4, title: "Book the dentist", isDone: false, dueDate: Date().addingTimeInterval(86400),
                bucket: .upcoming, projectName: "Health", projectColorHex: "#DF202E",
            ),
        ],
    )
}
