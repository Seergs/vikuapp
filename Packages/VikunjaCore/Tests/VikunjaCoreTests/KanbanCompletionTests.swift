import Testing
@testable import VikunjaCore

struct KanbanCompletionTests {
    @Test(arguments: [nil, 0] as [Int?])
    func `an unconfigured default falls back to the leftmost bucket`(defaultID: Int?) {
        #expect(KanbanCompletion.destination(
            isDone: false, currentBucketID: 30, doneBucketID: 30,
            defaultBucketID: defaultID, firstBucketID: 10,
        ) == 10)
    }

    @Test(arguments: [nil, 0] as [Int?])
    func `completing without a done bucket preserves the current placement`(doneID: Int?) {
        #expect(KanbanCompletion.destination(
            isDone: true, currentBucketID: 20, doneBucketID: doneID,
            defaultBucketID: 10, firstBucketID: 10,
        ) == 20)
    }
}
