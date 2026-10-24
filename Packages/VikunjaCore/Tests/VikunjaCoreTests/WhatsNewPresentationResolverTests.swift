import Foundation
import Testing
@testable import VikunjaCore

@MainActor
@Suite("WhatsNewPresentationResolver")
struct WhatsNewPresentationResolverTests {
    private struct FakeContentProvider: WhatsNewContentProviding {
        let content: WhatsNewContent?
        func content(for locale: Locale) -> WhatsNewContent? {
            content
        }
    }

    @MainActor
    private final class FakeSeenVersionStore: WhatsNewSeenVersionStoring {
        var lastSeenReleaseVersion: String?
        func setLastSeenReleaseVersion(_ version: String?) {
            lastSeenReleaseVersion = version
        }
    }

    private func content(version: String = "1.5", minAppVersion: String = "1.0.0") -> WhatsNewContent {
        let release = WhatsNewRelease(
            version: version, date: "2026-10-23", minAppVersion: minAppVersion, title: "T", subtitle: "S",
        )
        return WhatsNewContent(schemaVersion: 1, release: release)
    }

    @MainActor
    private func resolver(content: WhatsNewContent?, store: FakeSeenVersionStore) -> WhatsNewPresentationResolver {
        WhatsNewPresentationResolver(contentProvider: FakeContentProvider(content: content), seenVersionStore: store)
    }

    @Test
    func `no bundled content for this locale returns nil and writes nothing`() {
        let store = FakeSeenVersionStore()
        let result = resolver(content: nil, store: store).contentToPresent(
            locale: .init(identifier: "en"),
            currentAppVersion: "2.0.0",
            hasCompletedOnboarding: true,
            bypassMinimumVersion: false,
        )

        #expect(result == nil)
        #expect(store.lastSeenReleaseVersion == nil)
    }

    @Test
    func `an eligible release is returned, without writing the seen store itself`() {
        let store = FakeSeenVersionStore()
        let release = content()
        let result = resolver(content: release, store: store).contentToPresent(
            locale: .init(identifier: "en"),
            currentAppVersion: "2.0.0",
            hasCompletedOnboarding: true,
            bypassMinimumVersion: false,
        )

        #expect(result == release)
        #expect(store.lastSeenReleaseVersion == nil)
    }

    @Test
    func `an already seen release returns nil without rewriting the store`() {
        let store = FakeSeenVersionStore()
        store.lastSeenReleaseVersion = "1.5"
        let result = resolver(content: content(version: "1.5"), store: store).contentToPresent(
            locale: .init(identifier: "en"),
            currentAppVersion: "2.0.0",
            hasCompletedOnboarding: true,
            bypassMinimumVersion: false,
        )

        #expect(result == nil)
        #expect(store.lastSeenReleaseVersion == "1.5")
    }

    @Test
    func `below the minimum app version floor returns nil without writing the store`() {
        let store = FakeSeenVersionStore()
        let result = resolver(content: content(minAppVersion: "5.0.0"), store: store).contentToPresent(
            locale: .init(identifier: "en"),
            currentAppVersion: "2.0.0",
            hasCompletedOnboarding: true,
            bypassMinimumVersion: false,
        )

        #expect(result == nil)
        #expect(store.lastSeenReleaseVersion == nil)
    }

    @Test
    func `bypassing the minimum version still returns content below the floor`() {
        let store = FakeSeenVersionStore()
        let release = content(minAppVersion: "5.0.0")
        let result = resolver(content: release, store: store).contentToPresent(
            locale: .init(identifier: "en"),
            currentAppVersion: "2.0.0",
            hasCompletedOnboarding: true,
            bypassMinimumVersion: true,
        )

        #expect(result == release)
    }

    @Test
    func `a fresh install never sees content, and silently records it as seen`() {
        let store = FakeSeenVersionStore()
        let release = content(version: "1.5")
        let result = resolver(content: release, store: store).contentToPresent(
            locale: .init(identifier: "en"),
            currentAppVersion: "2.0.0",
            hasCompletedOnboarding: false,
            bypassMinimumVersion: false,
        )

        #expect(result == nil)
        #expect(store.lastSeenReleaseVersion == "1.5")
    }
}
