import AppIntents

/// Siri / Spotlight / Action Button phrases for the app's App Intents. The
/// system discovers these from the app bundle at install time, so an
/// `AppShortcutsProvider` has to live in the app target rather than a package.
struct VikuShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateTaskIntent(),
            phrases: [
                // Every phrase must contain \(.applicationName). Spanish
                // translations live in AppShortcuts.xcstrings — Siri matches
                // phrases in its own language, not by the words spoken.
                "Add a task in \(.applicationName)",
                "Add a task to \(.applicationName)",
                "New task in \(.applicationName)",
                "Create a task in \(.applicationName)",
                "Quick add in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle.fill",
        )
    }
}
