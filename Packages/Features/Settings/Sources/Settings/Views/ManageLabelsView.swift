import Foundation
import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore
import VikuUI

/// Lists every label on the active account, with a swatch + title per row.
/// Tap a row to rename/recolor it, the toolbar "+" to create one, swipe to
/// delete (behind a confirmation). Both create and edit happen in
/// `LabelEditorSheet`, presented as a `.sheet` rather than a pushed route.
struct ManageLabelsView: View {
    @State private var viewModel: ManageLabelsViewModel
    @State private var editorMode: LabelEditorMode?
    @State private var pendingDeletion: VikunjaCore.Label?

    /// Same rationale as `ConnectionsListView`: takes a factory and builds
    /// the view model inside `@State`'s initializer so SwiftUI keeps one
    /// instance (and its loaded `labels`) across any re-invocation of
    /// `SettingsRootView`'s `navigationDestination` content closure.
    init(makeViewModel: @escaping () -> ManageLabelsViewModel) {
        _viewModel = State(initialValue: makeViewModel())
    }

    var body: some View {
        content
            .background(VikuColor.Surface.page)
            .navigationTitle(Text("Manage Labels", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorMode = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("New Label", bundle: .module))
                }
            }
            .sheet(item: $editorMode) { mode in
                LabelEditorSheet(mode: mode) { title, hexColor in
                    switch mode {
                    case .create:
                        await viewModel.createLabel(title: title, hexColor: hexColor)
                    case let .edit(label):
                        await viewModel.updateLabel(label, title: title, hexColor: hexColor)
                    }
                }
            }
            .confirmationDialog(
                Text("Delete this label?", bundle: .module),
                isPresented: Binding(get: { pendingDeletion != nil }, set: {
                    if !$0 {
                        pendingDeletion = nil
                    }
                }),
                titleVisibility: .visible,
                presenting: pendingDeletion,
            ) { (label: VikunjaCore.Label) in
                Button(role: .destructive) {
                    Task { await viewModel.deleteLabel(label) }
                } label: {
                    Text("Delete \"\(label.title)\"", bundle: .module)
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel", bundle: .module)
                }
            } message: { (_: VikunjaCore.Label) in
                Text("It will be removed from every task it's attached to.", bundle: .module)
            }
            // `.onAppear` rather than `.task`: this view's identity survives a
            // sheet presentation and dismissal, so a one-shot `.task` would
            // never refire.
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
                title: String(localized: "Couldn't load labels", bundle: .module),
                message: message,
            ) {
                Task { await viewModel.load() }
            }
            .padding(.top, VikuSpacing.xxl)
        case .loaded:
            if viewModel.labels.isEmpty {
                VikuStatusView(
                    systemImage: "tag",
                    title: String(localized: "No labels yet", bundle: .module),
                    message: String(
                        localized: "Create a label to organize tasks across every project.",
                        bundle: .module,
                    ),
                )
                .padding(.top, VikuSpacing.xxl)
            } else {
                List {
                    ForEach(viewModel.labels) { label in
                        Button {
                            editorMode = .edit(label)
                        } label: {
                            LabelRow(label: label)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            // `role: .destructive` alone renders blue here, not
                            // red: the tab bar's `.tint(VikuColor.brandPrimary)`
                            // leaks into the swipe action, so tint it explicitly.
                            Button(
                                String(localized: "Delete", bundle: .module),
                                systemImage: "trash",
                                role: .destructive,
                            ) {
                                pendingDeletion = label
                            }
                            .tint(VikuColor.Semantic.danger)
                        }
                    }
                }
                .labelsListStyle()
            }
        }
    }
}

private struct LabelRow: View {
    let label: VikunjaCore.Label

    private var color: Color {
        Color(vikuMutedHex: label.hexColor) ?? VikuColor.textSecondary
    }

    var body: some View {
        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(verbatim: label.title)
                .font(VikuFont.body)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VikuColor.textTertiary)
        }
        .padding(.vertical, VikuSpacing.xxs)
        .contentShape(Rectangle())
    }
}

private extension View {
    @ViewBuilder
    func labelsListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        self
        #endif
    }
}
