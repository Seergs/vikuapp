import Foundation
import Observation
import VikunjaCore

/// Drives the "add/edit connection" screen (`ConnectionFormMode.create` or
/// `.edit`). Mirrors `Onboarding`'s `InstanceSetupViewModel` — same
/// normalize-then-probe-`/api/v1/info` flow, and the same choice between an
/// API token and username/password (plus TOTP) login when the instance
/// supports it — but assumes at least one connection already exists (there's
/// always a `ConnectionsListView` to return to), and additionally supports
/// editing and deleting an existing connection.
///
/// Saving always re-probes the server, in both modes: editing a connection
/// is exactly as likely to introduce a typo'd URL as creating one, so there's
/// no reason to trust an unchanged-looking field over a freshly typed one.
@MainActor
@Observable
public final class ConnectionFormViewModel {
    public let mode: ConnectionFormMode

    public var displayName: String = ""
    public var urlText: String = ""
    public var apiToken: String = ""
    public var credentialMode: InstanceAccount.AuthMethod = .apiToken
    public var username: String = ""
    public var password: String = ""
    public var totpPasscode: String = ""
    /// Opt-in to an `http://` instance address. Off by default — HTTPS is
    /// required unless the user explicitly turns this on for a local or
    /// trusted-network instance, and the view shows an "insecure connection"
    /// warning while it's on. Pre-enabled in `.edit` mode when the saved
    /// connection's address is already `http://`.
    public var allowInsecureConnection: Bool = false

    public private(set) var validationState: ConnectionValidationState = .idle
    /// The account `save()` most recently persisted — distinct from
    /// `validationState == .success`, which `testConnection()` also reports
    /// on a successful probe. Drives post-save dismissal.
    public private(set) var savedAccount: InstanceAccount?
    /// Whether the probed server reports local (username/password) login as
    /// enabled — known only after a probe has resolved (see
    /// `checkLocalAuthAvailability()`, called automatically as the user
    /// types the address); defaults to `false` so the password option starts
    /// disabled rather than hidden.
    public private(set) var localAuthAvailable = false
    /// OIDC providers the probed server has configured — known only after a
    /// probe has resolved, same timing as `localAuthAvailable`. Empty hides
    /// the "or continue with…" section entirely rather than showing it
    /// disabled, since unlike password there's no single toggle to disable.
    public private(set) var oidcProviders: [OIDCProvider] = []
    /// Set when a password login was rejected pending a TOTP code — the view
    /// reveals a code field and `save()` retries with it filled in.
    public private(set) var awaitingTOTP = false

