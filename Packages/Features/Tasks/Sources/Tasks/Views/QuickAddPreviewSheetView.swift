#if DEBUG
import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

/// The new layout uses the same editing and offline creation flow as the
/// original sheet. The debug switch keeps both available during migration.
public struct QuickAddPreviewSheetView: View {
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
    @State private var savingPresentation = QuickAddSavingPresentation()
    @State private var presentationOrigin = ContinuousClock.now
    @State private var saveTask: Task<Void, Never>?
    @State private var saveSucceeded = false
    @State private var titleFieldHeight: CGFloat = 25

    public init(viewModel: QuickAddTaskViewModel) {
        self.viewModel = viewModel
    }

    private var isSubmitting: Bool {
        viewModel.isSaving || savingPresentation.isVisible || saveSucceeded || saveTask != nil
    }

    private var detentHeight: CGFloat {
        var height: CGFloat = 180 + max(0, titleFieldHeight - 25)
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
        return height
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VikuSpacing.lg) {
                VStack(alignment: .leading, spacing: VikuSpacing.sm) {
                    titleField
                        .disabled(isSubmitting)
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
                        .disabled(isSubmitting)
                    }
                }
                if let message = viewModel.saveErrorMessage {
                    SaveErrorBanner(message: message)
                }
                if viewModel.isDatePreviewEnabled {
                    QuickAddDatePreview(result: viewModel.datePreview, timeZone: viewModel.dateParsingContext.timeZone)
                }
            }
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, VikuSpacing.lg)
            .padding(.bottom, VikuSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.pageBackground)
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VikuRadius.lg + VikuSpacing.sm)
        .interactiveDismissDisabled(isSubmitting)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86), value: titleFieldHeight)
        .sheet(isPresented: $isShowingProjectPicker) {
            ProjectPickerSheet(
                title: String(localized: "Choose Project", bundle: .module),
                projects: viewModel.projects,
                selectedProjectID: viewModel.selectedProjectID,
            ) { viewModel.pickProject($0) }
        }
        .sheet(isPresented: $isShowingDueDatePicker, onDismiss: presentDueDateRemovalIfNeeded) {
            DueDatePickerSheet(initialDate: viewModel.dueDate) { viewModel.pickDueDate($0) }
                .environment(\.timeZone, viewModel.dateParsingContext.timeZone)
        }
        .sheet(isPresented: $isShowingReminderPicker) {
            ReminderPickerSheet(
                initialReminder: viewModel.reminder,
                dueDate: viewModel.dueDate,
                onSave: { viewModel.setReminder($0) },
                onDelete: viewModel.reminder.map { _ in { viewModel.setReminder(nil) } },
            )
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
        .task(id: viewModel.isSaving) { await updateSavingPresentation() }
        .onChange(of: saveSucceeded) { _, _ in dismissAfterSaveIfReady() }
        .onDisappear { saveTask?.cancel() }
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

    private var suggestions: some View {
        // TODO: Gate on Quick Add Magic and use examples for its selected dialect.
        // Deferred deliberately while migrating the existing creation flow.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VikuSpacing.xs) {
                Text("Try", bundle: .module)
                suggestionPill(String(localized: "tomorrow", bundle: .module))
                suggestionPill(String(localized: "#work", bundle: .module))
                suggestionPill(String(localized: "!high", bundle: .module))
                suggestionPill(String(localized: "@design", bundle: .module))
            }
            .font(VikuFont.footnote)
            .foregroundStyle(palette.textTertiary)
        }
        .opacity(viewModel.input.isEmpty ? 1 : 0)
        .accessibilityHidden(!viewModel.input.isEmpty)
    }

    private var actions: some View {
        HStack(spacing: VikuSpacing.md) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: VikuSpacing.sm) {
                    projectButton
                    dueDateButton
                    priorityMenu
                    reminderButton
                    labelsButton
                }
            }
            .disabled(isSubmitting || viewModel.isConfirmingDueDateRemoval)

            Button {
                guard !isSubmitting, viewModel.canSave else { return }
                saveTask = Task {
                    saveSucceeded = await viewModel.save() != nil
                    saveTask = nil
                    dismissAfterSaveIfReady()
                }
            } label: {
                ZStack {
                    Image(systemName: "arrow.up")
                        .opacity(savingPresentation.isVisible ? 0 : 1)
                    if savingPresentation.isVisible {
                        ProgressView().tint(palette.brandForeground)
                    }
                }
                .font(VikuFont.headline)
                .foregroundStyle(palette.brandForeground)
                .frame(width: VikuSpacing.xxl, height: VikuSpacing.xxl)
                .background(palette.brand, in: Circle())
                .opacity(viewModel.canSave || isSubmitting ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSave || isSubmitting)
            .accessibilityLabel(Text("Create Task", bundle: .module))
        }
    }

    private var projectButton: some View {
        Button { isShowingProjectPicker = true } label: {
            if let project = viewModel.selectedProject ?? viewModel.displayProject {
                HStack(spacing: VikuSpacing.xs) {
                    Image(systemName: "folder")
                        .font(VikuFont.body)
                    Text(verbatim: project.title)
                        .font(VikuFont.footnote)
                        .fontWeight(.bold)
                        .lineLimit(1)
                }
                .foregroundStyle(Color(vikuHex: project.hexColor) ?? palette.brand)
                .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xs)
                .frame(height: VikuSpacing.xl + VikuSpacing.xs)
                .background((Color(vikuHex: project.hexColor) ?? palette.brand).opacity(0.1), in: Capsule())
            } else {
                shortcutIcon("folder", label: String(localized: "Project", bundle: .module))
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.projects.isEmpty)
        .accessibilityLabel(Text("Choose Project", bundle: .module))
        .accessibilityValue(Text(verbatim: (viewModel.selectedProject ?? viewModel.displayProject)?.title ?? ""))
    }

    private var dueDateButton: some View {
        Button { isShowingDueDatePicker = true } label: {
            if let dueDate = viewModel.dueDate {
                HStack(spacing: VikuSpacing.xs) {
                    Image(systemName: "calendar")
                        .font(VikuFont.body)
                    Text(verbatim: DueDateFormatter.compact(dueDate))
                        .font(VikuFont.footnote)
                        .fontWeight(.bold)
                        .lineLimit(1)
                }
                .foregroundStyle(palette.brand)
                .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xs)
                .frame(height: VikuSpacing.xl + VikuSpacing.xs)
                .background(palette.brand.opacity(0.1), in: Capsule())
            } else {
                shortcutIcon("calendar", label: String(localized: "Due Date", bundle: .module))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Due Date", bundle: .module))
        .accessibilityValue(dueDateAccessibilityValue)
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

    private var reminderButton: some View {
        Button { isShowingReminderPicker = true } label: {
            if let reminder = viewModel.reminder {
                HStack(spacing: VikuSpacing.xs) {
                    Image(systemName: "bell")
                        .font(VikuFont.body)
                    Text(verbatim: ReminderFormatter.compactLabel(for: reminder))
                        .font(VikuFont.footnote)
                        .fontWeight(.bold)
                        .lineLimit(1)
                }
                .foregroundStyle(palette.brand)
                .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xs)
                .frame(height: VikuSpacing.xl + VikuSpacing.xs)
                .background(palette.brand.opacity(0.1), in: Capsule())
            } else {
                shortcutIcon("bell", label: String(localized: "Reminders", bundle: .module))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Reminders", bundle: .module))
        .accessibilityValue(Text(verbatim: viewModel.reminder.map {
            [ReminderFormatter.label(for: $0), ReminderFormatter.preciseLabel(for: $0)].joined(separator: ", ")
        } ?? ""))
    }

    private func presentDueDateRemovalIfNeeded() {
        // A date picker dismisses after requesting removal. Wait for its
        // onDismiss before presenting a second modal on the parent sheet.
        if viewModel.isConfirmingDueDateRemoval {
            isShowingDueDateRemovalConfirmation = true
        }
    }

    private var labelsButton: some View {
        Button { isShowingLabelPicker = true } label: {
            if let first = viewModel.selectedLabels.first {
                HStack(spacing: VikuSpacing.xs) {
                    Image(systemName: "tag")
                        .font(VikuFont.body)
                    Text(verbatim: first.title)
                        .lineLimit(1)
                    if viewModel.selectedLabels.count > 1 {
                        Text("+\(viewModel.selectedLabels.count - 1)", bundle: .module)
                    }
                }
                .font(VikuFont.footnote)
                .fontWeight(.bold)
                .foregroundStyle(Color(vikuMutedHex: first.hexColor) ?? palette.brand)
                .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xs)
                .frame(height: VikuSpacing.xl + VikuSpacing.xs)
                .background((Color(vikuMutedHex: first.hexColor) ?? palette.brand).opacity(0.1), in: Capsule())
            } else {
                shortcutIcon("tag", label: String(localized: "Labels", bundle: .module))
            }
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canPickLabels)
        .accessibilityLabel(Text("Labels", bundle: .module))
        .accessibilityValue(Text(verbatim: viewModel.selectedLabels.map(\.title).joined(separator: ", ")))
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
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(VikunjaTask.Priority.selectable, id: \.self) { priority in
                Button {
                    viewModel.pickPriority(priority)
                } label: {
                    if viewModel.priority == priority {
                        Label { Text(verbatim: priority.localizedMenuLabel) } icon: { Image(systemName: "checkmark") }
                    } else {
                        Text(verbatim: priority.localizedMenuLabel)
                    }
                }
            }
        } label: {
            if viewModel.priority != .unset {
                HStack(spacing: VikuSpacing.xs) {
                    Image(systemName: "flag")
                        .font(VikuFont.body)
                    Text(verbatim: viewModel.priority.localizedMenuLabel)
                        .font(VikuFont.footnote)
                        .fontWeight(.bold)
                }
                .foregroundStyle(VikuColor.Priority.dot(for: viewModel.priority) ?? palette.brand)
                .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xs)
                .frame(height: VikuSpacing.xl + VikuSpacing.xs)
                .background(
                    (VikuColor.Priority.dot(for: viewModel.priority) ?? palette.brand).opacity(0.1),
                    in: Capsule(),
                )
            } else {
                shortcutIcon("flag", label: String(localized: "Priority", bundle: .module))
            }
        }
        .accessibilityLabel(Text("Priority", bundle: .module))
        .accessibilityValue(Text(verbatim: viewModel.priority.localizedMenuLabel))
    }

    private func suggestionPill(_ text: String) -> some View {
        Text(verbatim: text)
            .monospaced()
            .padding(.horizontal, VikuSpacing.sm)
            .padding(.vertical, VikuSpacing.xs)
            .background(palette.fieldBackground, in: Capsule())
    }

    private func shortcutIcon(_ systemName: String, label: String) -> some View {
        Image(systemName: systemName)
            .font(VikuFont.body)
            .foregroundStyle(palette.textSecondary)
            .frame(width: VikuSpacing.xl + VikuSpacing.xs, height: VikuSpacing.xl + VikuSpacing.xs)
            .background(palette.fieldBackground, in: Circle())
            .accessibilityLabel(Text(verbatim: label))
    }

    private func updateSavingPresentation() async {
        let clock = ContinuousClock()
        while !Task.isCancelled {
            let delay = savingPresentation.update(
                isSaving: viewModel.isSaving,
                at: presentationOrigin.duration(to: clock.now),
            )
            guard let delay else {
                dismissAfterSaveIfReady()
                return
            }
            do { try await clock.sleep(for: delay) } catch { return }
        }
    }

    private func dismissAfterSaveIfReady() {
        if saveSucceeded, !savingPresentation.isVisible {
            dismiss()
        }
    }
}
#endif
