# Shared Quick Add Magic settings

The account setting is `settings.frontend_settings.quick_add_magic_mode` on
`GET /api/v1/user` and `GET /api/v2/user`. Values are `disabled`, `vikunja`, and
`todoist`. Absent/null frontend settings or an absent mode use `vikunja`, matching
the web default. An unrecognized mode cannot be silently mapped to a known one:
synchronization fails and preserves the previous local value. Before any valid
snapshot or explicit selection, the local state is unknown and parsing is off.

Contract references checked during implementation:

- [Current web settings and defaults](https://github.com/go-vikunja/vikunja/blob/main/frontend/src/helpers/userSettings.ts)
- [Current wire mode values](https://github.com/go-vikunja/vikunja/blob/main/frontend/src/modules/quickAddMagic/prefixes.ts)
- [0.24.6 web settings default](https://github.com/go-vikunja/vikunja/blob/v0.24.6/frontend/src/models/userSettings.ts)
- [Shared general-settings wire struct](https://github.com/go-vikunja/vikunja/blob/main/pkg/models/user_settings.go)

The networking repository reads current settings, changes only the nested mode,
writes general settings (v1 POST, v2 PUT), then refetches the user. All modeled
general fields and arbitrary frontend fields survive. Missing settings or a
malformed frontend object must not trigger a destructive replacement. The JSON
contract fixture extends the existing captured `user.json` with the frontend
fields above; it is not a newly captured server response.

`OfflineQuickAddSettingsRepository` persists a mode and revision per account in
SQLite. Each selection transaction also replaces that account's queued Magic
operation with a new queue identity. The durable queue survives process restarts
and consolidates multiple choices into the latest one. It is displayed and retried
through the existing Pending Sync tooling, with failure/retry on the Magic selection screen in Settings → This connection.
The selector has no synchronization or pending subtitle; the guides explain that
it uses the server setting.

The ordinary account worker synchronizes Magic independently of other phases.
Pending local intent uploads first; without pending intent the remote mode wins.
Queue identities and local revisions guard both successful and failed old replies.
A refresh never applies to a newer local selection. Cancellation leaves the choice
pending. Account reload stages a fresh remote setting and atomically discards local
intent only after the entire replacement download succeeds.

The observable app bridge is immutable with respect to account identity and is
shared by Settings, Search, and task creation. Local presentation writes are
serialized; all durable state and network replay live outside the bridge. Search
re-evaluates when the mode changes. Quick Add pins the mode once a title is entered
and releases it when cleared; this also covers related-task creation from task
detail. Editing an existing task title remains literal, as before.

The old global `quickAdd.syntax` UserDefaults preference is never read or uploaded.
There is no migration prompt, conflict choice, or separate device override. Notes
for TestFlight: Quick Add Magic now uses the Vikunja account setting; changes made
in the app also apply on the web and synchronize after offline use.

General-settings writes replace a complete object. Reading immediately before a
write avoids replaying stale offline snapshots, but the API offers no conditional
write in this flow: simultaneous settings writes from independent clients can
still race. This is an existing limitation of the general-settings endpoint.
