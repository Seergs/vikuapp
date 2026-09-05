import Foundation
import Observation
import VikunjaCore

/// Drives the "add a connection" screen: the user names an instance, types its
/// address (a bare domain or a full URL, either works) and connects either
/// with an API token or, when the instance reports local auth is enabled,
/// with a username and password (plus a TOTP code, if that account has
/// two-factor enabled). On save, the address is normalized and probed with
/// `GET /api/v1/info` to confirm it's really a Vikunja instance before the
/// connection is persisted and made active.
@MainActor
@Observable
public final class InstanceSetupViewModel {
    public var displayName: String = ""
    public var urlText: String = ""
    public var apiToken: String = ""
    public var credentialMode: InstanceAccount.AuthMethod = .apiToken
    public var username: String = ""
    public var password: String = ""
    public var totpPasscode: String = ""

    public private(set) var validationState: InstanceSetupValidationState = .idle
    public private(set) var savedAccounts: [InstanceAccount] = []
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
    /// reveals a code field and `saveConnection()` retries with it filled in.
    public private(set) var awaitingTOTP = false

    /// The account `saveConnection()` most recently persisted — distinct from
    /// `validationState == .success`, which `testConnection()` also reports on
    /// a successful probe. Drives post-save navigation.
    public private(set) var savedAccount: InstanceAccount?

    public var isSaving: Bool {
        validationState == .validating
    }

    private let accountStore: AccountStoreProtocol
    private let clientFactory: InstanceClientFactoryProtocol
    private let oidcAuthenticator: OIDCAuthenticating
    private let oidcRedirectURI: URL

    public init(
        accountStore: AccountStoreProtocol,
        clientFactory: InstanceClientFactoryProtocol,
        oidcAuthenticator: OIDCAuthenticating,
        oidcRedirectURI: URL,
    ) {
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.oidcAuthenticator = oidcAuthenticator
        self.oidcRedirectURI = oidcRedirectURI
    }

    public var canSave: Bool {
        guard !trimmedDisplayName.isEmpty, !trimmedURLText.isEmpty, !isSaving else { return false }
        switch credentialMode {
        case .apiToken:
            return !trimmedToken.isEmpty
        case .password:
            return awaitingTOTP ? !trimmedTOTP.isEmpty : (!trimmedUsername.isEmpty && !trimmedPassword.isEmpty)
        case .oidc:
            // `credentialMode` itself never becomes `.oidc` — OIDC sign-in is
            // a separate action (`signInWithOIDC`), not routed through this
            // switch or `CredentialModePicker`.
            return false
        }
    }

    public var canTestConnection: Bool {
        !trimmedURLText.isEmpty
    }

    /// Whether a provider button in `oidcProviders` should be enabled —
    /// mirrors `canSave`'s name/address gating, minus the credential fields
    /// which OIDC sign-in doesn't use.
    public var canSignInWithOIDC: Bool {
        !trimmedDisplayName.isEmpty && !trimmedURLText.isEmpty && !isSaving
    }

    public func loadSavedAccounts() async {
        savedAccounts = await (try? accountStore.fetchAccounts()) ?? []
    }

    /// Silently probes the typed address to learn whether it supports local
    /// auth, without touching `validationState` — called as the user types
    /// the URL (debounced by the view) so the password option can enable
    /// itself before the user ever taps "Test Connection". Any failure
    /// (unreachable host, still mid-type) just leaves it unavailable.
    public func checkLocalAuthAvailability() async {
        guard !trimmedURLText.isEmpty, let baseURL = try? InstanceURL.normalize(urlText) else { return }
        let provider = clientFactory.makeCapabilityProvider(baseURL: baseURL)
        guard let info = try? await provider.serverInfo() else { return }
        await updateLocalAuthAvailable(provider.supports(.localAuth))
        oidcProviders = info.oidcProviders
    }

