import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import VikuDesignSystem
import VikunjaCore

/// A single task's detail screen: completion, due date, priority, labels,
/// subtasks, and dependencies. Pushed as a leaf screen inside whichever
/// feature's `NavigationStack` opened it (Projects, today) — this package
/// owns no `NavigationStack`/`Router` of its own.
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
                    TaskDetailStatusView(message: message) {
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
            guard let data = await viewModel.attachmentData(for: attachment) else { return }
            attachmentPreviewURL = AttachmentPreviewFile.write(data, named: attachment.fileName)
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

        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            Button {
                isShowingDueDatePicker = true
            } label: {
                InfoRow(
                    systemImage: "calendar",
                    iconColor: task.dueDate == nil ? VikuColor.textTertiary : VikuColor.textSecondary,
                    title: "Due",
                    value: task.dueDate.map(TaskDueDateFormatter.string(for:)) ?? "Set due date",
                    valueColor: task.dueDate == nil
                        ? VikuColor.textTertiary
                        : (isOverdue(task) ? VikuColor.Semantic.dangerText : nil),
                    showsChevron: true,
                )
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(VikunjaTask.Priority.allCases.filter { $0 != .doNow }, id: \.self) { priority in
                    Button {
                        Task { await viewModel.setPriority(priority) }
                    } label: {
                        HStack {
                            Text(priorityMenuLabel(priority))
                            if task.priority == priority {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                InfoRow(
                    systemImage: "flag",
                    iconColor: priorityDisplay(task.priority)?.color ?? VikuColor.textTertiary,
                    title: "Priority",
                    value: priorityDisplay(task.priority)?.label ?? "Set priority",
                    valueColor: priorityDisplay(task.priority)?.color ?? VikuColor.textTertiary,
                    showsChevron: true,
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, VikuSpacing.lg)

        SectionBlock(title: "Labels", trailing: AnyView(EditLabelsButton { isShowingLabelPicker = true })) {
            if task.labels.isEmpty {
                Button("Add labels…") {
                    isShowingLabelPicker = true
                }
                .buttonStyle(.plain)
                .font(VikuFont.subheadline)
                .foregroundStyle(VikuColor.textTertiary)
            } else {
                LabelsWrap(labels: task.labels)
            }
        }

        if !task.subtasks.isEmpty {
            SectionBlock(title: "Subtasks", count: "\(task.subtasks.filter(\.isDone).count)/\(task.subtasks.count)") {
                SubtasksCard(subtasks: task.subtasks, color: swatchColor(project))
            }
        }

        SectionBlock(title: "Relations", trailing: AnyView(AddRelationButton { relationSheetStep = .pickKind })) {
            let groups = relationGroups(for: task)
            if groups.isEmpty {
                Text("No relations with other tasks.")
                    .font(VikuFont.subheadline)
                    .foregroundStyle(VikuColor.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: VikuSpacing.md) {
                    ForEach(groups, id: \.kind) { group in
                        RelationGroupView(
                            kind: group.kind,
                            relations: group.relations,
                            projectTitle: projectTitle(for:),
                            onTap: openRelation,
                            onRemove: { relation in
                                Task { await viewModel.removeRelation(relation, kind: group.kind) }
                            },
                        )
                    }
                }
            }
        }

        SectionBlock(
            title: "Attachments",
            count: viewModel.attachments.isEmpty ? nil : "\(viewModel.attachments.count)",
            trailing: AnyView(
                AddAttachmentButton { isShowingFileImporter = true }
                    .disabled(viewModel.isUploadingAttachment),
            ),
        ) {
            AttachmentsSection(
                attachments: viewModel.attachments,
                loadState: viewModel.attachmentsLoadState,
                isUploading: viewModel.isUploadingAttachment,
                onOpen: openAttachment,
                onDelete: { attachment in attachmentPendingDeletion = attachment },
            )
        }

        SectionBlock(title: "Comments", count: viewModel.comments.isEmpty ? nil : "\(viewModel.comments.count)") {
            CommentsSection(
                comments: viewModel.comments,
                loadState: viewModel.commentsLoadState,
                onSubmit: { text in
                    Task { await viewModel.addComment(text) }
                },
                onEdit: { comment in commentPendingEdit = comment },
                onDelete: { comment in commentPendingDeletion = comment },
            )
        }
    }

    /// `Depends on` and `Blocks` grouped alongside every `otherRelations`
    /// kind under one umbrella "Relations" section (matching the design
    /// mockup's combined "Relaciones" section) — `Subtasks` stays its own
    /// section above since it renders as a checklist, not a relation list.
    private func relationGroups(for task: VikunjaTask) -> [(kind: RelationKind, relations: [TaskRelation])] {
        var groups: [(kind: RelationKind, relations: [TaskRelation])] = []
        if !task.dependsOn.isEmpty {
            groups.append((.blocked, task.dependsOn))
        }
        if !task.blocks.isEmpty {
            groups.append((.blocking, task.blocks))
        }
        groups.append(contentsOf: orderedOtherRelations(task))
        return groups
    }

    /// `task.otherRelations` is a dictionary — iterate `RelationKind.allCases`
    /// instead of the dictionary directly so section order stays stable
    /// across renders rather than following Swift's unordered `Dictionary`
    /// iteration.
    private func orderedOtherRelations(_ task: VikunjaTask) -> [(kind: RelationKind, relations: [TaskRelation])] {
        RelationKind.allCases.compactMap { kind in
            guard let relations = task.otherRelations[kind], !relations.isEmpty else { return nil }
            return (kind, relations)
        }
    }

    /// `TaskRelation` only carries a `projectID` (not a title, since a
    /// related task can live in any project and this screen doesn't have a
    /// project repository to resolve arbitrary ones) — this only resolves
    /// the name when the relation happens to sit in this task's own project,
    /// which covers subtasks and same-project dependencies without risking a
    /// wrong or fabricated name for the rest.
    private func projectTitle(for relation: TaskRelation) -> String? {
        relation.projectID == viewModel.project.id ? viewModel.project.title : nil
    }

    private func isOverdue(_ task: VikunjaTask) -> Bool {
        guard let dueDate = task.dueDate, !task.isDone else { return false }
        return dueDate < Date()
    }

    private func swatchColor(_ project: Project) -> Color {
        Color(vikuHex: project.hexColor) ?? VikuColor.brandPrimary
    }

    private struct PriorityDisplay {
        let label: String
        let color: Color
    }

    private func priorityDisplay(_ priority: VikunjaTask.Priority) -> PriorityDisplay? {
        switch priority {
        case .unset: nil
        case .low: PriorityDisplay(label: "Low", color: VikuColor.Priority.low)
        case .medium: PriorityDisplay(label: "Medium", color: VikuColor.Priority.medium)
        case .high: PriorityDisplay(label: "High", color: VikuColor.Priority.high)
        case .urgent, .doNow: PriorityDisplay(label: "Urgent", color: VikuColor.Priority.urgent)
        }
    }

    private func priorityMenuLabel(_ priority: VikunjaTask.Priority) -> String {
        priorityDisplay(priority)?.label ?? "None"
    }
}

private struct ProjectPill: View {
    let project: Project

    private var swatchColor: Color {
        Color(vikuHex: project.hexColor) ?? VikuColor.brandPrimary
    }

    var body: some View {
        HStack(spacing: VikuSpacing.xs + VikuSpacing.xxs) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(swatchColor)
                .frame(width: 10, height: 10)
            Text(project.title)
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(VikuColor.textSecondary)
        }
    }
}

private struct TaskDetailCheckbox: View {
    let isDone: Bool
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .strokeBorder(isDone ? Color.clear : color, lineWidth: 2)
            .background(Circle().fill(isDone ? color : Color.clear))
            .frame(width: size, height: size)
            .overlay {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.46, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }
}

private struct BlockedBanner: View {
    let waitingOn: Int

    var body: some View {
        HStack(spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            Image(systemName: "link")
                .font(.system(size: 11))
                .foregroundStyle(VikuColor.Semantic.dangerText)
            Text("Blocked · waiting on \(waitingOn) task\(waitingOn == 1 ? "" : "s")")
                .font(VikuFont.footnote)
                .fontWeight(.bold)
                .foregroundStyle(VikuColor.Semantic.dangerText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            VikuColor.Semantic.danger.opacity(0.12),
            in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
        )
    }
}

private struct InfoRow: View {
    let systemImage: String
    let iconColor: Color
    let title: String
    let value: String
    var valueColor: Color?
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 18)
            Text(title)
                .font(VikuFont.subheadline)
                .foregroundStyle(Color.primary)
            Spacer()
            Text(value)
                .font(VikuFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor ?? Color.primary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VikuColor.textTertiary)
            }
        }
        .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
        .background(VikuColor.Surface.card, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
    }
}

private struct SectionBlock<Content: View>: View {
    let title: String
    var count: String?
    var trailing: AnyView = .init(EmptyView())
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            HStack(spacing: VikuSpacing.xs) {
                Text(title)
                    .fontWeight(.bold)
                if let count {
                    Text(count)
                        .fontWeight(.regular)
                }
                Spacer(minLength: 0)
                trailing
            }
            .font(VikuFont.footnote)
            .foregroundStyle(VikuColor.textSecondary)
            .textCase(.uppercase)
            .kerning(0.3)

            content
        }
        .padding(.top, VikuSpacing.xl)
    }
}

