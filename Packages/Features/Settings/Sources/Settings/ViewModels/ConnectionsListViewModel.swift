import Foundation
import Observation
import SwiftUI
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
    /// keyed by account id. Seeded synchronously from `serverVersionCache`
    /// in `load()` (so an account's last known version renders immediately,
    /// alongside its name/host, with no pop-in), then refreshed in the
    /// background by `loadServerVersions()`. Best-effort: a missing entry
    /// just means neither the cache nor the probe has a value yet (or the
    /// probe failed) rather than a load-blocking error, since knowing which
    /// account is active/editable doesn't depend on it.
    public private(set) var serverVersions: [InstanceAccount.ID: String] = [:]

    public var isLoading: Bool {
        loadState == .loading
    }

    private let accountStore: AccountStoreProtocol
    private let clientFactory: InstanceClientFactoryProtocol
    private let serverVersionCache: ServerVersionCaching
    private let toastPresenter: ToastPresenting
    /// Fired after `setActive` may have changed which account is active, so
    /// the app target can rebuild the main tab shell against the new one.
    private let onActiveAccountChanged: () -> Void

    public init(
        accountStore: AccountStoreProtocol,
        clientFactory: InstanceClientFactoryProtocol,
        serverVersionCache: ServerVersionCaching,
        toastPresenter: ToastPresenting,
        onActiveAccountChanged: @escaping () -> Void,
    ) {
        self.accountStore = accountStore
        self.clientFactory = clientFactory
        self.serverVersionCache = serverVersionCache
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
            for account in accounts {
                if let cached = serverVersionCache.cachedVersion(forAccountID: account.id) {
                    serverVersions[account.id] = cached
                }
            }
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
    /// URL) simply keeps whatever was already in `serverVersions` (the
    /// cached value, or nothing) rather than failing the whole screen. A
    /// successful probe writes through to `serverVersionCache` too, so the
    /// next time this screen loads it already has the latest known value.
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
                guard let version else { continue }
                let isFirstReveal = serverVersions[accountID] == nil
                serverVersionCache.setCachedVersion(version, forAccountID: accountID)
                if isFirstReveal {
                    withAnimation(.easeOut(duration: 0.2)) {
                        serverVersions[accountID] = version
                    }
                } else {
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
