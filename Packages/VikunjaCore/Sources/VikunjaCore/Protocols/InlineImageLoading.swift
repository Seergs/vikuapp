import Foundation

/// Which rendition of an embedded image to load.
public enum InlineImageVariant: Hashable, Sendable {
    /// Sized for showing inside the text: Vikunja's `xl` preview (800 px) for
    /// attachments, falling back to the original when the server can't
    /// produce one.
    case display
    /// The file as uploaded, for the full-screen viewer.
    case original
}

public enum InlineImageLoadingError: Error, Equatable, Sendable {
    /// The `src` can't be loaded safely (not `https`, or an attachment of a
    /// different instance). Retrying won't help.
    case unsupportedSource
}

/// Loads the bytes of an image embedded in a rich-text field, given the raw
/// `src` from the HTML. Implementations decide how to authenticate; callers
/// only see image data or an error.
public protocol InlineImageLoading: Sendable {
    func imageData(for source: String, variant: InlineImageVariant) async throws -> Data
}
