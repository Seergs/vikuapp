import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// A single "how to" guide: numbered steps, an optional tip callout, and a
/// bottom bar with the guide's own primary/secondary actions. Purely
/// presentational — every string shown comes from the bundled guide content
/// (`Text(verbatim:)` throughout), same reasoning as `WhatsNewMainView`.
public struct WhatsNewGuideView: View {
    @State private var viewModel: WhatsNewGuideViewModel
    @Environment(\.vikuPalette) private var palette
    private let onBack: () -> Void

    /// Takes a factory, not an already-built view model — see
    /// `WhatsNewMainView.init`'s doc comment for why.
    public init(makeViewModel: @escaping () -> WhatsNewGuideViewModel, onBack: @escaping () -> Void) {
        _viewModel = State(initialValue: makeViewModel())
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: viewModel.title)
                        .font(VikuFont.title.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.top, VikuSpacing.lg)

                    Text(verbatim: viewModel.intro)
                        .font(VikuFont.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, VikuSpacing.xs)

                    VStack(alignment: .leading, spacing: VikuSpacing.lg + VikuSpacing.xs) {
                        ForEach(Array(viewModel.steps.enumerated()), id: \.offset) { index, step in
                            stepRow(number: index + 1, step: step)
                        }
                    }
                    .padding(.top, VikuSpacing.lg)

                    if let tip = viewModel.tip {
                        tipCallout(tip)
                            .padding(.top, VikuSpacing.xl - VikuSpacing.xs)
                    }
                }
                .padding(.horizontal, VikuSpacing.lg)
                .padding(.bottom, VikuSpacing.xxl)
            }

            bottomBar
        }
        .background(palette.pageBackground)
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.fieldBackground, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, VikuSpacing.lg)
        .padding(.top, VikuSpacing.lg)
    }

    private func stepRow(number: Int, step: WhatsNewGuide.Step) -> some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            HStack(alignment: .top, spacing: VikuSpacing.sm) {
                ZStack {
                    Circle().fill(palette.brand)
                    Text(number, format: .number)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.brandForeground)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: VikuSpacing.xxs + 1) {
                    Text(verbatim: step.title)
                        .font(VikuFont.callout.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(verbatim: step.body)
                        .font(VikuFont.subheadline)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            stepImage(step.image)
                .padding(.leading, 26 + VikuSpacing.sm)
        }
    }

    @ViewBuilder
    private func stepImage(_ name: String?) -> some View {
        if let name {
            Image(name)
                .resizable()
                .scaledToFill()
                .frame(height: 150)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous)
                .fill(palette.fieldBackground)
                .frame(height: 150)
        }
    }

    private func tipCallout(_ tip: String) -> some View {
        HStack(alignment: .top, spacing: VikuSpacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(palette.brand)
            Text(verbatim: tip)
                .font(VikuFont.subheadline)
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VikuSpacing.md)
        .background(palette.brand.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
    }

    @ViewBuilder
    private var bottomBar: some View {
        if viewModel.primaryAction != nil || viewModel.secondaryAction != nil {
            VStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                if let primaryAction = viewModel.primaryAction {
                    Button {
                        viewModel.handle(primaryAction)
                    } label: {
                        Text(verbatim: primaryAction.label)
                            .font(VikuFont.body.weight(.bold))
                            .foregroundStyle(palette.brandForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, VikuSpacing.md - VikuSpacing.xxs)
                    }
                    .background(palette.brand, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
                }

                if let secondaryAction = viewModel.secondaryAction {
                    Button {
                        viewModel.handle(secondaryAction)
                    } label: {
                        Text(verbatim: secondaryAction.label)
                            .font(VikuFont.subheadline.weight(.semibold))
                            .foregroundStyle(palette.brand)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, VikuSpacing.lg)
            .padding(.top, VikuSpacing.sm)
            .padding(.bottom, VikuSpacing.lg)
        }
    }
}
