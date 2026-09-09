import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the "Connections" screen: lists every saved instance and lets the
/// user switch which one is active. Deleting a connection happens from
/// within its own edit screen (`ConnectionFormViewModel.deleteConnection`),
/// not from this list.
@MainActor
@Observable
public final class ConnectionsListViewModel {
    public private(set) var accounts: [InstanceAccount] = []
    public private(set) var activeAccountID: InstanceAccount.ID?
    public private(set) var loadState: ScreenLoadState<Void> = .idle
    /// The Vikunja server version reported by each account's own `/info`,
    /// keyed by account id. Fetched best-effort, one probe per account,
    /// after the account list itself loads; a missing entry just means the
    /// probe hasn't finished (or failed) rather than a load-blocking error,
    /// since knowing which account is active/editable doesn't depend on it.
    public private(set) var serverVersions: [InstanceAccount.ID: String] = [:]

    public var isLoading: Bool {
        loadState == .loading
    }

    private let accountStore: AccountStoreProtocol
    private let clientFactory: InstanceClientFactoryProtocol
    private let toastPresenter: ToastPresenting
    /// Fired after `setActive` may have changed which account is active, so
    /// the app target can rebuild the main tab shell against the new one.
    private let onActiveAccountChanged: () -> Void

    public init(
        accountStore: AccountStoreProtocol,
        clientFactory: InstanceClientFactoryProtocol,
        toastPresenter: ToastPresenting,
        onActiveAccountChanged: @escaping () -> Void,
    ) {
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.toastPresenter = toastPresenter
        self.onActiveAccountChanged = onActiveAccountChanged
    }

    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            accounts = try await accountStore.fetchAccounts()
            activeAccountID = try await accountStore.activeAccount()?.id
            loadState = .loaded
            await loadServerVersions()
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    /// Probes every account's `/info` concurrently for its server version.
    /// Best-effort: an account whose probe fails (offline instance, bad
    /// URL) simply keeps no entry in `serverVersions` rather than failing
    /// the whole screen.
    private func loadServerVersions() async {
        let accounts = accounts
        await withTaskGroup(of: (InstanceAccount.ID, String?).self) { group in
            for account in accounts {
                group.addTask { [clientFactory] in
                    let info = try? await clientFactory.makeCapabilityProvider(baseURL: account.baseURL).serverInfo()
                    return (account.id, info?.version)
                }
            }
            for await (accountID, version) in group {
                if let version {
                    serverVersions[accountID] = version
                }
            }
        }
    }

    public func setActive(_ account: InstanceAccount) async {
        guard account.id != activeAccountID else { return }
        do {
            try await accountStore.setActiveAccount(id: account.id)
            activeAccountID = account.id
            onActiveAccountChanged()
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
        }
    }
}
