import SwiftUI
import VikunjaCore

/// Small, static glyph marking a task or project that still has a local edit
/// waiting in the offline mutation queue. Deliberately not animated: the
/// point is "this change isn't on the server yet", not "something is
/// loading", and a spinner on every edited row would read as the latter.
///
/// When `showsDetailsOnTap` is `true`, the glyph becomes a button that opens
/// a short explanation of what the state means. The shared row views leave it
/// `false` so tapping a row still opens the task or project instead.
public struct VikuPendingSyncIndicator: View {
    private let status: SyncItemStatus
    private let font: Font
    private let showsDetailsOnTap: Bool

    @Environment(\.vikuPalette) private var palette
    @Environment(\.vikuIsOnline) private var isOnline
    @State private var isShowingDetails = false

    public init(
        status: SyncItemStatus,
        font: Font = VikuFont.caption2,
        showsDetailsOnTap: Bool = false,
    ) {
        self.status = status
        self.font = font
        self.showsDetailsOnTap = showsDetailsOnTap
    }

    public var body: some View {
        if isOnline {
            EmptyView()
        } else if showsDetailsOnTap {
            Button {
                isShowingDetails = true
            } label: {
                glyph
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingDetails, arrowEdge: .top) {
                VikuPendingSyncDetails(status: status)
                    .presentationCompactAdaptation(.popover)
            }
        } else {
            glyph
        }
    }

    private var glyph: some View {
        Image(systemName: status.pendingSyncSymbolName)
            .font(font)
            .foregroundStyle(status.pendingSyncColor(in: palette))
            .accessibilityLabel(Text(status.pendingSyncTitle, bundle: .module))
    }
}

private struct VikuPendingSyncDetails: View {
    let status: SyncItemStatus

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            HStack(spacing: VikuSpacing.xs) {
                Image(systemName: status.pendingSyncSymbolName)
                    .foregroundStyle(status.pendingSyncColor(in: palette))
                Text(status.pendingSyncTitle, bundle: .module)
                    .font(VikuFont.subheadline)
                    .fontWeight(.semibold)
            }

            Text(message, bundle: .module)
                .font(VikuFont.footnote)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, VikuSpacing.lg)
        .padding(.vertical, VikuSpacing.xl)
        .frame(minWidth: 240, maxWidth: 300, alignment: .leading)
    }

    private var message: LocalizedStringKey {
        switch status {
        case .pending:
            "Local changes are saved on this device and will upload when the connection is available."
        case .failed:
            "The last upload attempt failed. The app will retry automatically."
        }
    }
}

extension SyncItemStatus {
    var pendingSyncSymbolName: String {
        switch self {
        case .pending: "arrow.up.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var pendingSyncTitle: LocalizedStringKey {
        switch self {
        case .pending: "Pending sync"
        case .failed: "Sync failed"
        }
    }

    func pendingSyncColor(in palette: VikuPalette) -> Color {
        switch self {
        case .pending: palette.textSecondary
        case .failed: palette.semanticDangerText
        }
    }
}

public extension EnvironmentValues {
    /// Pending edits matter to the user while offline. While connected, queued
    /// mutations are transient implementation state and should not flash in
    /// list rows as the queue drains.
    @Entry var vikuIsOnline: Bool = true

    /// Per-row pending-sync lookups, keyed by entity kind + id. Injected once
    /// by the app shell and read directly by the shared row views
    /// (`VikuTaskRow`, the projects list, a task's detail header), so no
    /// feature view model has to thread a status through every task/project
    /// it renders. Empty by default, so screens outside that shell (previews,
    /// tests) simply show no indicator.
    @Entry var pendingSyncStatuses: [SyncItemKey: SyncItemStatus] = [:]
}

extension EnvironmentValues {
    /// Also used by inline text glyphs, which cannot embed the indicator view.
    var visiblePendingSyncStatuses: [SyncItemKey: SyncItemStatus] {
        vikuIsOnline ? [:] : pendingSyncStatuses
    }
}
