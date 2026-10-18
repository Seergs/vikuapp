import UserNotifications

/// `UNNotificationCategory` identifiers for a push whose action buttons the
/// app shows on long-press. Mirrors `viku-apn-relay`'s
/// `push.CategoryTaskReminderFired`/`push.CategoryTaskOverdue` constants
/// (the `aps.category` values it sends) -- the two must stay in sync, since
/// this is what tells iOS which actions belong to which push.
enum PushNotificationCategory {
    static let taskReminderFired = "TASK_REMINDER_FIRED"
    static let taskOverdue = "TASK_OVERDUE"
}

/// `UNNotificationAction` identifiers, matched against
/// `UNNotificationResponse.actionIdentifier` in
/// `AppDelegate.userNotificationCenter(_:didReceive:)` and dispatched to
/// `AppContainer.performNotificationAction`.
enum PushNotificationActionIdentifier {
    static let snoozeReminderTenMinutes = "SNOOZE_REMINDER_10M"
    static let snoozeReminderOneHour = "SNOOZE_REMINDER_1H"
    static let snoozeReminderThreeHours = "SNOOZE_REMINDER_3H"
    static let snoozeReminderOneDay = "SNOOZE_REMINDER_1D"
    static let rescheduleDueTomorrow = "RESCHEDULE_DUE_TOMORROW"
}

/// Registers the action buttons for every push category the app supports.
/// Safe to call on every launch regardless of notification authorization --
/// iOS just won't surface them until the user has granted it. Called from
/// `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
func registerPushNotificationCategories() {
    let snoozeTenMinutes = UNNotificationAction(
        identifier: PushNotificationActionIdentifier.snoozeReminderTenMinutes,
        title: String(localized: "Snooze 10m"),
        options: [],
    )
    let snoozeOneHour = UNNotificationAction(
        identifier: PushNotificationActionIdentifier.snoozeReminderOneHour,
        title: String(localized: "Snooze 1h"),
        options: [],
    )
    let snoozeThreeHours = UNNotificationAction(
        identifier: PushNotificationActionIdentifier.snoozeReminderThreeHours,
        title: String(localized: "Snooze 3h"),
        options: [],
    )
    let snoozeOneDay = UNNotificationAction(
        identifier: PushNotificationActionIdentifier.snoozeReminderOneDay,
        title: String(localized: "Snooze 1 Day"),
        options: [],
    )
    let rescheduleDue = UNNotificationAction(
        identifier: PushNotificationActionIdentifier.rescheduleDueTomorrow,
        title: String(localized: "Due Tomorrow"),
        options: [],
    )

    // iOS shows at most 4 action buttons on a long-press -- these four
    // cover the common snooze durations without crowding out the rest.
    let reminderFired = UNNotificationCategory(
        identifier: PushNotificationCategory.taskReminderFired,
        actions: [snoozeTenMinutes, snoozeOneHour, snoozeThreeHours, snoozeOneDay],
        intentIdentifiers: [],
        options: [],
    )
    let overdue = UNNotificationCategory(
        identifier: PushNotificationCategory.taskOverdue,
        actions: [rescheduleDue],
        intentIdentifiers: [],
        options: [],
    )

    UNUserNotificationCenter.current().setNotificationCategories([reminderFired, overdue])
}
