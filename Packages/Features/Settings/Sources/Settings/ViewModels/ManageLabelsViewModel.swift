import Foundation
import Observation
import VikunjaCore
import VikuUI

/// Drives the "Manage Labels" screen: the account-wide list of labels, plus
/// create / rename+recolor / delete. Unlike `Features/Tasks`' label picker,
/// nothing here attaches a label to a task — this is label management on its
/// own. Every mutation is optimistic with rollback, matching the rest of the
/// app.
@MainActor
@Observable
public final class ManageLabelsViewModel {
    public private(set) var labels: [Label] = []
    public private(set) var loadState: ScreenLoadState<Void> = .idle

    public var isLoading: Bool {
        loadState == .loading
    }

    private let repository: LabelRepositoryProtocol
    private let toastPresenter: ToastPresenting

    public init(repository: LabelRepositoryProtocol, toastPresenter: ToastPresenting) {
        self.repository = repository
        self.toastPresenter = toastPresenter
    }

    public func load() async {
        if loadState != .loaded {
            loadState = .loading
        }
        do {
            labels = try await sorted(repository.fetchLabels())
            loadState = .loaded
        } catch let error as VikunjaError {
            loadState = .failure(error.displayMessage)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    public func createLabel(title: String, hexColor: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let created = try await repository.create(Label(id: 0, title: trimmed, hexColor: hexColor))
            labels = sorted(labels + [created])
            toastPresenter.show("Label created", style: .success)
        } catch let error as VikunjaError {
            toastPresenter.show(error.displayMessage, style: .error)
        } catch {
            toastPresenter.show(error.localizedDescription, style: .error)
        }
    }

    public func updateLabel(_ label: Label, title: String, hexColor: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = labels.firstIndex(where: { $0.id == label.id }) else { return }

        let previous = labels
        var edited = labels[index]
        edited.title = trimmed
        edited.hexColor = hexColor
        labels = sorted(labels.enumerated().map { $0.offset == index ? edited : $0.element })

        do {
            let saved = try await repository.update(edited)
            labels = sorted(labels.map { $0.id == saved.id ? saved : $0 })
            toastPresenter.show("Label updated", style: .success)
        } catch let error as VikunjaError {
            labels = previous
            toastPresenter.show(error.displayMessage, style: .error)
        } catch {
            labels = previous
            toastPresenter.show(error.localizedDescription, style: .error)
        }
    }

    public func deleteLabel(_ label: Label) async {
        let previous = labels
        labels.removeAll { $0.id == label.id }
        do {
            try await repository.delete(id: label.id)
            toastPresenter.show("Label deleted", style: .success)
        } catch let error as VikunjaError {
            labels = previous
            toastPresenter.show(error.displayMessage, style: .error)
        } catch {
            labels = previous
            toastPresenter.show(error.localizedDescription, style: .error)
        }
    }

    private func sorted(_ labels: [Label]) -> [Label] {
        labels.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
