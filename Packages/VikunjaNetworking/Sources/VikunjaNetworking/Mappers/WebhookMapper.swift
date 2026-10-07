import Foundation
import VikunjaCore

enum WebhookMapper {
    /// `nil` when `target_url` isn't a parseable URL — a malformed entry is
    /// dropped by the caller (`compactMap`) rather than failing the whole
    /// list decode, same spirit as `ServerInfoMapper.oidcProviders`.
    static func toDomain(_ dto: WebhookDTO) -> Webhook? {
        guard let targetURL = URL(string: dto.targetURL) else { return nil }
        return Webhook(
            id: dto.id,
            targetURL: targetURL,
            events: (dto.events ?? []).compactMap(WebhookEvent.init(rawValue:)),
            // `project_id`/`user_id` are non-pointer `int64`s on the server,
            // so whichever side doesn't apply comes back as `0`, never
            // absent/null — same server behavior `ProjectMapper` normalizes
            // for `parent_project_id`. Only one of the two is ever nonzero.
            projectID: zeroToNil(dto.projectID),
            userID: zeroToNil(dto.userID),
            createdAt: dto.created,
        )
    }

    private static func zeroToNil(_ value: Int?) -> Int? {
        value == 0 ? nil : value
    }

    /// Like `toDomain(_:)`, but throws instead of dropping the entry — for a
    /// create/update response, which should always echo back the valid URL
    /// this client just sent; an unparseable `target_url` there means
    /// something's genuinely wrong, not just one stale/bad list entry to skip.
    static func toDomainOrThrow(_ dto: WebhookDTO) throws -> Webhook {
        guard let webhook = toDomain(dto) else {
            throw VikunjaError.decoding("Webhook target_url is not a valid URL: \(dto.targetURL)")
        }
        return webhook
    }

    static func toDTO(_ webhook: Webhook) -> WebhookDTO {
        WebhookDTO(
            id: webhook.id,
            targetURL: webhook.targetURL.absoluteString,
            events: webhook.events.map(\.rawValue),
            projectID: webhook.projectID,
            userID: webhook.userID,
            secret: nil,
            created: webhook.createdAt,
        )
    }

    static func toCreateDTO(targetURL: URL, events: [WebhookEvent], secret: String?) -> WebhookDTO {
        WebhookDTO(
            id: 0,
            targetURL: targetURL.absoluteString,
            events: events.map(\.rawValue),
            projectID: nil,
            userID: nil,
            secret: secret,
            created: nil,
        )
    }

    /// Drops names the server returns that this enum doesn't know about yet
    /// (a newer Vikunja version added an event), and normalizes the v2
    /// `array | null` shape to an empty array.
    static func toEvents(_ names: [String]?) -> [WebhookEvent] {
        (names ?? []).compactMap(WebhookEvent.init(rawValue:))
    }
}
