import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The "See previous versions" timeline: a connected-dot line with one entry
/// per past release, each rendering its plain-text recap items. No actions,
/// no icons, every string is `Text(verbatim:)` since it's bundled content.
public struct WhatsNewHistoryView: View {
    @State private var viewModel: WhatsNewHistoryViewModel
    @Environment(\.vikuPalette) private var palette
    private let onBack: () -> Void

    /// Takes a factory, not an already-built view model — see
    /// `WhatsNewMainView.init`'s doc comment for why.
    public init(makeViewModel: @escaping () -> WhatsNewHistoryViewModel, onBack: @escaping () -> Void) {
        _viewModel = State(initialValue: makeViewModel())
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.offset) { index, entry in
                        timelineRow(entry, isLast: index == viewModel.entries.count - 1)
                    }
                }
                // Without this, the VStack only ever takes the width of
                // its narrowest-fitting content (here, short one-line recap
                // items that never need to wrap) instead of the
                // `ScrollView`'s full width — and `ScrollView` centers
                // content that's narrower than itself instead of pinning
                // it to the leading edge, which is what was actually
                // pushing the timeline to the right.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VikuSpacing.lg)
                .padding(.top, VikuSpacing.lg)
                .padding(.bottom, VikuSpacing.xxl)
            }
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
            // Tap target reaches the 44pt minimum without growing the
            // visible circle (stays 36pt) or shifting it off the same
            // leading edge the body content below is aligned to.
            .frame(width: 44, height: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityLabel(Text("Back", bundle: .module))

            Spacer()

            Text("Version history", bundle: .module)
                .font(VikuFont.subheadline.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, VikuSpacing.lg)
        .padding(.top, VikuSpacing.lg)
    }

    private func timelineRow(_ entry: WhatsNewHistoryEntry, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: VikuSpacing.md) {
            // Default (center) alignment, not `.leading` — the connecting
            // line is much thinner than the dot and must stay centered
            // under it, not flush against its left edge. Column width
            // matches the dot's own diameter exactly (no extra wrapping
            // frame), so the dot's leading edge lines up with this row's
            // own leading edge, same as the header's back button above it.
            VStack(spacing: 0) {
                Circle()
                    .fill(palette.textTertiary)
                    .frame(width: 11, height: 11)
                    .padding(.top, VikuSpacing.xxs + 1)

                if !isLast {
                    Rectangle()
                        .fill(palette.fieldBackground)
                        .frame(width: 1.5)
                        .padding(.top, VikuSpacing.xs)
                }
            }
            .frame(width: 11)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: VikuSpacing.xs) {
                    (
                        Text("Version", bundle: .module)
                            .font(VikuFont.headline.weight(.bold))
                            + Text(verbatim: " \(entry.version)")
                            .font(.system(.headline, design: .monospaced, weight: .bold)),
                    )
                    .foregroundStyle(palette.textPrimary)

                    if let dateLabel = viewModel.dateLabel(for: entry) {
                        Text(verbatim: dateLabel)
                            .font(VikuFont.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: VikuSpacing.xxs + 1) {
                    ForEach(entry.items, id: \.self) { item in
                        Text(verbatim: item)
                            .font(VikuFont.subheadline)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .padding(.bottom, VikuSpacing.xl - VikuSpacing.xs)
        }
    }
}
