@testable import Settings
import Testing
import VikunjaCore

@MainActor
struct WhatsNewSettingsViewModelTests {
    @Test(arguments: ["0.7.0", nil] as [String?])
    func `reset clears seen version and confirms next launch`(_ version: String?) {
        let store = FakeSeenVersionStore(version: version)
        let toast = FakeToastPresenter()
        let viewModel = WhatsNewSettingsViewModel(seenVersionStore: store, toastPresenter: toast)

        viewModel.reset()

        #expect(store.lastSeenReleaseVersion == nil)
        #expect(toast.shownMessages.count == 1)
        #expect(toast.shownMessages.first?.style == .success)
        #expect(toast.shownMessages.first?.message == "What's New will appear on the next launch")
    }
}

@MainActor
private final class FakeSeenVersionStore: WhatsNewSeenVersionStoring {
    var lastSeenReleaseVersion: String?

    init(version: String?) {
        self.lastSeenReleaseVersion = version
    }

    func setLastSeenReleaseVersion(_ version: String?) {
        lastSeenReleaseVersion = version
    }
}