/// The "+ Edit" affordance next to the Labels section header — always
/// present, per the mockup, whether or not the task already has labels.
private struct EditLabelsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VikuSpacing.xxs) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("Edit")
            }
            .foregroundStyle(VikuColor.brandPrimary)
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }
}

private struct LabelsWrap: View {
    let labels: [VikunjaCore.Label]

    var body: some View {
        FlowLayout(spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            ForEach(labels) { label in
                LabelPill(label: label)
            }
        }
    }
}

private struct LabelPill: View {
    let label: VikunjaCore.Label

    private var color: Color {
        Color(vikuHex: label.hexColor) ?? VikuColor.textSecondary
    }

    var body: some View {
        Text(label.title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.xxs)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// Simple wrapping row layout for labels — SwiftUI has no built-in flow
/// layout, and labels can't be forced onto a single scrollable row here the
/// way `ProjectOverviewView`'s filter chips are.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + (rowWidth > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Read-only for now: a `TaskRelation` is a thin summary (see its doc
/// comment), not enough to safely round-trip through
/// `TaskRepositoryProtocol.update(_:)` without first fetching the full task —
/// an extra request per row this screen doesn't make yet.
private struct SubtasksCard: View {
    let subtasks: [TaskRelation]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                if index > 0 {
                    Divider().padding(.leading, VikuSpacing.md - VikuSpacing.xxs)
                }
                HStack(spacing: VikuSpacing.sm) {
                    TaskDetailCheckbox(isDone: subtask.isDone, color: color, size: 20)
                    Text(subtask.title)
                        .font(VikuFont.subheadline)
                        .foregroundStyle(subtask.isDone ? VikuColor.textTertiary : Color.primary)
                        .strikethrough(subtask.isDone)
                    Spacer()
                }
                .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
                .padding(.vertical, VikuSpacing.sm + VikuSpacing.xs)
            }
        }
        .background(VikuColor.Surface.card, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
    }
}

