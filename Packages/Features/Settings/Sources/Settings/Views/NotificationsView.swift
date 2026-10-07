import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

#if os(iOS)
import UIKit
#endif

/// The push-notification opt-in screen: a master toggle gated behind
/// `NotificationsConsentSheet`, and — once enabled — a user-level toggle
/// plus one toggle per project. See `NotificationsViewModel` for the sync
/// that keeps Vikunja's webhooks matching whatever's shown here.
struct NotificationsView: View {
    @State private var viewModel: NotificationsViewModel
    @State private var isShowingConsent = false
    @Environment(\.openURL) private var openURL

    /// Same rationale as `ManageLabelsView`: takes a factory and builds the
    /// view model inside `@State`'s initializer so SwiftUI keeps one
    /// instance across any re-invocation of the destination closure.
    init(makeViewModel: @escaping () -> NotificationsViewModel) {
        _viewModel = State(initialValue: makeViewModel())
    }

    var body: some View {
        content
            .navigationTitle(Text("Notifications", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $isShowingConsent) {
                NotificationsConsentSheet {
                    Task { await viewModel.confirmEnable() }
                }
            }
            .onAppear { Task { await viewModel.load() } }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, VikuSpacing.xxl)
        case let .failure(message):
            VikuStatusView(
                systemImage: "exclamationmark.triangle.fill",
                title: String(localized: "Couldn't load projects", bundle: .module),
                message: message,
            ) {
                Task { await viewModel.load() }
            }
            .padding(.top, VikuSpacing.xxl)
        case .loaded:
            List {
                enableSection
                if viewModel.settings.isEnabled {
                    userLevelSection
                    projectsSection
                }
            }
            .notificationsListStyle()
        }
    }

    private var enableSection: some View {
        Section {
            Toggle(isOn: enabledBinding) {
                VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                    Text("Push Notifications", bundle: .module)
                    Text("Requires Viku Relay, a service hosted by the Viku team.", bundle: .module)
                        .font(VikuFont.footnote)
                        .foregroundStyle(VikuColor.textSecondary)
                    Text("Vikunja does not send push to iOS directly.", bundle: .module)
                        .font(VikuFont.footnote)
                        .foregroundStyle(VikuColor.textSecondary)
                }
            }
            .disabled(viewModel.isSyncing)

            if viewModel.isSyncing {
                syncingRow
            }
        } footer: {
            if viewModel.isPermissionDenied {
                deniedBanner
            }
        }
    }

    /// Shown while `confirmEnable()`/`disable()`/a toggle's sync is in
    /// flight — the OS permission prompt and relay round trip can take a
    /// few seconds on a real device, so without this the screen looks like
    /// nothing happened after tapping "Agree & Continue".
    private var syncingRow: some View {
        HStack(spacing: VikuSpacing.sm) {
            ProgressView()
            Text("Setting up notifications…", bundle: .module)
                .font(VikuFont.footnote)
                .foregroundStyle(VikuColor.textSecondary)
        }
    }

    private var deniedBanner: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            Text("Notifications are turned off for Viku in iOS Settings.", bundle: .module)
                .foregroundStyle(VikuColor.Semantic.dangerText)
            Button(String(localized: "Open Settings", bundle: .module)) {
                openSystemSettings()
            }
        }
    }

    private var userLevelSection: some View {
        Section {
            Toggle(String(localized: "Reminders & Overdue Tasks", bundle: .module), isOn: userLevelBinding)
                .disabled(viewModel.isSyncing)
        } header: {
            Text("User Notifications", bundle: .module)
        }
    }

    @ViewBuilder
    private var projectsSection: some View {
        if viewModel.projects.isEmpty {
            EmptyView()
        } else {
            Section {
                ForEach(viewModel.projects) { project in
                    Toggle(project.title, isOn: projectBinding(project))
                        .disabled(viewModel.isSyncing)
                }
            } header: {
                Text("Project Notifications", bundle: .module)
            } footer: {
                Text("Task created, updated, assigned, or commented on.", bundle: .module)
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.isEnabled },
            set: { newValue in
                if newValue {
                    isShowingConsent = true
                } else {
                    Task { await viewModel.disable() }
                }
            },
        )
    }

    private var userLevelBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.userLevelEnabled },
            set: { newValue in Task { await viewModel.setUserLevelEnabled(newValue) } },
        )
    }

    private func projectBinding(_ project: Project) -> Binding<Bool> {
        Binding(
            get: { viewModel.settings.enabledProjectIDs.contains(project.id) },
            set: { newValue in Task { await viewModel.setProject(project, isEnabled: newValue) } },
        )
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }
}

private extension View {
    @ViewBuilder
    func notificationsListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        self
        #endif
    }
}
