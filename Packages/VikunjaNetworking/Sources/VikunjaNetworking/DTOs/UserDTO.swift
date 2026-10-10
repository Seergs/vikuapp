struct UserDTO: Codable {
    let id: Int
    let username: String
    let name: String?
    let email: String?
    /// Only present on the `GET /api/v1/user` response — absent when a
    /// `UserDTO` shows up embedded elsewhere (e.g. a comment's author).
    let settings: UserSettingsDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case name
        case email
        case settings
    }
}

/// Mirrors Vikunja's `UserGeneralSettings` (`pkg/models/user_settings.go`).
/// `POST /api/v1/user/settings/general` (and v2's `PUT` equivalent) replaces
/// every one of these fields unconditionally, so a caller updating just one
/// field (e.g. `default_project_id`) must decode this from the current
/// `GET /user` response first, change only that field, and send the whole
/// struct back — otherwise it silently resets the user's name, language,
/// reminders, etc. `frontendSettings` is passed through as opaque `JSONValue`
/// for the same reason `TaskDTO.reminders`/`assignees` do (see `JSONValue`'s
/// doc comment) rather than modeling its shape, which this app never reads.
/// `extra_settings_links` is omitted: it's server-computed and not one of the
/// fields the write endpoint accepts.
struct UserSettingsDTO: Codable {
    let name: String?
    let emailRemindersEnabled: Bool?
    let discoverableByName: Bool?
    let discoverableByEmail: Bool?
    let overdueTasksRemindersEnabled: Bool?
    let overdueTasksRemindersTime: String?
    let defaultProjectId: Int?
    let weekStart: Int?
    let language: String?
    let timezone: String?
    let frontendSettings: JSONValue?

    init(
        name: String? = nil,
        emailRemindersEnabled: Bool? = nil,
        discoverableByName: Bool? = nil,
        discoverableByEmail: Bool? = nil,
        overdueTasksRemindersEnabled: Bool? = nil,
        overdueTasksRemindersTime: String? = nil,
        defaultProjectId: Int? = nil,
        weekStart: Int? = nil,
        language: String? = nil,
        timezone: String? = nil,
        frontendSettings: JSONValue? = nil,
    ) {
        self.name = name
        self.emailRemindersEnabled = emailRemindersEnabled
        self.discoverableByName = discoverableByName
        self.discoverableByEmail = discoverableByEmail
        self.overdueTasksRemindersEnabled = overdueTasksRemindersEnabled
        self.overdueTasksRemindersTime = overdueTasksRemindersTime
        self.defaultProjectId = defaultProjectId
        self.weekStart = weekStart
        self.language = language
        self.timezone = timezone
        self.frontendSettings = frontendSettings
    }

    enum CodingKeys: String, CodingKey {
        case name
        case emailRemindersEnabled = "email_reminders_enabled"
        case discoverableByName = "discoverable_by_name"
        case discoverableByEmail = "discoverable_by_email"
        case overdueTasksRemindersEnabled = "overdue_tasks_reminders_enabled"
        case overdueTasksRemindersTime = "overdue_tasks_reminders_time"
        case defaultProjectId = "default_project_id"
        case weekStart = "week_start"
        case language
        case timezone
        case frontendSettings = "frontend_settings"
    }

    /// Returns a copy with only `default_project_id` changed, keeping every
    /// other field as-is for the required read-modify-write round trip.
    func updatingDefaultProjectId(_ newValue: Int) -> UserSettingsDTO {
        UserSettingsDTO(
            name: name,
            emailRemindersEnabled: emailRemindersEnabled,
            discoverableByName: discoverableByName,
            discoverableByEmail: discoverableByEmail,
            overdueTasksRemindersEnabled: overdueTasksRemindersEnabled,
            overdueTasksRemindersTime: overdueTasksRemindersTime,
            defaultProjectId: newValue,
            weekStart: weekStart,
            language: language,
            timezone: timezone,
            frontendSettings: frontendSettings,
        )
    }

    /// Returns a copy with only `overdue_tasks_reminders_time` changed,
    /// keeping every other field as-is for the required read-modify-write
    /// round trip.
    func updatingOverdueTasksRemindersTime(_ newValue: String) -> UserSettingsDTO {
        UserSettingsDTO(
            name: name,
            emailRemindersEnabled: emailRemindersEnabled,
            discoverableByName: discoverableByName,
            discoverableByEmail: discoverableByEmail,
            overdueTasksRemindersEnabled: overdueTasksRemindersEnabled,
            overdueTasksRemindersTime: newValue,
            defaultProjectId: defaultProjectId,
            weekStart: weekStart,
            language: language,
            timezone: timezone,
            frontendSettings: frontendSettings,
        )
    }
}