/// One relation kind and its rows. When a kind carries more than
/// `collapseThreshold` relations the list starts collapsed to the first few,
/// with a "Show N more"/"Show less" toggle — long relation lists (a task that
/// blocks a dozen others) otherwise push the rest of the screen far down.
private struct RelationGroupView: View {
    let kind: RelationKind
    let relations: [TaskRelation]
    let projectTitle: (TaskRelation) -> String?
    let onTap: (TaskRelation) -> Void
    let onRemove: (TaskRelation) -> Void

    @State private var isExpanded = false

    private static let collapseThreshold = 3

    private var isCollapsible: Bool {
        relations.count > Self.collapseThreshold
    }

    private var visibleRelations: ArraySlice<TaskRelation> {
        isCollapsible && !isExpanded ? relations.prefix(Self.collapseThreshold) : relations[...]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xs) {
            Text(kind.displayName)
                .font(VikuFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(VikuColor.textTertiary)
            VStack(spacing: VikuSpacing.sm) {
                ForEach(visibleRelations) { relation in
                    DependencyRow(
                        relation: relation,
                        projectTitle: projectTitle(relation),
                        onTap: { onTap(relation) },
                        onRemove: { onRemove(relation) },
                    )
                }
            }
            if isCollapsible {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: VikuSpacing.xxs) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isExpanded
                            ? "Show less"
                            : "Show \(relations.count - Self.collapseThreshold) more")
                    }
                    .font(VikuFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(VikuColor.brandPrimary)
                }
                .buttonStyle(.plain)
                .padding(.top, VikuSpacing.xxs)
            }
        }
    }
}

