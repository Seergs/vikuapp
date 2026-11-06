# Bulk completion fixture

`task-bulk-completion.json` reuses the existing `task.json` and
`task-no-due-date.json` task payloads inside the modern BulkTask response envelope.
Completion and update timestamps are set for the completion scenario. It is an
adapted contract fixture, not a new recording of a live bulk mutation.

The envelope was checked against Vikunja v2.8.0's handlers:

- v1: `pkg/web/handler/update.go` returns the updated BulkTask object, whose
  `pkg/models/bulk_task.go` implementation populates `tasks`.
- v2: `pkg/routes/api/v2/bulk_task.go` returns the same BulkTask body.

Source: https://github.com/go-vikunja/vikunja/tree/v2.8.0

Tests adapt this fixture for pending tasks and malformed responses. Full task
bodies exercise the existing TaskDTO and TaskMapper, including dates, labels,
relations, reminders, and the server update timestamp used by synchronization.

`TaskBulkUpdateTests` also adapts this fixture for bulk due-date updates by
setting each task's `due_date` (and the echoed `fields`/`values`) to the
requested date. The v2.8.0 handlers accept `due_date` as a bulk field and apply
it through the same `updateTasks` path as `done`.
