import Foundation
import Observation

/// The lifecycle state of a connection editor's probe/save.
public enum ConnectionEditorPhase: Equatable, Sendable {
    case idle
    case validating
    case success
    case failure(String)
}

/// Drives the "add/edit a connection" form shared by `Features/Onboarding`
/// (first-run, no accounts yet) and `Features/Settings` (add, edit, or delete
/// an account). Both features can't depend on each other, so the fields,
/// validation, and the probe/OIDC/password/save flows live here, next to
/// `PasswordLoginCoordinator`, and each feature's view model is a thin wrapper
/// that adds only what's specific to it (Onboarding: reload the saved-account
/// list; Settings: `mode`, delete, toast + active-account notification).
///
/// Whether the save adds a new account or updates an existing one is decided
/// by `editingAccount`: `nil` adds, non-`nil` updates that account in place.
/// Post-save side effects a wrapper needs go in `onStored`.
@MainActor
@Observable
public final class ConnectionEditorCore {
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
    /// warning while it's on.
    public var allowInsecureConnection: Bool = false

    public private(set) var phase: ConnectionEditorPhase = .idle
    /// The account `save()`/`signInWithOIDC(_:)` most recently persisted —
    /// distinct from `phase == .success`, which `testConnection()` also
    /// reports on a successful probe. Drives post-save navigation.
    public private(set) var savedAccount: InstanceAccount?
    /// Whether the probed server reports local (username/password) login as
    /// enabled — known only after a probe has resolved (see
    /// `checkLocalAuthAvailability()`, called automatically as the user types
    /// the address); defaults to `false` so the password option starts
    /// disabled rather than hidden.
    public private(set) var localAuthAvailable = false
    /// OIDC providers the probed server has configured — known only after a
    /// probe has resolved, same timing as `localAuthAvailable`. Empty hides
    /// the "or continue with…" section entirely rather than showing it
    /// disabled, since unlike password there's no single toggle to disable.
    public private(set) var oidcProviders: [OIDCProvider] = []
    /// Set when a password login was rejected pending a TOTP code — the view
    /// reveals a code field and the save retries with it filled in.
    public private(set) var awaitingTOTP = false

    /// The account being edited, or `nil` when adding a new one.
    public let editingAccount: InstanceAccount?

    /// Runs after a save persists an account, on the main actor. The wrapper
    /// does its own post-save work here (reset the form, reload the account
    /// list, show a toast, tell the app the active account may have changed).
    public var onStored: ((InstanceAccount) async -> Void)?

    private let accountStore: AccountStoreProtocol
    private let clientFactory: InstanceClientFactoryProtocol
    private let oidcAuthenticator: OIDCAuthenticating
    private let oidcRedirectURI: URL

    public init(
        editingAccount: InstanceAccount?,
        accountStore: AccountStoreProtocol,
        clientFactory: InstanceClientFactoryProtocol,
        oidcAuthenticator: OIDCAuthenticating,
        oidcRedirectURI: URL,
    ) {
        self.editingAccount = editingAccount
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.oidcAuthenticator = oidcAuthenticator
        self.oidcRedirectURI = oidcRedirectURI

        if let editingAccount {
            self.displayName = editingAccount.displayName
            self.urlText = editingAccount.baseURL.absoluteString
            self.credentialMode = editingAccount.authMethod
            self.allowInsecureConnection = editingAccount.baseURL.scheme?.lowercased() == "http"
        }
    }

