import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// Add/remove labels on a task, and create a new one on the fly — matches
/// the design mockup's label sheet. A `.searchable` list rather than a
/// custom text field; unlike the project picker, tapping a row here toggles
/// membership instead of dismissing, since a task can carry more than one
/// label. Driven entirely by closures/values rather than a concrete view
/// model, so it lives in `VikuUI` rather than `Features/Tasks` - every screen
/// that lists tasks (Today, a project's task list, the task detail overflow
/// menu) can offer it without importing another feature, mirroring
/// `DueDatePickerSheet`. Callers pass live, freshly-computed `taskLabels` on
/// every body re-evaluation (rather than a snapshot captured once) so the
/// checkmarks stay in sync while the sheet is open.
public struct LabelPickerSheet: View {
    let taskLabels: [VikunjaCore.Label]
    let allLabels: [VikunjaCore.Label]
    let labelAliases: [EntityID: EntityID]
    let onLoad: () async -> Void
    let onToggle: (VikunjaCore.Label) -> Void
    let onCreate: ((String, String) async -> VikunjaCore.Label?)?
    @Environment(\.dismiss) private var dismiss
    @State private var state: LabelPickerState
    @State private var pickedColor = VikuColor.SwatchPalette.labelSwatches[0]

    public init(
        taskLabels: [VikunjaCore.Label],
        allLabels: [VikunjaCore.Label],
        labelAliases: [EntityID: EntityID] = [:],
        onLoad: @escaping () async -> Void,
        onToggle: @escaping (VikunjaCore.Label) -> Void,
        onCreate: ((String, String) async -> VikunjaCore.Label?)? = nil,
    ) {
        _state = State(initialValue: LabelPickerState(taskLabels: taskLabels))
        self.taskLabels = taskLabels
        self.allLabels = allLabels
        self.labelAliases = labelAliases
        self.onLoad = onLoad
        self.onToggle = onToggle
        self.onCreate = onCreate
    }

    private var trimmedQuery: String {
        state.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredItems: [LabelPickerItem] {
        state.ordering.items(
            catalog: LabelCatalog(labels: allLabels, aliases: labelAliases),
            taskLabels: taskLabels, query: trimmedQuery,
        )
    }

    private var hasExactMatch: Bool {
        (allLabels + taskLabels).contains { $0.title.caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    public var body: some View {
        let items = filteredItems
        let selectedHeaderID = items.first(where: { $0.section == .onTask })?.id
        let otherHeaderID = items.first(where: { $0.section == .other })?.id
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VikuSpacing.xs) {
                    ForEach(items) { item in
                        if item.id == selectedHeaderID {
                            sectionHeader(String(localized: "On this task", bundle: .module))
                        } else if item.id == otherHeaderID {
                            sectionHeader(
                                state.ordering.hasOnTaskSection
                                    ? String(localized: "Other labels", bundle: .module)
                                    : String(localized: "Available labels", bundle: .module),
                                separated: selectedHeaderID != nil,
                            )
                        }
                        LabelPickerRow(label: item.label, isSelected: item.isSelected) {
                            onToggle(item.label)
                        }
                    }

                    if onCreate == nil, !trimmedQuery.isEmpty, items.isEmpty {
                        Text("No labels found", bundle: .module)
                            .font(VikuFont.footnote)
                            .padding(VikuSpacing.md)
                    }

                    if let onCreate, !trimmedQuery.isEmpty, !hasExactMatch || state.ordering.isCreating {
                        CreateLabelCard(
                            title: trimmedQuery, pickedColor: $pickedColor, isCreating: state.ordering.isCreating,
                        ) {
                            let title = trimmedQuery
                            let color = pickedColor
                            state.ordering.beginCreation(
                                catalog: LabelCatalog(labels: allLabels, aliases: labelAliases), taskLabels: taskLabels,
                            )
                            Task {
                                let created = await onCreate(title, color)
                                state.finishCreation(created)
                            }
                        }
                        .disabled(state.ordering.isCreating)
                    }
                }
                .padding(.vertical, VikuSpacing.sm)
            }
            .searchable(
                text: $state.query, isPresented: $state.isSearchPresented,
                prompt: onCreate == nil
                    ? Text("Search labels...", bundle: .module)
                    : Text("Search or create label...", bundle: .module),
            )
            .navigationTitle(Text("Labels", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .module)) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .task { await onLoad() }
    }

    private func sectionHeader(_ title: String, separated: Bool = false) -> some View {
        Text(verbatim: title)
            .vikuSectionHeader()
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, separated ? VikuSpacing.lg : VikuSpacing.sm)
            .padding(.bottom, VikuSpacing.xs)
    }
}

private struct LabelPickerRow: View {
    let label: VikunjaCore.Label
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.vikuPalette) private var palette

    private var color: Color {
        Color(vikuMutedHex: label.hexColor) ?? palette.textSecondary
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
                isSelected ? palette.fieldBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: VikuRadius.sm - VikuSpacing.xxs, style: .continuous),
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, VikuSpacing.sm)
    }
}

/// A neutral checkbox with an accent checkmark. System label/fill colors already
/// include their own opacity, so avoid multiplying it down on the empty ring.
private struct LabelSelectionIndicator: View {
    let isSelected: Bool
    var size: CGFloat = 22

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        Circle()
            .strokeBorder(palette.textSecondary.opacity(isSelected ? 0 : 1), lineWidth: 1.5)
            .background(Circle().fill(palette.fieldBackground.opacity(isSelected ? 1 : 0)))
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.46, weight: .bold))
                        .foregroundStyle(palette.brand)
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
    let isCreating: Bool
    let action: () -> Void

    @Environment(\.vikuPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            Text("Create New Label", bundle: .module)
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(palette.textSecondary)

            HStack(spacing: VikuSpacing.sm) {
                Circle()
                    .fill(Color(vikuHex: pickedColor) ?? palette.brand)
                    .frame(width: 12, height: 12)
                Text(verbatim: "\"\(title)\"")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }

            HStack(spacing: VikuSpacing.sm) {
                ForEach(VikuColor.SwatchPalette.labelSwatches, id: \.self) { swatch in
                    Circle()
                        .fill(Color(vikuHex: swatch) ?? palette.brand)
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
                Text(verbatim: isCreating
                    ? String(localized: "Creating label...", bundle: .module)
                    : String(localized: "Create and Add", bundle: .module))
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(palette.brandForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VikuSpacing.sm)
                    .background(
                        palette.brand,
                        in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(VikuSpacing.md - VikuSpacing.xxs)
        .background(palette.fieldBackground, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
        .padding(.horizontal, VikuSpacing.sm)
        .padding(.top, VikuSpacing.xs)
    }
}
