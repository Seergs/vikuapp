import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

/// The quick-add sheet shared by the floating button and external entry points.
/// Picker selections edit the draft; creating the task uses the offline repository.
public struct QuickAddSheetView: View {
    @Bindable private var viewModel: QuickAddTaskViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.vikuPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isShowingProjectPicker = false
    @State private var isShowingDueDatePicker = false
    @State private var isShowingLabelPicker = false
    @State private var isShowingReminderPicker = false
    @State private var isShowingDueDateRemovalConfirmation = false
    @State private var submission = TaskComposerSubmission()
    @State private var titleFieldHeight: CGFloat = 25
    @State private var suggestionRowHeight: CGFloat = VikuSpacing.lg
    @State private var relationBannerHeight: CGFloat = 0

    public init(viewModel: QuickAddTaskViewModel) {
        self.viewModel = viewModel
    }

    private var detentHeight: CGFloat {
        var height: CGFloat = 180 + max(0, titleFieldHeight - 25)
        if viewModel.suggestions.isEmpty {
            height -= suggestionRowHeight + VikuSpacing.sm
        }
        if viewModel.saveErrorMessage != nil {
            height += 66
        }
        if case .failure = viewModel.loadState {
            height += 66
        }
        if QuickAddShortcutChips.hasChip(in: viewModel.shortcutChips) {
            height += QuickAddShortcutChips.height + VikuSpacing.lg
        }
        if viewModel.isDatePreviewEnabled {
            height += QuickAddDatePreview.height + VikuSpacing.lg
        }
        if viewModel.relationContext != nil {
            height += relationBannerHeight + VikuSpacing.lg
        }
        return height
    }

