import Testing
@testable import VikunjaCore

struct ServerVersionTests {
    @Test
    func `parses A plain major minor patch string`() {
        let version = ServerVersion("2.4.0")

        #expect(version == ServerVersion(major: 2, minor: 4, patch: 0))
    }

    @Test
    func `defaults missing minor AND patch to zero`() {
        let version = ServerVersion("2")

        #expect(version == ServerVersion(major: 2, minor: 0, patch: 0))
    }

    @Test
    func `defaults missing patch to zero`() {
        let version = ServerVersion("2.4")

        #expect(version == ServerVersion(major: 2, minor: 4, patch: 0))
    }

    @Test
    func `strips A leading V prefix`() {
        let version = ServerVersion("v2.4.0")

        #expect(version == ServerVersion(major: 2, minor: 4, patch: 0))
    }

    @Test
    func `ignores A prerelease suffix on the patch component`() {
        let version = ServerVersion("2.4.0-beta.1")

        #expect(version == ServerVersion(major: 2, minor: 4, patch: 0))
    }

    @Test
    func `ignores A build suffix on the patch component`() {
        let version = ServerVersion("2.4.0+dev")

        #expect(version == ServerVersion(major: 2, minor: 4, patch: 0))
    }

    @Test
    func `returns nil for A non numeric version string`() {
        #expect(ServerVersion("unknown") == nil)
    }

    @Test
    func `returns nil for an empty string`() {
        #expect(ServerVersion("") == nil)
    }

    @Test
    func `compares versions by major THEN minor THEN patch`() {
        #expect(ServerVersion(major: 2, minor: 4, patch: 0) >= ServerVersion(major: 2, minor: 4, patch: 0))
        #expect(ServerVersion(major: 2, minor: 4, patch: 1) > ServerVersion(major: 2, minor: 4, patch: 0))
        #expect(ServerVersion(major: 2, minor: 5, patch: 0) > ServerVersion(major: 2, minor: 4, patch: 9))
        #expect(ServerVersion(major: 3, minor: 0, patch: 0) > ServerVersion(major: 2, minor: 9, patch: 9))
        #expect(ServerVersion(major: 2, minor: 3, patch: 9) < ServerVersion(major: 2, minor: 4, patch: 0))
    }
}
