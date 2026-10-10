/// Reads and updates the signed-in user's account settings (`GET`/`POST`
/// `/api/v1/user`, `/api/v1/user/settings/general`). Kept separate from
/// `AuthServiceProtocol` (which only knows how to exchange credentials for a
/// token) and from `ProjectRepositoryProtocol` — this is a user query/command,
/// not a project one.
public protocol UserRepositoryProtocol: Sendable {
    func fetchCurrentUser() async throws -> User

    /// Sets the project new tasks default into, or clears it when `id` is
    /// `nil`. Vikunja's general-settings endpoint replaces the whole settings
    /// object on write, so implementations must read-modify-write the other
    /// fields (name, language, reminders, …) rather than resetting them.
    func updateDefaultProject(id: Int?) async throws -> User

    /// Sets the time of day (`HH:mm`, 24-hour) Vikunja checks this user's
    /// overdue tasks at — see `User.overdueTasksRemindersTime`. Same
    /// read-modify-write requirement as `updateDefaultProject`.
    func updateOverdueTasksRemindersTime(_ time: String) async throws -> User
}
