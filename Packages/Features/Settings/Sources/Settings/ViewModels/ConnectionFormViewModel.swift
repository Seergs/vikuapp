import Foundation
import Observation
import VikunjaCore

/// Drives the "add/edit connection" screen (`ConnectionFormMode.create` or
/// `.edit`). The fields, validation, and the probe/OIDC/password/save flows
/// all live in `VikunjaCore`'s `ConnectionEditorCore`, shared with
/// `Onboarding`'s `InstanceSetupViewModel`. This adds only what's specific to
/// managing an existing set of connections: `mode` (and the `isEditing`/
/// `currentMethod` it drives), prefilling an existing token, deleting a
/// connection, and a toast + active-account notification after every save.
///
/// Saving always re-probes the server, in both modes: editing a connection is
/// exactly as likely to introduce a typo'd URL as creating one, so there's no
/// reason to trust an unchanged-looking field over a freshly typed one.
@MainActor
@Observable
public final class ConnectionFormViewModel {
    public let mode: ConnectionFormMode

    private let core: ConnectionEditorCore
    private let accountStore: AccountStoreProtocol
    private let notificationSettingsStore: NotificationSettingsStore
    /// Deletes `account`'s webhooks and unregisters it from the push relay.
    /// Lives in the composition root, not here: resolving a working
    /// credential for a password/OIDC account needs `PasswordSessionRefresher`
    /// (`VikunjaNetworking`), which Features may never import — only
    /// `AppContainer` is allowed to know about it. Called unconditionally;
    /// it's this closure's own job to no-op when notifications aren't
    /// enabled for the account.
    private let teardownNotifications: (InstanceAccount) async -> Void
    private let toastPresenter: ToastPresenting
    /// Fired after a save/delete that may have changed which account is
    /// active, or edited the active account's own address — either way the
    /// app target needs to rebuild the main tab shell. See
    /// `ConnectionsListViewModel`'s copy of the same reasoning.
    private let onActiveAccountChanged: () -> Void

    public init(
        mode: ConnectionFormMode,
        accountStore: AccountStoreProtocol,
        clientFactory: InstanceClientFactoryProtocol,
        notificationSettingsStore: NotificationSettingsStore,
        teardownNotifications: @escaping (InstanceAccount) async -> Void,
        toastPresenter: ToastPresenting,
        oidcAuthenticator: OIDCAuthenticating,
        oidcRedirectURI: URL,
        onActiveAccountChanged: @escaping () -> Void,
    ) {
        self.mode = mode
        self.accountStore = accountStore
        self.notificationSettingsStore = notificationSettingsStore
        self.teardownNotifications = teardownNotifications
        self.toastPresenter = toastPresenter
        self.onActiveAccountChanged = onActiveAccountChanged

        let editingAccount: InstanceAccount? = if case let .edit(account) = mode {
            account
        } else {
            nil
        }
        self.core = ConnectionEditorCore(
            editingAccount: editingAccount,
            accountStore: accountStore,
            clientFactory: clientFactory,
            oidcAuthenticator: oidcAuthenticator,
            oidcRedirectURI: oidcRedirectURI,
        )
        core.onStored = { [weak self] _ in
            guard let self else { return }
            toastPresenter.show(
                isEditing
                    ? String(localized: "Connection updated", bundle: .module)
                    : String(localized: "Connection added", bundle: .module),
                style: .success,
            )
            onActiveAccountChanged()
        }
    }

    public var displayName: String {
        get { core.displayName }
        set { core.displayName = newValue }
    }

    public var urlText: String {
        get { core.urlText }
        set { core.urlText = newValue }
    }

    public var apiToken: String {
        get { core.apiToken }
        set { core.apiToken = newValue }
    }

    public var credentialMode: InstanceAccount.AuthMethod {
        get { core.credentialMode }
        set { core.credentialMode = newValue }
    }

    public var username: String {
        get { core.username }
        set { core.username = newValue }
    }

    public var password: String {
        get { core.password }
        set { core.password = newValue }
    }