private struct DependencyRow: View {
    let relation: TaskRelation
    let projectTitle: String?
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: VikuSpacing.sm) {
            Button(action: onTap) {
                HStack(spacing: VikuSpacing.sm) {
                    Circle()
                        .strokeBorder(relation.isDone ? Color.clear : VikuColor.textTertiary, lineWidth: 2)
                        .background(Circle().fill(relation.isDone ? VikuColor.Semantic.success : Color.clear))
                        .frame(width: 20, height: 20)
                        .overlay {
                            if relation.isDone {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }

                    VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                        Text(relation.title)
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundStyle(Color.primary)
                            .strikethrough(relation.isDone)
                        if let projectTitle {
                            Text(projectTitle)
                                .font(VikuFont.caption)
                                .foregroundStyle(VikuColor.textTertiary)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(VikuColor.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(VikuColor.Surface.field, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.sm)
        .background(VikuColor.Surface.card, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
    }
}

/// Identifies which related task's detail screen to push, resolved
/// asynchronously via `TaskDetailViewModel.loadRelatedTask(_:)` when a
/// `DependencyRow` is tapped.
private struct RelatedTaskDestination: Identifiable, Hashable {
    let task: VikunjaTask
    let project: Project

    var id: Int {
        task.id
    }
}

/// Wraps the type-erased `AnyView` `projectDestination(_:)` builds, computed
/// once at tap time rather than inside the `.navigationDestination(item:)`
/// closure itself. That closure re-runs on every re-render of this screen —
/// unlike `.navigationDestination(for:)`, which keys off a stable value
/// already sitting in the `NavigationPath` and only rebuilds when the path
/// actually changes — and `AnyView` erases the type identity SwiftUI would
/// otherwise use to recognize "this is still the same destination" across
/// those reruns. Rebuilding the `AnyView` (and the `ProjectOverviewViewModel`
/// inside it) fresh each time meant the pushed screen kept getting torn down
/// and remounted from scratch, restarting its `.task { load() }` before it
/// ever finished — an endless-looking spinner. Building it once here and
/// handing the closure the same cached value every time avoids that; the
/// concrete-typed `relatedTaskDestination` above doesn't need this same
/// treatment since it pushes a real `TaskDetailView`, not an `AnyView`.
private struct ProjectDestinationBox: Identifiable, Hashable {
    let id: Int
    let content: AnyView

    /// Written by hand: `AnyView` isn't `Hashable`, and identity here only
    /// ever needs to key off `id` anyway.
    static func == (lhs: ProjectDestinationBox, rhs: ProjectDestinationBox) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// The "+ Add" affordance next to the Relations section header.
private struct AddRelationButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VikuSpacing.xxs) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("Add")
            }
            .foregroundStyle(VikuColor.brandPrimary)
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }
}

/// The attachment file-importer, QuickLook preview, and delete confirmation,
/// grouped off `TaskDetailView.body` — its modifier chain is long enough that
/// folding these in inline pushes the type-checker past its time budget.
private struct AttachmentActionsModifier: ViewModifier {
    @Bindable var viewModel: TaskDetailViewModel
    @Binding var isShowingFileImporter: Bool
    @Binding var pendingDeletion: TaskAttachment?
    @Binding var previewURL: URL?

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false,
            ) { result in
                guard case let .success(urls) = result, let url = urls.first else { return }
                guard let picked = PickedFile(url: url) else {
                    viewModel.reportAttachmentReadFailure()
                    return
                }
                Task {
                    await viewModel.uploadAttachment(
                        data: picked.data,
                        fileName: picked.fileName,
                        mimeType: picked.mimeType,
                    )
                }
            }
            .quickLookPreview($previewURL)
            .confirmationDialog(
                "This permanently deletes the attachment.",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: {
                        if !$0 {
                            pendingDeletion = nil
                        }
                    },
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion,
            ) { attachment in
                Button("Delete Attachment", role: .destructive) {
                    Task { await viewModel.deleteAttachment(attachment) }
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

/// The "+ Add" affordance next to the Attachments section header.
private struct AddAttachmentButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VikuSpacing.xxs) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("Add")
            }
            .foregroundStyle(VikuColor.brandPrimary)
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }
}

/// One file the user picked through `.fileImporter`, read into memory with
/// its name and MIME type resolved — `nil` if the bytes can't be read (a
/// security-scoped URL that won't open).
private struct PickedFile {
    let data: Data
    let fileName: String
    let mimeType: String

    init?(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else { return nil }
        self.data = data
        self.fileName = url.lastPathComponent
        let resolved = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        self.mimeType = resolved?.preferredMIMEType ?? "application/octet-stream"
    }
}

