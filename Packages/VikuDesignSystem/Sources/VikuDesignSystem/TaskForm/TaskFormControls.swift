import SwiftUI
import VikunjaCore

// The small building blocks shared by the compact task sheets
// (`QuickAddSheetView` in Features/Tasks, `DuplicateTaskSheetView` in VikuUI)
// so they stay visually identical — a field-group label, the collapsed
// "Project" row that opens a picker, the priority chip row, and the
// save-error banner. Public because those sheets live in different modules
// (Tasks, VikuUI) that both already depend on VikuDesignSystem.

/// A field-group caption ("Project", "Priority", ...).
///
/// `title` is treated as opaque, already-resolved display text, not a
/// catalog key: callers outside this module pass their own feature's
/// strings, and a `Text(_:bundle: .module)` lookup here would always
/// resolve against VikuDesignSystem's own catalog, never the caller's.
/// A caller that owns its string localizes it first (e.g.
/// `String(localized: "Priority", bundle: .module)` for a string this
/// module owns) and hands the resolved value in.
public struct FieldLabel: View {
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(verbatim: title)
            .font(VikuFont.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(VikuColor.textSecondary)
    }
}

/// The collapsed "Project" row: shows the current selection (or a
/// placeholder when none is chosen yet) and runs `action` — typically
/// opening a `ProjectPickerSheet` — on tap.
public struct ProjectField: View {
    let project: Project?
    let action: () -> Void

    public init(project: Project?, action: @escaping () -> Void) {
        self.project = project
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: VikuSpacing.sm) {
                if let project {
                    ProjectPickerIcon(hexColor: project.hexColor)
                    Text(project.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.primary)
                } else {
                    Text("Choose project", bundle: .module)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(VikuColor.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VikuColor.textTertiary)
            }
            .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.sm + VikuSpacing.xs)
            .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

public struct PriorityOption: Identifiable, Sendable {
    let priority: VikunjaTask.Priority
    let label: String
    let color: Color

    public var id: VikunjaTask.Priority {
        priority
    }

    /// The four pickable priorities shown as chips (the sheets don't offer
    /// `.unset`/`.doNow`).
    public static let all: [PriorityOption] = [
        PriorityOption(
            priority: .low,
            label: String(localized: "Low", bundle: .module),
            color: VikuColor.Priority.low,
        ),
        PriorityOption(
            priority: .medium,
            label: String(localized: "Medium", bundle: .module),
            color: VikuColor.Priority.medium,
        ),
        PriorityOption(
            priority: .high,
            label: String(localized: "High", bundle: .module),
            color: VikuColor.Priority.high,
        ),
        PriorityOption(
            priority: .urgent,
            label: String(localized: "Urgent", bundle: .module),
            color: VikuColor.Priority.urgent,
        ),
    ]
}

/// The horizontal priority chip row. `selection` is a binding so tapping the
/// active chip clears it back to `.unset`.
public struct PriorityChipRow: View {
    @Binding var selection: VikunjaTask.Priority

    public init(selection: Binding<VikunjaTask.Priority>) {
        _selection = selection
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            FieldLabel(String(localized: "Priority", bundle: .module))
            HStack(spacing: VikuSpacing.sm) {
                ForEach(PriorityOption.all) { option in
                    PriorityChip(option: option, isSelected: selection == option.priority) {
                        selection = selection == option.priority ? .unset : option.priority
                    }
                }
            }
        }
    }
}

private struct PriorityChip: View {
    let option: PriorityOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VikuSpacing.xs) {
                Image(systemName: "flag")
                    .font(.system(size: 11))
                Text(verbatim: option.label)
                    .font(.system(size: 13.5, weight: .semibold))
            }
            .foregroundStyle(isSelected ? option.color : VikuColor.textTertiary)
            .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xs)
            .padding(.vertical, VikuSpacing.xs + VikuSpacing.xxs)
            .background(
                Capsule().fill(isSelected ? option.color.opacity(0.14) : VikuColor.Surface.field),
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? option.color : Color.clear, lineWidth: 1.5),
            )
        }
        .buttonStyle(.plain)
    }
}

/// Same tinted-card language as `TaskDetailView`'s `BlockedBanner` — a red
/// card rather than plain inline text, so a save failure reads as clearly as
/// every other error state in the app.
public struct SaveErrorBanner: View {
    let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .center, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(VikuColor.Semantic.dangerText)
            Text(verbatim: message)
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
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
