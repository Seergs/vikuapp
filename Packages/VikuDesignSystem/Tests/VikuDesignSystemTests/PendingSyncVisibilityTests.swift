import SwiftUI
import Testing
@testable import VikuDesignSystem
import VikunjaCore

struct PendingSyncVisibilityTests {
    @Test(arguments: [SyncItemStatus.pending, .failed])
    func `queued task indicators appear only offline and respond to reconnection`(status: SyncItemStatus) {
        let key = SyncItemKey(kind: .task, id: .remote(42))
        var environment = EnvironmentValues()
        environment.pendingSyncStatuses = [key: status]

        #expect(environment.visiblePendingSyncStatuses.isEmpty)

        environment.vikuIsOnline = false
        #expect(environment.visiblePendingSyncStatuses[key] == status)

        environment.vikuIsOnline = true
        #expect(environment.visiblePendingSyncStatuses.isEmpty)
        #expect(environment.pendingSyncStatuses[key] == status)

        environment.vikuIsOnline = false
        #expect(environment.visiblePendingSyncStatuses[key] == status)

        environment.pendingSyncStatuses = [:]
        #expect(environment.visiblePendingSyncStatuses.isEmpty)
    }

    @Test
    func `tasks without queued changes have no indicator offline`() {
        var environment = EnvironmentValues()
        environment.vikuIsOnline = false

        #expect(environment.visiblePendingSyncStatuses.isEmpty)
    }
}
