import AppAuth
import Foundation
import Testing
@testable import VikuAuth
import VikunjaCore

struct OIDCAuthCoordinatorTests {
    private let provider = OIDCProvider(
        key: "authentik",
        name: "Authentik",
        authURL: URL(string: "https://auth.example.com/application/o/authorize/")!,
        clientID: "vikunja-client-id",
        scope: "openid email profile",
    )

    @Test
    func `builds an authorization request from the provider's config`() throws {
        let redirectURI = try #require(URL(string: "viku://oidc-callback"))

        let request = OIDCAuthCoordinator.makeAuthorizationRequest(provider: provider, redirectURI: redirectURI)

        #expect(request.configuration.authorizationEndpoint == provider.authURL)
        #expect(request.clientID == provider.clientID)
        #expect(request.scope == provider.scope)
        #expect(request.redirectURL == redirectURI)
        #expect(request.responseType == OIDResponseTypeCode)
    }

    @Test
    func `recognizes appauth's user canceled error`() {
        let error = NSError(domain: OIDGeneralErrorDomain, code: OIDErrorCode.userCanceledAuthorizationFlow.rawValue)

        #expect(OIDCAuthCoordinator.isUserCanceled(error) == true)
    }

    @Test
    func `does not treat other appauth errors as canceled`() {
        let error = NSError(domain: OIDGeneralErrorDomain, code: OIDErrorCode.networkError.rawValue)

        #expect(OIDCAuthCoordinator.isUserCanceled(error) == false)
    }

    @Test
    func `does not treat A nil error as canceled`() {
        #expect(OIDCAuthCoordinator.isUserCanceled(nil) == false)
    }
}
