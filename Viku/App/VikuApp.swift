//
//  VikuApp.swift
//  Viku
//
//  Created by Sergio Suárez álvarez on 24/08/26.
//

import SwiftUI
import VikunjaPersistence

@main
struct VikuApp: App {
    private let container = AppContainer()

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    /// Set the first time the scene ever reaches `.active`, so the
    /// foreground sync trigger below can skip exactly that one activation
    /// (the cold launch) without needing to guess at the OS's exact phase
    /// sequence — a real return from the background goes `.background ->
    /// .inactive -> .active`, so `oldPhase` at that point is `.inactive`,
    /// not `.background`, indistinguishable from a cold launch's own first
    /// `.inactive -> .active` step by `oldPhase` alone.
    @State private var hasCompletedInitialActivation = false

    init() {
        AppDelegate.container = container
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
        .onChange(of: scenePhase) { _, phase in
            // Refresh the widgets' shared snapshots whenever the app leaves
            // the foreground — the user may have just added or completed a
            // task. The app fetches with its own credentials and writes the
            // App Group caches the widgets render, so this works even where
            // the widgets can't read the keychain themselves.
            if phase == .background {
                container.refreshWidgetSnapshotsBeforeSuspension()
                AppDelegate.scheduleNextBackgroundSync()
            }
            if phase == .active {
                // A genuine return from the background — matches the user's
                // own mental model ("I just came back, check now"). Skipped
                // on the very first activation (cold launch), which
                // `AppContainer.bootstrap()`'s `syncCoordinator.start()`
                // already covers on its own.
                if hasCompletedInitialActivation {
                    Task { await container.syncCoordinator.syncAllAccounts() }
                }
                hasCompletedInitialActivation = true
            }
        }
    }
}
