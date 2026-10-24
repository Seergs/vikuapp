import Observation
import VikunjaCore

/// Drives a single "how to" guide screen, opened from a hero or feature's
/// `.guide` action. Holds no routing logic of its own — which guide to show,
/// and what happens when this screen's own action is handled, are decided by
/// whatever presents this (see `WhatsNewSheetViewModel`).
@MainActor
@Observable
public final class WhatsNewGuideViewModel {
    public let title: String
    public let intro: String
    public let steps: [WhatsNewGuide.Step]
    public let tip: String?
    public let primaryAction: WhatsNewAction?
    public let secondaryAction: WhatsNewAction?

    private let onAction: (WhatsNewAction) -> Void

    public init(guide: WhatsNewGuide, onAction: @escaping (WhatsNewAction) -> Void) {
        self.title = guide.title
        self.intro = guide.intro
        self.steps = guide.steps
        self.tip = guide.tip
        self.primaryAction = guide.primaryAction
        self.secondaryAction = guide.secondaryAction
        self.onAction = onAction
    }

    public func handle(_ action: WhatsNewAction) {
        onAction(action)
    }
}
