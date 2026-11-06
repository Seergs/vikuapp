/// Session-only developer control for the read-only Quick Add date panel.
/// Implementations start hidden and never persist visibility across app launches.
/// Owned by the composition root and shared by Settings and Quick Add.
@MainActor
public protocol QuickAddDatePreviewStoring: AnyObject {
    var isQuickAddDatePreviewVisible: Bool { get }
    func setQuickAddDatePreviewVisible(_ visible: Bool)
}
