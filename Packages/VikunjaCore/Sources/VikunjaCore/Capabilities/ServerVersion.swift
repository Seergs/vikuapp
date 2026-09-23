/// A parsed `major.minor.patch` version, for comparing a server's reported
/// version against the minimum a capability requires (e.g. the v2 API
/// baseline, `2.4.0`).
///
/// Vikunja's `/api/v1/info` reports versions like `"0.24.6"` or, on a
/// from-source build, a non-numeric string such as `"unknown"` or a git
/// describe output. Comparisons against an unparseable version must fail
/// safe: the caller should treat it as *not* meeting the minimum, never
/// crash or assume the newest behavior.
public struct ServerVersion: Equatable, Sendable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses the leading `x.y.z` out of `raw`, tolerant of a `v` prefix and
    /// a trailing prerelease/build suffix (`"2.4.0-beta.1"`, `"v2.4.0+dev"`).
    /// Missing trailing components default to `0` (`"2.4"` → `2.4.0`).
    /// Returns `nil` when no leading numeric version can be found at all.
    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") {
            text.removeFirst()
        }

        let components = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return nil }

        func leadingInt(_ substring: Substring) -> Int? {
            let digits = substring.prefix { $0.isNumber }
            return digits.isEmpty ? nil : Int(digits)
        }

        guard let major = components.indices.contains(0) ? leadingInt(components[0]) : nil else { return nil }
        let minor = components.indices.contains(1) ? (leadingInt(components[1]) ?? 0) : 0
        let patch = components.indices.contains(2) ? (leadingInt(components[2]) ?? 0) : 0

        self.init(major: major, minor: minor, patch: patch)
    }

    public static func < (lhs: ServerVersion, rhs: ServerVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
