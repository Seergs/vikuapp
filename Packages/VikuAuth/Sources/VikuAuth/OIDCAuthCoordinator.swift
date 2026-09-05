import AppAuth
import VikunjaCore

#if canImport(UIKit)
import UIKit
#endif

/// Presents an OIDC provider's authorization page in `ASWebAuthenticationSession`
/// (via AppAuth) and returns the resulting authorization code. Never contacts
/// a token endpoint itself — Vikunja's backend does that exchange server-side
/// (see `AuthServiceProtocol.loginWithOIDC`), so `OIDServiceConfiguration`'s
/// required `tokenEndpoint` is filled with a value that's never dereferenced.
@MainActor
public final class OIDCAuthCoordinator: OIDCAuthenticating {
    #if canImport(UIKit)
    private var currentSession: OIDExternalUserAgentSession?
    #endif

    public init() {}

    public func authenticate(provider: OIDCProvider, redirectURI: URL) async throws -> String {
        #if canImport(UIKit)
        guard let presentingViewController = Self.foregroundPresentingViewController() else {
            throw OIDCAuthError.noPresentingViewController
        }
        guard let agent = OIDExternalUserAgentIOS(presenting: presentingViewController) else {
            throw OIDCAuthError.presentationUnavailable
        }

        let request = Self.makeAuthorizationRequest(provider: provider, redirectURI: redirectURI)

        return try await withCheckedThrowingContinuation { continuation in
            currentSession = OIDAuthorizationService.present(
                request,
                externalUserAgent: agent,
            ) { [weak self] response, error in
                self?.currentSession = nil
                if let code = response?.authorizationCode {
                    continuation.resume(returning: code)
                } else if Self.isUserCanceled(error) {
                    continuation.resume(throwing: OIDCAuthError.canceled)
                } else {
                    continuation.resume(throwing: error ?? OIDCAuthError.missingAuthorizationCode)
                }
            }
        }
        #else
        throw OIDCAuthError.unsupportedPlatform
        #endif
    }

    /// Cancels an in-flight authentication, if any — e.g. the presenting
    /// screen was dismissed before the user finished.
    public func cancel() {
        #if canImport(UIKit)
        currentSession?.cancel()
        currentSession = nil
        #endif
    }

    #if canImport(UIKit)
    private static func foregroundPresentingViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }?
            .rootViewController
    }
    #endif

    /// Whether `error` is AppAuth's own "user tapped Cancel in the browser
    /// session" signal, as opposed to a real failure (network, malformed
    /// response, the provider itself rejecting the request).
    nonisolated static func isUserCanceled(_ error: Error?) -> Bool {
        guard let error = error as? NSError else { return false }
        return error.domain == OIDGeneralErrorDomain
            && error.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue
    }

    /// Pulled out of `authenticate` so it's testable without UIKit —
    /// `OIDAuthorizationRequest`/`OIDServiceConfiguration` come from
    /// `AppAuthCore`, which has no platform gating.
    nonisolated static func makeAuthorizationRequest(provider: OIDCProvider, redirectURI: URL) -> OIDAuthorizationRequest {
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: provider.authURL,
            tokenEndpoint: provider.authURL,
        )
        return OIDAuthorizationRequest(
            configuration: configuration,
            clientId: provider.clientID,
            scopes: provider.scope.split(separator: " ").map(String.init),
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil,
        )
    }
}
