import Foundation

/// Writes downloaded attachment bytes to a temp file so QuickLook can preview
/// it — the download is bearer-authed, so its remote URL can't be handed to
/// QuickLook directly. Files land in a dedicated subfolder that's cleared on
/// each write to keep only the most recent preview around. Lives here rather
/// than in the view so `TaskDetailViewModel` owns the disk write (ARCH-MVVM-02).
enum AttachmentPreviewFile {
    static func write(_ data: Data, named fileName: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("attachment-previews", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sanitized = fileName.replacingOccurrences(of: "/", with: "_")
            let url = directory.appendingPathComponent(sanitized.isEmpty ? "attachment" : sanitized)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
