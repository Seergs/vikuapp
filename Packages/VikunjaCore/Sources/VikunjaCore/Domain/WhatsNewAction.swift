import Foundation

/// What tapping a "What's New" button does. Every case carries its own
/// button label because the label is authored content (localized per
/// release, not derived from the action kind), not a fixed string the app
/// can supply.
///
/// `VikunjaCore` has no notion of navigation or networking: `.deeplink`
/// only carries the `viku://` URL to open, `.url` only carries the external
/// link to open in a browser. Whatever presents the "What's New" sheet is
/// responsible for actually dispatching those.
public enum WhatsNewAction: Hashable, Sendable {
    case guide(label: String, guideId: String)
    case deeplink(label: String, url: URL)
    case url(label: String, url: URL)
    case dismiss(label: String)

    public var label: String {
        switch self {
        case let .guide(label, _): label
        case let .deeplink(label, _): label
        case let .url(label, _): label
        case let .dismiss(label): label
        }
    }
}

extension WhatsNewAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case label
        case guideId
        case url
    }

    private enum Kind: String, Codable {
        case guide
        case deeplink
        case url
        case dismiss
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let label = try container.decode(String.self, forKey: .label)
        switch try container.decode(Kind.self, forKey: .type) {
        case .guide:
            self = try .guide(label: label, guideId: container.decode(String.self, forKey: .guideId))
        case .deeplink:
            self = try .deeplink(label: label, url: container.decode(URL.self, forKey: .url))
        case .url:
            self = try .url(label: label, url: container.decode(URL.self, forKey: .url))
        case .dismiss:
            self = .dismiss(label: label)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .guide(label, guideId):
            try container.encode(Kind.guide, forKey: .type)
            try container.encode(label, forKey: .label)
            try container.encode(guideId, forKey: .guideId)
        case let .deeplink(label, url):
            try container.encode(Kind.deeplink, forKey: .type)
            try container.encode(label, forKey: .label)
            try container.encode(url, forKey: .url)
        case let .url(label, url):
            try container.encode(Kind.url, forKey: .type)
            try container.encode(label, forKey: .label)
            try container.encode(url, forKey: .url)
        case let .dismiss(label):
            try container.encode(Kind.dismiss, forKey: .type)
            try container.encode(label, forKey: .label)
        }
    }
}
