import SwiftUI
import VikuDesignSystem
import VikunjaCore

struct AppearancePickerView: View {
    let themeStore: AppThemeStoring

    @Environment(\.vikuPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .subheadline) private var indicatorSize: CGFloat = 18

    private let selectionAnimation = Animation.easeInOut(duration: 0.2)
    private let previewScaleAnimation = Animation.smooth(duration: 0.38)
    private let ringOutset: CGFloat = 5
    private let ringWidth: CGFloat = 2.5

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: VikuSpacing.md, alignment: .top),
        count: 2,
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VikuSpacing.lg) {
                Text(
                    "The theme changes buttons, checkboxes, and accents. Your project and label colors stay the same.",
                    bundle: .module,
                )
                .font(VikuFont.footnote)
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("settings.appearance.note")

                LazyVGrid(columns: columns, spacing: VikuSpacing.lg) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        option(for: theme)
                    }
                }
            }
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, VikuSpacing.sm)
            .padding(.bottom, VikuSpacing.lg)
        }
        .background(palette.pageBackground)
        .navigationTitle(Text("Appearance", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    private func option(for theme: AppTheme) -> some View {
        let isSelected = theme == themeStore.theme
        return Button {
            themeStore.setTheme(theme)
        } label: {
            VStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                previewCard(for: theme, isSelected: isSelected)

                HStack(spacing: VikuSpacing.xs) {
                    selectionIndicator(for: theme, isSelected: isSelected)
                    Text(verbatim: theme.displayName)
                        .font(VikuFont.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Theme \(theme.displayName)", bundle: .module))
        .accessibilityIdentifier("settings.appearance.option.\(theme.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func previewCard(for theme: AppTheme, isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: VikuRadius.lg)
        let shadowOpacity = colorScheme == .dark ? 0.3 : 0.06
        return preview(for: theme)
            .clipShape(shape)
            .animation(selectionAnimation) { card in
                card
                    .shadow(color: .black.opacity(isSelected ? 0 : shadowOpacity), radius: 3, y: 1)
                    .overlay {
                        shape.strokeBorder(palette.textTertiary, lineWidth: 0.5)
                            .opacity(isSelected ? 0 : 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: VikuRadius.lg + ringOutset)
                            .strokeBorder(theme.palette.brand, lineWidth: isSelected || reduceMotion ? ringWidth : 0)
                            .padding(-ringOutset)
                            .opacity(isSelected ? 1 : 0)
                    }
            }
            .animation(reduceMotion ? nil : previewScaleAnimation) { card in
                card.scaleEffect(isSelected || reduceMotion ? 1 : 0.975)
            }
            .accessibilityHidden(true)
    }

    private func selectionIndicator(for theme: AppTheme, isSelected: Bool) -> some View {
        Circle()
            .strokeBorder(palette.textTertiary, lineWidth: 1.5)
            .animation(selectionAnimation) { outline in
                outline
                    .opacity(isSelected ? 0 : 1)
                    .background {
                        Circle()
                            .fill(theme.palette.brand)
                            .opacity(isSelected ? 1 : 0)
                    }
            }
            .overlay {
                Image(systemName: "checkmark")
                    .font(VikuFont.caption2.weight(.bold))
                    .foregroundStyle(theme.palette.brandForeground)
                    .opacity(isSelected ? 1 : 0)
            }
            .frame(width: indicatorSize, height: indicatorSize)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func preview(for theme: AppTheme) -> some View {
        if let colorScheme = theme.colorScheme {
            TodayThemePreview(palette: theme.palette)
                .environment(\.colorScheme, colorScheme)
        } else {
            TodayThemePreview(palette: theme.palette)
                .environment(\.colorScheme, .light)
                .overlay {
                    TodayThemePreview(palette: theme.palette)
                        .environment(\.colorScheme, .dark)
                        .mask {
                            HStack(spacing: 0) {
                                Color.clear
                                Rectangle()
                            }
                        }
                }
        }
    }
}
