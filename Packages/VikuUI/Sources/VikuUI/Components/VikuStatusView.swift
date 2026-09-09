import SwiftUI
import VikuDesignSystem

/// The empty / error "status" state shared by every feature screen: a large
/// SF Symbol, a headline title, a secondary message, and an optional bordered
/// "Try Again" button. Replaces the per-feature `*StatusView` copies.
public struct VikuStatusView: View {
    private let systemImage: String
    private let title: String
    private let message: String
    private let iconSize: CGFloat
    private let fillsHeight: Bool
    private let retry: (() -> Void)?

    /// - Parameters:
    ///   - fillsHeight: expand to fill the available height (the default —
    ///     screens that own their whole content area). Pass `false` when the
    ///     view sits inside a `ScrollView` alongside other content (task detail).
    ///   - retry: shows a "Try Again" button when non-nil.
    public init(
        systemImage: String,
        title: String,
        message: String,
        iconSize: CGFloat = 40,
        fillsHeight: Bool = true,
        retry: (() -> Void)? = nil,
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.iconSize = iconSize
        self.fillsHeight = fillsHeight
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: VikuSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(VikuColor.textTertiary)

            Text(title)
                .font(VikuFont.headline)

            Text(message)
                .font(VikuFont.subheadline)
                .foregroundStyle(VikuColor.textSecondary)
                .multilineTextAlignment(.center)

            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered)
                    .padding(.top, VikuSpacing.xs)
            }
        }
        .padding(VikuSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil)
    }
}
