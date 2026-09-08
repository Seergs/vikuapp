import Foundation
import UniformTypeIdentifiers

/// One file the user picked through `.fileImporter`, read into memory with its
/// name and MIME type resolved — `nil` if the bytes can't be read (a
/// security-scoped URL that won't open). Lives here rather than in the view so
/// `TaskDetailViewModel` owns "turn a picked URL into bytes" (ARCH-MVVM-02).
struct PickedFile {
    let data: Data
    let fileName: String
    let mimeType: String

    init?(contentsOf url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else { return nil }
        self.data = data
        self.fileName = url.lastPathComponent
        let resolved = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        self.mimeType = resolved?.preferredMIMEType ?? "application/octet-stream"
    }
}
