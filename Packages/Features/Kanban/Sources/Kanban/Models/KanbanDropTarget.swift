/// A board has one highlighted destination. Ignore late exit events from
/// a previous column so they cannot clear the current destination.
struct KanbanDropTarget {
    private(set) var bucketID: Int?

    mutating func update(isTargeted: Bool, bucketID: Int) {
        if isTargeted {
            self.bucketID = bucketID
        } else if self.bucketID == bucketID {
            self.bucketID = nil
        }
    }

    mutating func reset() {
        bucketID = nil
    }
}
