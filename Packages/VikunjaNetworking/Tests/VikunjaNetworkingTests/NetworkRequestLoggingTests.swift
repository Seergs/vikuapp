import Testing
@testable import VikunjaNetworking

/// `.serialized`: `shared` is a process-wide singleton, so a test that
/// leaves it enabled would leak into whichever test runs next otherwise.
@Suite(.serialized)
struct NetworkRequestLoggingTests {
    @Test
    func `is disabled by default`() {
        #expect(NetworkRequestLogging.shared.isEnabled == false)
    }

    @Test
    func `toggling isEnabled round trips`() {
        NetworkRequestLogging.shared.isEnabled = true
        defer { NetworkRequestLogging.shared.isEnabled = false }

        #expect(NetworkRequestLogging.shared.isEnabled == true)
    }
}
