import SwiftUI
import VikuDesignSystem

/// Layout and presentation shared by task composers. A caller can provide a
/// detent or use the measured content height.
public struct TaskComposerSheet<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = 0

    private let detentHeight: CGFloat?
    private let submission: TaskComposerSubmission
    private let content: Content

    public init(
        detentHeight: CGFloat? = nil,
        submission: TaskComposerSubmission,
        @ViewBuilder content: () -> Content,
    ) {
        self.detentHeight = detentHeight
        self.submission = submission
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VikuSpacing.lg) {
                content
            }
            .padding(.horizontal, VikuSpacing.md)
            .padding(.top, VikuSpacing.lg)
            .padding(.bottom, VikuSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: {
                if detentHeight == nil {
                    contentHeight = $0
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.height(detentHeight ?? max(VikuSpacing.xxl * 3, contentHeight))])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VikuRadius.lg + VikuSpacing.sm)
        .interactiveDismissDisabled(submission.isSubmitting)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86), value: contentHeight)
        .onDisappear { submission.cancel() }
    }
}
