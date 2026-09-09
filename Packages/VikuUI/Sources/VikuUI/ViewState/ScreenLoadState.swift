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
    /// Phase equality: two `.loaded` values are equal regardless of payload
    /// (content-in-view-model screens only ever ask "are we in the loaded
    /// phase?", and Search never compares). `.failure` compares its message.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
            true
        case let (.failure(lhsMessage), .failure(rhsMessage)):
            lhsMessage == rhsMessage
        default:
            false
        }
    }
}
