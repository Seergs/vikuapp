import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore
import VikuUI
#if os(iOS)
import UIKit
#endif

/// A single task's detail screen: completion, due date, priority, labels,
/// subtasks, and dependencies. Pushed as a leaf screen inside whichever
/// feature's `NavigationStack` opened it (Projects, today) — this package
/// owns no `NavigationStack`/`Router` of its own.
///
/// The screen is a shell: each section renders through its own view in
/// `TaskDetail/Sections/`, each sheet through `TaskDetail/Sheets/`, and the
/// shared building blocks live in `TaskDetail/TaskDetailComponents.swift`.
public struct TaskDetailView: View {
    @Bindable var viewModel: TaskDetailViewModel
    /// The hosting stack's router. A tapped relation, the project pill, and a
    /// just-created duplicate all navigate by pushing an `AppRoute` onto it,
    /// resolved by the app target's `.appDestinations(...)` - this package
    /// never imports `Projects` or knows what screen a route resolves to.
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDueDatePicker = false
    @State private var reminderEditTarget: ReminderEditTarget?
    @State private var isShowingLabelPicker = false
    @State private var isShowingMovePicker = false
    @State private var isShowingDuplicateSheet = false
    @State private var isShowingDeleteConfirmation = false
    @State private var commentPendingDeletion: TaskComment?
    @State private var commentPendingEdit: TaskComment?
    @State private var relationEditStep: RelationEditStep?
    @State private var isShowingFileImporter = false
    @State private var attachmentPendingDeletion: TaskAttachment?
    @State private var attachmentPreviewURL: URL?
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @State private var isEditingDescription = false
    @State private var descriptionDraft = ""
    @FocusState private var focusedField: EditableField?
    // The comment composer sits at the very bottom of the scroll content, with
    // barely any padding below it. SwiftUI's automatic keyboard avoidance only
    // shrinks the visible viewport - it doesn't add scrollable room - so once
    // the composer is the last thing on screen there's nowhere left to scroll
    // it above the keyboard. Padding the content by the live keyboard height
    // gives the scroll view that missing room.
    @State private var keyboardHeight: CGFloat = 0
    // Threaded down into `CommentComposer`'s `TextField` so the screen knows
    // to scroll it into view once the keyboard has room to reveal it (see the
    // `keyboardHeight` change handler below) rather than relying solely on
    // iOS's own best-effort scroll, which fires before `keyboardHeight` (and
    // the extra bottom padding it drives) has actually been applied.
    @FocusState private var isCommentComposerFocused: Bool
    private static let commentsAnchorID = "comments-section"

    private enum EditableField: Hashable {
        case title
        case description
    }

    /// `nil` index means "creating a new reminder"; `reminder` is only used
    /// to prefill the sheet when editing an existing one.
    private struct ReminderEditTarget: Identifiable {
        let id = UUID()
        let index: Int?
        let reminder: TaskReminder?
    }

