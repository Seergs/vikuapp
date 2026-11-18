#if canImport(AppIntents)
import AppIntents
import Foundation
import VikunjaCore

/// Saves explicit completion locally and attempts a bounded upload without
/// opening the app. Accepted local changes request updated widget timelines.
/// Replayed taps from an old timeline
/// cannot toggle an already accepted completion back to its previous state.
public struct ToggleTaskDoneIntent: AppIntent {
    public static let title: LocalizedStringResource = "Toggle Task Completion"
    public static let description = IntentDescription("Marks a Vikunja task done or not done.")
    public static let isDiscoverable = false

    @Parameter(title: "Task ID")
    public var taskID: Int

    @Parameter(title: "Account ID")
    public var accountID: String

    @Parameter(title: "Completed")
    public var isDone: Bool

    public init() {}

    public init(taskID: Int, accountID: String, isDone: Bool) {
        self.taskID = taskID
        self.accountID = accountID
        self.isDone = isDone
    }

    public func perform() async throws -> some IntentResult {
        guard let accountID = UUID(uuidString: accountID) else { throw VikunjaError.notFound }
        let completion = try await VikuWidgetEnvironment.makeCompletion(accountID: accountID, taskID: taskID)
        let taskID = taskID
        let isDone = isDone
        try await completion.setCompletion(taskID: taskID, isDone: isDone)
        return .result()
    }
}
#endif
