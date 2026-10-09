@testable import Settings
import Testing

@MainActor
struct AppIconBadgeViewModelTests {
    private func makeViewModel(
        store: FakeAppIconBadgeStoring = FakeAppIconBadgeStoring(),
        permissionRequester: FakeAppIconBadgePermissionRequesting = FakeAppIconBadgePermissionRequesting(),
    ) -> AppIconBadgeViewModel {
        AppIconBadgeViewModel(store: store, permissionRequester: permissionRequester)
    }

    @Test
    func `init reads the stored preference`() {
        let viewModel = makeViewModel(store: FakeAppIconBadgeStoring(isEnabled: true))

        #expect(viewModel.isEnabled)
    }

    @Test
    func `confirm enable persists and clears any stale denied flag once authorization succeeds`() async {
        let store = FakeAppIconBadgeStoring()
        let permissionRequester = FakeAppIconBadgePermissionRequesting()
        let viewModel = makeViewModel(store: store, permissionRequester: permissionRequester)

        await viewModel.confirmEnable()

        #expect(viewModel.isEnabled)
        #expect(viewModel.isPermissionDenied == false)
        #expect(store.setEnabledCalls == [true])
    }

    @Test
    func `confirm enable leaves the feature off and flags denied when the OS refuses`() async {
        let store = FakeAppIconBadgeStoring()
        let permissionRequester = FakeAppIconBadgePermissionRequesting()
        permissionRequester.requestAuthorizationResult = false
        let viewModel = makeViewModel(store: store, permissionRequester: permissionRequester)

        await viewModel.confirmEnable()

        #expect(viewModel.isEnabled == false)
        #expect(viewModel.isPermissionDenied)
        #expect(store.setEnabledCalls.isEmpty)
    }

    @Test
    func `disable persists immediately with no permission check`() async {
        let store = FakeAppIconBadgeStoring()
        let permissionRequester = FakeAppIconBadgePermissionRequesting()
        let viewModel = makeViewModel(store: store, permissionRequester: permissionRequester)
        await viewModel.confirmEnable()

        viewModel.disable()

        #expect(viewModel.isEnabled == false)
        #expect(viewModel.isPermissionDenied == false)
        #expect(store.setEnabledCalls == [true, false])
    }

    @Test
    func `refresh permission status is a no op while the feature is off`() async {
        let permissionRequester = FakeAppIconBadgePermissionRequesting()
        permissionRequester.isAuthorizationDeniedResult = true
        let viewModel = makeViewModel(permissionRequester: permissionRequester)

        await viewModel.refreshPermissionStatus()

        #expect(viewModel.isPermissionDenied == false)
    }

    @Test
    func `refresh permission status catches a permission revoked since the last launch`() async {
        let store = FakeAppIconBadgeStoring(isEnabled: true)
        let permissionRequester = FakeAppIconBadgePermissionRequesting()
        permissionRequester.isAuthorizationDeniedResult = true
        let viewModel = makeViewModel(store: store, permissionRequester: permissionRequester)

        await viewModel.refreshPermissionStatus()

        #expect(viewModel.isPermissionDenied)
    }
}
