import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the "Notifications" screen: the opt-in toggle (behind the consent
/// modal — see `NotificationsConsentSheet`), the user-level event
/// checkboxes, and each project's own event checkboxes — there's no
/// separate per-project on/off switch, selecting at least one event is what
/// turns a project's webhook on. Every change re-syncs Vikunja's webhooks to
/// match (`WebhookSyncing`) and persists the result, so the server and
/// `notificationSettingsStore` never drift from what's shown here.
@MainActor
@Observable
public final class NotificationsViewModel {
    public private(set) var settings: NotificationSettings
    public private(set) var projects: [Project] = []
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    /// Set when the OS permission is (or has become) denied — the view
    /// shows a banner pointing at the system Settings app instead of
    /// letting the toggle take effect.
    public private(set) var isPermissionDenied = false

    /// Which single row a change is currently in flight for — the OS
    /// permission prompt and relay round trip on first enable (which can
    /// take a few seconds on a real device), or the webhook sync that
    /// follows any other change. Scoped per-row rather than one shared
    /// flag: disabling (and `isSyncing`-driven styling) only ever applies
    /// to the row actually being changed, so flipping one toggle doesn't
    /// dim every other toggle on the screen at the same time.
    public enum PendingChange: Equatable, Sendable {
        case enabling
        case disabling
        case userLevel
        case project(Int)
    }

    public private(set) var pendingChange: PendingChange?

    /// The time of day (`HH:mm`, 24-hour) Vikunja checks this user's
    /// overdue tasks at — the "Overdue Tasks" row's own settings control.
    /// Drives both the server's daily overdue-tasks email and the
    /// `task.overdue` webhook this app subscribes to via `userLevelEvents`.
    /// Defaults to Vikunja's own default until `load()` fetches the real
    /// value, so the picker never flashes an empty state.
    public private(set) var overdueTasksRemindersTime = "09:00"
    /// The user's account-wide IANA zone (`User.timezone`) — not something
    /// specific to overdue reminders. It's what Vikunja uses to localize any
    /// of the user's reminder times, overdue reminders included, so
    /// `overdueTasksRemindersTime` must be read against this, not the
    /// device's own zone. `nil` until `load()` reports a value Vikunja
    /// actually has on file (the user never set one, or the fetch hasn't
    /// completed yet).
    public private(set) var accountTimezone: String?

    /// Whether *anything* is in flight — drives the delayed "Setting up
    /// notifications…" row, which isn't tied to any single toggle.
    public var isSyncing: Bool {
        pendingChange != nil
    }

    public var isLoading: Bool {
        loadState == .loading
    }

    /// This device's current relay registration, obtained the first time
    /// `enable(vikunjaUserID:)` succeeds — `nil` until then, or after
    /// `disable()`. Re-fetched (cheaply: see `RelayPushRegistrationService`)
    /// on every `load()` while `settings.isEnabled`, so a permission revoked
    /// from the system Settings app since the last launch is caught here.
    private var currentRegistration: PushRegistration?
    private var currentUserID: Int?
    /// The in-flight `load()` call, if any. `NotificationsView`'s `onAppear`
    /// can refire `load()` on this same cached view model (e.g. navigating
    /// into a project's notification screen and back) before the previous
    /// call has finished — without this, that re-entrant call would start a
    /// second concurrent `refreshRegistration()` round trip to the push
    /// relay, which the relay's own rate limiting on
    /// `POST /v1/registrations` can reject.
    private var loadTask: Task<Void, Never>?
    /// When `refreshRegistration()` last actually attempted its relay round
    /// trip. `load()` fires on every screen appearance, and the relay rate
    /// limits `POST /v1/registrations` per IP regardless of whether the
    /// calls are otherwise correctly serialized, so simply re-entering this
    /// screen a few times in under a minute would still trip it without
    /// this — `confirmEnable()`, a deliberate one-off user action, is never
    /// throttled by it.
    private var lastRegistrationRefreshAttempt: Date?
    private static let registrationRefreshCooldown: TimeInterval = 60

    private let accountID: InstanceAccount.ID
    private let webhookRepository: WebhookRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let userRepository: UserRepositoryProtocol
    private let pushNotificationRegistering: PushNotificationRegistering
    private let notificationSettingsStore: NotificationSettingsStore
    /// Read-only here: only used to inherit the device-wide preference onto
    /// this account the moment it enables push (`confirmEnable()`). Changing
    /// the preference itself, and fanning that change out to every other
    /// enabled account, is `GroupOverdueNotificationsViewModel`'s job, not
    /// this (per-account) view model's — see that type's doc comment.
    private let groupOverdueNotificationsStore: GroupOverdueNotificationsStoring
    private let toastPresenter: ToastPresenting
    private let syncCoordinator: WebhookSyncCoordinator

    public init(
        accountID: InstanceAccount.ID,
        webhookRepository: WebhookRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        userRepository: UserRepositoryProtocol,
        pushNotificationRegistering: PushNotificationRegistering,
        notificationSettingsStore: NotificationSettingsStore,
        groupOverdueNotificationsStore: GroupOverdueNotificationsStoring,
        toastPresenter: ToastPresenting,
        syncPlanner: WebhookSyncing = WebhookSyncPlanner(),
    ) {
        self.accountID = accountID
        self.webhookRepository = webhookRepository
        self.projectRepository = projectRepository
        self.userRepository = userRepository
        self.pushNotificationRegistering = pushNotificationRegistering
        self.notificationSettingsStore = notificationSettingsStore
        self.groupOverdueNotificationsStore = groupOverdueNotificationsStore
        self.toastPresenter = toastPresenter
        self.syncCoordinator = WebhookSyncCoordinator(webhookRepository: webhookRepository, syncPlanner: syncPlanner)
        self.settings = notificationSettingsStore.settings(for: accountID)
    }

    /// This device's relay URL, once registered — what a screen shows as
    /// "this is where your instance's webhooks point." `nil` until
    /// `confirmEnable()`/`load()` has successfully registered.
    public var relayTargetURL: URL? {
        currentRegistration?.targetURL
    }

    public func load() async {
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            async let fetchedProjects = projectRepository.fetchProjects()
            async let currentUser = userRepository.fetchCurrentUser()
            projects = try await fetchedProjects
            let user = try await currentUser
            currentUserID = user.id
            overdueTasksRemindersTime = user.overdueTasksRemindersTime ?? overdueTasksRemindersTime
            accountTimezone = user.timezone
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }

        if settings.isEnabled, isRegistrationRefreshDue {
            pendingChange = .enabling
            defer { pendingChange = nil }
            await refreshRegistration()
        }
    }

    private var isRegistrationRefreshDue: Bool {
        guard let lastRegistrationRefreshAttempt else { return true }
        return Date().timeIntervalSince(lastRegistrationRefreshAttempt) >= Self.registrationRefreshCooldown
    }

    /// Called from the consent modal's confirm button. `pendingChange`
    /// covers this whole flow, not just the webhook sync at the end — the
    /// OS permission prompt and the relay round trip
    /// (`refreshRegistration()`) can themselves take a few seconds on a
    /// real device, and the view should show that something's happening
    /// rather than look stuck.
    public func confirmEnable() async {
        pendingChange = .enabling
        defer { pendingChange = nil }

        guard await refreshRegistration() else { return }
        // So this account inherits the device's current group-overdue
        // preference right away, instead of defaulting to one push per task
        // until the next time the device-wide toggle happens to change (see
        // `GroupOverdueNotificationsViewModel.setEnabled(_:)`). Best-effort,
        // like every other relay call here: a failure leaves this account
        // ungrouped until the next launch's sync retries it
        // (`AppContainer.syncNotificationWebhooks`).
        try? await pushNotificationRegistering.updatePreferences(
            groupOverdueNotifications: groupOverdueNotificationsStore.isEnabled,
            accountID: accountID,
        )
        var updated = settings
        updated.isEnabled = true
        await apply(updated)
    }

    /// Resets the user-level and per-project selections along with turning
    /// the feature off, rather than leaving them checked but inert — so
    /// re-enabling later starts from a clean slate instead of silently
    /// recreating whatever was on before, which would look like it came
    /// back from nowhere.
    public func disable() async {
        pendingChange = .disabling
        defer { pendingChange = nil }

        var updated = settings
        updated.isEnabled = false
        updated.userLevelEvents = []
        updated.projectEvents = [:]
        await apply(updated)
        try? await pushNotificationRegistering.disable(accountID: accountID)
        currentRegistration = nil
    }

    public func setUserLevelEvent(_ event: WebhookEvent, isEnabled: Bool) async {
        pendingChange = .userLevel
        defer { pendingChange = nil }

        var updated = settings
        if isEnabled {
            updated.userLevelEvents.insert(event)
        } else {
            updated.userLevelEvents.remove(event)
        }
        await apply(updated)
    }

    /// Commits a new overdue-reminders time to Vikunja. Optimistic, with
    /// rollback on failure — matches `DefaultProjectSettingsViewModel`'s
    /// toast-on-failure convention. Not folded into `apply(_:)`: this is a
    /// plain user-settings write (`UserRepositoryProtocol`), not a webhook
    /// sync, so there's no registration/`syncCoordinator` round trip to do.
    public func setOverdueTasksRemindersTime(_ time: String) async {
        let previous = overdueTasksRemindersTime
        overdueTasksRemindersTime = time
        do {
            let updated = try await userRepository.updateOverdueTasksRemindersTime(time)
            overdueTasksRemindersTime = updated.overdueTasksRemindersTime ?? time
        } catch let error as VikunjaError {
            overdueTasksRemindersTime = previous
            toastPresenter.show(error.displayMessage, style: .error)
        } catch {
            overdueTasksRemindersTime = previous
            toastPresenter.show(error.localizedDescription, style: .error)
        }
    }

    public func setProjectEvent(_ event: WebhookEvent, isEnabled: Bool, for project: Project) async {
        pendingChange = .project(project.id)
        defer { pendingChange = nil }

        var updated = settings
        var events = updated.events(for: project.id)
        if isEnabled {
            events.insert(event)
        } else {
            events.remove(event)
        }
        updated.projectEvents[project.id] = events
        await apply(updated)
    }

    /// Replaces a project's whole event selection in one sync round trip —
    /// backs the event-group presets (Recommended/All/None) on the
    /// per-project screen, where applying each event individually would mean
    /// one sync call per toggle instead of one for the whole preset.
    public func setProjectEvents(_ events: Set<WebhookEvent>, for project: Project) async {
        pendingChange = .project(project.id)
        defer { pendingChange = nil }

        var updated = settings
        updated.projectEvents[project.id] = events
        await apply(updated)
    }

    /// Clears a project's event selection, which is what tears down its
    /// webhook — mirrors unchecking every event by hand, in one call.
    public func disableProjectWebhook(_ project: Project) async {
        await setProjectEvents([], for: project)
    }

    /// The webhooks already configured on this project that this device
    /// didn't create (a teammate's own Viku install, or one set up by hand —
    /// e.g. a Slack integration). Read-only: shown so a project's webhook
    /// screen doesn't look like it's the only thing pointed at that project
    /// when it isn't. Matches `WebhookSyncPlanner`'s own notion of "ours" —
    /// an exact `targetURL` match against this device's relay registration.
    public func otherWebhooks(for projectID: Int) async -> [Webhook] {
        guard let webhooks = try? await webhookRepository.fetchWebhooks(projectID: projectID) else { return [] }
        guard let relayTargetURL else { return webhooks }
        return webhooks.filter { $0.targetURL != relayTargetURL }
    }

    // MARK: - Private

    /// Requests authorization (a no-op prompt-wise if already decided) and
    /// registers with the relay. Sets `isPermissionDenied` either way, so
    /// the view's banner reflects the OS's current answer even when this is
    /// called from `load()` rather than a user tapping the toggle.
    ///
    /// `enable(vikunjaUserID:)` returning `nil` and it throwing are kept
    /// distinct on purpose: `nil` means the OS denied authorization (the
    /// view should point at the system Settings app), while a thrown error
    /// is a transient failure — the device-token request timing out, or the
    /// relay being unreachable — which the "re-enable in Settings" banner
    /// would misdescribe, so that surfaces as a toast instead.
    @discardableResult
    private func refreshRegistration() async -> Bool {
        guard let userID = await resolveUserID() else { return false }
        lastRegistrationRefreshAttempt = Date()
        do {
            guard let registration = try await pushNotificationRegistering.enable(
                vikunjaUserID: userID,
                accountID: accountID,
            ) else {
                isPermissionDenied = true
                currentRegistration = nil
                return false
            }
            isPermissionDenied = false
            currentRegistration = registration
            return true
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
            return false
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
            return false
        }
    }

    private func resolveUserID() async -> Int? {
        if let currentUserID {
            return currentUserID
        }
        guard let user = try? await userRepository.fetchCurrentUser() else { return nil }
        currentUserID = user.id
        return user.id
    }

    /// Reconciles the server's webhooks to `newSettings` via
    /// `syncCoordinator`, then persists it — only once the sync succeeds,
    /// so a failed request never leaves `notificationSettingsStore`
    /// claiming a state the server doesn't actually have.
    private func apply(_ newSettings: NotificationSettings) async {
        guard let registration = currentRegistration else {
            // Nothing to reconcile against (never enabled, or already
            // disabled) — e.g. toggling a project off while the feature
            // itself is off. Persist and exit.
            settings = newSettings
            notificationSettingsStore.save(newSettings, for: accountID)
            return
        }

        do {
            try await syncCoordinator.sync(settings: newSettings, registration: registration, projects: projects)
            settings = newSettings
            notificationSettingsStore.save(newSettings, for: accountID)
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
        }
    }
}
