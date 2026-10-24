import Testing
@testable import VikunjaCore

@Suite("WhatsNewEligibility")
struct WhatsNewEligibilityTests {
    private func release(version: String = "1.5", minAppVersion: String = "1.5.0") -> WhatsNewRelease {
        WhatsNewRelease(version: version, date: "2026-10-23", minAppVersion: minAppVersion, title: "", subtitle: "")
    }

    @Test
    func `a fresh install never shows, regardless of versions`() {
        #expect(WhatsNewEligibility.shouldPresent(
            release: release(),
            currentAppVersion: "1.5.0",
            lastSeenReleaseVersion: nil,
            hasCompletedOnboarding: false,
        ) == false)
    }

    @Test
    func `an existing user updating to a new release sees it`() {
        #expect(WhatsNewEligibility.shouldPresent(
            release: release(version: "1.5"),
            currentAppVersion: "1.5.0",
            lastSeenReleaseVersion: "1.4",
            hasCompletedOnboarding: true,
        ) == true)
    }

    @Test
    func `relaunching the same release does not show it again`() {
        #expect(WhatsNewEligibility.shouldPresent(
            release: release(version: "1.5"),
            currentAppVersion: "1.5.0",
            lastSeenReleaseVersion: "1.5",
            hasCompletedOnboarding: true,
        ) == false)
    }

    @Test
    func `the minimum version floor blocks a release that has not been reached yet`() {
        #expect(WhatsNewEligibility.shouldPresent(
            release: release(version: "1.0", minAppVersion: "1.0.0"),
            currentAppVersion: "0.9.5",
            lastSeenReleaseVersion: nil,
            hasCompletedOnboarding: true,
        ) == false)
    }

    @Test
    func `bypassing the minimum version lets a Debug build preview content ahead of its floor`() {
        #expect(WhatsNewEligibility.shouldPresent(
            release: release(version: "1.0", minAppVersion: "1.0.0"),
            currentAppVersion: "0.9.5",
            lastSeenReleaseVersion: nil,
            hasCompletedOnboarding: true,
            bypassMinimumVersion: true,
        ) == true)
    }

    @Test
    func `a release that ships with no new content stays unseen across every version it spans`() {
        // The maintainer chose not to announce 1.1.1 or 1.2.0, so the
        // bundled file is untouched and still carries 1.1's identity.
        let unchanged = release(version: "1.1", minAppVersion: "1.1.0")
        for runningVersion in ["1.1.1", "1.2.0"] {
            #expect(WhatsNewEligibility.shouldPresent(
                release: unchanged,
                currentAppVersion: runningVersion,
                lastSeenReleaseVersion: "1.1",
                hasCompletedOnboarding: true,
            ) == false)
        }
    }

    @Test
    func `a pre floor user upgrading past the floor for the first time sees it`() {
        // Pre-1.0 TestFlight user: onboarded long ago, but the floor never
        // let anything show, so lastSeenReleaseVersion was never written.
        #expect(WhatsNewEligibility.shouldPresent(
            release: release(version: "1.0", minAppVersion: "1.0.0"),
            currentAppVersion: "1.0.0",
            lastSeenReleaseVersion: nil,
            hasCompletedOnboarding: true,
        ) == true)
    }

    @Test
    func `already seeing a release during TestFlight beta skips it again on the App Store build`() {
        // Same release.version label, different exact build — the
        // App Store release doesn't have to be byte-identical to the beta.
        #expect(WhatsNewEligibility.shouldPresent(
            release: release(version: "1.0", minAppVersion: "1.0.0"),
            currentAppVersion: "1.0.1",
            lastSeenReleaseVersion: "1.0",
            hasCompletedOnboarding: true,
        ) == false)
    }

    @Test
    func `an unparseable current app version fails safe rather than showing`() {
        #expect(WhatsNewEligibility.shouldPresent(
            release: release(),
            currentAppVersion: "not-a-version",
            lastSeenReleaseVersion: nil,
            hasCompletedOnboarding: true,
        ) == false)
    }

    @Test
    func `an unparseable minAppVersion fails safe rather than showing`() {
        #expect(WhatsNewEligibility.shouldPresent(
            release: release(minAppVersion: "unknown"),
            currentAppVersion: "1.5.0",
            lastSeenReleaseVersion: nil,
            hasCompletedOnboarding: true,
        ) == false)
    }
}
