import Foundation

/// Maps a file's MIME type to an SF Symbol for its attachment row. Feature-local
/// (like the priority-to-color mapping) — it's an attachment-display concern,
/// not a design token.
enum AttachmentIcon {
    static func systemName(forMimeType mime: String) -> String {
        let mime = mime.lowercased()
        if mime.hasPrefix("image/") {
            return "photo"
        }
        if mime.hasPrefix("video/") {
            return "film"
        }
        if mime.hasPrefix("audio/") {
            return "music.note"
        }
        if mime == "application/pdf" {
            return "doc.richtext"
        }
        if mime.hasPrefix("text/") {
            return "doc.text"
        }
        if mime.contains("zip") || mime.contains("compressed") || mime.contains("tar") {
            return "doc.zipper"
        }
        return "doc"
    }
}

enum AttachmentSizeFormatter {
    static func string(for bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }
}