/// The two steps of adding a relation, matching the design mockup: first
/// pick a relation kind, then pick the other task. Modeled as one
/// `Identifiable` enum (rather than two independent `Bool`s) so exactly one
/// sheet is ever presented at a time and picking a kind can hand off
/// straight into the task picker.
private enum RelationSheetStep: Identifiable {
    case pickKind
    case pickTask(RelationKind)

    var id: String {
        switch self {
        case .pickKind: "pickKind"
        case let .pickTask(kind): "pickTask-\(kind.rawValue)"
        }
    }
}

/// Lets the user choose which kind of relation to add — every `RelationKind`
/// except `subtask`/`parenttask`, which are represented on this screen
/// through the (read-only, for now) Subtasks checklist instead.
private struct RelationKindPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (RelationKind) -> Void

    private var kinds: [RelationKind] {
        RelationKind.allCases.filter { $0 != .subtask && $0 != .parenttask }
    }

    var body: some View {
        NavigationStack {
            List(kinds, id: \.self) { kind in
                Button {
                    onPick(kind)
                } label: {
                    HStack(spacing: VikuSpacing.sm) {
                        Image(systemName: "link")
                            .font(.system(size: 15))
                            .foregroundStyle(VikuColor.brandPrimary)
                        Text(kind.displayName)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(VikuColor.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Relation Type")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Searches every task on the instance (via
/// `TaskDetailViewModel.searchTasksForRelation(query:)`) to pick the other
/// side of a new relation of the given `kind`.
private struct RelationTaskPickerSheet: View {
    @Bindable var viewModel: TaskDetailViewModel
    let kind: RelationKind
    let onSelect: (VikunjaTask) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.relationSearchResults.isEmpty {
                    VStack {
                        Spacer()
                        Text(isSearching ? "No results" : "No other tasks in this project")
                            .font(VikuFont.subheadline)
                            .foregroundStyle(VikuColor.textTertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.relationSearchResults) { candidate in
                        Button {
                            onSelect(candidate)
                        } label: {
                            RelationCandidateRow(
                                task: candidate,
                                projectTitle: viewModel.projectTitle(forProjectID: candidate.projectID),
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search tasks...")
            .onChange(of: query) { _, newValue in
                Task { await viewModel.searchTasksForRelation(query: newValue) }
            }
            .navigationTitle(kind.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .task {
            await viewModel.loadAllProjects()
            await viewModel.loadRelationSuggestions()
        }
    }
}

private struct RelationCandidateRow: View {
    let task: VikunjaTask
    let projectTitle: String?

    private var priorityColor: Color? {
        switch task.priority {
        case .unset: nil
        case .low: VikuColor.Priority.low
        case .medium: VikuColor.Priority.medium
        case .high: VikuColor.Priority.high
        case .urgent, .doNow: VikuColor.Priority.urgent
        }
    }

    var body: some View {
        HStack(spacing: VikuSpacing.sm) {
            if let priorityColor {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                Text(task.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                if let projectTitle {
                    Text(projectTitle)
                        .font(VikuFont.caption)
                        .foregroundStyle(VikuColor.textTertiary)
                }
            }
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VikuColor.brandPrimary)
        }
    }
}

private struct TaskDetailStatusView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: VikuSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(VikuColor.textTertiary)
            Text("Couldn't load this task")
                .font(VikuFont.headline)
            Text(message)
                .font(VikuFont.subheadline)
                .foregroundStyle(VikuColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retryAction)
                .buttonStyle(.bordered)
                .padding(.top, VikuSpacing.xs)
        }
        .padding(VikuSpacing.lg)
        .frame(maxWidth: .infinity)
    }
}

/// Lets the user pick (or clear) a due date/time. A small sheet rather than
/// an inline `DatePicker`, matching `QuickAddSheetView`'s pattern of pushing
/// pickers into their own sheet — `TaskDetailView` has no toolbar of its own
/// to host a "Done" button otherwise.
private struct DueDatePickerSheet: View {
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss
    private let hadInitialDate: Bool
    private let onSave: (Date?) -> Void

    init(initialDate: Date?, onSave: @escaping (Date?) -> Void) {
        _date = State(initialValue: initialDate ?? Date())
        self.hadInitialDate = initialDate != nil
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    DatePicker("Due date", selection: $date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()

                    if hadInitialDate {
                        Button("Remove Due Date", role: .destructive) {
                            onSave(nil)
                            dismiss()
                        }
                        .padding(.top, VikuSpacing.sm)
                    }
                }
                .padding(.horizontal, VikuSpacing.md)
                .padding(.top, VikuSpacing.sm)
            }
            .navigationTitle("Due Date")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(date)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        // Two detents (not one fixed height) so the sheet can be dragged
        // taller — the graphical calendar plus the hour/minute wheel the
        // `.graphical` style appends below it don't both fit at the smaller
        // detent, and a fixed single detent left the wheel unreachable.
        .presentationDetents([.fraction(0.6), .large])
        .presentationDragIndicator(.visible)
    }
}

/// Add/remove labels on the task, and create a new one on the fly — matches
/// the design mockup's label sheet. A `.searchable` list rather than a
/// custom text field; unlike the project picker, tapping a row here toggles
/// membership instead of dismissing, since a task can carry more than one
/// label.
private struct LabelPickerSheet: View {
    @Bindable var viewModel: TaskDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var pickedColor = VikuColor.SwatchPalette.swatches[0]

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredLabels: [VikunjaCore.Label] {
        guard !trimmedQuery.isEmpty else { return viewModel.allLabels }
        return viewModel.allLabels.filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private var hasExactMatch: Bool {
        viewModel.allLabels.contains { $0.title.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                    ForEach(filteredLabels) { label in
                        LabelPickerRow(label: label, isSelected: viewModel.task.labels.contains(label)) {
                            Task { await viewModel.toggleLabel(label) }
                        }
                    }

                    if !trimmedQuery.isEmpty, !hasExactMatch {
                        CreateLabelCard(title: trimmedQuery, pickedColor: $pickedColor) {
                            let title = trimmedQuery
                            let color = pickedColor
                            query = ""
                            Task { await viewModel.createAndAddLabel(title: title, hexColor: color) }
                        }
                    }
                }
                .padding(.vertical, VikuSpacing.sm)
            }
            .searchable(text: $query, prompt: "Search or create label...")
            .navigationTitle("Labels")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .task { await viewModel.loadAllLabels() }
    }
}

private struct LabelPickerRow: View {
    let label: VikunjaCore.Label
    let isSelected: Bool
    let action: () -> Void

    private var color: Color {
        Color(vikuHex: label.hexColor) ?? VikuColor.textSecondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: VikuSpacing.sm) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(label.title)
                    .font(.system(size: 15.5))
                    .foregroundStyle(Color.primary)
                Spacer()
                // An explicit checkbox rather than a checkmark that only
                // appears once selected — an empty circle makes it obvious
                // up front that rows are multi-select, not "pick one".
                LabelSelectionIndicator(isSelected: isSelected)
            }
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.sm + VikuSpacing.xs)
            .background(
                isSelected ? VikuColor.Surface.field : Color.clear,
                in: RoundedRectangle(cornerRadius: VikuRadius.sm - VikuSpacing.xxs, style: .continuous),
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, VikuSpacing.sm)
    }
}

/// A quieter checkbox than `TaskDetailCheckbox` — a thin, low-opacity ring
/// that fills with a soft gray tint (not a solid color) and a muted
/// checkmark, matching the mockup's subtler treatment for "is this label
/// picked" versus the task's own bold completion toggle.
private struct LabelSelectionIndicator: View {
    let isSelected: Bool
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .strokeBorder(VikuColor.textTertiary.opacity(isSelected ? 0 : 0.4), lineWidth: 1.5)
            .background(Circle().fill(VikuColor.textTertiary.opacity(isSelected ? 0.22 : 0)))
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.46, weight: .bold))
                        .foregroundStyle(VikuColor.textSecondary)
                }
            }
    }
}

