import Foundation
import VikunjaCore

@MainActor
final class WhatsNewSettingsViewModel {
    private let seenVersionStore: WhatsNewSeenVersionStoring
    private let toastPresenter: ToastPresenting

    init(seenVersionStore: WhatsNewSeenVersionStoring, toastPresenter: ToastPresenting) {
        self.seenVersionStore = seenVersionStore
        self.toastPresenter = toastPresenter
    }

    func reset() {
        seenVersionStore.setLastSeenReleaseVersion(nil)
        toastPresenter.show(
            String(localized: "What's New will appear on the next launch", bundle: .module),
            style: .success,
        )
    }
}
