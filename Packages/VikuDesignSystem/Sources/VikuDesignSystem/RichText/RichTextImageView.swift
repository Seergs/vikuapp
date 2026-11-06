import ImageIO
import SwiftUI
import VikunjaCore

public extension View {
    /// Supplies the loader `RichTextView` uses for embedded images. Without
    /// one, images show their "unavailable" state.
    func richTextImageLoader(_ loader: (any InlineImageLoading)?) -> some View {
        environment(\.richTextImageLoader, loader)
    }

    /// Called when the user taps a loaded embedded image, typically to open the
    /// full-size original.
    func onRichTextImageTap(_ action: ((RichTextImage) -> Void)?) -> some View {
        environment(\.richTextImageTap, action)
    }
}

extension EnvironmentValues {
    @Entry var richTextImageLoader: (any InlineImageLoading)?
    @Entry var richTextImageTap: ((RichTextImage) -> Void)?
}

/// One embedded image: loads the display rendition through the environment's
/// loader, reserving space while it loads and showing the alt text when it
/// can't.
///
/// The spinner follows the app-wide rule: it appears only after one second of
/// loading and then stays for at least one second. That only delays when the
/// result is shown, never the download itself.
struct RichTextImageView: View {
    let image: RichTextImage

    @Environment(\.richTextImageLoader) private var loader
    @Environment(\.richTextImageTap) private var onTap
    @Environment(\.vikuPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Phase = .loading
    @State private var attempt = 0
    @State private var showsSpinner = false
    @State private var spinnerShownAt: ContinuousClock.Instant?

    private static let placeholderHeight: CGFloat = 180
    private static let maxDisplayHeight: CGFloat = 420
    /// Decoding cap: well above the 800 px `xl` preview, and enough for a
    /// full-width image on any iPhone without decoding a huge original.
    private static let maxDecodedPixelSize = 2048

    private enum Phase {
        case loading
        case loaded(DecodedImage)
        case failed(retryable: Bool)

        var isLoading: Bool {
            if case .loading = self {
                return true
            }
            return false
        }
    }

    private struct LoadID: Hashable {
        let source: String
        let attempt: Int
        let hasLoader: Bool
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: LoadID(source: image.source, attempt: attempt, hasLoader: loader != nil)) {
                await load()
            }
            .task(id: phase.isLoading) {
                await revealSpinnerIfStillLoading()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingPlaceholder
        case let .loaded(decoded):
            loadedImage(decoded)
        case let .failed(retryable):
            failure(retryable: retryable)
        }
    }

    // MARK: States

    private var loadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous)
            .fill(palette.fieldBackground)
            .frame(maxWidth: .infinity)
            .frame(height: Self.placeholderHeight)
            .overlay {
                if showsSpinner {
                    ProgressView()
                        .transition(.opacity)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Loading image", bundle: .module))
    }

    @ViewBuilder
    private func loadedImage(_ decoded: DecodedImage) -> some View {
        // Image pixels count as points, the way a browser sizes an <img>: a
        // small icon stays small, an 800 px preview fills the width.
        let picture = Image(decorative: decoded.cgImage, scale: 1)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: CGFloat(decoded.cgImage.width), maxHeight: Self.maxDisplayHeight)
            .clipShape(RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))

        if let onTap {
            Button { onTap(image) } label: { picture }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityName)
                .accessibilityAddTraits(.isImage)
                .accessibilityHint(Text("Opens the full-size image", bundle: .module))
        } else {
            picture
                .accessibilityElement()
                .accessibilityLabel(accessibilityName)
                .accessibilityAddTraits(.isImage)
        }
    }

    private func failure(retryable: Bool) -> some View {
        HStack(spacing: VikuSpacing.sm) {
            Image(systemName: "photo")
                .foregroundStyle(palette.textTertiary)
                .accessibilityHidden(true)
            Group {
                if let alt = image.alt {
                    Text(verbatim: alt)
                } else {
                    Text("Image unavailable", bundle: .module)
                }
            }
            .font(VikuFont.footnote)
            .foregroundStyle(palette.textTertiary)
            .lineLimit(2)
            Spacer(minLength: VikuSpacing.sm)
            if retryable {
                Button {
                    phase = .loading
                    attempt += 1
                } label: {
                    Text("Retry", bundle: .module)
                        .font(VikuFont.footnote)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(VikuSpacing.sm + VikuSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.fieldBackground,
            in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous),
        )
        .accessibilityElement(children: .combine)
    }

    private var accessibilityName: Text {
        if let alt = image.alt {
            Text(verbatim: alt)
        } else {
            Text("Image", bundle: .module)
        }
    }

    // MARK: Loading

    private func load() async {
        guard let loader else {
            phase = .failed(retryable: false)
            return
        }
        // A new source (the description was edited) starts from the
        // placeholder rather than keeping the previous picture.
        if !phase.isLoading {
            phase = .loading
        }

        let result: Phase
        do {
            let data = try await loader.imageData(for: image.source, variant: .display)
            if let decoded = await RichTextImageDecoder.decode(data, maxPixelSize: Self.maxDecodedPixelSize) {
                result = .loaded(decoded)
            } else {
                result = .failed(retryable: false)
            }
        } catch is CancellationError {
            return
        } catch InlineImageLoadingError.unsupportedSource {
            result = .failed(retryable: false)
        } catch {
            result = .failed(retryable: true)
        }
        guard !Task.isCancelled else { return }

        if let shownAt = spinnerShownAt {
            try? await ContinuousClock().sleep(until: shownAt.advanced(by: .seconds(1)))
            guard !Task.isCancelled else { return }
        }

        // Only a load the user actually waited for animates into place; a
        // cached image just appears.
        let animate = !reduceMotion && spinnerShownAt != nil
        withAnimation(animate ? .smooth : nil) {
            phase = result
            showsSpinner = false
        }
        spinnerShownAt = nil
    }

    private func revealSpinnerIfStillLoading() async {
        guard phase.isLoading else { return }
        do {
            try await Task.sleep(for: .seconds(1))
        } catch {
            return
        }
        guard phase.isLoading else { return }
        spinnerShownAt = .now
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) {
            showsSpinner = true
        }
    }
}

/// A decoded bitmap. `CGImage` is immutable, so handing it across actors is
/// safe even though Core Graphics doesn't declare it `Sendable`.
struct DecodedImage: @unchecked Sendable {
    let cgImage: CGImage
}

/// Decodes off the main actor and downsamples on the way, so a large original
/// never lands in memory at full size.
enum RichTextImageDecoder {
    static func decode(_ data: Data, maxPixelSize: Int) async -> DecodedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return DecodedImage(cgImage: image)
    }
}
