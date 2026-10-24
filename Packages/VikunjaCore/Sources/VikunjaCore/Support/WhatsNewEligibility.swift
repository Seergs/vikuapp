/// Whether to present the "What's New" sheet for a given release, given the
/// running app's own state. Pure and I/O-free: nothing here reads or writes
/// `UserDefaults`, checks the build configuration, or touches onboarding
/// state directly — those live at the call site (see `WhatsNewRelease`'s
/// doc comment for the overall design, and the app composition root for how
/// this gets wired).
public enum WhatsNewEligibility {
    /// - `release`: the bundled release's own identity (`version`) and
    ///   eligibility floor (`minAppVersion`).
    /// - `currentAppVersion`: the running app's own marketing version.
    /// - `lastSeenReleaseVersion`: the `release.version` this device last
    ///   showed the sheet for, or `nil` if it never has. Compared by content
    ///   identity, not by `currentAppVersion`'s exact build — a release that
    ///   ships with no new content simply keeps the previous `version`
    ///   label, which is what makes "ship nothing to skip a release" work
    ///   with no extra flag, and what makes a user crossing from a
    ///   TestFlight build to the matching App Store build not see the same
    ///   content twice.
    /// - `hasCompletedOnboarding`: `false` on a fresh install — the sheet
    ///   never appears there; the caller should still silently record
    ///   `release.version` as seen so the device doesn't later mistake a
    ///   fresh install for a pre-floor user who's never had a chance to see
    ///   anything (see the eligibility floor note below).
    /// - `bypassMinimumVersion`: `true` from a Debug build, so the sheet can
    ///   be authored and previewed against `release.minAppVersion` set far
    ///   ahead of the current app version, without waiting to actually
    ///   reach it. The caller decides this (e.g. from `#if DEBUG`), not this
    ///   function — keeping the decision itself testable under any
    ///   combination of inputs.
    public static func shouldPresent(
        release: WhatsNewRelease,
        currentAppVersion: String,
        lastSeenReleaseVersion: String?,
        hasCompletedOnboarding: Bool,
        bypassMinimumVersion: Bool = false,
    ) -> Bool {
        guard hasCompletedOnboarding else { return false }
        guard bypassMinimumVersion || meetsMinimumVersion(release: release, currentAppVersion: currentAppVersion) else {
            return false
        }
        return lastSeenReleaseVersion != release.version
    }

    /// Fails safe: an unparseable `currentAppVersion`/`minAppVersion` never
    /// qualifies, rather than crashing or assuming the newest behavior —
    /// same reasoning as `ServerVersion`'s own doc comment.
    private static func meetsMinimumVersion(release: WhatsNewRelease, currentAppVersion: String) -> Bool {
        guard let current = ServerVersion(currentAppVersion), let minimum = ServerVersion(release.minAppVersion) else {
            return false
        }
        return current >= minimum
    }
}