    public var totpPasscode: String {
        get { core.totpPasscode }
        set { core.totpPasscode = newValue }
    }

    public var allowInsecureConnection: Bool {
        get { core.allowInsecureConnection }
        set { core.allowInsecureConnection = newValue }
    }

    public var validationState: ConnectionEditorPhase {
        core.phase
    }

    public var savedAccount: InstanceAccount? {
        core.savedAccount
    }

    public var localAuthAvailable: Bool {
        core.localAuthAvailable
    }

    public var oidcProviders: [OIDCProvider] {
        core.oidcProviders
    }

    public var awaitingTOTP: Bool {
        core.awaitingTOTP
    }

    public var isSaving: Bool {
        core.isSaving
    }

    /// Set while `deleteConnection()` is running — the webhook/relay
    /// teardown is a few real network round trips, so the toast can take a
    /// moment to appear and the screen would otherwise look stuck.
    public private(set) var isDeleting = false

    public var canSave: Bool {
        core.canSave
    }

    public var canTestConnection: Bool {
        core.canTestConnection
    }

    public var urlUsesInsecureScheme: Bool {
        core.urlUsesInsecureScheme
    }

    public var canSignInWithOIDC: Bool {
        core.canSignInWithOIDC
    }

    public var isEditing: Bool {
        if case .edit = mode {
            true
        } else {
            false
        }
    }

    /// The auth method the saved connection currently uses — `nil` in
    /// `.create` mode. Drives the "Current" tag on the matching accordion card
    /// so the user can see which method is stored before changing it.
    public var currentMethod: InstanceAccount.AuthMethod? {
        if case let .edit(account) = mode {
            account.authMethod
        } else {
            nil
        }
    }

    /// Fills in the existing token for `.edit` mode. Separate from `init`
    /// since reading it is async (Keychain) — the form renders immediately
    /// with name/URL already populated and the token field fills in a moment
    /// later, same as any other server-backed load in this app. A password or
    /// OIDC account's stored credential is opaque, so this only fills the
    /// token field for API-token accounts.
    public func load() async {
        guard case let .edit(account) = mode, account.authMethod == .apiToken else { return }
        core.apiToken = await (try? accountStore.token(forAccountID: account.id)) ?? ""
    }

    public func checkLocalAuthAvailability() async {
        await core.checkLocalAuthAvailability()
    }

    public func testConnection() async {
        await core.testConnection()
    }

    public func signInWithOIDC(_ provider: OIDCProvider) async {
        await core.signInWithOIDC(provider)
    }

    public func save() async {
        await core.save()
    }

    /// Whether notifications are currently enabled for the connection being
    /// edited — `false` outside `.edit` mode. Drives the extra line in the
    /// delete confirmation dialog warning that removing the connection also
    /// turns off its notifications.
    public var notificationsEnabledForThisConnection: Bool {
        guard case let .edit(account) = mode else { return false }
        return notificationSettingsStore.settings(for: account.id).isEnabled
    }

    /// Deletes the connection being edited. No-op outside `.edit` mode.
    /// Refuses (with a toast) to delete the last remaining connection —
    /// there always has to be one active account for the main tab shell to
    /// render against.
    @discardableResult
    public func deleteConnection() async -> Bool {
        guard case let .edit(account) = mode else { return false }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let remaining = try await accountStore.fetchAccounts()
            guard remaining.count > 1 else {
                toastPresenter.show(
                    String(localized: "You need at least one connection", bundle: .module),
                    style: .error,
                )
                return false
            }
            let activeID = try await accountStore.activeAccount()?.id
            // Tear down notifications before removing the account — the
            // credential needed to delete the webhook server-side goes away
            // with it, so this is the last chance to do it cleanly.
            await teardownNotifications(account)
            try await accountStore.removeAccount(id: account.id)
            toastPresenter.show(String(localized: "Connection removed", bundle: .module), style: .success)
            if activeID == account.id {
                onActiveAccountChanged()
            }
            return true
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
            return false
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
            return false
        }
    }
}
