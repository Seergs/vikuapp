import Foundation
import Testing
import VikuNavigation
import VikunjaCore
@testable import WhatsNew

@MainActor
@Suite("WhatsNewActionDispatcher")
struct WhatsNewActionDispatcherTests {
    @MainActor
    private final class Spy {
        var dismissCalled = false
        var resolvedURL: URL?
        var openedDeepLink: DeepLink?
        var openedURL: URL?

        func dispatcher(resolving link: DeepLink?) -> WhatsNewActionDispatcher {
            WhatsNewActionDispatcher(
                dismissSheet: { self.dismissCalled = true },
                resolveDeepLink: { url in
                    self.resolvedURL = url
                    return link
                },
                openDeepLink: { self.openedDeepLink = $0 },
                openURL: { self.openedURL = $0 },
            )
        }
    }

    @Test
    func `dismiss closes the sheet and does nothing else`() {
        let spy = Spy()
        spy.dispatcher(resolving: nil).dispatch(.dismiss(label: "Got it"))

        #expect(spy.dismissCalled == true)
        #expect(spy.openedDeepLink == nil)
        #expect(spy.openedURL == nil)
    }

    @Test
    func `a deeplink that resolves dismisses the sheet first, then opens the deep link`() throws {
        let spy = Spy()
        let link = DeepLink.quickAdd(projectID: nil)
        let url = try #require(URL(string: "viku://quick-add"))

        spy.dispatcher(resolving: link).dispatch(.deeplink(label: "Open", url: url))

        #expect(spy.dismissCalled == true)
        #expect(spy.resolvedURL == url)
        #expect(spy.openedDeepLink == link)
        #expect(spy.openedURL == nil)
    }

    @Test
    func `a deeplink that doesn't resolve still dismisses but opens nothing, failing safe`() throws {
        let spy = Spy()
        let url = try #require(URL(string: "viku://not-a-real-destination"))

        spy.dispatcher(resolving: nil).dispatch(.deeplink(label: "Open", url: url))

        #expect(spy.dismissCalled == true)
        #expect(spy.openedDeepLink == nil)
        #expect(spy.openedURL == nil)
    }

    @Test
    func `a url action opens it externally without touching the sheet`() throws {
        let spy = Spy()
        let url = try #require(URL(string: "https://viku.app/docs"))

        spy.dispatcher(resolving: nil).dispatch(.url(label: "Read more", url: url))

        #expect(spy.openedURL == url)
        #expect(spy.dismissCalled == false)
        #expect(spy.openedDeepLink == nil)
    }

    @Test
    func `a guide action that slipped through is dropped without side effects`() {
        let spy = Spy()
        spy.dispatcher(resolving: nil).dispatch(.guide(label: "How to", guideId: "missing"))

        #expect(spy.dismissCalled == false)
        #expect(spy.openedDeepLink == nil)
        #expect(spy.openedURL == nil)
    }
}
