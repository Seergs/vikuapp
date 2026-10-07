import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the "Notifications" screen: the opt-in toggle (behind the consent
/// modal — see `NotificationsConsentSheet`), the user-level toggle, and a
/// per-project toggle list. Every toggle change re-syncs Vikunja's webhooks
/// to match (`WebhookSyncing`) and persists the result, so the server and
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
    /// True for the whole duration of a toggle's effect: the OS permission
    /// prompt and relay round trip on first enable (which can take a few
    /// seconds on a real device), plus the webhook sync that follows every
    /// settings change. The view disables its toggles and shows a spinner
    /// while this is true, so a slow round trip doesn't look like nothing
    /// happened.
    public private(set) var isSyncing = false

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

    private let webhookRepository: WebhookRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let userRepository: UserRepositoryProtocol
    private let pushNotificationRegistering: PushNotificationRegistering
    private let notificationSettingsStore: NotificationSettingsStore
    private let toastPresenter: ToastPresenting
    private let syncPlanner: WebhookSyncing

    public init(
        webhookRepository: WebhookRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        userRepository: UserRepositoryProtocol,
        pushNotificationRegistering: PushNotificationRegistering,
        notificationSettingsStore: NotificationSettingsStore,
        toastPresenter: ToastPresenting,
        syncPlanner: WebhookSyncing = WebhookSyncPlanner(),
    ) {
        self.webhookRepository = webhookRepository
        self.projectRepository = projectRepository
        self.userRepository = userRepository
        self.pushNotificationRegistering = pushNotificationRegistering
        self.notificationSettingsStore = notificationSettingsStore
        self.toastPresenter = toastPresenter
        self.syncPlanner = syncPlanner
        self.settings = notificationSettingsStore.settings
    }

    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            projects = try await projectRepository.fetchProjects()
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }

        if settings.isEnabled {
            isSyncing = true
            defer { isSyncing = false }
            await refreshRegistration()
        }
    }

    /// Called from the consent modal's confirm button. `isSyncing` covers
    /// this whole flow, not just the webhook sync at the end — the OS
    /// permission prompt and the relay round trip (`refreshRegistration()`)
    /// can themselves take a few seconds on a real device, and the view
    /// should show that something's happening rather than look stuck.
    public func confirmEnable() async {
        isSyncing = true
        defer { isSyncing = false }

        guard await refreshRegistration() else { return }
        var updated = settings
        updated.isEnabled = true
        await apply(updated)
    }

    public func disable() async {
        isSyncing = true
        defer { isSyncing = false }

        var updated = settings
        updated.isEnabled = false
        await apply(updated)
        try? await pushNotificationRegistering.disable()
        currentRegistration = nil
    }

    public func setUserLevelEnabled(_ isEnabled: Bool) async {
        isSyncing = true
        defer { isSyncing = false }

        var updated = settings
        updated.userLevelEnabled = isEnabled
        await apply(updated)
    }

    public func setProject(_ project: Project, isEnabled: Bool) async {
        isSyncing = true
        defer { isSyncing = false }

        var updated = settings
        if isEnabled {
            updated.enabledProjectIDs.insert(project.id)
        } else {
            updated.enabledProjectIDs.remove(project.id)
        }
        await apply(updated)
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
        do {
            guard let registration = try await pushNotificationRegistering.enable(vikunjaUserID: userID) else {
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

    /// Reconciles the server's webhooks to `newSettings` via `syncPlanner`,
    /// then persists it — only once the sync succeeds, so a failed request
    /// never leaves `notificationSettingsStore` claiming a state the server
    /// doesn't actually have.
    private func apply(_ newSettings: NotificationSettings) async {
        guard let registration = currentRegistration else {
            // Nothing to reconcile against (never enabled, or already
            // disabled) — e.g. toggling a project off while the feature
            // itself is off. Persist and exit.
            settings = newSettings
            notificationSettingsStore.save(newSettings)
            return
        }

        do {
            let userWebhooks = try await webhookRepository.fetchUserWebhooks()
            var projectWebhooks: [Int: [Webhook]] = [:]
            for project in projects {
                projectWebhooks[project.id] = try await webhookRepository.fetchWebhooks(projectID: project.id)
            }

            let plan = syncPlanner.plan(
                settings: newSettings,
                registration: registration,
                existingUserWebhooks: userWebhooks,
                existingProjectWebhooks: projectWebhooks,
            )
            try await applyPlan(
                plan,
                registration: registration,
                userWebhooks: userWebhooks,
                projectWebhooks: projectWebhooks,
            )

            settings = newSettings
            notificationSettingsStore.save(newSettings)
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
        }
    }

    private func applyPlan(
        _ plan: WebhookSyncPlan,
        registration: PushRegistration,
        userWebhooks: [Webhook],
        projectWebhooks: [Int: [Webhook]],
    ) async throws {
        for create in plan.creates {
            switch create.scope {
            case .user:
                _ = try await webhookRepository.createUserWebhook(
                    targetURL: registration.targetURL,
                    events: create.events,
                    secret: registration.secret,
                )
            case let .project(projectID):
                _ = try await webhookRepository.createWebhook(
                    projectID: projectID,
                    targetURL: registration.targetURL,
                    events: create.events,
                    secret: registration.secret,
                )
            }
        }

        for update in plan.updates {
            switch update.scope {
            case .user:
                guard var webhook = userWebhooks.first(where: { $0.id == update.webhookID }) else { continue }
                webhook.events = update.events
                _ = try await webhookRepository.updateUserWebhook(webhook)
            case let .project(projectID):
                guard var webhook = projectWebhooks[projectID]?.first(where: { $0.id == update.webhookID }) else {
                    continue
                }
                webhook.events = update.events
                _ = try await webhookRepository.updateWebhook(projectID: projectID, webhook)
            }
        }

        for delete in plan.deletes {
            switch delete.scope {
            case .user:
                try await webhookRepository.deleteUserWebhook(webhookID: delete.webhookID)
            case let .project(projectID):
                try await webhookRepository.deleteWebhook(projectID: projectID, webhookID: delete.webhookID)
            }
        }
    }
}
