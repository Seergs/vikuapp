/// Relay filter for assignment creation notifications within one project.
public enum AssignmentNotificationMode: String, Codable, Sendable, CaseIterable {
    case all
    case onlyMe = "only_me"
}
