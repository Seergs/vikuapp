//
//  VikuApp.swift
//  Viku
//
//  Created by Sergio Suárez álvarez on 24/08/26.
//

import SwiftUI

@main
struct VikuApp: App {
    private let container = AppContainer()

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

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
            }
        }
    }
}
