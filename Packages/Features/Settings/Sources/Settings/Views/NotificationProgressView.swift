import SwiftUI
import VikuDesignSystem

/// Presentation-only timing shared by the project notification screens.
struct NotificationProgressView: View {
    let isActive: Bool
    let title: String

    @State private var progress = NotificationProgressPresentation()
    @Environment(\.vikuPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Keep the task on a persistent container, including while no indicator
        // is rendered. Group would attach its lifecycle modifiers to the
        // conditional children and leave no task host in the hidden state.
        VStack(alignment: .leading, spacing: 0) {
            if progress.isVisible {
                HStack(spacing: VikuSpacing.sm) {
                    ProgressView()
                    Text(verbatim: title)
                        .font(VikuFont.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.vertical, VikuSpacing.sm)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: progress.isVisible)
        .task(id: isActive) {
            progress.update(isActive: isActive)
            guard let deadline = progress.nextUpdate else { return }
            do {
                try await ContinuousClock().sleep(until: deadline)
                try Task.checkCancellation()
                progress.advance()
            } catch {
                // The underlying request is independent of presentation timing.
            }
        }
        .onDisappear { progress = NotificationProgressPresentation() }
    }
}