    public var isSaving: Bool {
        phase == .validating
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

    /// Silently probes the typed address to learn whether it supports local
    /// auth, without touching `phase` — called as the user types the URL
    /// (debounced by the view) so the password option can enable itself before
    /// the user ever taps "Test Connection". Any failure (unreachable host,
    /// still mid-type) just leaves it unavailable.
    public func checkLocalAuthAvailability() async {
        guard !trimmedURLText.isEmpty,
              let baseURL = try? InstanceURL.normalize(urlText, allowInsecureHTTP: allowInsecureConnection)
        else {
            applyAvailability(localAuth: false, providers: [])
            return
        }
        let provider = clientFactory.makeCapabilityProvider(baseURL: baseURL)
        guard let info = try? await provider.serverInfo() else {
            applyAvailability(localAuth: false, providers: [])
            return
        }
        await applyAvailability(localAuth: provider.supports(.localAuth), providers: info.oidcProviders)
    }

    /// Probes the typed address without persisting anything — backs a
    /// standalone "test connection" action, distinct from `save()`.
    public func testConnection() async {
        guard canTestConnection else { return }
        phase = .validating
        do {
            let baseURL = try InstanceURL.normalize(urlText, allowInsecureHTTP: allowInsecureConnection)
            let provider = clientFactory.makeCapabilityProvider(baseURL: baseURL)
            let info = try await provider.serverInfo()
            await applyAvailability(localAuth: provider.supports(.localAuth), providers: info.oidcProviders)
            phase = .success
        } catch let error as VikunjaError {
            phase = .failure(Self.message(for: error))
        } catch {
            phase = .failure(error.localizedDescription)
        }
    }

    /// Signs in via `provider`'s own login page, presented in a system browser
    /// session. Bypasses `credentialMode`/`canSave` entirely — tapping a
    /// provider button commits directly, there's nothing else on screen to
    /// fill in first.
    public func signInWithOIDC(_ provider: OIDCProvider) async {
        guard canSignInWithOIDC else { return }
        phase = .validating
        do {
            let baseURL = try InstanceURL.normalize(urlText, allowInsecureHTTP: allowInsecureConnection)
            let code = try await oidcAuthenticator.authenticate(provider: provider, redirectURI: oidcRedirectURI)
            let session = try await clientFactory.makeAuthService(baseURL: baseURL).loginWithOIDC(
                provider: provider,
                code: code,
                redirectURI: oidcRedirectURI,
            )
            let account = try await storeAccount(baseURL: baseURL, authMethod: .oidc, token: session.token)
            await finish(account)
        } catch OIDCAuthError.canceled {
            // The user dismissed the browser session — back to idle, no error
            // banner for what isn't really a failure.
            phase = .idle
        } catch let error as OIDCAuthError {
            phase = .failure(Self.message(for: error))
        } catch let error as VikunjaError {
            phase = .failure(Self.message(for: error))
        } catch {
            phase = .failure(error.localizedDescription)
        }
    }

    /// Probes the typed address and persists the connection with the
    /// credentials for the selected `credentialMode`. OIDC is not saved here —
    /// it goes through `signInWithOIDC(_:)`.
    public func save() async {
        guard canSave else { return }
        phase = .validating

        // Deliberately doesn't re-probe local-auth availability into
        // `credentialMode` here — this save is already committed to whichever
        // mode the user picked (and filled in the matching fields for), so a
        // flaky re-probe result must not switch it out from under them.
        do {
            let baseURL = try InstanceURL.normalize(urlText, allowInsecureHTTP: allowInsecureConnection)
            let provider = clientFactory.makeCapabilityProvider(baseURL: baseURL)
            _ = try await provider.serverInfo()
            localAuthAvailable = await provider.supports(.localAuth)

            switch credentialMode {
            case .apiToken:
                let account = try await storeAccount(baseURL: baseURL, authMethod: .apiToken, token: trimmedToken)
                await finish(account)
            case .password:
                await savePasswordAccount(baseURL: baseURL)
            case .oidc:
                // `canSave` already refused this branch.
                break
            }
        } catch let error as VikunjaError {
            phase = .failure(Self.message(for: error))
        } catch {
            phase = .failure(error.localizedDescription)
        }
    }

    /// Clears every typed field and the probe results back to a blank form.
    /// Leaves `phase`/`savedAccount` alone — a wrapper calls this from
    /// `onStored`, after a successful save, and still wants to read those.
    public func resetInputs() {
        displayName = ""
        urlText = ""
        apiToken = ""
        username = ""
        password = ""
        totpPasscode = ""
        awaitingTOTP = false
        allowInsecureConnection = false
        credentialMode = .apiToken
        oidcProviders = []
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
                let account = try await storeAccount(baseURL: baseURL, authMethod: .password, token: session.token)
                await finish(account)
            } catch let error as VikunjaError {
                phase = .failure(Self.message(for: error))
            } catch {
                phase = .failure(error.localizedDescription)
            }
        case .awaitingTOTP:
            awaitingTOTP = true
            phase = .idle
        case let .failure(error):
            phase = .failure(Self.message(for: error))
        case .idle, .authenticating:
            phase = .idle
        }
    }

    /// Adds a new account, or updates `editingAccount` in place, and returns
    /// the stored value.
    private func storeAccount(
        baseURL: URL,
        authMethod: InstanceAccount.AuthMethod,
        token: String,
    ) async throws -> InstanceAccount {
        if let editingAccount {
            var account = editingAccount
            account.displayName = trimmedDisplayName
            account.baseURL = baseURL
            account.authMethod = authMethod
            try await accountStore.updateAccount(account, token: token)
            return account
        }
        let account = InstanceAccount(displayName: trimmedDisplayName, baseURL: baseURL, authMethod: authMethod)
        try await accountStore.addAccount(account, token: token)
        return account
    }

    private func finish(_ account: InstanceAccount) async {
        phase = .success
        savedAccount = account
        await onStored?(account)
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

    private static func message(for error: OIDCAuthError) -> String {
        switch error {
        case .canceled:
            "" // Handled by the caller before this is ever reached.
        case .noPresentingViewController, .presentationUnavailable, .unsupportedPlatform:
            "Couldn't open the sign-in page. Try again."
        case .missingAuthorizationCode:
            "Sign-in didn't complete. Make sure this app's redirect URI is allowed on your identity"
                + " provider, then try again."
        }
    }

    private static func message(for error: VikunjaError) -> String {
        switch error {
        case .invalidInstanceURL:
            "That doesn't look like a valid instance address."
        case .insecureInstanceURL:
            "That address uses http. Turn on \"Allow insecure connection\" to connect over an unencrypted link."
        case .network:
            "Couldn't reach that server. Check the address and your connection."
        case .notFound, .decoding:
            "That address didn't respond like a Vikunja instance."
        case .unauthorized:
            "That server rejected the request."
        case let .server(_, statusCode):
            "The server responded with an error (\(statusCode))."
        case let .unsupportedServerVersion(minimumRequired, _):
            "This app needs Vikunja \(minimumRequired) or newer."
        case .totpRequired:
            "This account needs a two-factor code."
        }
    }
}
