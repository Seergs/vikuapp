import Foundation
import Testing
import VikunjaCore
@testable import WhatsNew

@MainActor
@Suite("WhatsNewGuideViewModel")
struct WhatsNewGuideViewModelTests {
    private func guide(
        tip: String? = "A tip",
        primaryAction: WhatsNewAction? = .dismiss(label: "Got it"),
        secondaryAction: WhatsNewAction? = nil,
    ) -> WhatsNewGuide {
        WhatsNewGuide(
            title: "Add the widget",
            intro: "Takes less than a minute.",
            steps: [WhatsNewGuide.Step(title: "Step 1", body: "Do this")],
            tip: tip,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
        )
    }

    @Test
    func `exposes the guide's own fields`() {
        let viewModel = WhatsNewGuideViewModel(guide: guide()) { _ in }

        #expect(viewModel.title == "Add the widget")
        #expect(viewModel.steps.count == 1)
        #expect(viewModel.tip == "A tip")
        #expect(viewModel.primaryAction == .dismiss(label: "Got it"))
    }

    @Test
    func `handling an action forwards it to the caller unchanged`() throws {
        var received: WhatsNewAction?
        let viewModel = WhatsNewGuideViewModel(guide: guide()) { received = $0 }

        try viewModel.handle(.url(label: "Read more", url: #require(URL(string: "https://viku.app"))))

        #expect(try received == .url(label: "Read more", url: #require(URL(string: "https://viku.app"))))
    }
}