    public var isSaving: Bool {
        validationState == .validating
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

    public var canSave: Bool {
        guard !trimmedDisplayName.isEmpty, !trimmedURLText.isEmpty, !isSaving else { return false }
        switch credentialMode {
        case .apiToken:
            return !trimmedToken.isEmpty
        case .password:
            return awaitingTOTP ? !trimmedTOTP.isEmpty : (!trimmedUsername.isEmpty && !trimmedPassword.isEmpty)
        case .oidc:
            // `credentialMode` is `.oidc` only while that card is expanded;
            // OIDC sign-in is its own action (`signInWithOIDC`), and the view
            // hides the save button entirely in this case.
            return false
        }
    }

    public var canTestConnection: Bool {
        !trimmedURLText.isEmpty && !isSaving
    }

    /// Whether the address as typed explicitly uses an `http://` scheme — the
    /// only case where the "Allow insecure connection" toggle is relevant (a
    /// bare domain or `https://` always resolves to HTTPS). The view reveals
    /// the toggle only while this is true.
    public var urlUsesInsecureScheme: Bool {
        trimmedURLText.lowercased().hasPrefix("http://")
    }

    /// Whether a provider button in `oidcProviders` should be enabled —
    /// mirrors `canSave`'s name/address gating, minus the credential fields
    /// which OIDC sign-in doesn't use.
    public var canSignInWithOIDC: Bool {
        !trimmedDisplayName.isEmpty && !trimmedURLText.isEmpty && !isSaving
    }

    private let accountStore: AccountStoreProtocol
    private let clientFactory: InstanceClientFactoryProtocol
    private let toastPresenter: ToastPresenting
    private let oidcAuthenticator: OIDCAuthenticating
    private let oidcRedirectURI: URL
    /// Fired after a save/delete that may have changed which account is
    /// active, or edited the active account's own address — either way the
    /// app target needs to rebuild the main tab shell. See
    /// `ConnectionsListViewModel`'s copy of the same reasoning.
    private let onActiveAccountChanged: () -> Void

    public init(
        mode: ConnectionFormMode,
        accountStore: AccountStoreProtocol,
        clientFactory: InstanceClientFactoryProtocol,
        toastPresenter: ToastPresenting,
        oidcAuthenticator: OIDCAuthenticating,
        oidcRedirectURI: URL,
        onActiveAccountChanged: @escaping () -> Void,
    ) {
        self.mode = mode
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.toastPresenter = toastPresenter
        self.oidcAuthenticator = oidcAuthenticator
        self.oidcRedirectURI = oidcRedirectURI
        self.onActiveAccountChanged = onActiveAccountChanged

        if case let .edit(account) = mode {
            self.displayName = account.displayName
            self.urlText = account.baseURL.absoluteString
            self.credentialMode = account.authMethod
            self.allowInsecureConnection = account.baseURL.scheme?.lowercased() == "http"
        }
    }

    /// Fills in the existing token for `.edit` mode. Separate from `init`
    /// since reading it is async (Keychain) — the form renders immediately
    /// with name/URL already populated and the token field fills in a moment
    /// later, same as any other server-backed load in this app. A password
    /// account's stored credential is opaque, so this only fills the token
    /// field for API-token accounts.
    public func load() async {
        guard case let .edit(account) = mode, account.authMethod == .apiToken else { return }
        apiToken = await (try? accountStore.token(forAccountID: account.id)) ?? ""
    }

    /// Silently probes the typed address to learn whether it supports local
    /// auth, without touching `validationState` — called as the user types
    /// the URL (debounced by the view) so the password option can enable
    /// itself before the user ever taps "Test Connection". Any failure
    /// (unreachable host, still mid-type) just leaves it unavailable.
    public func checkLocalAuthAvailability() async {
        guard !trimmedURLText.isEmpty,
              let baseURL = try? InstanceURL.normalize(urlText, allowInsecureHTTP: allowInsecureConnection)
        else {
            await applyAvailability(localAuth: false, providers: [])
            return
        }
        let provider = clientFactory.makeCapabilityProvider(baseURL: baseURL)
        guard let info = try? await provider.serverInfo() else {
            await applyAvailability(localAuth: false, providers: [])
            return
        }
        await applyAvailability(localAuth: provider.supports(.localAuth), providers: info.oidcProviders)
    }

    /// Probes the typed address without persisting anything — backs a
    /// standalone "test connection" action, distinct from `save()`.
    public func testConnection() async {
        guard canTestConnection else { return }
        validationState = .validating
        do {
            let baseURL = try InstanceURL.normalize(urlText, allowInsecureHTTP: allowInsecureConnection)
            let provider = clientFactory.makeCapabilityProvider(baseURL: baseURL)
            let info = try await provider.serverInfo()
            await applyAvailability(localAuth: provider.supports(.localAuth), providers: info.oidcProviders)
            validationState = .success
        } catch let error as VikunjaError {
            validationState = .failure(error.displayMessage)
        } catch {
            validationState = .failure(error.localizedDescription)
        }
    }

    /// Signs in via `provider`'s own login page, presented in a system
    /// browser session. Bypasses `credentialMode`/`canSave` entirely —
    /// tapping a provider button commits directly, there's nothing else on
    /// screen to fill in first.
    public func signInWithOIDC(_ provider: OIDCProvider) async {
        guard canSignInWithOIDC else { return }
        validationState = .validating

        do {
            let baseURL = try InstanceURL.normalize(urlText, allowInsecureHTTP: allowInsecureConnection)
            let code = try await oidcAuthenticator.authenticate(provider: provider, redirectURI: oidcRedirectURI)
            let session = try await clientFactory.makeAuthService(baseURL: baseURL).loginWithOIDC(
                provider: provider,
                code: code,
                redirectURI: oidcRedirectURI,
            )
            switch mode {
            case .create:
                let account = InstanceAccount(displayName: trimmedDisplayName, baseURL: baseURL, authMethod: .oidc)
                try await accountStore.addAccount(account, token: session.token)
                finishSaving(account, toast: "Connection added")
            case let .edit(original):
                var account = original
                account.displayName = trimmedDisplayName
                account.baseURL = baseURL
                account.authMethod = .oidc
                try await accountStore.updateAccount(account, token: session.token)
                finishSaving(account, toast: "Connection updated")
            }
        } catch OIDCAuthError.canceled {
            // The user dismissed the browser session — back to idle, no
            // error banner for what isn't really a failure.
            validationState = .idle
        } catch let error as OIDCAuthError {
            validationState = .failure(error.displayMessage)
        } catch let error as VikunjaError {
            validationState = .failure(error.displayMessage)
        } catch {
            validationState = .failure(error.localizedDescription)
        }
    }

    public func save() async {
        guard canSave else { return }
        validationState = .validating
        // Deliberately doesn't call `updateLocalAuthAvailable` here — this
        // save is already committed to whichever mode the user picked (and
        // filled in the matching fields for), so a flaky re-probe result
        // must not silently switch `credentialMode` out from under it.
        do {
            let baseURL = try InstanceURL.normalize(urlText, allowInsecureHTTP: allowInsecureConnection)
            let provider = clientFactory.makeCapabilityProvider(baseURL: baseURL)
            _ = try await provider.serverInfo()
            localAuthAvailable = await provider.supports(.localAuth)

            switch credentialMode {
            case .apiToken:
                try await saveAPITokenAccount(baseURL: baseURL)
            case .password:
                await savePasswordAccount(baseURL: baseURL)
            case .oidc:
                // `canSave` already refused this branch — OIDC sign-in goes
                // through `signInWithOIDC` instead.
                break
            }
        } catch let error as VikunjaError {
            validationState = .failure(error.displayMessage)
        } catch {
            validationState = .failure(error.localizedDescription)
        }
    }

    /// Deletes the connection being edited. No-op outside `.edit` mode.
    /// Refuses (with a toast) to delete the last remaining connection —
    /// there always has to be one active account for the main tab shell to
    /// render against.
    @discardableResult
    public func deleteConnection() async -> Bool {
        guard case let .edit(account) = mode else { return false }
        do {
            let remaining = try await accountStore.fetchAccounts()
            guard remaining.count > 1 else {
                toastPresenter.show("You need at least one connection", style: .error)
                return false
            }
            let activeID = try await accountStore.activeAccount()?.id
            try await accountStore.removeAccount(id: account.id)
            toastPresenter.show("Connection removed", style: .success)
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

    private func saveAPITokenAccount(baseURL: URL) async throws {
        switch mode {
        case .create:
            let account = InstanceAccount(displayName: trimmedDisplayName, baseURL: baseURL, authMethod: .apiToken)
            try await accountStore.addAccount(account, token: trimmedToken)
            finishSaving(account, toast: "Connection added")
        case let .edit(original):
            var account = original
            account.displayName = trimmedDisplayName
            account.baseURL = baseURL
            account.authMethod = .apiToken
            try await accountStore.updateAccount(account, token: trimmedToken)
            finishSaving(account, toast: "Connection updated")
        }
    }

    private func savePasswordAccount(baseURL: URL) async {
        let coordinator = PasswordLoginCoordinator(authService: clientFactory.makeAuthService(baseURL: baseURL))
        let state = if awaitingTOTP {
            await coordinator.retryWithTOTP(trimmedTOTP, username: trimmedUsername, password: trimmedPassword)
        } else {
            await coordinator.attempt(username: trimmedUsername, password: trimmedPassword)
        }

        switch state {
        case let .success(session):
            do {
                switch mode {
                case .create:
                    let account = InstanceAccount(
                        displayName: trimmedDisplayName, baseURL: baseURL, authMethod: .password,
                    )
                    try await accountStore.addAccount(account, token: session.token)
                    finishSaving(account, toast: "Connection added")
                case let .edit(original):
                    var account = original
                    account.displayName = trimmedDisplayName
                    account.baseURL = baseURL
                    account.authMethod = .password
                    try await accountStore.updateAccount(account, token: session.token)
                    finishSaving(account, toast: "Connection updated")
                }
            } catch let error as VikunjaError {
                validationState = .failure(error.displayMessage)
            } catch {
                validationState = .failure(error.localizedDescription)
            }
        case .awaitingTOTP:
            awaitingTOTP = true
            validationState = .idle
        case let .failure(error):
            validationState = .failure(error.displayMessage)
        case .idle, .authenticating:
            validationState = .idle
        }
    }

    /// Records what the latest probe reported, and snaps the expanded card
    /// back to `.apiToken` if it landed on an option the probe just ruled out
    /// (e.g. the user edited the URL to point at a different server), so the
    /// form never sits expanded on a disabled card.
    private func applyAvailability(localAuth: Bool, providers: [OIDCProvider]) {
        localAuthAvailable = localAuth
        oidcProviders = providers
        if credentialMode == .password, !localAuth {
            credentialMode = .apiToken
        }
        if credentialMode == .oidc, providers.isEmpty {
            credentialMode = .apiToken
        }
    }

    private func finishSaving(_ account: InstanceAccount, toast: String) {
        savedAccount = account
        toastPresenter.show(toast, style: .success)
        validationState = .success
        onActiveAccountChanged()
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedURLText: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedToken: String {
        apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTOTP: String {
        totpPasscode.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
