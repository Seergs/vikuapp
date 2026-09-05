import VikunjaCore

/// The small per-connection glyph + accessible label shown in
/// `ConnectionsListView`'s row, so a saved connection's credential type is
/// visible at a glance without opening it.
extension InstanceAccount.AuthMethod {
    var badgeSystemImage: String {
        switch self {
        case .apiToken:
            "key.fill"
        case .password:
            "person.badge.key.fill"
        case .oidc:
            "person.badge.shield.checkmark.fill"
        }
    }

    var badgeAccessibilityLabel: String {
        switch self {
        case .apiToken:
            "API Token"
        case .password:
            "Username & Password"
        case .oidc:
            "Single Sign-On"
        }
    }
}
