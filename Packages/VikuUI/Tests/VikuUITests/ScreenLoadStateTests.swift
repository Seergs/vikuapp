import Testing
@testable import VikuUI

struct ScreenLoadStateTests {
    @Test
    func `phase flags reflect the case`() {
        #expect(ScreenLoadState<Void>.idle.isLoading == false)
        #expect(ScreenLoadState<Void>.loading.isLoading == true)
        #expect(ScreenLoadState<Void>.loaded.isLoaded == true)
        #expect(ScreenLoadState<Void>.loading.isLoaded == false)
    }

    @Test
    func `value is the loaded payload`() {
        #expect(ScreenLoadState<[Int]>.loaded([1, 2]).value == [1, 2])
        #expect(ScreenLoadState<[Int]>.loading.value == nil)
    }

    @Test
    func `failureMessage is the failure string`() {
        #expect(ScreenLoadState<Void>.failure("nope").failureMessage == "nope")
        #expect(ScreenLoadState<Void>.idle.failureMessage == nil)
    }

    @Test
    func `equality is by phase, with failure comparing its message`() {
        #expect(ScreenLoadState<Void>.loading == .loading)
        #expect(ScreenLoadState<Void>.loaded == .loaded)
        #expect(ScreenLoadState<Void>.loading != .loaded)
        #expect(ScreenLoadState<Void>.failure("a") == .failure("a"))
        #expect(ScreenLoadState<Void>.failure("a") != .failure("b"))
    }

    @Test
    func `loaded payloads compare equal regardless of value`() {
        #expect(ScreenLoadState<[Int]>.loaded([1]) == .loaded([2]))
    }
}