    public init(viewModel: TaskDetailViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch viewModel.loadState {
                    case let .failure(message):
                        VikuStatusView(
                            systemImage: "exclamationmark.triangle.fill",
                            title: String(localized: "Couldn't load this task", bundle: .module),
                            message: message,
                            fillsHeight: false,
                        ) {
                            Task { await viewModel.load() }
                        }
                        .padding(.top, VikuSpacing.xxl)
                    default:
                        loadedContent
                    }
                }
                .padding(.horizontal, VikuSpacing.md)
                .padding(.bottom, VikuSpacing.xl + keyboardHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(VikuColor.Surface.page)
            .contentShape(Rectangle())
            .onTapGesture { focusedField = nil }
            .scrollDismissesKeyboard(.interactively)
            // The tap-outside/scroll dismissal above isn't reliable on a physical
            // device once the keyboard is up (a background tap there commonly
            // resigns the keyboard through UIKit without SwiftUI's gesture ever
            // firing) — a checkmark in the nav bar, matching Notes/Reminders, is
            // the dependable way to commit the description edit. The title field
            // doesn't need it: it's single-line, so its own Return key already
            // submits.
            .toolbar {
                if focusedField == .description || focusedField == .title {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            focusedField = nil
                        } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(
                            viewModel.task.isDone
                                ? String(localized: "Mark as Not Done", bundle: .module)
                                : String(localized: "Mark as Done", bundle: .module),
                            systemImage: viewModel.task.isDone ? "circle" : "checkmark.circle",
                        ) {
                            Task { await viewModel.toggleDone() }
                        }
                        Divider()
                        Button(String(localized: "Due Date", bundle: .module), systemImage: "calendar") {
                            isShowingDueDatePicker = true
                        }
                        Menu(String(localized: "Priority", bundle: .module), systemImage: "flag") {
                            ForEach(VikunjaTask.Priority.selectable, id: \.self) { priority in
                                Button {
                                    Task { await viewModel.setPriority(priority) }
                                } label: {
                                    HStack {
                                        Text(verbatim: priority.localizedMenuLabel)
                                        if viewModel.task.priority == priority {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        Button(String(localized: "Labels", bundle: .module), systemImage: "tag") {
                            isShowingLabelPicker = true
                        }
                        Button(String(localized: "Reminders", bundle: .module), systemImage: "bell") {
                            reminderEditTarget = ReminderEditTarget(index: nil, reminder: nil)
                        }
                        Divider()
                        Button(String(localized: "Add Relation", bundle: .module), systemImage: "link") {
                            relationEditStep = .pickKind(viewModel.task)
                        }
                        Button(
                            String(localized: "Duplicate Task", bundle: .module),
                            systemImage: "plus.square.on.square",
                        ) {
                            isShowingDuplicateSheet = true
                        }
                        Button(String(localized: "Move to Project", bundle: .module), systemImage: "folder") {
                            isShowingMovePicker = true
                        }
                        Divider()
                        // `role: .destructive` alone renders blue here, not red:
                        // the tab bar's `.tint(VikuColor.brandPrimary)` leaks
                        // into this menu and overrides the role's tint — mirrors
                        // `ProjectTaskRow`'s context menu in `Features/Projects`.
                        Button(
                            String(localized: "Delete Task", bundle: .module),
                            systemImage: "trash",
                            role: .destructive,
                        ) {
                            isShowingDeleteConfirmation = true
                        }
                        .tint(VikuColor.Semantic.danger)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationTitle(Text("Task Details", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { await viewModel.load() }
            .task { await viewModel.loadComments() }
            .task { await viewModel.loadAttachments() }
            .onAppear { viewModel.markVisible() }
            .onDisappear { viewModel.markHidden() }
            #if os(iOS)
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification),
            ) { notification in
                let info = notification.userInfo
                guard let endFrame = info?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                      let duration = info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
                else { return }
                let newHeight = max(0, UIScreen.main.bounds.height - endFrame.origin.y)
                withAnimation(.easeInOut(duration: duration)) {
                    keyboardHeight = newHeight
                }
                if newHeight > 0, isCommentComposerFocused {
                    withAnimation(.easeInOut(duration: duration)) {
                        proxy.scrollTo(Self.commentsAnchorID, anchor: .bottom)
                    }
                }
            }
            #endif
            .refreshable {
                await viewModel.load()
                await viewModel.loadComments()
                await viewModel.loadAttachments()
            }
            .sheet(isPresented: $isShowingDueDatePicker) {
                DueDatePickerSheet(initialDate: viewModel.task.dueDate) { newDate in
                    Task { await viewModel.setDueDate(newDate) }
                }
            }
            .sheet(item: $reminderEditTarget) { target in
                ReminderPickerSheet(
                    initialReminder: target.reminder,
                    dueDate: viewModel.task.dueDate,
                    onSave: { reminder in
                        Task {
                            if let index = target.index {
                                await viewModel.updateReminder(at: index, to: reminder)
                            } else {
                                await viewModel.addReminder(reminder)
                            }
                        }
                    },
                    onDelete: target.index.map { index in
                        { Task { await viewModel.removeReminder(at: index) } }
                    },
                )
            }
            .sheet(isPresented: $isShowingLabelPicker) {
                LabelPickerSheet(
                    taskLabels: viewModel.task.labels,
                    allLabels: viewModel.allLabels,
                    onLoad: { await viewModel.loadAllLabels() },
                    onToggle: { label in Task { await viewModel.toggleLabel(label) } },
                    onCreate: { title, hexColor in
                        Task { await viewModel.createAndAddLabel(title: title, hexColor: hexColor) }
                    },
                )
            }
            .sheet(isPresented: $isShowingMovePicker) {
                ProjectPickerSheet(
                    title: String(localized: "Move to Project", bundle: .module),
                    projects: viewModel.allProjects,
                    selectedProjectID: nil,
                    excludingSubtreeOf: viewModel.task.projectID,
                ) { project in
                    guard let project else { return }
                    Task {
                        if await viewModel.move(to: project) {
                            dismiss()
                        }
                    }
                }
                .task { await viewModel.loadAllProjects() }
            }
            .sheet(isPresented: $isShowingDuplicateSheet) {
                DuplicateTaskSheetView(
                    makeViewModel: { viewModel.makeDuplicateTaskViewModel() },
                    onDuplicated: { task, project in
                        // Reuses the same push path a tapped relation row takes.
                        router.push(.taskDetail(task, project))
                    },
                )
            }
            .confirmationDialog(
                Text("This permanently deletes the task.", bundle: .module),
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible,
            ) {
                Button(role: .destructive) {
                    Task {
                        if await viewModel.deleteTask() {
                            dismiss()
                        }
                    }
                } label: {
                    Text("Delete Task", bundle: .module)
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel", bundle: .module)
                }
            }
            .confirmationDialog(
                Text("This permanently deletes the comment.", bundle: .module),
                isPresented: Binding(
                    get: { commentPendingDeletion != nil },
                    set: {
                        if !$0 {
                            commentPendingDeletion = nil
                        }
                    },
                ),
                titleVisibility: .visible,
                presenting: commentPendingDeletion,
            ) { comment in
                Button(role: .destructive) {
                    Task { await viewModel.deleteComment(comment) }
                } label: {
                    Text("Delete Comment", bundle: .module)
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel", bundle: .module)
                }
            }
            .sheet(item: $commentPendingEdit) { comment in
                EditCommentSheet(initialText: RichText.plainText(from: comment.comment)) { newText in
                    Task { await viewModel.editComment(comment, newText: newText) }
                }
            }
            .modifier(
                AttachmentActionsModifier(
                    viewModel: viewModel,
                    isShowingFileImporter: $isShowingFileImporter,
                    pendingDeletion: $attachmentPendingDeletion,
                    previewURL: $attachmentPreviewURL,
                ),
            )
            .sheet(item: $relationEditStep) { step in
                switch step {
                case let .pickKind(task):
                    RelationKindPickerSheet { kind in
                        relationEditStep = .pickTask(task, kind)
                    }
                case let .pickTask(_, kind):
                    RelationTaskPickerSheet(
                        kind: kind,
                        results: viewModel.relationSearchResults,
                        projectTitle: { candidate in viewModel.projectTitle(forProjectID: candidate.projectID) },
                        onAppear: {
                            await viewModel.loadAllProjects()
                            await viewModel.loadRelationSuggestions()
                        },
                        onSearch: { query in await viewModel.searchTasksForRelation(query: query) },
                        onSelect: { candidate in
                            let relation = TaskRelation(
                                id: candidate.id, title: candidate.title,
                                isDone: candidate.isDone, projectID: candidate.projectID,
                            )
                            Task { await viewModel.addRelation(relation, kind: kind) }
                            relationEditStep = nil
                        },
                    )
                }
            }
            .onChange(of: focusedField) { previous, current in
                if previous == .title, current != .title {
                    commitTitleEdit()
                }
                if previous == .description, current != .description {
                    commitDescriptionEdit()
                }
            }
        }
    }

    private func beginEditingTitle() {
        titleDraft = viewModel.task.title
        isEditingTitle = true
        focusedField = .title
    }

    private func commitTitleEdit() {
        isEditingTitle = false
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != viewModel.task.title else { return }
        Task { await viewModel.setTitle(trimmed) }
    }

    private func beginEditingDescription() {
        // The stored value is the web editor's HTML. Editing it as rich text
        // isn't supported yet, so an empty description (often `<p></p>`) opens
        // a blank field rather than showing that markup; a non-empty one still
        // opens its raw HTML (see `commitDescriptionEdit`).
        let stored = viewModel.task.description ?? ""
        descriptionDraft = RichText.isEmpty(stored) ? "" : stored
        isEditingDescription = true
        focusedField = .description
    }

    private func commitDescriptionEdit() {
        isEditingDescription = false
        let trimmed = descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDescription = trimmed.isEmpty ? nil : trimmed
        guard newDescription != viewModel.task.description else { return }
        // Don't fire a write when both the draft and the stored value are
        // effectively empty (stored is often the editor's `<p></p>`).
        if newDescription == nil, RichText.isEmpty(viewModel.task.description ?? "") {
            return
        }
        Task { await viewModel.setDescription(newDescription) }
    }

    private func openRelation(_ relation: TaskRelation) {
        Task {
            if let (task, project) = await viewModel.loadRelatedTask(relation) {
                router.push(.taskDetail(task, project))
            }
        }
    }

    private func openAttachment(_ attachment: TaskAttachment) {
        Task {
            attachmentPreviewURL = await viewModel.attachmentPreviewURL(for: attachment)
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        let task = viewModel.task
        let project = viewModel.project

        Button {
            router.push(.projectOverview(project))
        } label: {
            ProjectPill(project: project)
        }
        .buttonStyle(.plain)
        .padding(.top, VikuSpacing.sm)

        HStack(alignment: .top, spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            Button {
                Task { await viewModel.toggleDone() }
            } label: {
                TaskDetailCheckbox(isDone: task.isDone, color: swatchColor(project))
            }
            .buttonStyle(.plain)
            .padding(.top, VikuSpacing.xxs)

            if isEditingTitle {
                TextField(String(localized: "Task title", bundle: .module), text: $titleDraft, axis: .vertical)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .focused($focusedField, equals: .title)
            } else {
                Text(verbatim: task.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .strikethrough(task.isDone)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditingTitle() }
            }
        }
        .padding(.top, VikuSpacing.sm)

        if task.isBlocked {
            BlockedBanner(waitingOn: task.dependsOn.filter { !$0.isDone }.count)
                .padding(.top, VikuSpacing.md)
        }

        descriptionRow(task: task)

        DueDatePriorityRows(viewModel: viewModel) { isShowingDueDatePicker = true }

        RemindersSection(
            reminders: task.reminders,
            onAdd: { reminderEditTarget = ReminderEditTarget(index: nil, reminder: nil) },
            onEdit: { index in reminderEditTarget = ReminderEditTarget(index: index, reminder: task.reminders[index]) },
            onRemove: { index in Task { await viewModel.removeReminder(at: index) } },
        )

        LabelsSection(labels: task.labels) { isShowingLabelPicker = true }

        if !task.subtasks.isEmpty {
            SubtasksSection(subtasks: task.subtasks, color: swatchColor(project))
        }

        RelationsSection(
            viewModel: viewModel,
            onAdd: { relationEditStep = .pickKind(viewModel.task) },
            onOpenRelation: openRelation,
        )

        AttachmentsSection(
            viewModel: viewModel,
            onAdd: { isShowingFileImporter = true },
            onOpen: openAttachment,
            onDelete: { attachmentPendingDeletion = $0 },
        )

        CommentsSection(
            viewModel: viewModel,
            onEdit: { commentPendingEdit = $0 },
            onDelete: { commentPendingDeletion = $0 },
            isComposerFocused: $isCommentComposerFocused,
        )
        // The extra bottom padding is inside the scrolled-to id, so
        // `anchor: .bottom` below leaves this much breathing room between
        // the composer and the keyboard instead of butting flush against it.
        .padding(.bottom, VikuSpacing.md)
        .id(Self.commentsAnchorID)
    }

    @ViewBuilder
    private func descriptionRow(task: VikunjaTask) -> some View {
        if isEditingDescription {
            // Multi-line (`axis: .vertical`) so it grows with the text and
            // Return inserts a line break, matching a description's normal
            // multi-paragraph use — unlike the title, there's no `onSubmit`
            // here since a multi-line field never submits on Return. Committing
            // happens via the nav bar checkmark below, or by tapping
            // elsewhere (see `focusedField`'s `onChange` above).
            TextField(
                String(localized: "Add description...", bundle: .module),
                text: $descriptionDraft,
                axis: .vertical,
            )
            .font(VikuFont.callout)
            .foregroundStyle(VikuColor.textSecondary)
            .focused($focusedField, equals: .description)
            .padding(.top, VikuSpacing.md)
        } else if let description = task.description, !RichText.isEmpty(description) {
            // Vikunja stores the description as its web editor's HTML output;
            // render it, don't show the raw markup. Tapping still opens the
            // inline editor (which edits plain text, see `beginEditingDescription`).
            RichTextView(html: description)
                .foregroundStyle(VikuColor.textSecondary)
                .contentShape(Rectangle())
                .onTapGesture { beginEditingDescription() }
                .padding(.top, VikuSpacing.md)
        } else {
            Text("Add description...", bundle: .module)
                .font(VikuFont.callout)
                .foregroundStyle(VikuColor.textTertiary)
                .contentShape(Rectangle())
                .onTapGesture { beginEditingDescription() }
                .padding(.top, VikuSpacing.md)
        }
    }

    private func swatchColor(_ project: Project) -> Color {
        Color(vikuHex: project.hexColor) ?? VikuColor.brandPrimary
    }
}
