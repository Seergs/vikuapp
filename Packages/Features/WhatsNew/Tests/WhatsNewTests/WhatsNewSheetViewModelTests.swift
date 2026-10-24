import Foundation
import Testing
import VikunjaCore
@testable import WhatsNew

@MainActor
@Suite("WhatsNewSheetViewModel")
struct WhatsNewSheetViewModelTests {
    private func content(guides: [String: WhatsNewGuide] = [:]) -> WhatsNewContent {
        let release = WhatsNewRelease(
            version: "1.5", date: "2026-10-23", minAppVersion: "1.5.0", title: "T", subtitle: "S",
        )
        return WhatsNewContent(schemaVersion: 1, release: release, guides: guides)
    }

    private func guide() -> WhatsNewGuide {
        WhatsNewGuide(title: "Add the widget", intro: "Intro", steps: [])
    }

    @Test
    func `starts on the main screen`() {
        let viewModel = WhatsNewSheetViewModel(content: content()) { _ in }
        guard case .new = viewModel.screen else {
            Issue.record("expected .new")
            return
        }
    }

    @Test
    func `a guide action with a known id switches to that guide locally, without bubbling`() {
        let guide = guide()
        var received: WhatsNewAction?
        let viewModel = WhatsNewSheetViewModel(content: content(guides: ["add-widget": guide])) { received = $0 }

        let mainViewModel = viewModel.makeMainViewModel()
        mainViewModel.handle(.guide(label: "How to add it", guideId: "add-widget"))

        guard case let .guide(shown) = viewModel.screen else {
            Issue.record("expected .guide")
            return
        }
        #expect(shown == guide)
        #expect(received == nil)
    }

    @Test
    func `a guide action with an unknown id fails safe by bubbling instead of switching`() {
        var received: WhatsNewAction?
        let viewModel = WhatsNewSheetViewModel(content: content()) { received = $0 }

        let mainViewModel = viewModel.makeMainViewModel()
        mainViewModel.handle(.guide(label: "How to add it", guideId: "missing"))

        guard case .new = viewModel.screen else {
            Issue.record("expected to stay on .new")
            return
        }
        #expect(received == .guide(label: "How to add it", guideId: "missing"))
    }

    @Test
    func `a non guide action from the main screen always bubbles up`() {
        var received: WhatsNewAction?
        let viewModel = WhatsNewSheetViewModel(content: content()) { received = $0 }

        let mainViewModel = viewModel.makeMainViewModel()
        mainViewModel.handle(.dismiss(label: "Got it"))

        #expect(received == .dismiss(label: "Got it"))
    }

    @Test
    func `an action from the guide screen always bubbles up unchanged`() throws {
        let guide = guide()
        var received: WhatsNewAction?
        let viewModel = WhatsNewSheetViewModel(content: content(guides: ["add-widget": guide])) { received = $0 }

        let guideViewModel = viewModel.makeGuideViewModel(for: guide)
        try guideViewModel.handle(.url(label: "Read more", url: #require(URL(string: "https://viku.app"))))

        #expect(try received == .url(label: "Read more", url: #require(URL(string: "https://viku.app"))))
    }

    @Test
    func `backToMain returns from a guide to the main screen`() {
        let guide = guide()
        let viewModel = WhatsNewSheetViewModel(content: content(guides: ["add-widget": guide])) { _ in }
        viewModel.makeMainViewModel().handle(.guide(label: "How to add it", guideId: "add-widget"))

        viewModel.backToMain()

        guard case .new = viewModel.screen else {
            Issue.record("expected .new")
            return
        }
    }
}
