import Foundation
import Observation
import VikunjaCore

/// Presentation bridge for one account's durable shared setting. Persistence
/// and synchronization belong to the injected repository, never UserDefaults.
@Observable
@MainActor
final class QuickAddSyntaxCenter: QuickAddSyntaxStore {
    private(set) var syntax: QuickAddSyntax?
    private(set) var hasKnownMode = false
    private(set) var syncStatus: SyncItemStatus?
    private(set) var failureMessage: String?
    private let repository: QuickAddSettingsRepositoryProtocol
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    private var generation = 0
    private var pendingWrites = 0
    private var unpersistedMode: QuickAddMagicMode?

    init(repository: QuickAddSettingsRepositoryProtocol) {
        self.repository = repository
        self.observationTask = Task { [weak self, repository] in
            do {
                for try await _ in await repository.observeSettings() {
                    guard let self else { return }
                    let observedGeneration = generation
                    let settings = try await repository.settings()
                    if pendingWrites == 0, generation == observedGeneration {
                        apply(settings)
                    }
                }
            } catch {
                self?.failureMessage = (error as? VikunjaError ?? .network(String(describing: error))).displayMessage
            }
        }
    }

    deinit { observationTask?.cancel() }

    func setSyntax(_ syntax: QuickAddSyntax?) {
        self.syntax = syntax
        hasKnownMode = true
        syncStatus = .pending
        failureMessage = nil
        let mode = QuickAddMagicMode(syntax: syntax)
        generation += 1
        let currentGeneration = generation
        pendingWrites += 1
        let previous = writeTask
        writeTask = Task { [self] in
            // Serialize local transactions without delaying the selector or
            // awaiting any network work. Rapid selections persist in order.
            await previous?.value
            defer { pendingWrites -= 1 }
            do {
                try await repository.setMode(mode)
                guard generation == currentGeneration else { return }
                unpersistedMode = nil
                let settings = try await repository.settings()
                guard generation == currentGeneration else { return }
                apply(settings)
            } catch {
                guard generation == currentGeneration else { return }
                unpersistedMode = mode
                syncStatus = .failed
                failureMessage = (error as? VikunjaError ?? .network(String(describing: error))).displayMessage
            }
        }
    }

    func retrySync() {
        if let unpersistedMode {
            setSyntax(unpersistedMode.syntax)
        } else {
            Task { await repository.retrySync() }
        }
    }

    private func apply(_ settings: QuickAddMagicSettings) {
        guard unpersistedMode == nil else { return }
        hasKnownMode = settings.mode != nil
        syntax = settings.mode?.syntax
        syncStatus = settings.syncStatus
        failureMessage = settings.failureMessage
    }
}
