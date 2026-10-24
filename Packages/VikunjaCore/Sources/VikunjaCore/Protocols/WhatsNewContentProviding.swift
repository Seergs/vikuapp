import Foundation

/// What presenting "What's New" needs in order to load this release's
/// content, without knowing anything about where it's bundled or how
/// locale fallback works.
///
/// A decode failure never throws — whatever calls this treats `nil` the
/// same as there being nothing to show, so a mistake in the bundled file
/// (which, unlike a server response, can't be hot-fixed) can never be the
/// reason app launch breaks.
public protocol WhatsNewContentProviding: Sendable {
    func content(for locale: Locale) -> WhatsNewContent?
}
