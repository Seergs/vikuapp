/// The shared account preference. `nil` settings means not downloaded yet;
/// `.disabled` is a known, explicit server value.
public enum QuickAddMagicMode: String, Codable, CaseIterable, Sendable {
    case disabled
    case vikunja
    case todoist

    public var syntax: QuickAddSyntax? {
        switch self {
        case .disabled: nil
        case .vikunja: .vikunja
        case .todoist: .todoist
        }
    }

    public init(syntax: QuickAddSyntax?) {
        switch syntax {
        case nil: self = .disabled
        case .vikunja: self = .vikunja
        case .todoist: self = .todoist
        }
    }
}

public struct QuickAddMagicSettings: Equatable, Sendable {
    public var mode: QuickAddMagicMode?
    public var syncStatus: SyncItemStatus?
    public var failureMessage: String?

    public init(mode: QuickAddMagicMode? = nil, syncStatus: SyncItemStatus? = nil, failureMessage: String? = nil) {
        self.mode = mode
        self.syncStatus = syncStatus
        self.failureMessage = failureMessage
    }
}
