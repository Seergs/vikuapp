import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The combined "Relations" section: `dependsOn` and `blocks` grouped alongside
/// every `otherRelations` kind under one header (matching the design mockup's
/// combined section). `Subtasks` stays its own section above since it renders
/// as a checklist, not a relation list.
struct RelationsSection: View {
    @Bindable var viewModel: TaskDetailViewModel
    let onAdd: () -> Void
    let onOpenRelation: (TaskRelation) -> Void

    var body: some View {
        let task = viewModel.task
        let groups = relationGroups(for: task)

        SectionBlock(title: "Relations", trailing: AnyView(SectionHeaderButton(title: "Add", action: onAdd))) {
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
                            onTap: onOpenRelation,
                            onRemove: { relation in
                                Task { await viewModel.removeRelation(relation, kind: group.kind) }
                            },
                        )
                    }
                }
            }
        }
    }

    /// `Depends on` and `Blocks` first, then every `otherRelations` kind.
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
