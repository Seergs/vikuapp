import Foundation
import Observation
import VikunjaCore

/// Drives the main "What's New" screen: the release header, the optional
/// hero, the feature list, and the collapsible fixes section.
///
/// Holds no loading logic of its own — `content` arrives already decoded
/// (see `WhatsNewContentProviding`), and this is built once by the caller
/// rather than inside a `.sheet`/navigation closure, the same lesson every
/// other view model in this app learned the hard way: building one inside
/// such a closure lets SwiftUI silently discard and rebuild it on an
/// unrelated re-render.
@MainActor
@Observable
public final class WhatsNewMainViewModel {
    public let release: WhatsNewRelease
    public let hero: WhatsNewHero?
    public let features: [WhatsNewFeature]
    public let fixes: [String]
    public let hasHistory: Bool

    public private(set) var isFixesExpanded = false

    private let onAction: (WhatsNewAction) -> Void
    private let onShowHistory: () -> Void

    public init(
        content: WhatsNewContent,
        onAction: @escaping (WhatsNewAction) -> Void,
        onShowHistory: @escaping () -> Void = {},
    ) {
        self.release = content.release
        self.hero = content.hero
        self.features = content.features
        self.fixes = content.fixes
        self.hasHistory = !content.history.isEmpty
        self.onAction = onAction
        self.onShowHistory = onShowHistory
    }

    public func toggleFixesExpanded() {
        isFixesExpanded.toggle()
    }

    /// Forwards to the closure the caller supplied — this view model doesn't
    /// decide what a `.guide`/`.deeplink`/`.url`/`.dismiss` action actually
    /// does, only that tapping something reports it upward.
    public func handle(_ action: WhatsNewAction) {
        onAction(action)
    }

    /// "See previous versions" isn't a `WhatsNewAction` from the bundled
    /// content, it's chrome owned by this screen, so it gets its own
    /// callback rather than going through `handle`.
    public func showHistory() {
        onShowHistory()
    }

    /// The release date, formatted as an absolute "Oct 23, 2026" — not
    /// `DueDateFormatter`'s relative phrasing, which reads oddly for a
    /// release date months in the past. `nil` if `release.date` isn't a
    /// valid `yyyy-MM-dd` string, so the view can omit it rather than show
    /// garbage.
    public var dateLabel: String? {
        Self.dateFormatter.date(from: release.date).map {
            $0.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
