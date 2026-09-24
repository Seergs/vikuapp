import Foundation

public struct VikunjaTask: Identifiable, Equatable, Hashable, Sendable {
    public let id: Int
    public var title: String
    public var description: String?
    public var isDone: Bool
    public var dueDate: Date?
    public var priority: Priority
    public var projectID: Int
    public var labels: [Label]
    /// Other tasks related to this one, keyed by relation direction rather
    /// than Vikunja's raw relation-kind strings ("subtask", "blocked",
    /// "blocking", ...) — this is the subset the app surfaces today; more
    /// kinds (e.g. "related", "duplicates") can be added the same way once a
    /// screen needs them.
    public var subtasks: [TaskRelation]
    /// Tasks this one is blocked by (Vikunja's "blocked" relation kind).
    public var dependsOn: [TaskRelation]
    /// Tasks waiting on this one (Vikunja's "blocking" relation kind).
    public var blocks: [TaskRelation]
    /// Every other relation kind Vikunja reports (e.g. "related", "precedes",
    /// "follows", "duplicateof") — kinds that don't need distinct UI
    /// treatment, so they're kept generic here rather than as one named
    /// property each.
    public var otherRelations: [RelationKind: [TaskRelation]]

    public init(
        id: Int,
        title: String,
        description: String? = nil,
        isDone: Bool = false,
        dueDate: Date? = nil,
        priority: Priority = .unset,
        projectID: Int,
        labels: [Label] = [],
        subtasks: [TaskRelation] = [],
        dependsOn: [TaskRelation] = [],
        blocks: [TaskRelation] = [],
        otherRelations: [RelationKind: [TaskRelation]] = [:],
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.isDone = isDone
        self.dueDate = dueDate
        self.priority = priority
        self.projectID = projectID
        self.labels = labels
        self.subtasks = subtasks
        self.dependsOn = dependsOn
        self.blocks = blocks
        self.otherRelations = otherRelations
    }

    /// Whether this task is still waiting on an incomplete `dependsOn` task.
    public var isBlocked: Bool {
        dependsOn.contains { !$0.isDone }
    }

    /// Whether this task has any relation shown in `TaskDetailView`'s
    /// "Relations" section — `dependsOn`, `blocks`, or any `otherRelations`
    /// kind. Deliberately excludes `subtasks`, which get their own checklist
    /// section instead.
    public var hasRelations: Bool {
        !dependsOn.isEmpty || !blocks.isEmpty || !otherRelations.isEmpty
    }

    public enum Priority: Int, Sendable, CaseIterable, Hashable {
        case unset = 0
        case low = 1
        case medium = 2
        case high = 3
        case urgent = 4
        case doNow = 5

        /// Human-readable label for priority menus. `.doNow` reads as
        /// "Urgent" - Vikunja's fifth priority level, but the app gives it
        /// no UI treatment distinct from `.urgent`.
        public var displayName: String {
            switch self {
            case .unset: "None"
            case .low: "Low"
            case .medium: "Medium"
            case .high: "High"
            case .urgent, .doNow: "Urgent"
            }
        }

        /// Every case a priority-picker menu should offer, in order - all of
        /// `allCases` except `.doNow`, which `displayName` already folds into
        /// `.urgent` and which no picker lets a user choose directly.
        public static var selectable: [Priority] {
            allCases.filter { $0 != .doNow }
        }
    }
}
