import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore

/// Lists every saved instance connection: tap a row to make it the active
/// one, the pencil to edit it. Deleting a connection only happens from
/// within its edit screen (`ConnectionFormView`), not from this list.
struct ConnectionsListView: View {
    @State private var viewModel: ConnectionsListViewModel
    let router: Router<SettingsRoute>

    /// Takes a factory rather than an already-built view model: this view is
    /// pushed from `SettingsRootView`'s `navigationDestination(for:)`, whose
    /// content closure SwiftUI can re-invoke independently of this view's own
    /// identity. Building the view model inside `@State`'s `init` means
    /// SwiftUI only uses `makeViewModel()`'s result the first time this
    /// screen's identity is created and keeps that same instance (and its
    /// already-loaded `accounts`) across any later re-invocation — otherwise
    /// a re-invocation would hand back a fresh, unloaded view model and the
    /// list would render blank after returning from a pushed screen.
    init(makeViewModel: @escaping () -> ConnectionsListViewModel, router: Router<SettingsRoute>) {
        _viewModel = State(initialValue: makeViewModel())
        self.router = router
    }

    var body: some View {
        content
            .background(VikuColor.Surface.page)
            .navigationTitle("Connections")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // `.onAppear` rather than `.task`: this view's own identity (and
            // its `@State` view model) survives a push into
            // `ConnectionFormView` and back, so a one-shot `.task` would
            // never refire — leaving a just-added/edited/deleted connection
            // stale once the user returns here.
            .onAppear { Task { await viewModel.load() } }
    }

    /// A plain `ScrollView`/`VStack`, not a `List` — `.insetGrouped` draws
    /// its own rounded card background behind each section, and that
    /// system-drawn shape visibly clashed against `AddConnectionButton`'s own
    /// rounded dashed border when the button lived inside a section. Building
    /// the "card" of connections by hand sidesteps that entirely and matches
    /// `ConnectionFormView`'s own `ScrollView`-based layout.
    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, VikuSpacing.xxl)
        case let .failure(message):
            ConnectionsStatusView(
                systemImage: "exclamationmark.triangle.fill",
                title: "Couldn't load connections",
                message: message,
            ) {
                Task { await viewModel.load() }
            }
            .padding(.top, VikuSpacing.xxl)
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: VikuSpacing.md) {
                    Text("Choose the Vikunja instance you want to sync your tasks with.")
                        .font(VikuFont.footnote)
                        .foregroundStyle(VikuColor.textSecondary)

                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.accounts.enumerated()), id: \.element.id) { index, account in
                            ConnectionRow(
                                account: account,
                                isActive: account.id == viewModel.activeAccountID,
                                serverVersion: viewModel.serverVersions[account.id],
                                onSelect: { Task { await viewModel.setActive(account) } },
                                onEdit: { router.push(.connectionForm(.edit(account))) },
                            )
                            .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)

                            if index < viewModel.accounts.count - 1 {
                                Divider()
                                    .padding(
                                        .leading,
                                        VikuSpacing.md - VikuSpacing.xxs + 40 + VikuSpacing.sm + VikuSpacing.xxs,
                                    )
                            }
                        }
                    }
                    .padding(.vertical, VikuSpacing.xs)
                    .background(
                        VikuColor.Surface.card,
                        in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous),
                    )

                    AddConnectionButton {
                        router.push(.connectionForm(.create))
                    }
                }
                .padding(VikuSpacing.md)
            }
        }
    }
}

/// Matches the design mock's dashed-border "Add Connection" affordance.
private struct AddConnectionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VikuSpacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add Connection")
                    .font(VikuFont.body)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(VikuColor.brandPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, VikuSpacing.md)
            .background {
                // Plain `.circular` corners, not `.continuous`: a continuous
                // (squircle) corner's arc curvature varies along its length,
                // which throws off how evenly a dash pattern lands — it reads
                // as the border getting "cut" right where the straight edge
                // meets the corner. True circular arcs dash evenly.
                RoundedRectangle(cornerRadius: VikuRadius.md, style: .circular)
                    .strokeBorder(
                        VikuColor.textTertiary.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 5]),
                    )
            }
            // A dashed stroke only paints the outline, not the interior, so
            // without this only the icon/text/border pixels themselves are
            // tappable — the transparent middle of the card is not.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ConnectionRow: View {
    let account: InstanceAccount
    let isActive: Bool
    let serverVersion: String?
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            Button(action: onSelect) {
                HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
                    RoundedRectangle(cornerRadius: VikuRadius.sm - VikuSpacing.xs, style: .continuous)
                        .fill(VikuColor.brandPrimary.opacity(isActive ? 0.18 : 0.08))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "server.rack")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(isActive ? VikuColor.brandPrimary : VikuColor.textTertiary)
                        }

                    VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                        HStack(spacing: VikuSpacing.xs + VikuSpacing.xxs) {
                            Text(account.displayName)
                                .font(VikuFont.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)

                            if isActive {
                                Text("ACTIVE")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(VikuColor.brandPrimary)
                                    .padding(.horizontal, VikuSpacing.xs + VikuSpacing.xxs)
                                    .padding(.vertical, VikuSpacing.xxs)
                                    .background(VikuColor.brandPrimary.opacity(0.14), in: Capsule())
                            }
                        }

                        Text(account.baseURL.absoluteString)
                            .font(VikuFont.footnote)
                            .foregroundStyle(VikuColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: account.authMethod.badgeSystemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VikuColor.textTertiary)
                        .accessibilityLabel(account.authMethod.badgeAccessibilityLabel)

                    if let serverVersion {
                        Text(serverVersion.hasPrefix("v") ? serverVersion : "v\(serverVersion)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(VikuColor.textTertiary)
                            .lineLimit(1)
                            .padding(.horizontal, VikuSpacing.xs + VikuSpacing.xxs)
                            .padding(.vertical, VikuSpacing.xxs)
                            .background(VikuColor.Surface.field, in: Capsule())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VikuColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(VikuColor.Surface.field, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(account.displayName)")
        }
        .padding(.vertical, VikuSpacing.sm)
    }
}

/// Shared empty/error state layout for the connections list.
private struct ConnectionsStatusView: View {
    let systemImage: String
    let title: String
    let message: String
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: VikuSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(VikuColor.textTertiary)

            Text(title)
                .font(VikuFont.headline)

            Text(message)
                .font(VikuFont.subheadline)
                .foregroundStyle(VikuColor.textSecondary)
                .multilineTextAlignment(.center)

            if let retryAction {
                Button("Try Again", action: retryAction)
                    .buttonStyle(.bordered)
                    .padding(.top, VikuSpacing.xs)
            }
        }
        .padding(VikuSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