    public var body: some View {
        TaskComposerSheet(detentHeight: detentHeight, submission: submission) {
            if let relationContext = viewModel.relationContext {
                RelationContextBanner(relationContext: relationContext)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { relationBannerHeight = $0 }
            }

            VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                titleField
                    .accessibilityIdentifier("quickAdd.title")
                    .disabled(submission.isSubmitting)
                suggestions
            }

            QuickAddShortcutChips(input: viewModel.input, tokens: viewModel.shortcutChips)
            actions

            if case let .failure(message) = viewModel.loadState {
                VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                    Text(verbatim: message)
                        .font(VikuFont.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Button(String(localized: "Retry", bundle: .module)) {
                        Task { await viewModel.load() }
                    }
                    .disabled(submission.isSubmitting)
                }
            }
            if let message = viewModel.saveErrorMessage {
                SaveErrorBanner(message: message)
            }
            if viewModel.isDatePreviewEnabled {
                QuickAddDatePreview(result: viewModel.datePreview, timeZone: viewModel.dateParsingContext.timeZone)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86), value: titleFieldHeight)
        .sheet(isPresented: $isShowingProjectPicker) {
            ProjectPickerSheet(
                title: String(localized: "Choose Project", bundle: .module),
                projects: viewModel.projects,
                selectedProjectID: viewModel.selectedProjectID,
            ) { viewModel.pickProject($0) }
                .vikuNativeSheetAppearance()
        }
        .sheet(isPresented: $isShowingDueDatePicker, onDismiss: presentDueDateRemovalIfNeeded) {
            DueDatePickerSheet(initialDate: viewModel.dueDate) { viewModel.pickDueDate($0) }
                .vikuNativeSheetAppearance()
                .environment(\.timeZone, viewModel.dateParsingContext.timeZone)
        }
        .sheet(isPresented: $isShowingReminderPicker) {
            ReminderPickerSheet(
                initialReminder: viewModel.reminder,
                dueDate: viewModel.dueDate,
                onSave: { viewModel.setReminder($0) },
                onDelete: viewModel.reminder.map { _ in { viewModel.setReminder(nil) } },
            )
            .vikuNativeSheetAppearance()
            .environment(\.timeZone, viewModel.dateParsingContext.timeZone)
        }
        .sheet(isPresented: $isShowingLabelPicker) { labelsPicker }
        .alert(
            String(localized: "Remove due date and reminder?", bundle: .module),
            isPresented: $isShowingDueDateRemovalConfirmation,
        ) {
            Button(String(localized: "Remove Both", bundle: .module), role: .destructive) {
                viewModel.confirmDueDateRemoval()
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {
                viewModel.cancelDueDateRemoval()
            }
        } message: {
            Text("This reminder depends on the due date. Removing the due date will remove both.", bundle: .module)
        }
        .onChange(of: viewModel.isConfirmingDueDateRemoval) { _, isPending in
            if isPending, !isShowingDueDatePicker {
                presentDueDateRemovalIfNeeded()
            }
        }
        .task {
            isFocused = true
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var titleField: some View {
        #if os(iOS)
        ZStack(alignment: .topLeading) {
            ShortcutTitleField(
                text: $viewModel.input,
                highlights: viewModel.titleHighlights,
                focusOnAppear: true,
                textStyle: .title3,
            )
            if viewModel.input.isEmpty {
                Text("What needs to be done?", bundle: .module)
                    .font(VikuFont.title3)
                    .foregroundStyle(palette.textTertiary)
                    .allowsHitTesting(false)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { titleFieldHeight = $0 }
        .accessibilityLabel(Text("What needs to be done?", bundle: .module))
        #else
        TextField(String(localized: "What needs to be done?", bundle: .module), text: $viewModel.input, axis: .vertical)
            .textFieldStyle(.plain)
            .font(VikuFont.title3)
            .foregroundStyle(palette.textPrimary)
            .lineLimit(1 ... 3)
            .focused($isFocused)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { titleFieldHeight = $0 }
        #endif
    }

    @ViewBuilder
    private var suggestions: some View {
        if !viewModel.suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: VikuSpacing.xs) {
                    Text("Try", bundle: .module)
                    ForEach(viewModel.suggestions, id: \.self) { suggestion in
                        suggestionPill(suggestion)
                    }
                }
                .font(VikuFont.footnote)
                .foregroundStyle(palette.textTertiary)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { suggestionRowHeight = $0 }
        }
    }

    private var actions: some View {
        TaskComposerActions(
            submission: submission,
            canSubmit: viewModel.canSave,
            submitIcon: "arrow.up",
            submitLabel: Text("Create Task", bundle: .module),
            submitIdentifier: "quickAdd.create",
            submit: {
                guard viewModel.canSave else { return }
                submission.submit(operation: { await viewModel.save() }, onSuccess: { _ in dismiss() })
            },
            fields: {
                Group {
                    TaskComposerProjectButton(project: viewModel.selectedProject ?? viewModel.displayProject) {
                        isShowingProjectPicker = true
                    }
                    .disabled(viewModel.projects.isEmpty)
                    .accessibilityIdentifier("quickAdd.project")

                    dueDateButton
                    TaskComposerPriorityMenu(priority: viewModel.priority, onSelect: viewModel.pickPriority)
                    reminderButton
                    labelsButton
                }
                .disabled(viewModel.isConfirmingDueDateRemoval)
            },
        )
    }

    @ViewBuilder
    private var dueDateButton: some View {
        if let dueDate = viewModel.dueDate {
            TaskComposerRemovableChip(
                color: palette.brand,
                removeLabel: String(localized: "Remove Due Date", bundle: .module),
                remove: { viewModel.pickDueDate(nil) },
                content: {
                    Button { isShowingDueDatePicker = true } label: {
                        selectionChipLabel("calendar", title: DueDateFormatter.compact(dueDate))
                    }
                    .accessibilityLabel(Text("Due Date", bundle: .module))
                    .accessibilityIdentifier("quickAdd.dueDate")
                    .accessibilityValue(dueDateAccessibilityValue)
                },
            )
        } else {
            Button { isShowingDueDatePicker = true } label: {
                TaskComposerShortcutIcon("calendar")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Due Date", bundle: .module))
            .accessibilityIdentifier("quickAdd.dueDate")
        }
    }

    private var dueDateAccessibilityValue: Text {
        if let date = viewModel.dueDate {
            Text(date, format: Date.FormatStyle(
                date: .abbreviated,
                time: .shortened,
                timeZone: viewModel.dateParsingContext.timeZone,
            ))
        } else {
            Text("None", bundle: .module)
        }
    }

    @ViewBuilder
    private var reminderButton: some View {
        if let reminder = viewModel.reminder {
            TaskComposerRemovableChip(
                color: palette.brand,
                removeLabel: String(localized: "Remove Reminder", bundle: .module),
                remove: { viewModel.setReminder(nil) },
                content: {
                    Button { isShowingReminderPicker = true } label: {
                        selectionChipLabel("bell", title: ReminderFormatter.compactLabel(for: reminder))
                    }
                    .accessibilityLabel(Text("Reminders", bundle: .module))
                    .accessibilityValue(Text(verbatim: [
                        ReminderFormatter.label(for: reminder), ReminderFormatter.preciseLabel(for: reminder),
                    ].joined(separator: ", ")))
                },
            )
        } else {
            Button { isShowingReminderPicker = true } label: {
                TaskComposerShortcutIcon("bell")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Reminders", bundle: .module))
        }
    }

    private func presentDueDateRemovalIfNeeded() {
        // A date picker dismisses after requesting removal. Wait for its
        // onDismiss before presenting a second modal on the parent sheet.
        if viewModel.isConfirmingDueDateRemoval {
            isShowingDueDateRemovalConfirmation = true
        }
    }

    @ViewBuilder
    private var labelsButton: some View {
        if let first = viewModel.selectedLabels.first {
            TaskComposerRemovableChip(
                color: Color(vikuMutedHex: first.hexColor) ?? palette.brand,
                removeLabel: String(localized: "Remove Labels", bundle: .module),
                remove: { viewModel.clearLabels() },
                content: {
                    Button { isShowingLabelPicker = true } label: {
                        selectionChipLabel(
                            "tag", title: first.title,
                            additionalCount: viewModel.selectedLabels.count - 1,
                        )
                    }
                    .accessibilityLabel(Text("Labels", bundle: .module))
                    .accessibilityValue(Text(verbatim: viewModel.selectedLabels.map(\.title).joined(separator: ", ")))
                },
            )
        } else {
            Button { isShowingLabelPicker = true } label: {
                TaskComposerShortcutIcon("tag")
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canPickLabels)
            .accessibilityLabel(Text("Labels", bundle: .module))
        }
    }

    private var labelsPicker: some View {
        LabelPickerSheet(
            taskLabels: viewModel.selectedLabels,
            allLabels: viewModel.labelCatalog.labels,
            labelAliases: viewModel.labelCatalog.aliases,
            onLoad: { await viewModel.loadLabels() },
            onToggle: { viewModel.toggleLabel($0) },
        )
        .safeAreaInset(edge: .bottom) {
            if viewModel.labelsLoadState != .loaded || viewModel.labelCatalog.labels.isEmpty {
                VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                    switch viewModel.labelsLoadState {
                    case let .failure(message):
                        Text(verbatim: message)
                        Button(String(localized: "Retry", bundle: .module)) {
                            Task { await viewModel.loadLabels() }
                        }
                    case .idle, .loading:
                        Text("Loading labels...", bundle: .module)
                    case .loaded:
                        Text("No labels available", bundle: .module)
                    }
                }
                .font(VikuFont.footnote)
                .foregroundStyle(palette.textSecondary)
                .padding(VikuSpacing.md)
            }
        }
        .vikuNativeSheetAppearance()
    }

    private func selectionChipLabel(_ icon: String, title: String, additionalCount: Int = 0) -> some View {
        HStack(spacing: VikuSpacing.xs) {
            Image(systemName: icon)
                .font(VikuFont.title3)
            Text(verbatim: title)
                .lineLimit(1)
            if additionalCount > 0 {
                Text("+\(additionalCount)", bundle: .module)
            }
        }
        .font(VikuFont.footnote)
        .fontWeight(.bold)
        .padding(.leading, VikuSpacing.sm + VikuSpacing.xs)
        .frame(minHeight: VikuSpacing.xxl - VikuSpacing.xs)
        .contentShape(Rectangle())
    }

    private func suggestionPill(_ text: String) -> some View {
        Text(verbatim: text)
            .monospaced()
            .padding(.horizontal, VikuSpacing.sm)
            .padding(.vertical, VikuSpacing.xs)
            .background(palette.fieldBackground, in: Capsule())
    }
}

/// Shown above the title field when this sheet was opened to create the
/// other side of a relation inline (`TaskDetailViewModel.makeQuickAddTaskViewModel`),
/// so the task being created never looks like a plain, unrelated quick-add.
private struct RelationContextBanner: View {
    let relationContext: QuickAddRelationContext

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            Image(systemName: "link")
                .font(VikuFont.footnote.weight(.semibold))
                .foregroundStyle(palette.brand)
            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                Text(verbatim: relationContext.bannerText)
                    .font(VikuFont.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.brand)
                Text("Will be linked automatically on save", bundle: .module)
                    .font(VikuFont.caption)
                    .foregroundStyle(palette.brand.opacity(0.8))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.brand.opacity(0.12),
            in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
        )
    }
}
