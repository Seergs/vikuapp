import SwiftUI

public extension Image {
    /// The real production app icon, bundled as a flat (unmasked) square —
    /// exactly how Xcode exports it, same as the OS itself masks it onto
    /// the Home Screen. Callers that want the rounded-corner look apply
    /// their own `.clipShape(RoundedRectangle(...))`, the same way a real
    /// icon slot would. For UI that needs to show "this is literally your
    /// icon" rather than describe it — see `AppIconBadgeConsentSheet`.
    static var vikuAppIcon: Image {
        Image("AppIconPreview", bundle: .module)
    }
}
