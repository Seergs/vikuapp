#if DEBUG
import Foundation
import VikunjaCore

nonisolated enum UITestFixtureError: Error {
    case unsupported(String)
}

/// Minimal auxiliary catalogs for the fixture. Unimplemented commands fail
/// explicitly; no method can fall back to a live network adapter.
actor UITestAuxiliaryRepository: AuthServiceProtocol, LabelRepositoryProtocol, UserRepositoryProtocol,
    TaskRelationRepositoryProtocol,
    TaskCommentRepositoryProtocol, TaskAttachmentRepositoryProtocol, BucketRepositoryProtocol,
    FilterRepositoryProtocol, WebhookRepositoryProtocol {
    func login(_ credentials: LoginCredentials) async throws -> AuthSession {
        throw UITestFixtureError.unsupported("login")
    }

    func loginWithAPIToken(_ token: String) async throws -> AuthSession {
        throw UITestFixtureError.unsupported("loginWithAPIToken")
    }

    func loginWithOIDC(provider: OIDCProvider, code: String, redirectURI: URL) async throws -> AuthSession {
        throw UITestFixtureError.unsupported("loginWithOIDC")
    }

    func logout() async {
        ()
    }

    func fetchLabels() async throws -> [Label] {
        [UITestFixtures.navigationLabel]
    }

    func create(_ label: Label) async throws -> Label {
        throw UITestFixtureError.unsupported("create")
    }

    func update(_ label: Label) async throws -> Label {
        throw UITestFixtureError.unsupported("update")
    }

    func delete(id: EntityID) async throws {
        throw UITestFixtureError.unsupported("delete")
    }

    func addLabel(_ labelID: EntityID, toTask taskID: EntityID) async throws {
        throw UITestFixtureError.unsupported("addLabel")
    }

    func removeLabel(_ labelID: EntityID, fromTask taskID: EntityID) async throws {
        throw UITestFixtureError.unsupported("removeLabel")
    }

    func fetchCurrentUser() async throws -> User {
        User(id: 1, username: "uitester", defaultProjectID: 1, quickAddMagicMode: .disabled)
    }

    func updateQuickAddMagicMode(_ mode: QuickAddMagicMode) async throws -> User {
        throw UITestFixtureError.unsupported("updateQuickAddMagicMode")
    }

    func updateDefaultProject(id: Int?) async throws -> User {
        throw UITestFixtureError.unsupported("updateDefaultProject")
    }

    func updateOverdueTasksRemindersTime(_ time: String) async throws -> User {
        throw UITestFixtureError.unsupported("updateOverdueTasksRemindersTime")
    }

    func addRelation(kind: RelationKind, otherTaskID: EntityID, toTask taskID: EntityID) async throws {
        throw UITestFixtureError.unsupported("addRelation")
    }

    func removeRelation(kind: RelationKind, otherTaskID: EntityID, fromTask taskID: EntityID) async throws {
        throw UITestFixtureError.unsupported("removeRelation")
    }

    func fetchComments(taskID: EntityID) async throws -> [TaskComment] {
        []
    }

    func addComment(_ text: String, toTask taskID: EntityID) async throws -> TaskComment {
        throw UITestFixtureError.unsupported("addComment")
    }

    func updateComment(_ commentID: EntityID, text: String, onTask taskID: EntityID) async throws -> TaskComment {
        throw UITestFixtureError.unsupported("updateComment")
    }

    func deleteComment(_ commentID: EntityID, fromTask taskID: EntityID) async throws {
        throw UITestFixtureError.unsupported("deleteComment")
    }

    func cachedAttachmentSnapshot(taskID: Int) async throws -> TaskAttachmentSnapshot? {
        nil
    }

    func fetchAttachments(taskID: Int) async throws -> [TaskAttachment] {
        []
    }

    func uploadAttachment(
        data: Data,
        fileName: String,
        mimeType: String,
        toTask taskID: Int,
    ) async throws -> [TaskAttachment] {
        throw UITestFixtureError.unsupported("uploadAttachment")
    }

    func downloadAttachment(
        _ id: Int,
        fromTask taskID: Int,
        previewSize: AttachmentPreviewSize?,
    ) async throws -> Data {
        throw UITestFixtureError.unsupported("downloadAttachment")
    }

    func deleteAttachment(_ id: Int, fromTask taskID: Int) async throws {
        throw UITestFixtureError.unsupported("deleteAttachment")
    }

    func setTaskPosition(taskID: Int, viewID: Int, position: Double) async throws -> TaskViewPosition {
        throw UITestFixtureError.unsupported("setTaskPosition")
    }

    func downloadBoard(projectID: Int, viewID: Int?) async throws -> KanbanDownload {
        throw UITestFixtureError.unsupported("downloadBoard")
    }

    func fetchBuckets(projectID: Int) async throws -> [KanbanBucket] {
        []
    }

    func moveTask(taskID: Int, toBucketID: Int, projectID: Int, viewID: Int?) async throws -> VikunjaTask {
        throw UITestFixtureError.unsupported("moveTask")
    }

    func createTask(_ task: VikunjaTask, bucketID: Int, projectID: Int) async throws -> VikunjaTask {
        throw UITestFixtureError.unsupported("createTask")
    }

    func fetchFilter(id: Int) async throws -> SavedFilterDetail {
        throw UITestFixtureError.unsupported("fetchFilter")
    }

    func renameFilter(id: Int, title: String) async throws -> SavedFilterDetail {
        throw UITestFixtureError.unsupported("renameFilter")
    }

    func deleteFilter(id: Int) async throws {
        throw UITestFixtureError.unsupported("deleteFilter")
    }

    func fetchWebhooks(projectID: Int) async throws -> [Webhook] {
        []
    }

    func createWebhook(projectID: Int, targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        throw UITestFixtureError.unsupported("createWebhook")
    }

    func updateWebhook(projectID: Int, _ webhook: Webhook) async throws -> Webhook {
        throw UITestFixtureError.unsupported("updateWebhook")
    }

    func deleteWebhook(projectID: Int, webhookID: Int) async throws {
        throw UITestFixtureError.unsupported("deleteWebhook")
    }

    func fetchAvailableEvents() async throws -> [WebhookEvent] {
        []
    }

    func fetchUserWebhooks() async throws -> [Webhook] {
        []
    }

    func createUserWebhook(targetURL: URL, events: [WebhookEvent], secret: String?) async throws -> Webhook {
        throw UITestFixtureError.unsupported("createUserWebhook")
    }

    func updateUserWebhook(_ webhook: Webhook) async throws -> Webhook {
        throw UITestFixtureError.unsupported("updateUserWebhook")
    }

    func deleteUserWebhook(webhookID: Int) async throws {
        throw UITestFixtureError.unsupported("deleteUserWebhook")
    }

    func fetchAvailableUserEvents() async throws -> [WebhookEvent] {
        []
    }
}
#endif
