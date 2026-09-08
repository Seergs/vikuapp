import SwiftUI
import Testing
@testable import VikuDesignSystem
import VikunjaCore

struct PriorityDotColorTests {
    @Test
    func `unset priority has no dot`() {
        #expect(VikuColor.Priority.dot(for: .unset) == nil)
    }

    @Test
    func `each set priority maps to its token`() {
        #expect(VikuColor.Priority.dot(for: .low) == VikuColor.Priority.low)
        #expect(VikuColor.Priority.dot(for: .medium) == VikuColor.Priority.medium)
        #expect(VikuColor.Priority.dot(for: .high) == VikuColor.Priority.high)
        #expect(VikuColor.Priority.dot(for: .urgent) == VikuColor.Priority.urgent)
    }

    @Test
    func `do now shares the urgent color`() {
        #expect(VikuColor.Priority.dot(for: .doNow) == VikuColor.Priority.urgent)
    }
}
