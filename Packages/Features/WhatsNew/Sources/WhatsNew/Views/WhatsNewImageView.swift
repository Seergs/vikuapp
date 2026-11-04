import SwiftUI
import VikuDesignSystem

/// A fixed-size decorative image; loading never moves the surrounding content.
struct WhatsNewImageView: View {
    let value: String?
    let height: CGFloat
    @Environment(\.vikuPalette) private var palette
    @State private var viewModel = WhatsNewImageViewModel()

    var body: some View {
        Rectangle()
            .fill(palette.fieldBackground)
            .frame(height: height)
            .overlay {
                switch WhatsNewImageSource(value) {
                case let .asset(name):
                    Image(name)
                        .resizable()
                        .scaledToFill()
                case let .remote(url):
                    if viewModel.imageURL == url, let image = viewModel.image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                case .placeholder:
                    EmptyView()
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: value) {
                await viewModel.load(WhatsNewImageSource(value))
            }
    }
}
