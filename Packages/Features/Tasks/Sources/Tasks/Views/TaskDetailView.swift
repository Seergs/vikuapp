import SwiftUI
import VikuDesignSystem
import VikunjaCore
import VikuUI

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
    /// Type-erased, like `Features/Projects`' and `Features/Home`'s own
    /// `taskDetailDestination` closures — this package can't import
    /// `Projects` directly, so `AppContainer` supplies the actual
    /// `ProjectOverviewRootView` to push when the project pill is tapped.
    private let projectDestination: (Project) -> AnyView
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDueDatePicker = false
    @State private var isShowingLabelPicker = false
    @State private var isShowingMovePicker = false
    @State private var isShowingDuplicateSheet = false
    @State private var isShowingDeleteConfirmation = false
    @State private var commentPendingDeletion: TaskComment?
    @State private var commentPendingEdit: TaskComment?
    @State private var relationSheetStep: RelationSheetStep?
    @State private var isShowingFileImporter = false
    @State private var attachmentPendingDeletion: TaskAttachment?
    @State private var attachmentPreviewURL: URL?
    @State private var relatedTaskDestination: RelatedTaskDestination?
    @State private var projectDestinationBox: ProjectDestinationBox?
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @State private var isEditingDescription = false
    @State private var descriptionDraft = ""
    @FocusState private var focusedField: EditableField?

    private enum EditableField: Hashable {
        case title
        case description
    }

    public init(viewModel: TaskDetailViewModel, projectDestination: @escaping (Project) -> AnyView) {
        self.viewModel = viewModel
        self.projectDestination = projectDestination
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch viewModel.loadState {
                case let .failure(message):
                    VikuStatusView(
                        systemImage: "exclamationmark.triangle.fill",
                        title: "Couldn't load this task",
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
            .padding(.bottom, VikuSpacing.xl)
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
                    Button("Duplicate Task", systemImage: "plus.square.on.square") {
                        isShowingDuplicateSheet = true
                    }
                    Button("Move to Project", systemImage: "folder") {
                        isShowingMovePicker = true
                    }
                    // `role: .destructive` alone renders blue here, not red:
                    // the tab bar's `.tint(VikuColor.brandPrimary)` leaks
                    // into this menu and overrides the role's tint — mirrors
                    // `ProjectTaskRow`'s context menu in `Features/Projects`.
                    Button("Delete Task", systemImage: "trash", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                    .tint(VikuColor.Semantic.danger)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationTitle("Task Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await viewModel.load() }
        .task { await viewModel.loadComments() }
        .task { await viewModel.loadAttachments() }
        .onAppear { viewModel.markVisible() }
        .onDisappear { viewModel.markHidden() }
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
        .sheet(isPresented: $isShowingLabelPicker) {
            LabelPickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingMovePicker) {
            ProjectPickerSheet(
                title: "Move to Project",
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
            DuplicateTaskSheetView(viewModel: viewModel.makeDuplicateTaskViewModel()) { task, project in
                // Reuses the same push path a tapped relation row takes.
                relatedTaskDestination = RelatedTaskDestination(task: task, project: project)
            }
        }
        .confirmationDialog(
            "This permanently deletes the task.",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible,
        ) {
            Button("Delete Task", role: .destructive) {
                Task {
                    if await viewModel.deleteTask() {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "This permanently deletes the comment.",
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
            Button("Delete Comment", role: .destructive) {
                Task { await viewModel.deleteComment(comment) }
            }
            Button("Cancel", role: .cancel) {}
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
        .sheet(item: $relationSheetStep) { step in
            switch step {
            case .pickKind:
                RelationKindPickerSheet { kind in
                    relationSheetStep = .pickTask(kind)
                }
            case let .pickTask(kind):
                RelationTaskPickerSheet(viewModel: viewModel, kind: kind) { candidate in
                    let relation = TaskRelation(
                        id: candidate.id, title: candidate.title,
                        isDone: candidate.isDone, projectID: candidate.projectID,
                    )
                    Task { await viewModel.addRelation(relation, kind: kind) }
                    relationSheetStep = nil
                }
            }
        }
        .navigationDestination(item: $relatedTaskDestination) { destination in
            TaskDetailView(
                viewModel: viewModel.makeDetailViewModel(task: destination.task, project: destination.project),
                projectDestination: projectDestination,
            )
        }
        // The `AnyView` is built once, at tap time, and stashed in
        // `projectDestinationBox` rather than called fresh inside this
        // closure — see `ProjectDestinationBox`'s doc comment for why that
        // distinction matters here.
        .navigationDestination(item: $projectDestinationBox) { box in
            box.content
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
                relatedTaskDestination = RelatedTaskDestination(task: task, project: project)
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
            projectDestinationBox = ProjectDestinationBox(id: project.id, content: projectDestination(project))
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
                TextField("Task title", text: $titleDraft, axis: .vertical)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .focused($focusedField, equals: .title)
            } else {
                Text(task.title)
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

        LabelsSection(labels: task.labels) { isShowingLabelPicker = true }

        if !task.subtasks.isEmpty {
            SubtasksSection(subtasks: task.subtasks, color: swatchColor(project))
        }

        RelationsSection(
            viewModel: viewModel,
            onAdd: { relationSheetStep = .pickKind },
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
        )
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
            TextField("Add description...", text: $descriptionDraft, axis: .vertical)
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
            Text("Add description...")
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
