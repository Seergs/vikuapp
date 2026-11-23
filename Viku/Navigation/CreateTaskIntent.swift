import AppIntents
import Foundation
import VikunjaCore

struct CreateTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description = IntentDescription("Adds a task to your default project in Viku.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Task Title", requestValueDialog: "What would you like to add?")
    var taskTitle: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$taskTitle) to the default project")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = AppContainer.launchContainer
        do {
            guard let account = try await container.accountStore.activeAccount() else {
                throw Failure.noAccount
            }
            let saved = try await container.createTaskFromSiri(title: taskTitle, account: account)
            let title = saved.taskTitle
            let project = saved.projectTitle
            if saved.isAwaitingConnectivity {
                return .result(dialog: "I added “\(title)” to \(project). It will sync when you're back online.")
            }
            return .result(dialog: "I added “\(title)” to \(project).")
        } catch DefaultProjectTaskCreator.Failure.emptyTitle {
            throw $taskTitle.needsValueError("What would you like to add?")
        } catch DefaultProjectTaskCreator.Failure.missingDefaultProject {
            throw Failure.missingDefaultProject
        } catch DefaultProjectTaskCreator.Failure.unavailableDefaultProject {
            throw Failure.unavailableDefaultProject
        } catch let error as Failure {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.saveFailed
        }
    }

    private enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case noAccount
        case missingDefaultProject
        case unavailableDefaultProject
        case saveFailed

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .noAccount: "Sign in to Viku before adding a task."
            case .missingDefaultProject: "Choose a default project in Viku before adding a task."
            case .unavailableDefaultProject: "Your default project is unavailable. Check it in Viku."
            case .saveFailed: "I couldn't add the task. Try again."
            }
        }
    }
}