/// Offered only once the search query doesn't match any existing label
/// exactly — lets the user pick a swatch from `VikuColor.SwatchPalette`
/// and create+attach the label in one tap.
private struct CreateLabelCard: View {
    let title: String
    @Binding var pickedColor: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            Text("Create New Label")
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(VikuColor.textSecondary)

            HStack(spacing: VikuSpacing.sm) {
                Circle()
                    .fill(Color(vikuHex: pickedColor) ?? VikuColor.brandPrimary)
                    .frame(width: 12, height: 12)
                Text("\"\(title)\"")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }

            HStack(spacing: VikuSpacing.sm) {
                ForEach(VikuColor.SwatchPalette.swatches, id: \.self) { swatch in
                    Circle()
                        .fill(Color(vikuHex: swatch) ?? VikuColor.brandPrimary)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if swatch == pickedColor {
                                Circle().strokeBorder(Color.primary, lineWidth: 2)
                            }
                        }
                        .onTapGesture { pickedColor = swatch }
                }
            }

            Button(action: action) {
                Text("Create and Add")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VikuSpacing.sm)
                    .background(
                        VikuColor.brandPrimary,
                        in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(VikuSpacing.md - VikuSpacing.xxs)
        .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
        .padding(.horizontal, VikuSpacing.sm)
        .padding(.top, VikuSpacing.xs)
    }
}

