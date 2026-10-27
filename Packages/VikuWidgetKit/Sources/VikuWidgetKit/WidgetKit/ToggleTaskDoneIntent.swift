#if canImport(AppIntents)
import AppIntents
import VikunjaCore
import WidgetKit

/// Flips a task's completion state straight from the widget, without opening
/// the app. Backed by the same repository stack the timeline provider uses;
/// WidgetKit reloads the timeline once `perform()` returns.
public struct ToggleTaskDoneIntent: AppIntent {
    public static let title: LocalizedStringResource = "Toggle Task Completion"
    public static let description = IntentDescription("Marks a Vikunja task done or not done.")
    public static let isDiscoverable = false

    @Parameter(title: "Task ID")
    public var taskID: Int

    public init() {}

    public init(taskID: Int) {
        self.taskID = taskID
    }

    public func perform() async throws -> some IntentResult {
        guard let repository = await VikuWidgetEnvironment.makeTaskRepository() else {
            return .result()
        }
        var task = try await repository.fetchTask(id: .remote(taskID))
        task.isDone.toggle()
        _ = try await repository.update(task)
        return .result()
    }
}
#endif
