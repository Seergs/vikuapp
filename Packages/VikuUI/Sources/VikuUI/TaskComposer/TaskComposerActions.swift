import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// Horizontally scrolling task fields alongside a fixed confirmation button.
public struct TaskComposerActions<Fields: View>: View {
    @Environment(\.vikuPalette) private var palette

    private let submission: TaskComposerSubmission
    private let canSubmit: Bool
    private let submitIcon: String
    private let submitLabel: Text
    private let submitIdentifier: String
    private let submit: () -> Void
    private let fields: Fields

    public init(
        submission: TaskComposerSubmission,
        canSubmit: Bool,
        submitIcon: String,
        submitLabel: Text,
        submitIdentifier: String,
        submit: @escaping () -> Void,
        @ViewBuilder fields: () -> Fields,
    ) {
        self.submission = submission
        self.canSubmit = canSubmit
        self.submitIcon = submitIcon
        self.submitLabel = submitLabel
        self.submitIdentifier = submitIdentifier
        self.submit = submit
        self.fields = fields()
    }

    public var body: some View {
        HStack(spacing: VikuSpacing.md) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: VikuSpacing.sm) { fields }
            }
            .disabled(submission.isSubmitting)

            Button(action: submit) {
                ZStack {
                    Image(systemName: submitIcon)
                        .opacity(submission.showsProgress ? 0 : 1)
                    if submission.showsProgress {
                        ProgressView().tint(palette.brandForeground)
                    }
                }
                .font(VikuFont.headline)
                .foregroundStyle(palette.brandForeground)
                .frame(width: VikuSpacing.xxl, height: VikuSpacing.xxl)
                .background(palette.brand, in: Circle())
                .opacity(canSubmit || submission.isSubmitting ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || submission.isSubmitting)
            .accessibilityLabel(submitLabel)
            .accessibilityIdentifier(submitIdentifier)
        }
    }
}

public struct TaskComposerProjectButton: View {
    @Environment(\.vikuPalette) private var palette

    private let project: Project?
    private let action: () -> Void

    public init(project: Project?, action: @escaping () -> Void) {
        self.project = project
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            if let project {
                let color = Color(vikuHex: project.hexColor) ?? palette.brand
                HStack(spacing: VikuSpacing.xs) {
                    Image(systemName: "folder")
                        .font(VikuFont.title3)
                    Text(verbatim: project.title)
                        .font(VikuFont.footnote.weight(.bold))
                        .lineLimit(1)
                }
                .foregroundStyle(color)
                .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xs)
                .frame(height: VikuSpacing.xl + VikuSpacing.xs)
                .background(color.opacity(0.1), in: Capsule())
            } else {
                TaskComposerShortcutIcon("folder")
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Choose Project", bundle: .module))
        .accessibilityValue(Text(verbatim: project?.title ?? ""))
    }
}

public struct TaskComposerPriorityMenu: View {
    @Environment(\.vikuPalette) private var palette

    private let priority: VikunjaTask.Priority
    private let onSelect: (VikunjaTask.Priority) -> Void

    public init(priority: VikunjaTask.Priority, onSelect: @escaping (VikunjaTask.Priority) -> Void) {
        self.priority = priority
        self.onSelect = onSelect
    }

    public var body: some View {
        if priority == .unset {
            menu
        } else {
            TaskComposerRemovableChip(
                color: VikuColor.Priority.dot(for: priority) ?? palette.brand,
                removeLabel: String(localized: "Remove Priority", bundle: .module),
                remove: { onSelect(.unset) },
                content: { menu },
            )
        }
    }

    private var menu: some View {
        Menu {
            ForEach(VikunjaTask.Priority.selectable, id: \.self) { option in
                Button { onSelect(option) } label: {
                    if option == priority {
                        Label { Text(verbatim: title(for: option)) } icon: { Image(systemName: "checkmark") }
                    } else {
                        Text(verbatim: title(for: option))
                    }
                }
            }
        } label: {
            if priority == .unset {
                TaskComposerShortcutIcon("flag")
            } else {
                HStack(spacing: VikuSpacing.xs) {
                    Image(systemName: "flag")
                        .font(VikuFont.title3)
                    Text(verbatim: title(for: priority))
                        .lineLimit(1)
                }
                .font(VikuFont.footnote.weight(.bold))
                .padding(.leading, VikuSpacing.sm + VikuSpacing.xs)
                .frame(minHeight: VikuSpacing.xxl - VikuSpacing.xs)
                .contentShape(Rectangle())
            }
        }
        .accessibilityLabel(Text("Priority", bundle: .module))
        .accessibilityValue(Text(verbatim: title(for: priority)))
    }

    private func title(for priority: VikunjaTask.Priority) -> String {
        switch priority {
        case .unset: String(localized: "None", bundle: .module)
        case .low: String(localized: "Low", bundle: .module)
        case .medium: String(localized: "Medium", bundle: .module)
        case .high: String(localized: "High", bundle: .module)
        case .urgent, .doNow: String(localized: "Urgent", bundle: .module)
        }
    }
}

public struct TaskComposerRemovableChip<Content: View>: View {
    private let color: Color
    private let removeLabel: String
    private let remove: () -> Void
    private let content: Content

    public init(
        color: Color,
        removeLabel: String,
        remove: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
    ) {
        self.color = color
        self.removeLabel = removeLabel
        self.remove = remove
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 0) {
            content
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(VikuFont.caption.weight(.semibold))
                    .frame(width: VikuSpacing.xl, height: VikuSpacing.xxl - VikuSpacing.xs)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(verbatim: removeLabel))
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .background {
            Capsule()
                .fill(color.opacity(0.1))
                .frame(height: VikuSpacing.xl + VikuSpacing.xs)
        }
        .accessibilityElement(children: .contain)
    }
}

public struct TaskComposerShortcutIcon: View {
    @Environment(\.vikuPalette) private var palette

    private let systemName: String

    public init(_ systemName: String) {
        self.systemName = systemName
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(VikuFont.title3)
            .foregroundStyle(palette.textSecondary)
            .frame(width: VikuSpacing.xl + VikuSpacing.xs, height: VikuSpacing.xl + VikuSpacing.xs)
            .background(palette.fieldBackground, in: Circle())
    }
}
