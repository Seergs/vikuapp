#if canImport(AppKit)
import AppKit
@testable import Settings
import SwiftUI
import Testing

@MainActor
struct NotificationProgressViewLifecycleTests {
    @Test(arguments: [false, true])
    func `an initially hidden indicator starts its timer and survives until its minimum duration`(
        insideToggle: Bool,
    ) async throws {
        let host = NSHostingView(rootView: ProgressFixture(isActive: true, insideToggle: insideToggle))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        defer { window.contentView = nil }

        #expect(spinnerCount(in: host) == 0)
        try await Task.sleep(for: .milliseconds(1300))
        host.layoutSubtreeIfNeeded()
        #expect(spinnerCount(in: host) == 1)

        host.rootView = ProgressFixture(isActive: false, insideToggle: insideToggle)
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        #expect(spinnerCount(in: host) == 1)

        try await Task.sleep(for: .milliseconds(1300))
        host.layoutSubtreeIfNeeded()
        #expect(spinnerCount(in: host) == 0)
    }

    private struct ProgressFixture: View {
        let isActive: Bool
        let insideToggle: Bool

        var body: some View {
            if insideToggle {
                Toggle(isOn: .constant(true)) {
                    VStack {
                        Text(verbatim: "Test option")
                        indicator
                    }
                }
                .disabled(isActive)
            } else {
                indicator
            }
        }

        private var indicator: some View {
            NotificationProgressView(isActive: isActive, title: "Saving lifecycle test")
        }
    }

    private func spinnerCount(in view: NSView) -> Int {
        (view is NSProgressIndicator ? 1 : 0) + view.subviews.reduce(0) { $0 + spinnerCount(in: $1) }
    }
}
#endif
