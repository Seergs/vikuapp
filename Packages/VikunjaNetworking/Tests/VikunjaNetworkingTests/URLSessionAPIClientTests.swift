import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

/// MockURLProtocol uses static state shared across requests, so this suite runs
/// serialized to avoid clobbering itself with tests running in parallel.
@Suite(.serialized)
struct URLSessionAPIClientTests {
    @Test
    func `decodes successful response`() async throws {
        let (session, _) = MockURLProtocol.makeSession(statusCode: 200, body: #"{"version":"0.24.6"}"#)
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)

        let info: ServerInfoDTO = try await client.send(VikunjaEndpoints.info())

        #expect(info.version == "0.24.6")
    }

    @Test
    func `maps unauthorized status to domain error`() async throws {
        let (session, _) = MockURLProtocol.makeSession(statusCode: 401, body: "")
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)

        await #expect(throws: VikunjaError.unauthorized) {
            let _: ServerInfoDTO = try await client.send(VikunjaEndpoints.info())
        }
    }

    @Test
    func `attaches bearer token from provider`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: #"{"version":"0.24.6"}"#)
        let client = try URLSessionAPIClient(
            baseURL: #require(URL(string: "https://vikunja.example.com")),
            session: session,
            authTokenProvider: { "test-token" },
        )

        let _: ServerInfoDTO = try await client.send(VikunjaEndpoints.info())

        #expect(await capture.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    // `VikunjaTaskRepository.update(_:)`'s safe-update behavior is tested
    // here rather than in its own suite: it's driven by the same
    // `MockURLProtocol` shared static state, and `.serialized` only
    // serializes tests *within* one suite — a second suite touching that
    // state runs concurrently with this one by default and corrupts it.
    @Test
    func `update fetches the current task first then sends A merged body`() async throws {
        let getResponse = #"""
        {
          "id": 1, "title": "Buy coffee", "description": "Whole beans", "done": false,
          "due_date": "2026-08-30T00:00:00Z", "priority": 3, "project_id": 4,
          "percent_done": 0.5, "hex_color": "00ff00", "is_favorite": true,
          "repeat_after": 604800, "repeat_mode": 1, "cover_image_attachment_id": 42
        }
        """#
        // Simulates Vikunja's real behavior: the update response doesn't
        // echo every field back (no percent_done/hex_color/... here) — that
        // asymmetry is exactly why `update(_:)` must merge onto a prior GET
        // rather than trust this response to carry everything.
        let postResponse = #"""
        {
          "id": 1, "title": "Buy coffee", "description": "Whole beans", "done": true,
          "due_date": "2026-08-30T00:00:00Z", "priority": 3, "project_id": 4
        }
        """#
        let (session, capture) = MockURLProtocol.makeSession(responses: [
            (200, getResponse),
            (200, postResponse),
        ])
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaTaskRepository(client: client)

        let updated = try await repository.update(
            VikunjaTask(
                id: 1,
                title: "Buy coffee",
                description: "Whole beans",
                isDone: true,
                priority: .high,
                projectID: 4,
            ),
        )

        #expect(updated.isDone == true)

        let requests = await capture.requests
        #expect(requests.count == 2)
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[0].url?.path == "/api/v1/tasks/1")
        #expect(requests[1].httpMethod == "POST")
        #expect(requests[1].url?.path == "/api/v1/tasks/1")

        let sentBody = try #require(requests[1].httpBody)
        let sentJSON = try #require(JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
        #expect(sentJSON["done"] as? Bool == true)
        #expect(sentJSON["percent_done"] as? Double == 0.5)
        #expect(sentJSON["hex_color"] as? String == "00ff00")
        #expect(sentJSON["is_favorite"] as? Bool == true)
        #expect(sentJSON["repeat_after"] as? Int == 604_800)
        #expect(sentJSON["repeat_mode"] as? Int == 1)
        #expect(sentJSON["cover_image_attachment_id"] as? Int == 42)
    }

    // `VikunjaLabelRepository` is tested here rather than in its own suite
    // for the same reason as `VikunjaTaskRepository.update(_:)` above: it
    // shares `MockURLProtocol`'s static state with this suite, and only
    // tests *within* one `.serialized` suite are guaranteed not to run
    // concurrently with each other.

    @Test
    func `fetch labels decodes the label list`() async throws {
        let (session, _) = MockURLProtocol.makeSession(
            statusCode: 200,
            body: #"[{"id":10,"title":"home","hex_color":"ff00ff"}]"#,
        )
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaLabelRepository(client: client)

        let labels = try await repository.fetchLabels()

        #expect(labels == [Label(id: 10, title: "home", hexColor: "ff00ff")])
    }

    @Test
    func `create label PU ts to the labels endpoint`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(
            statusCode: 200,
            body: #"{"id":11,"title":"work","hex_color":"00ff00"}"#,
        )
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaLabelRepository(client: client)

        let created = try await repository.create(Label(id: 0, title: "work", hexColor: "00ff00"))

        #expect(created == Label(id: 11, title: "work", hexColor: "00ff00"))
        let request = try #require(await capture.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/v1/labels")
    }

    @Test
    func `delete label DELET es the label by ID`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: "")
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaLabelRepository(client: client)

        try await repository.delete(id: 11)

        let request = try #require(await capture.lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/api/v1/labels/11")
    }

    @Test
    func `add label PU ts the label ID onto the tasks labels endpoint`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: "")
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaLabelRepository(client: client)

        try await repository.addLabel(10, toTask: 1)

        let request = try #require(await capture.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/v1/tasks/1/labels")
        let sentBody = try #require(request.httpBody)
        let sentJSON = try #require(JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
        #expect(sentJSON["label_id"] as? Int == 10)
    }

    @Test
    func `remove label DELET es the label from the task`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: "")
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaLabelRepository(client: client)

        try await repository.removeLabel(10, fromTask: 1)

        let request = try #require(await capture.lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/api/v1/tasks/1/labels/10")
    }

    // `VikunjaTaskRelationRepository` is tested here for the same reason as
    // `VikunjaLabelRepository` above.

    @Test
    func `add relation PU ts the relation kind and other task ID onto the tasks relations endpoint`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: "")
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaTaskRelationRepository(client: client)

        try await repository.addRelation(kind: .subtask, otherTaskID: 2, toTask: 1)

        let request = try #require(await capture.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/v1/tasks/1/relations")
        let sentBody = try #require(request.httpBody)
        let sentJSON = try #require(JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
        #expect(sentJSON["relation_kind"] as? String == "subtask")
        #expect(sentJSON["other_task_id"] as? Int == 2)
    }

    @Test
    func `remove relation DELET es the relation by kind and other task ID`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: "")
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaTaskRelationRepository(client: client)

        try await repository.removeRelation(kind: .blocked, otherTaskID: 3, fromTask: 1)

        let request = try #require(await capture.lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/api/v1/tasks/1/relations/blocked/3")
    }

    @Test
    func `fetch current user GE ts the user and reads the nested default project`() async throws {
        let body = #"""
        {"id": 3, "username": "qa-user", "name": "QA User",
         "settings": {"default_project_id": 6, "week_start": 0}}
        """#
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: body)
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaUserRepository(client: client)

        let user = try await repository.fetchCurrentUser()

        let request = try #require(await capture.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/v1/user")
        #expect(user.defaultProjectID == 6)
    }

    @Test
    func `delete project DELET es the project by ID`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: "")
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaProjectRepository(client: client)

        try await repository.delete(id: 7)

        let request = try #require(await capture.lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/api/v1/projects/7")
    }

    @Test
    func `data returns the response body untouched`() async throws {
        // A body that is not JSON — `data(_:)` must hand it back as-is
        // rather than trying to decode it.
        let raw = "%PDF-1.4 not json at all"
        let (session, _) = MockURLProtocol.makeSession(statusCode: 200, body: raw)
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)

        let received = try await client.data(Endpoint(path: "/api/v1/tasks/1/attachments/2"))

        #expect(received == Data(raw.utf8))
    }

    @Test
    func `data maps unauthorized status to domain error`() async throws {
        let (session, _) = MockURLProtocol.makeSession(statusCode: 401, body: "")
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)

        await #expect(throws: VikunjaError.unauthorized) {
            _ = try await client.data(Endpoint(path: "/api/v1/tasks/1/attachments/2"))
        }
    }

    // `VikunjaTaskAttachmentRepository` is tested here for the same reason as
    // `VikunjaLabelRepository` above — it shares `MockURLProtocol`'s static
    // state with this `.serialized` suite.

    @Test
    func `fetch attachments GE ts the tasks attachments endpoint`() async throws {
        let body = #"""
        [{"id":1,"task_id":42,"created_by":{"id":7,"username":"alex"},
          "file":{"id":100,"name":"a.pdf","mime":"application/pdf","size":10,"created":"2026-08-20T09:00:00Z"},
          "created":"2026-08-20T09:00:00Z"}]
        """#
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: body)
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaTaskAttachmentRepository(client: client)

        let attachments = try await repository.fetchAttachments(taskID: 42)

        #expect(attachments.map(\.fileName) == ["a.pdf"])
        let request = try #require(await capture.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/v1/tasks/42/attachments")
    }

    @Test
    func `upload attachment PU ts A multipart body to the attachments endpoint`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(
            statusCode: 200,
            // swiftlint:disable:next line_length
            body: #"{"errors":[],"success":[{"id":3,"task_id":42,"created_by":{"id":7,"username":"alex"},"file":{"id":102,"name":"notes.txt","mime":"text/plain","size":2,"created":"2026-08-22T10:15:00Z"},"created":"2026-08-22T10:15:00Z"}]}"#,
        )
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaTaskAttachmentRepository(client: client)

        let created = try await repository.uploadAttachment(
            data: Data("hi".utf8), fileName: "notes.txt", mimeType: "text/plain", toTask: 42,
        )

        #expect(created.map(\.id) == [3])
        let request = try #require(await capture.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/v1/tasks/42/attachments")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let bodyData = try #require(request.httpBody)
        let sentBody = try #require(String(data: bodyData, encoding: .utf8))
        #expect(sentBody.contains(#"name="files"; filename="notes.txt""#))
        #expect(sentBody.contains("hi"))
    }

    @Test
    func `download attachment GE ts the raw bytes with the preview size query`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: "RAWBYTES")
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaTaskAttachmentRepository(client: client)

        let data = try await repository.downloadAttachment(2, fromTask: 42, previewSize: .sm)

        #expect(data == Data("RAWBYTES".utf8))
        let request = try #require(await capture.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/v1/tasks/42/attachments/2")
        #expect(request.url?.query == "preview_size=sm")
    }

    @Test
    func `delete attachment DELET es the attachment by ID`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: "")
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)
        let repository = VikunjaTaskAttachmentRepository(client: client)

        try await repository.deleteAttachment(2, fromTask: 42)

        let request = try #require(await capture.lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/api/v1/tasks/42/attachments/2")
    }

    @Test
    func `sends the endpoints content type for A multipart body`() async throws {
        var form = MultipartFormData(boundary: "TESTBOUNDARY")
        form.addFile(name: "files", fileName: "a.txt", mimeType: "text/plain", data: Data("hi".utf8))
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: "{}")
        let client = try URLSessionAPIClient(baseURL: #require(URL(string: "https://vikunja.example.com")), session: session)

        try await client.send(Endpoint.multipart(path: "/api/v1/tasks/1/attachments", method: .put, form: form))

        let request = try #require(await capture.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=TESTBOUNDARY")
        let sentBody = try #require(request.httpBody)
        #expect(String(data: sentBody, encoding: .utf8)?.contains(#"name="files"; filename="a.txt""#) == true)
    }

    // `VikunjaAuthService` and `PasswordSessionRefresher` are tested here for
    // the same reason as `VikunjaLabelRepository` above — they share
    // `MockURLProtocol`'s static state with this `.serialized` suite.

    @Test
    func `login with no refresh cookie stores A credential with no refresh token`() async throws {
        let (session, _) = MockURLProtocol.makeSession(statusCode: 200, body: #"{"token":"pre-2.0-jwt"}"#)
        let baseURL = try #require(URL(string: "https://vikunja.example.com"))
        let apiClient = URLSessionAPIClient(baseURL: baseURL, session: session)
        let service = VikunjaAuthService(client: apiClient, baseURL: baseURL)

        let authSession = try await service.login(LoginCredentials(username: "sergio", password: "hunter2"))

        let credential = try JSONDecoder().decode(PasswordSessionCredential.self, from: Data(authSession.token.utf8))
        #expect(credential.accessToken == "pre-2.0-jwt")
        #expect(credential.refreshToken == nil)
    }

    @Test
    func `login with A refresh cookie captures the refresh token`() async throws {
        let (session, _) = MockURLProtocol.makeSession(
            statusCode: 200,
            body: #"{"token":"v2-jwt"}"#,
            headers: ["Set-Cookie": "vikunja_refresh_token=refresh-abc; Path=/api/v1/user/token/refresh; HttpOnly"],
        )
        let baseURL = try #require(URL(string: "https://vikunja.example.com"))
        let apiClient = URLSessionAPIClient(baseURL: baseURL, session: session)
        let service = VikunjaAuthService(client: apiClient, baseURL: baseURL)

        let authSession = try await service.login(LoginCredentials(username: "sergio", password: "hunter2"))

        let credential = try JSONDecoder().decode(PasswordSessionCredential.self, from: Data(authSession.token.utf8))
        #expect(credential.accessToken == "v2-jwt")
        #expect(credential.refreshToken == "refresh-abc")
    }

    @Test
    func `login with A 412 response surfaces as totpRequired`() async throws {
        let (session, _) = MockURLProtocol.makeSession(statusCode: 412, body: #"{"message":"Invalid totp passcode."}"#)
        let baseURL = try #require(URL(string: "https://vikunja.example.com"))
        let apiClient = URLSessionAPIClient(baseURL: baseURL, session: session)
        let service = VikunjaAuthService(client: apiClient, baseURL: baseURL)

        await #expect(throws: VikunjaError.totpRequired) {
            _ = try await service.login(LoginCredentials(username: "sergio", password: "hunter2"))
        }
    }

    private static let oidcProvider = OIDCProvider(
        key: "authentik",
        name: "Authentik",
        authURL: URL(string: "https://auth.example.com/o/authorize/")!,
        clientID: "vikunja-client-id",
        scope: "openid email profile",
    )

    @Test
    func `login with oidc PO STs the provider key code scope and redirect url`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: #"{"token":"oidc-jwt"}"#)
        let baseURL = try #require(URL(string: "https://vikunja.example.com"))
        let apiClient = URLSessionAPIClient(baseURL: baseURL, session: session)
        let service = VikunjaAuthService(client: apiClient, baseURL: baseURL)
        let redirectURI = try #require(URL(string: "viku://oidc-callback"))

        _ = try await service.loginWithOIDC(provider: Self.oidcProvider, code: "auth-code", redirectURI: redirectURI)

        let request = await capture.lastRequest
        #expect(request?.url?.path == "/api/v1/auth/openid/authentik/callback")
        let sentBody = try #require(request?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
        #expect(json["code"] as? String == "auth-code")
        #expect(json["scope"] as? String == "openid email profile")
        #expect(json["redirect_url"] as? String == "viku://oidc-callback")
    }

    @Test
    func `login with oidc and no refresh cookie stores A credential with no refresh token`() async throws {
        let (session, _) = MockURLProtocol.makeSession(statusCode: 200, body: #"{"token":"oidc-jwt"}"#)
        let baseURL = try #require(URL(string: "https://vikunja.example.com"))
        let apiClient = URLSessionAPIClient(baseURL: baseURL, session: session)
        let service = VikunjaAuthService(client: apiClient, baseURL: baseURL)
        let redirectURI = try #require(URL(string: "viku://oidc-callback"))

        let authSession = try await service.loginWithOIDC(
            provider: Self.oidcProvider,
            code: "auth-code",
            redirectURI: redirectURI,
        )

        let credential = try JSONDecoder().decode(PasswordSessionCredential.self, from: Data(authSession.token.utf8))
        #expect(credential.accessToken == "oidc-jwt")
        #expect(credential.refreshToken == nil)
    }

    @Test
    func `login with oidc and A refresh cookie captures the refresh token`() async throws {
        let (session, _) = MockURLProtocol.makeSession(
            statusCode: 200,
            body: #"{"token":"oidc-jwt"}"#,
            headers: ["Set-Cookie": "vikunja_refresh_token=refresh-abc; Path=/api/v1/user/token/refresh; HttpOnly"],
        )
        let baseURL = try #require(URL(string: "https://vikunja.example.com"))
        let apiClient = URLSessionAPIClient(baseURL: baseURL, session: session)
        let service = VikunjaAuthService(client: apiClient, baseURL: baseURL)
        let redirectURI = try #require(URL(string: "viku://oidc-callback"))

        let authSession = try await service.loginWithOIDC(
            provider: Self.oidcProvider,
            code: "auth-code",
            redirectURI: redirectURI,
        )

        let credential = try JSONDecoder().decode(PasswordSessionCredential.self, from: Data(authSession.token.utf8))
        #expect(credential.accessToken == "oidc-jwt")
        #expect(credential.refreshToken == "refresh-abc")
    }

    @Test
    func `password refresher passes an api token account through with no refresh attempt`() async throws {
        let account = try PasswordRefresherFixtures.makeAccount(authMethod: .apiToken)
        let store = PasswordRefresherFixtures.FakeAccountStore(tokens: [account.id: "raw-api-token"])
        let refresher = PasswordSessionRefresher(accountStore: store)

        let token = await refresher.validToken(for: account)

        #expect(token == "raw-api-token")
    }

    @Test
    func `password refresher returns A not yet expired token with no network call`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: #"{"token":"new"}"#)
        let jwt = PasswordRefresherFixtures.makeJWT(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let account = try PasswordRefresherFixtures.makeAccount(authMethod: .password)
        let store = try PasswordRefresherFixtures.FakeAccountStore(
            tokens: [account.id: PasswordRefresherFixtures.encode(accessToken: jwt, refreshToken: nil)],
        )
        let refresher = PasswordSessionRefresher(accountStore: store, session: session)

        let token = await refresher.validToken(for: account)

        #expect(token == jwt)
        #expect(await capture.requests.isEmpty)
    }

    @Test
    func `password refresher also renews an expiring oidc account's token`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: #"{"token":"renewed-jwt"}"#)
        let expiringJWT = PasswordRefresherFixtures.makeJWT(exp: Date().addingTimeInterval(10).timeIntervalSince1970)
        let account = try PasswordRefresherFixtures.makeAccount(authMethod: .oidc)
        let store = try PasswordRefresherFixtures.FakeAccountStore(
            tokens: [account.id: PasswordRefresherFixtures.encode(accessToken: expiringJWT, refreshToken: nil)],
        )
        let refresher = PasswordSessionRefresher(accountStore: store, session: session)

        let token = await refresher.validToken(for: account)

        #expect(token == "renewed-jwt")
        let request = try #require(await capture.lastRequest)
        #expect(request.url?.path == "/api/v1/user/token")
    }

    @Test
    func `password refresher renews an expiring token with no refresh token via the bearer endpoint`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: #"{"token":"renewed-jwt"}"#)
        let expiringJWT = PasswordRefresherFixtures.makeJWT(exp: Date().addingTimeInterval(10).timeIntervalSince1970)
        let account = try PasswordRefresherFixtures.makeAccount(authMethod: .password)
        let store = try PasswordRefresherFixtures.FakeAccountStore(
            tokens: [account.id: PasswordRefresherFixtures.encode(accessToken: expiringJWT, refreshToken: nil)],
        )
        let refresher = PasswordSessionRefresher(accountStore: store, session: session)

        let token = await refresher.validToken(for: account)

        #expect(token == "renewed-jwt")
        let request = try #require(await capture.lastRequest)
        #expect(request.url?.path == "/api/v1/user/token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(expiringJWT)")
        let updated = try await store.token(forAccountID: account.id)
        #expect(try PasswordRefresherFixtures.decode(updated).accessToken == "renewed-jwt")
    }

    @Test
    func `password refresher renews an expiring token with A refresh token via the cookie endpoint`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(
            statusCode: 200,
            body: #"{"token":"rotated-jwt"}"#,
            headers: ["Set-Cookie": "vikunja_refresh_token=rotated-refresh"],
        )
        let expiringJWT = PasswordRefresherFixtures.makeJWT(exp: Date().addingTimeInterval(10).timeIntervalSince1970)
        let account = try PasswordRefresherFixtures.makeAccount(authMethod: .password)
        let credential = try PasswordRefresherFixtures.encode(accessToken: expiringJWT, refreshToken: "old-refresh")
        let store = PasswordRefresherFixtures.FakeAccountStore(tokens: [account.id: credential])
        let refresher = PasswordSessionRefresher(accountStore: store, session: session)

        let token = await refresher.validToken(for: account)

        #expect(token == "rotated-jwt")
        let request = try #require(await capture.lastRequest)
        #expect(request.url?.path == "/api/v1/user/token/refresh")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "vikunja_refresh_token=old-refresh")
        let updated = try await store.token(forAccountID: account.id)
        let decoded = try PasswordRefresherFixtures.decode(updated)
        #expect(decoded.accessToken == "rotated-jwt")
        #expect(decoded.refreshToken == "rotated-refresh")
    }

    @Test
    func `password refresher single flights concurrent refreshes for the same account`() async throws {
        let (session, capture) = MockURLProtocol.makeSession(statusCode: 200, body: #"{"token":"renewed-jwt"}"#)
        let expiringJWT = PasswordRefresherFixtures.makeJWT(exp: Date().addingTimeInterval(10).timeIntervalSince1970)
        let account = try PasswordRefresherFixtures.makeAccount(authMethod: .password)
        let store = try PasswordRefresherFixtures.FakeAccountStore(
            tokens: [account.id: PasswordRefresherFixtures.encode(accessToken: expiringJWT, refreshToken: nil)],
        )
        let refresher = PasswordSessionRefresher(accountStore: store, session: session)

        async let first = refresher.validToken(for: account)
        async let second = refresher.validToken(for: account)
        async let third = refresher.validToken(for: account)
        let results = await [first, second, third]

        #expect(results.allSatisfy { $0 == "renewed-jwt" })
        #expect(await capture.requests.count == 1)
    }
}

/// Shared helpers for the `PasswordSessionRefresher` tests above.
private enum PasswordRefresherFixtures {
    static func makeAccount(authMethod: InstanceAccount.AuthMethod) throws -> InstanceAccount {
        try InstanceAccount(
            displayName: "Home",
            baseURL: #require(URL(string: "https://vikunja.example.com")),
            authMethod: authMethod,
        )
    }

    static func makeJWT(exp: Double) -> String {
        let header = base64URL(Data(#"{"alg":"HS256"}"#.utf8))
        let payload = base64URL(Data(#"{"exp":\#(exp)}"#.utf8))
        return "\(header).\(payload).signature"
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func encode(accessToken: String, refreshToken: String?) throws -> String {
        let credential = PasswordSessionCredential(accessToken: accessToken, refreshToken: refreshToken)
        let data = try JSONEncoder().encode(credential)
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decode(_ token: String?) throws -> PasswordSessionCredential {
        try JSONDecoder().decode(PasswordSessionCredential.self, from: Data((token ?? "").utf8))
    }

    actor FakeAccountStore: AccountStoreProtocol {
        private var tokens: [InstanceAccount.ID: String]

        init(tokens: [InstanceAccount.ID: String]) {
            self.tokens = tokens
        }

        func fetchAccounts() async throws -> [InstanceAccount] {
            []
        }

        func activeAccount() async throws -> InstanceAccount? {
            nil
        }

        func addAccount(_ account: InstanceAccount, token: String) async throws {
            tokens[account.id] = token
        }

        func updateAccount(_ account: InstanceAccount, token: String?) async throws {
            if let token {
                tokens[account.id] = token
            }
        }

        func removeAccount(id: InstanceAccount.ID) async throws {
            tokens[id] = nil
        }

        func setActiveAccount(id: InstanceAccount.ID) async throws {}

        func token(forAccountID id: InstanceAccount.ID) async throws -> String? {
            tokens[id]
        }
    }
}
