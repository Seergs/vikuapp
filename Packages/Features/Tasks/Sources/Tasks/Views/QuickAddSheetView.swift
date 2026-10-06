import Foundation
import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The quick-add sheet opened from the tab bar's floating action button:
/// title + project + priority only, matching the design mockup's
/// `AddTaskSheet` (no due date/labels/assignee yet — see
/// `QuickAddTaskViewModel`'s doc comment). A compact bottom sheet: a
/// `NavigationStack` with an inline title and `Cancel`/`Save` in the toolbar
/// (the system pins that bar to the top of the sheet, so it can't drift when
/// the keyboard opens and nudges the sheet to its taller detent), switching
/// between two fixed `presentationDetents` heights (see `compactHeight`/
/// `expandedHeight`) so it only grows when the error banner needs the room.
/// Content is anchored to the top rather than centered, so the extra space at
/// the taller detent pools below the fields instead of above the title.
/// Presented as a plain `.sheet` by whichever screen owns the FAB.
public struct QuickAddSheetView: View {
    @Bindable var viewModel: QuickAddTaskViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingProjectPicker = false
    @FocusState private var isTitleFocused: Bool

    /// A single detent sized to the current content, not a two-detent set:
    /// when a sheet offers more than one detent and the keyboard appears,
    /// iOS jumps it to the *largest* one — which left a big gap between the
    /// priority chips and the keyboard. One height, grown only when the
    /// error banner needs the room, keeps the sheet exactly as tall as its
    /// content.
    private var detentHeight: CGFloat {
        let base = viewModel.saveErrorMessage != nil ? Self.expandedHeight : Self.compactHeight
        return viewModel.shortcutChips.isEmpty ? base : base + Self.shortcutChipsHeight
    }

    public init(viewModel: QuickAddTaskViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: VikuSpacing.md) {
                titleField
                    .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
                    .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
                    .background(
                        VikuColor.Surface.field,
                        in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
                    )

                QuickAddShortcutChips(input: viewModel.input, tokens: viewModel.shortcutChips)

                projectSection

                PriorityChipRow(selection: Binding(
                    get: { viewModel.priority },
                    set: { viewModel.pickPriority($0) },
                ))

                if let message = viewModel.saveErrorMessage {
                    SaveErrorBanner(message: message)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, VikuSpacing.md)
            // Anchored to the top: when the keyboard nudges the sheet up to
            // its taller detent, the slack falls below the priority chips
            // instead of being split above and below a vertically-centered
            // block (which pushed the title away from the toolbar).
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // A spring rather than `.easeInOut`: closer to the curve the
            // system itself uses to animate a sheet's own detent resize, so
            // our content's own transition doesn't visibly race against it.
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.saveErrorMessage)
            .navigationTitle(Text("New Task", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button(String(localized: "Save", bundle: .module)) {
                            Task {
                                if await viewModel.save() != nil {
                                    dismiss()
                                }
                            }
                        }
                        .fontWeight(.bold)
                        .disabled(!viewModel.canSave)
                    }
                }
            }
        }
        .presentationDetents([.height(detentHeight)])
        .presentationCornerRadius(VikuRadius.lg + VikuSpacing.sm)
        .sheet(isPresented: $isShowingProjectPicker) {
            ProjectPickerSheet(
                title: String(localized: "Choose Project", bundle: .module),
                projects: viewModel.projects,
                selectedProjectID: viewModel.selectedProjectID,
            ) { project in
                viewModel.pickProject(project)
            }
        }
        .task {
            isTitleFocused = true
            await viewModel.load()
        }
    }

    /// On iOS the title is a `UITextView` so the shortcuts can be colored
    /// as the user types. Elsewhere it stays a plain `TextField`.
    @ViewBuilder
    private var titleField: some View {
        #if os(iOS)
        ZStack(alignment: .leading) {
            ShortcutTitleField(
                text: $viewModel.input,
                tokens: viewModel.parsed.tokens,
                focusOnAppear: true,
            )
            if viewModel.input.isEmpty {
                Text("Task title", bundle: .module)
                    .font(VikuFont.body)
                    .foregroundStyle(VikuColor.textTertiary)
                    .allowsHitTesting(false)
            }
        }
        #else
        TextField(String(localized: "Task title", bundle: .module), text: $viewModel.input)
            .font(VikuFont.body)
            .focused($isTitleFocused)
            .submitLabel(.done)
        #endif
    }

    @ViewBuilder
    private var projectSection: some View {
        switch viewModel.loadState {
        case let .failure(message):
            Text(verbatim: message)
                .font(VikuFont.footnote)
                .foregroundStyle(VikuColor.textSecondary)
        case .loading, .idle:
            ProgressView()
        case .loaded:
            VStack(alignment: .leading, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
                FieldLabel(String(localized: "Project", bundle: .module))
                ProjectField(project: viewModel.selectedProject) {
                    isShowingProjectPicker = true
                }
            }
        }
    }

    /// Fixed, hand-measured heights rather than a live content measurement:
    /// a `.sheet` proposes its current detent's height back to its own
    /// content as a ceiling, so `GeometryReader`/`onGeometryChange`/
    /// `.fixedSize` just report that already-capped size back — a feedback
    /// loop that can never settle. `compactHeight` fits the title/project/
    /// priority rows above the keyboard with no slack; `expandedHeight` adds
    /// room for the error banner.
    private static let compactHeight: CGFloat = 300
    private static let expandedHeight: CGFloat = 366
    /// Room for the shortcut chip row, added only while a shortcut needs a chip.
    private static let shortcutChipsHeight: CGFloat = 36
}
