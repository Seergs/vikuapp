import VikunjaCore

/// Search changes the visible cards, but capacity always reflects the full
/// local bucket, including tasks waiting to synchronize.
struct KanbanColumnContent {
    let visibleTasks: [VikunjaTask]
    let capacityFraction: Double?

    init(bucket: KanbanBucket, searchText: String) {
        self.visibleTasks = searchText.isEmpty
            ? bucket.tasks
            : bucket.tasks.filter { $0.title.localizedStandardContains(searchText) }
        self.capacityFraction = bucket.limit > 0
            ? min(Double(bucket.tasks.count) / Double(bucket.limit), 1)
            : nil
    }
}
