/// Which of Vikunja's two webhook scopes (`VikunjaCore.WebhookRepositoryProtocol`)
/// an operation applies to.
public enum WebhookScope: Hashable, Sendable {
    case user
    case project(Int)
}
