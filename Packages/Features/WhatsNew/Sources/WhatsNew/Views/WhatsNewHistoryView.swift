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
                .padding(.horizontal, VikuSpacing.lg)
                .padding(.top, VikuSpacing.sm)
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

            Spacer()

            Text("Version history", bundle: .module)
                .font(VikuFont.subheadline.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, VikuSpacing.lg)
        .padding(.top, VikuSpacing.lg)
    }

    private func timelineRow(_ entry: WhatsNewHistoryEntry, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: VikuSpacing.md) {
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
            .frame(width: 12)

            VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: VikuSpacing.xs) {
                    (
                        Text("Version", bundle: .module)
                            + Text(verbatim: " \(entry.version)"),
                    )
                    .font(VikuFont.headline.weight(.bold))
                    .foregroundStyle(palette.textPrimary)

                    if let dateLabel = viewModel.dateLabel(for: entry) {
                        Text(verbatim: dateLabel)
                            .font(.system(.caption, design: .monospaced))
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
