import SwiftUI
import VikuDesignSystem

/// Lets the user pick (or clear) a due date/time. A small sheet rather than
/// an inline `DatePicker`, matching `QuickAddSheetView`'s pattern of pushing
/// pickers into their own sheet. Lives in `VikuUI` rather than
/// `Features/Tasks` so every screen that lists tasks (Today, a project's task
/// list, the task detail overflow menu) can offer it without importing
/// another feature - mirrors `DuplicateTaskSheetView`.
public struct DueDatePickerSheet: View {
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss
    private let hadInitialDate: Bool
    private let onSave: (Date?) -> Void

    public init(initialDate: Date?, onSave: @escaping (Date?) -> Void) {
        _date = State(initialValue: initialDate ?? Date())
        self.hadInitialDate = initialDate != nil
        self.onSave = onSave
    }

    public var body: some View {
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
