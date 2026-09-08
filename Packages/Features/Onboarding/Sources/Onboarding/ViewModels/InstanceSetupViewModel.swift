import Foundation
import Observation
import VikunjaCore

/// Drives the "add a connection" screen: the user names an instance, types its
/// address (a bare domain or a full URL, either works) and connects either
/// with an API token or, when the instance reports local auth is enabled,
/// with a username and password (plus a TOTP code, if that account has
/// two-factor enabled), or via one of the instance's OIDC providers. On save,
/// the address is normalized and probed with `GET /api/v1/info` to confirm
/// it's really a Vikunja instance before the connection is persisted and made
/// active.
///
/// The fields, validation, and the probe/OIDC/password/save flows all live in
/// `VikunjaCore`'s `ConnectionEditorCore`, shared with `Settings`'
/// `ConnectionFormViewModel`. This adds only what's specific to first-run
/// onboarding: after a save, the form clears and the saved-account list
/// reloads.
@MainActor
@Observable
public final class InstanceSetupViewModel {
    private let core: ConnectionEditorCore
    private let accountStore: AccountStoreProtocol

    public private(set) var savedAccounts: [InstanceAccount] = []

    public init(
        accountStore: AccountStoreProtocol,
        clientFactory: InstanceClientFactoryProtocol,
        oidcAuthenticator: OIDCAuthenticating,
        oidcRedirectURI: URL,
    ) {
        self.accountStore = accountStore
        self.core = ConnectionEditorCore(
            editingAccount: nil,
            accountStore: accountStore,
            clientFactory: clientFactory,
            oidcAuthenticator: oidcAuthenticator,
            oidcRedirectURI: oidcRedirectURI,
        )
        core.onStored = { [weak self] _ in
            self?.core.resetInputs()
            await self?.loadSavedAccounts()
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

    public func loadSavedAccounts() async {
        savedAccounts = await (try? accountStore.fetchAccounts()) ?? []
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

    public func saveConnection() async {
        await core.save()
    }
}
