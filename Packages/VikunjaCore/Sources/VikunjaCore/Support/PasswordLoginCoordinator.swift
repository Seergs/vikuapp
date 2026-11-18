/// The state of an in-progress username/password login attempt.
public enum PasswordLoginState: Equatable, Sendable {
    case idle
    case authenticating
    /// The server rejected the attempt because the account has TOTP enabled
    /// — call `retryWithTOTP(_:)` once the user has entered their code.
    case awaitingTOTP
    case success(AuthSession)
    case failure(VikunjaError)
}

/// Orchestrates a username/password login attempt, including the TOTP
/// retry step, so `Features/Onboarding` and `Features/Settings` (which can't
/// depend on each other) don't each reimplement the same flow. Pure Swift,
/// no networking or UI dependency — the actual HTTP call happens inside
/// whatever `AuthServiceProtocol` implementation is injected.
public final class PasswordLoginCoordinator: Sendable {
    private let authService: AuthServiceProtocol

    public init(authService: AuthServiceProtocol) {
        self.authService = authService
    }

    /// Attempts a login with no TOTP code. Returns `.awaitingTOTP` (rather
    /// than throwing) when the server reports the account needs one, so
    /// callers can reveal a code field without treating it as a hard failure.
    public func attempt(username: String, password: String, longToken: Bool = false) async -> PasswordLoginState {
        await login(LoginCredentials(username: username, password: password, longToken: longToken))
    }

    /// Retries the most recent attempt with a TOTP passcode filled in. No-op
    /// (returns the current state unchanged) if called outside `.awaitingTOTP`.
    public func retryWithTOTP(
        _ passcode: String,
        username: String,
        password: String,
        longToken: Bool = false,
    ) async -> PasswordLoginState {
        let credentials = LoginCredentials(
            username: username, password: password, totpPasscode: passcode, longToken: longToken,
        )
        return await login(credentials)
    }

    private func login(_ credentials: LoginCredentials) async -> PasswordLoginState {
        do {
            let session = try await authService.login(credentials)
            return .success(session)
        } catch is CancellationError {
            return .idle
        } catch VikunjaError.totpRequired {
            return .awaitingTOTP
        } catch let error as VikunjaError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
