import Foundation

/// The single question the app's composition root needs answered at
/// launch: "is there a release to show right now, and if so, what's in
/// it?" Combines the bundled content provider, `WhatsNewEligibility`'s
/// rule, and the on-device "last seen" record.
///
/// Also owns the one side effect the decision itself requires: when
/// `hasCompletedOnboarding` is `false`, this silently records the current
/// release as already seen rather than ever presenting it — see
/// `WhatsNewEligibility.shouldPresent`'s `hasCompletedOnboarding` doc
/// comment for why a fresh install must never be shown content that
/// predates its own first launch.
public struct WhatsNewPresentationResolver {
    private let contentProvider: WhatsNewContentProviding
    private let seenVersionStore: WhatsNewSeenVersionStoring

    public init(contentProvider: WhatsNewContentProviding, seenVersionStore: WhatsNewSeenVersionStoring) {
        self.contentProvider = contentProvider
        self.seenVersionStore = seenVersionStore
    }

    /// - `hasCompletedOnboarding`: pass `false` only from the exact call
    ///   site where an account was just created by onboarding, not a
    ///   returning launch — that's what triggers the silent "already seen"
    ///   recording instead of ever returning content to show.
    /// - `bypassMinimumVersion`: the caller's own `#if DEBUG` decision, see
    ///   `WhatsNewEligibility`.
    @MainActor
    public func contentToPresent(
        locale: Locale,
        currentAppVersion: String,
        hasCompletedOnboarding: Bool,
        bypassMinimumVersion: Bool,
    ) -> WhatsNewContent? {
        guard let content = contentProvider.content(for: locale) else { return nil }

        let shouldPresent = WhatsNewEligibility.shouldPresent(
            release: content.release,
            currentAppVersion: currentAppVersion,
            lastSeenReleaseVersion: seenVersionStore.lastSeenReleaseVersion,
            hasCompletedOnboarding: hasCompletedOnboarding,
            bypassMinimumVersion: bypassMinimumVersion,
        )
        guard shouldPresent else {
            if !hasCompletedOnboarding {
                seenVersionStore.setLastSeenReleaseVersion(content.release.version)
            }
            return nil
        }
        return content
    }
}
