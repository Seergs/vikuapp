public enum VikunjaFeature: Sendable {
    case caldav
    case totp
    case registration
    /// Whether the instance has username/password login enabled.
    case localAuth
    /// Whether the instance has at least one OIDC provider configured.
    case openIDConnect
    /// Whether the instance serves Vikunja's v2 API (`/api/v2/...`),
    /// available from server version 2.4.0 onward. Unlike the other cases,
    /// this isn't a server-reported flag — it's derived from comparing
    /// `VikunjaServerInfo.version` against that minimum.
    case apiV2
}
