import SwiftUI
import VikuDesignSystem
import VikunjaCore

// Small building blocks shared across `TaskDetailView`'s sections and sheets.
// Split out of `TaskDetailView.swift` so the screen file stays a shell.

struct ProjectPill: View {
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

struct TaskDetailCheckbox: View {
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

struct BlockedBanner: View {
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

struct InfoRow: View {
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

struct SectionBlock<Content: View>: View {
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

/// The "+ Edit" / "+ Add" affordance next to a section header — always present
/// per the mockup, whether or not the section has content. One view for all
/// three headers (Labels, Relations, Attachments); only the word differs.
struct SectionHeaderButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VikuSpacing.xxs) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
            }
            .foregroundStyle(VikuColor.brandPrimary)
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }
}

struct LabelPill: View {
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

struct LabelsWrap: View {
    let labels: [VikunjaCore.Label]

    var body: some View {
        FlowLayout(spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            ForEach(labels) { label in
                LabelPill(label: label)
            }
        }
    }
}

struct TaskDetailStatusView: View {
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
