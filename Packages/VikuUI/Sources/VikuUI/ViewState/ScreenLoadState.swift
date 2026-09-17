/// The request-lifecycle state shared by every feature screen — not a domain
/// model. A screen's view model owns its own content (`tasks`, `rootNodes`, ...)
/// alongside this; `Value` is the payload for the screens that instead keep
/// their loaded content inside the state itself (Search). Content-in-view-model
/// screens use `ScreenLoadState<Void>` and never touch the payload.
public enum ScreenLoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failure(String)
}

public extension ScreenLoadState {
    var isLoading: Bool {
        if case .loading = self {
            true
        } else {
            false
        }
    }

    var isLoaded: Bool {
        if case .loaded = self {
            true
        } else {
            false
        }
    }

    var value: Value? {
        if case let .loaded(value) = self {
            value
        } else {
            nil
        }
    }

    var failureMessage: String? {
        if case let .failure(message) = self {
            message
        } else {
            nil
        }
    }
}

/// Lets the content-in-view-model screens keep writing `.loaded` (and
/// `== .loaded` / `!= .loaded`) even though the case now carries `Void`.
public extension ScreenLoadState where Value == Void {
    static var loaded: ScreenLoadState {
        .loaded(())
    }
}

extension ScreenLoadState: Equatable {
    /// For content-in-view-model screens (`Value == Void`) this is phase
    /// equality: two `.loaded` values are equal regardless of payload, since
    /// those screens only ever ask "are we in the loaded phase?". For a
    /// screen that keeps its loaded content inside the state itself (Search,
    /// `Value == [VikunjaTask]`), the payload is compared too when `Value`
    /// happens to be `Equatable` (checked dynamically since this conformance
    /// can't be conditional on that — see below).
    ///
    /// The payload comparison matters because `@Observable`'s generated
    /// setter skips its change notification when the old and new values
    /// compare equal. A phase-only equality would make a view never re-render
    /// when a second search lands new results while the state stays
    /// `.loaded` — exactly Search's debounced-search-as-you-type case.
    ///
    /// Swift doesn't allow two conditional `Equatable` conformances for the
    /// same type (`where Value == Void` and `where Value: Equatable` would
    /// conflict even though the constraints are mutually exclusive), so this
    /// single conformance dynamically checks for `Equatable` instead.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading):
            true
        case let (.loaded(lhsValue), .loaded(rhsValue)):
            areEqual(lhsValue, rhsValue)
        case let (.failure(lhsMessage), .failure(rhsMessage)):
            lhsMessage == rhsMessage
        default:
            false
        }
    }
}

/// `true` when neither value is `Equatable` (phase-only equality, matching
/// `Value == Void` screens) or when both are and compare equal.
private func areEqual(_ lhs: some Any, _ rhs: some Any) -> Bool {
    guard let lhsEquatable = lhs as? any Equatable else { return true }
    func open<T: Equatable>(_ lhsValue: T) -> Bool {
        (rhs as? T).map { lhsValue == $0 } ?? false
    }
    return open(lhsEquatable)
}
