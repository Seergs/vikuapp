import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The main "What's New" screen: release header, optional hero, feature
/// list, and a collapsible fixes section. Purely presentational — every
/// string shown comes from the bundled release content (`Text(verbatim:)`
/// throughout), not this module's own String Catalog, which only covers
/// this screen's own chrome ("VERSION", "Fixes & improvements").
public struct WhatsNewMainView: View {
    @State private var viewModel: WhatsNewMainViewModel
    @Environment(\.vikuPalette) private var palette

    /// Takes a factory, not an already-built view model — whatever presents
    /// this inside a `.sheet`/`.fullScreenCover` must still only ever call
    /// `makeViewModel()` once per sheet presentation. Building it directly
    /// inside that modifier's closure instead (skipping this `@State`
    /// factory pattern) is exactly the bug `ConnectionsListView`/
    /// `InstanceSetupView` already had to work around: SwiftUI can silently
    /// discard and rebuild the view model on an unrelated re-render.
    public init(makeViewModel: @escaping () -> WhatsNewMainViewModel) {
        _viewModel = State(initialValue: makeViewModel())
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if let hero = viewModel.hero {
                    heroCard(hero)
                        .padding(.top, VikuSpacing.lg)
                }

                if !viewModel.features.isEmpty {
                    VStack(alignment: .leading, spacing: VikuSpacing.lg + VikuSpacing.xxs) {
                        ForEach(viewModel.features, id: \.id) { feature in
                            featureRow(feature)
                        }
                    }
                    .padding(.top, VikuSpacing.xl - VikuSpacing.xs)
                }

                if !viewModel.fixes.isEmpty {
                    fixesSection
                        .padding(.top, VikuSpacing.xl - VikuSpacing.sm)
                }

                if viewModel.hasHistory {
                    seePreviousVersionsLink
                        .padding(.top, VikuSpacing.xl - VikuSpacing.sm)
                }
            }
            .padding(.horizontal, VikuSpacing.lg)
            .padding(.bottom, VikuSpacing.xxl)
        }
        .background(palette.pageBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: VikuSpacing.xs) {
                ZStack {
                    Circle().fill(palette.brand)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.brandForeground)
                }
                .frame(width: 20, height: 20)

                (
                    Text("VERSION", bundle: .module)
                        + Text(verbatim: " \(viewModel.release.version)")
                )
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .foregroundStyle(palette.brand)
            }

            if let dateLabel = viewModel.dateLabel {
                Text(verbatim: dateLabel)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, VikuSpacing.xxs)
            }

            Text(verbatim: viewModel.release.title)
                .font(VikuFont.largeTitle.weight(.bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, VikuSpacing.md)

            Text(verbatim: viewModel.release.subtitle)
                .font(VikuFont.body)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, VikuSpacing.sm)
        }
        .padding(.top, VikuSpacing.xl)
    }

    private func heroCard(_ hero: WhatsNewHero) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                heroImage(hero.image)

                if let badge = hero.badge {
                    Text(verbatim: badge)
                        .font(VikuFont.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, VikuSpacing.sm)
                        .padding(.vertical, VikuSpacing.xxs + 2)
                        .background(palette.brand, in: Capsule())
                        .padding(VikuSpacing.sm)
                }
            }

            VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                Text(verbatim: hero.title)
                    .font(VikuFont.headline)
                    .foregroundStyle(palette.textPrimary)
                Text(verbatim: hero.body)
                    .font(VikuFont.subheadline)
                    .foregroundStyle(palette.textSecondary)

                if let action = hero.action {
                    actionLink(action)
                        .padding(.top, VikuSpacing.xs)
                }
            }
            .padding(VikuSpacing.md)
        }
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VikuRadius.lg, style: .continuous))
    }

    @ViewBuilder
    private func heroImage(_ name: String?) -> some View {
        if let name {
            Image(name)
                .resizable()
                .scaledToFill()
                .frame(height: 180)
                .clipped()
        } else {
            Rectangle()
                .fill(palette.fieldBackground)
                .frame(height: 180)
        }
    }

    private func featureRow(_ feature: WhatsNewFeature) -> some View {
        HStack(alignment: .top, spacing: VikuSpacing.md - VikuSpacing.xxs) {
            iconBadge(systemName: feature.icon, tint: VikuColor.AccentTint.named(feature.tint).color)

            VStack(alignment: .leading, spacing: VikuSpacing.xxs + 1) {
                Text(verbatim: feature.title)
                    .font(VikuFont.callout.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(verbatim: feature.body)
                    .font(VikuFont.subheadline)
                    .foregroundStyle(palette.textSecondary)

                if let action = feature.action {
                    actionLink(action, isCompact: true)
                        .padding(.top, VikuSpacing.xxs)
                }
            }
        }
    }

    private func iconBadge(systemName: String, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: VikuRadius.sm - VikuSpacing.xs, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: 42, height: 42)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
    }

    private func actionLink(_ action: WhatsNewAction, isCompact: Bool = false) -> some View {
        Button {
            viewModel.handle(action)
        } label: {
            HStack(spacing: VikuSpacing.xxs) {
                Text(verbatim: action.label)
                    .font(isCompact ? VikuFont.subheadline.weight(.semibold) : VikuFont.callout.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: isCompact ? 11 : 12, weight: .bold))
            }
            .foregroundStyle(palette.brand)
        }
        .buttonStyle(.plain)
    }

    private var fixesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                viewModel.toggleFixesExpanded()
            } label: {
                HStack {
                    Text("Fixes & improvements", bundle: .module)
                        .font(VikuFont.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(viewModel.fixes.count, format: .number)
                        .font(VikuFont.footnote)
                        .foregroundStyle(palette.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                        .rotationEffect(.degrees(viewModel.isFixesExpanded ? 90 : 0))
                }
                .padding(VikuSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if viewModel.isFixesExpanded {
                VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                    ForEach(viewModel.fixes, id: \.self) { fix in
                        HStack(alignment: .top, spacing: VikuSpacing.sm) {
                            Circle()
                                .fill(palette.textTertiary)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(verbatim: fix)
                                .font(VikuFont.subheadline)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, VikuSpacing.md)
                .padding(.bottom, VikuSpacing.md)
            }
        }
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
        .animation(.default, value: viewModel.isFixesExpanded)
    }

    private var seePreviousVersionsLink: some View {
        Button {
            viewModel.showHistory()
        } label: {
            Text("See previous versions", bundle: .module)
                .font(VikuFont.subheadline.weight(.semibold))
                .foregroundStyle(palette.brand)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
    }
}