/// The task's comment thread: existing comments (oldest first, matching
/// Vikunja's own order) plus the composer to post a new one. A failure
/// loading comments only replaces the "no comments yet" placeholder — the
/// composer stays available either way, matching the design mockup, which
/// never blocks posting on the thread having loaded successfully.
private struct AttachmentsSection: View {
    let attachments: [TaskAttachment]
    let loadState: ScreenLoadState
    var isUploading = false
    let onOpen: (TaskAttachment) -> Void
    let onDelete: (TaskAttachment) -> Void

    private var emptyStateMessage: String {
        if case let .failure(message) = loadState {
            return message
        }
        return "No attachments yet."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xs) {
            if attachments.isEmpty, !isUploading {
                Text(emptyStateMessage)
                    .font(VikuFont.subheadline)
                    .foregroundStyle(VikuColor.textTertiary)
            } else {
                ForEach(attachments) { attachment in
                    AttachmentRow(
                        attachment: attachment,
                        onOpen: { onOpen(attachment) },
                        onDelete: { onDelete(attachment) },
                    )
                }
            }

            if isUploading {
                AttachmentUploadingRow()
            }
        }
    }
}

private struct AttachmentUploadingRow: View {
    var body: some View {
        HStack(spacing: VikuSpacing.sm) {
            ProgressView()
                .frame(width: 28)
            Text("Uploading…")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(VikuColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.xs + VikuSpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VikuColor.Surface.card, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
    }
}

private struct AttachmentRow: View {
    let attachment: TaskAttachment
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var subtitle: String {
        let size = AttachmentSizeFormatter.string(for: attachment.sizeBytes)
        let date = CommentTimeFormatter.string(for: attachment.created)
        return "\(size) · \(date)"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: VikuSpacing.sm) {
                Image(systemName: AttachmentIcon.systemName(forMimeType: attachment.mimeType))
                    .font(.system(size: 17))
                    .foregroundStyle(VikuColor.brandPrimary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                    Text(attachment.fileName)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(VikuColor.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(VikuColor.textTertiary)
            }
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.xs + VikuSpacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VikuColor.Surface.card, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            // `role: .destructive` alone renders blue here — the tab bar's
            // `.tint(VikuColor.brandPrimary)` leaks in, same as
            // `CommentRow`'s context menu.
            Button("Delete Attachment", systemImage: "trash", role: .destructive, action: onDelete)
                .tint(VikuColor.Semantic.danger)
        }
    }
}

/// Maps a file's MIME type to an SF Symbol for its attachment row. Kept local
/// (like `priorityDisplay`) — it's a view concern, not a design token.
private enum AttachmentIcon {
    static func systemName(forMimeType mime: String) -> String {
        let mime = mime.lowercased()
        if mime.hasPrefix("image/") {
            return "photo"
        }
        if mime.hasPrefix("video/") {
            return "film"
        }
        if mime.hasPrefix("audio/") {
            return "music.note"
        }
        if mime == "application/pdf" {
            return "doc.richtext"
        }
        if mime.hasPrefix("text/") {
            return "doc.text"
        }
        if mime.contains("zip") || mime.contains("compressed") || mime.contains("tar") {
            return "doc.zipper"
        }
        return "doc"
    }
}

private enum AttachmentSizeFormatter {
    static func string(for bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }
}

/// Writes downloaded attachment bytes to a temp file so QuickLook can preview
/// it — the download is bearer-authed, so its remote URL can't be handed to
/// QuickLook directly. Files land in a dedicated subfolder that's cleared on
/// each write to keep only the most recent preview around.
private enum AttachmentPreviewFile {
    static func write(_ data: Data, named fileName: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("attachment-previews", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sanitized = fileName.replacingOccurrences(of: "/", with: "_")
            let url = directory.appendingPathComponent(sanitized.isEmpty ? "attachment" : sanitized)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

private struct CommentsSection: View {
    let comments: [TaskComment]
    let loadState: ScreenLoadState
    let onSubmit: (String) -> Void
    let onEdit: (TaskComment) -> Void
    let onDelete: (TaskComment) -> Void
    @State private var draft = ""

    private var emptyStateMessage: String {
        if case let .failure(message) = loadState {
            return message
        }
        return "No comments yet."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.md - VikuSpacing.xxs) {
            if comments.isEmpty {
                Text(emptyStateMessage)
                    .font(VikuFont.subheadline)
                    .foregroundStyle(VikuColor.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: VikuSpacing.md - VikuSpacing.xxs) {
                    ForEach(comments) { comment in
                        CommentRow(
                            comment: comment,
                            onEdit: { onEdit(comment) },
                            onDelete: { onDelete(comment) },
                        )
                    }
                }
            }

            CommentComposer(draft: $draft) {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                draft = ""
                onSubmit(text)
            }
        }
    }
}

private struct CommentRow: View {
    let comment: TaskComment
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var displayName: String {
        let name = comment.author.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return name
        }
        return comment.author.username
    }

    private var initials: String {
        let letters = displayName.split(separator: " ").prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }

    var body: some View {
        HStack(alignment: .top, spacing: VikuSpacing.sm) {
            Circle()
                .fill(VikuColor.Surface.field)
                .frame(width: 30, height: 30)
                .overlay {
                    Text(initials)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(VikuColor.textSecondary)
                }

            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: VikuSpacing.xs) {
                    Text(displayName)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text(CommentTimeFormatter.string(for: comment.created))
                        .font(.system(size: 12))
                        .foregroundStyle(VikuColor.textTertiary)
                }
                RichTextView(html: comment.comment, baseFont: VikuFont.subheadline)
                    .foregroundStyle(VikuColor.textSecondary)
            }
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.xs + VikuSpacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VikuColor.Surface.card, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit Comment", systemImage: "pencil", action: onEdit)
            // `role: .destructive` alone renders blue here, not red: the tab
            // bar's `.tint(VikuColor.brandPrimary)` leaks into the context
            // menu — an explicit `.tint` is what forces the red, mirroring
            // `ProjectTaskRow`'s context menu in `Features/Projects`.
            Button("Delete Comment", systemImage: "trash", role: .destructive, action: onDelete)
                .tint(VikuColor.Semantic.danger)
        }
    }
}

private struct CommentComposer: View {
    @Binding var draft: String
    let onSubmit: () -> Void

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: VikuSpacing.xs) {
            TextField("Write a comment...", text: $draft)
                .font(.system(size: 15))
                .foregroundStyle(Color.primary)
                .submitLabel(.send)
                .onSubmit(onSubmit)
                .padding(.leading, VikuSpacing.sm)
                .padding(.vertical, VikuSpacing.xs + VikuSpacing.xxs)

            Button(action: onSubmit) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canSubmit ? .white : VikuColor.textTertiary)
                    .frame(width: 34, height: 34)
                    .background(canSubmit ? VikuColor.brandPrimary : VikuColor.Surface.field, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.trailing, VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.xxs)
        .background(VikuColor.Surface.card, in: Capsule())
    }
}

