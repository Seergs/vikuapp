import Foundation

/// A read-only search. Names resolve against the current account's local catalog;
/// unknown names impose no restriction and duplicate names include every match.
public struct TaskSearchQuery: Equatable, Sendable {
    public let text: String
    public let projectName: String?
    public let labelNames: [String]
    public let priority: VikunjaTask.Priority?

    public init(
        text: String,
        projectName: String? = nil,
        labelNames: [String] = [],
        priority: VikunjaTask.Priority? = nil,
    ) {
        self.text = text
        self.projectName = projectName
        self.labelNames = labelNames
        self.priority = priority
    }

    /// Text, project and priority combine with AND. Labels combine with OR.
    /// Matching uses EntityID so pending local creations remain searchable.
    public func filter(tasks: [VikunjaTask], projects: [Project], labels: [Label]) -> [VikunjaTask] {
        let projectIDs = Set(projects.filter { project in
            projectName.map { Self.fold(project.title) == Self.fold($0) } ?? false
        }.map(\.id))
        let names = Set(labelNames.map(Self.fold))
        let labelIDs = Set(labels.filter { names.contains(Self.fold($0.title)) }.map(\.id))

        return tasks.filter { task in
            (text.isEmpty || task.title.localizedCaseInsensitiveContains(text))
                && (projectIDs.isEmpty || projectIDs.contains(task.projectID))
                && (labelIDs.isEmpty || task.labels.contains { labelIDs.contains($0.id) })
                && (priority == nil || task.priority == priority)
        }
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
