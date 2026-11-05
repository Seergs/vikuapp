import VikunjaCore

/// Search and list presentation advance together when creation completes.
struct LabelPickerState {
    var ordering: LabelPickerOrdering
    var query = ""
    var isSearchPresented = false

    init(taskLabels: [Label]) {
        self.ordering = LabelPickerOrdering(taskLabels: taskLabels)
    }

    mutating func finishCreation(_ label: Label?) {
        ordering.finishCreation(label)
        guard label != nil else { return }
        query = ""
        isSearchPresented = false
    }
}
