/// What presenting "What's New" needs in order to remember which release's
/// content this device has already shown, without knowing anything about
/// where it's persisted. Implemented by `WhatsNewSeenVersionStore` in the
/// app target and injected via `AppContainer`, the same way
/// `ServerVersionCaching` is.
///
/// Stores `WhatsNewRelease.version` — the content's own identity — never
/// the running app's exact build number. See `WhatsNewRelease`'s doc
/// comment for why that distinction is what makes skipping a release (by
/// shipping no new content) and crossing from a TestFlight build to the
/// matching App Store build both work with no special-casing in
/// `WhatsNewEligibility`.
///
/// Whether a device counts as a fresh install — which should never show the
/// sheet, only silently record the current release as seen — is derived
/// from whether it already has a connected account, not from this store
/// being empty: a pre-1.0 user who's been onboarded for months would also
/// have never written anything here, since `WhatsNewEligibility`'s minimum
/// version floor kept the sheet from ever showing before.
@MainActor
public protocol WhatsNewSeenVersionStoring {
    var lastSeenReleaseVersion: String? { get }
    func setLastSeenReleaseVersion(_ version: String?)
}
