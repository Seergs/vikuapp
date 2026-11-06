import Foundation
import Observation
import VikunjaCore

/// Moves a list's overdue tasks to the end of today or tomorrow in one bulk
/// write. Owns the busy state and the feedback, like `TaskBulkSelection`, so
/// every list that shows an Overdue section behaves the same way.
///
/// The local repository accepts the write without waiting for the server, so
/// there is no loading indicator; the control is only disabled while the
/// local write runs. Upload failures surface in Pending Sync.
@MainActor
@Observable
public final class OverdueRescheduler {
    /// The only destinations offered: "today" and "tomorrow" both resolve to
    /// 11:59:59 PM of their day (see `DueDateShortcut.resolvedDate`).
    public static let shortcuts: [DueDateShortcut] = [.today, .tomorrow]

    public private(set) var isRescheduling = false
    /// Increments after each accepted reschedule. Views use it to animate
    /// only the row moves that reschedule causes.
    public private(set) var completedCount = 0

    private let toastPresenter: ToastPresenting

    public init(toastPresenter: ToastPresenting) {
        self.toastPresenter = toastPresenter
    }

    /// `perform` receives each task ID once and the resolved due date. A
    /// thrown error keeps every task where it was and reports one failure.
    public func reschedule(
        _ tasks: [VikunjaTask],
        to shortcut: DueDateShortcut,
        now: Date = Date(),
        calendar: Calendar = .current,
        perform: ([EntityID], Date) async throws -> Void,
    ) async {
        guard !isRescheduling, !Task.isCancelled, Self.shortcuts.contains(shortcut) else { return }
        var seen: Set<EntityID> = []
        let taskIDs = tasks.map(\.id).filter { seen.insert($0).inserted }
        guard !taskIDs.isEmpty, let dueDate = shortcut.resolvedDate(now: now, calendar: calendar) else { return }
        isRescheduling = true
        defer { isRescheduling = false }
        do {
            try await perform(taskIDs, dueDate)
            completedCount += 1
            let count = taskIDs.count
            let message = shortcut == .today
                ? String(localized: "\(count) tasks moved to today", bundle: .module)
                : String(localized: "\(count) tasks moved to tomorrow", bundle: .module)
            toastPresenter.show(message, style: .success)
        } catch is CancellationError {
            // Nothing was accepted; the tasks stay overdue and can be retried.
        } catch {
            toastPresenter.show(
                String(localized: "Couldn’t reschedule overdue tasks. Try again.", bundle: .module),
                style: .error,
            )
        }
    }
}