    /// Probes the typed address without persisting anything — backs a
    /// standalone "test connection" action, distinct from `saveConnection()`.
    public func testConnection() async {
        guard canTestConnection, !isSaving else { return }
        validationState = .validating

        do {
            let baseURL = try InstanceURL.normalize(urlText)
            let provider = clientFactory.makeCapabilityProvider(baseURL: baseURL)
            let info = try await provider.serverInfo()
            await updateLocalAuthAvailable(provider.supports(.localAuth))
            oidcProviders = info.oidcProviders
            validationState = .success
        } catch let error as VikunjaError {
            validationState = .failure(Self.message(for: error))
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
            let baseURL = try InstanceURL.normalize(urlText)
            let code = try await oidcAuthenticator.authenticate(provider: provider, redirectURI: oidcRedirectURI)
            let session = try await clientFactory.makeAuthService(baseURL: baseURL).loginWithOIDC(
                provider: provider,
                code: code,
                redirectURI: oidcRedirectURI,
            )
            let account = InstanceAccount(displayName: trimmedDisplayName, baseURL: baseURL, authMethod: .oidc)
            try await accountStore.addAccount(account, token: session.token)
            await finishSaving(account)
        } catch OIDCAuthError.canceled {
            // The user dismissed the browser session — back to idle, no
            // error banner for what isn't really a failure.
            validationState = .idle
        } catch let error as OIDCAuthError {
            validationState = .failure(Self.message(for: error))
        } catch let error as VikunjaError {
            validationState = .failure(Self.message(for: error))
        } catch {
            validationState = .failure(error.localizedDescription)
        }
    }

    public func saveConnection() async {
        guard canSave, !isSaving else { return }
        validationState = .validating

        // Deliberately doesn't call `updateLocalAuthAvailable` here — this
        // save is already committed to whichever mode the user picked (and
        // filled in the matching fields for), so a flaky re-probe result
        // must not silently switch `credentialMode` out from under it.
        do {
            let baseURL = try InstanceURL.normalize(urlText)
            let provider = clientFactory.makeCapabilityProvider(baseURL: baseURL)
            _ = try await provider.serverInfo()
            localAuthAvailable = await provider.supports(.localAuth)

            switch credentialMode {
            case .apiToken:
                let account = InstanceAccount(displayName: trimmedDisplayName, baseURL: baseURL, authMethod: .apiToken)
                try await accountStore.addAccount(account, token: trimmedToken)
                await finishSaving(account)
            case .password:
                await savePasswordAccount(baseURL: baseURL)
            case .oidc:
                // Unreachable — `canSave` refuses this branch since OIDC
                // sign-in goes through `signInWithOIDC` instead.
                break
            }
        } catch let error as VikunjaError {
            validationState = .failure(Self.message(for: error))
        } catch {
            validationState = .failure(error.localizedDescription)
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
            let account = InstanceAccount(displayName: trimmedDisplayName, baseURL: baseURL, authMethod: .password)
            do {
                try await accountStore.addAccount(account, token: session.token)
                await finishSaving(account)
            } catch let error as VikunjaError {
                validationState = .failure(Self.message(for: error))
            } catch {
                validationState = .failure(error.localizedDescription)
            }
        case .awaitingTOTP:
            awaitingTOTP = true
            validationState = .idle
        case let .failure(error):
            validationState = .failure(Self.message(for: error))
        case .idle, .authenticating:
            validationState = .idle
        }
    }

    /// Snaps back to `.apiToken` if the currently-selected password mode
    /// just became unavailable (e.g. the user edited the URL to point at a
    /// different server) so the form never sits on a disabled option.
    private func updateLocalAuthAvailable(_ available: Bool) {
        localAuthAvailable = available
        if !available, credentialMode == .password {
            credentialMode = .apiToken
        }
    }

    private func finishSaving(_ account: InstanceAccount) async {
        validationState = .success
        savedAccount = account
        resetInputs()
        await loadSavedAccounts()
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

    private func resetInputs() {
        displayName = ""
        urlText = ""
        apiToken = ""
        username = ""
        password = ""
        totpPasscode = ""
        awaitingTOTP = false
        credentialMode = .apiToken
        oidcProviders = []
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