/// Edits an existing comment's body. A small sheet with a "Save" toolbar
/// button, matching `DueDatePickerSheet`'s pattern rather than the inline
/// edit the task title/description use — `CommentRow` is a nested private
/// view with no toolbar of its own to host a commit affordance. The field
/// starts from the comment's plain-text form (Vikunja stores the body as the
/// web editor's HTML; see `RichText.plainText(from:)`), and `onSave` sends
/// plain text back the same way the composer does for a new comment.
private struct EditCommentSheet: View {
    @State private var draft: String
    private let initialText: String
    private let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(initialText: String, onSave: @escaping (String) -> Void) {
        self.initialText = initialText
        _draft = State(initialValue: initialText)
        self.onSave = onSave
    }

    private var canSave: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != initialText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                TextField("Comment", text: $draft, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                    .padding(VikuSpacing.sm)
                    .background(
                        VikuColor.Surface.card,
                        in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
                    )
                    .padding(.horizontal, VikuSpacing.md)
                    .padding(.top, VikuSpacing.md)
            }
            .navigationTitle("Edit Comment")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

@MainActor
private enum CommentTimeFormatter {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func string(for date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Formats a due date the way the design mirrors relative-day phrasing
/// (today/tomorrow/yesterday/weekday) before falling back to an absolute date.
private enum TaskDueDateFormatter {
    static func string(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today, \(date.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date),
        ).day ?? 0
        if abs(days) <= 6 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
