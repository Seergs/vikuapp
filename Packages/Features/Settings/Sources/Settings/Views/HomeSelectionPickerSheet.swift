import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// The "Home Screen" row's picker: choose "Today" (the default digest) or
/// pin a project/saved filter as the Home tab's content instead.
///
/// Deliberately not built on the shared `ProjectPickerSheet` — that one
/// renders a collapsible subproject tree, which doesn't fit here (saved
/// filters have no hierarchy, and nesting them under real projects would be
/// misleading). A flat list, sectioned by kind, fits a one-off pin better
/// and lets filters carry their own icon instead of reading as anonymous
/// projects.
struct HomeSelectionPickerSheet: View {
    let projects: [Project]
    let selectedID: Int?
    let onSelect: (Project?) -> Void

    @Environment(\.dismiss) private var dismiss

    private var realProjects: [Project] {
        projects.filter { $0.kind == .project }.sorted { $0.position < $1.position }
    }

    private var savedFilters: [Project] {
        projects.filter { $0.kind == .savedFilter }.sorted { $0.title < $1.title }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Row(
                        icon: "calendar.badge.checkmark",
                        hexColor: "",
                        title: String(localized: "Today", bundle: .module),
                        isSelected: selectedID == nil,
                        onSelect: { select(nil) },
                    )
                }

                if !realProjects.isEmpty {
                    Section(String(localized: "Projects", bundle: .module)) {
                        ForEach(realProjects) { project in
                            Row(
                                icon: "list.bullet.rectangle.fill",
                                hexColor: project.hexColor,
                                title: project.title,
                                isSelected: project.id == selectedID,
                                onSelect: { select(project) },
                            )
                        }
                    }
                }

                if !savedFilters.isEmpty {
                    Section(String(localized: "Saved Filters", bundle: .module)) {
                        ForEach(savedFilters) { filter in
                            Row(
                                icon: "line.3.horizontal.decrease.circle.fill",
                                hexColor: "",
                                title: filter.title,
                                isSelected: filter.id == selectedID,
                                onSelect: { select(filter) },
                            )
                        }
                    }
                }
            }
            .navigationTitle(Text("Home Screen", bundle: .module))
            #if os(iOS)
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Cancel", bundle: .module))
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
    }

    private func select(_ project: Project?) {
        dismiss()
        onSelect(project)
    }

    private struct Row: View {
        let icon: String
        let hexColor: String
        let title: String
        let isSelected: Bool
        let onSelect: () -> Void

        @Environment(\.vikuPalette) private var palette

        var body: some View {
            Button(action: onSelect) {
                HStack(spacing: VikuSpacing.sm) {
                    Image(systemName: icon)
                        .font(VikuFont.body)
                        .foregroundStyle(Color(vikuHex: hexColor) ?? palette.brand)
                        .frame(width: 24, alignment: .center)

                    Text(verbatim: title)
                        .font(VikuFont.body)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Spacer(minLength: VikuSpacing.sm)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(VikuFont.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(palette.brand)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
