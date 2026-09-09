# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Native iOS SwiftUI client for [Vikunja](https://vikunja.io), the open-source
self-hosted task manager. Each user points the app at their own Vikunja instance
(their own URL, their own server version, their own enabled features), so the
architecture is built around isolating "talking to Vikunja's API" from everything
else, and around detecting server capabilities at runtime rather than assuming one
fixed API shape.

## Commands

Fastest iteration loop is building/testing the Swift packages directly (no
simulator boot required):

```sh
cd Packages/VikunjaCore && swift build && swift test
cd Packages/VikunjaNetworking && swift build && swift test
cd Packages/VikuAuth && swift build && swift test
cd Packages/VikuNavigation && swift build && swift test
cd Packages/VikuDesignSystem && swift build && swift test
cd Packages/Features/Onboarding && swift build && swift test
cd Packages/Features/Home && swift build && swift test
cd Packages/Features/Projects && swift build && swift test
cd Packages/Features/Tasks && swift build && swift test
cd Packages/Features/Settings && swift build && swift test
cd Packages/VikuWidgetKit && swift build && swift test
```

Run a single test (packages use swift-testing, not XCTest):

```sh
swift test --filter <SuiteName>          # whole suite
swift test --filter <SuiteName>/<testName>
```

Build the full app target (compiles both local packages and links them in):

```sh
xcodebuild -project Viku.xcodeproj -scheme Viku -destination 'generic/platform=iOS Simulator' build
```

List targets/schemes:

```sh
xcodebuild -list -project Viku.xcodeproj
```

## Architecture

Full design rationale (including the parts not built yet — see `ARCHITECTURE.md`'s
own "Next steps") lives in `ARCHITECTURE.md`. This section is the current,
code-derived summary.

MVVM with protocol-oriented layering, split across local Swift Packages under
`Packages/` and linked into the `Viku` Xcode app target as local package
dependencies (added via `XCLocalSwiftPackageReference` in `project.pbxproj`, the
same thing Xcode's "Add Local Package" does). The dependency direction is enforced
by the compiler, not just convention:

- **`VikunjaCore`** — pure Swift, no networking, no UI, no dependencies.
  - `Domain/` — domain models (`VikunjaTask`, `Project`, `User`, `Label`,
    `TaskRelation`, `RelationKind`, `TaskComment`, `InstanceAccount`,
    `InstanceURL`, `ToastStyle`). `InstanceAccount` holds
    id/displayName/baseURL/createdAt plus `authMethod: AuthMethod`
    (`.apiToken`/`.password`/`.oidc`) — which login method produced the
    credential stored (opaque, keyed by the account's `id`) behind
    `AccountStoreProtocol`, never the credential itself. `InstanceURL.normalize(_:)` turns a bare
    domain or full URL the user typed into the scheme+host `URL` the
    networking layer expects as `baseURL`. `TaskRelation` is a thin
    id/title/isDone/projectID summary (not a full recursive `VikunjaTask`) used
    for `VikunjaTask.subtasks`, `.dependsOn`, `.blocks`, and `.otherRelations`
    — Vikunja represents every relation the same way, as a "related task"
    keyed by relation kind. `RelationKind` is that key: `subtask`/`blocked`/
    `blocking` map onto the three named `VikunjaTask` fields (they get distinct
    UI — checkboxes, the "Blocked" banner); every other kind (`related`,
    `precedes`, `duplicateof`, ...) is carried generically in
    `VikunjaTask.otherRelations` (`[RelationKind: [TaskRelation]]`).
    `TaskComment` is id/comment/author/created/updated — a task's comment
    thread, kept separate from `VikunjaTask` itself since it's loaded and
    posted through its own endpoint. `TaskAttachment` is
    id/taskID/fileName/mimeType/sizeBytes/created/createdBy — one uploaded
    file's metadata (the bytes come from a separate download endpoint), kept
    separate from `VikunjaTask` for the same reason as `TaskComment`;
    `AttachmentPreviewSize` (`sm`/`md`/`lg`/`xl`) is the optional
    image-thumbnail rendition the download can ask for.
  - `Protocols/` — the contracts Features are meant to depend on
    (`TaskRepositoryProtocol`, `ProjectRepositoryProtocol`,
    `LabelRepositoryProtocol`, `TaskRelationRepositoryProtocol`,
    `TaskCommentRepositoryProtocol`, `TaskAttachmentRepositoryProtocol`,
    `AuthServiceProtocol`,
    `AccountStoreProtocol`, `InstanceClientFactoryProtocol`,
    `ToastPresenting`, `OIDCAuthenticating`).
    `AuthServiceProtocol` covers all three login methods —
    `login(_:)` (username/password, `LoginCredentials`), `loginWithAPIToken(_:)`,
    and `loginWithOIDC(provider:code:redirectURI:)` — every one returning an
    `AuthSession` whose `token` is an opaque, persisted-credential blob for
    password/OIDC (never the raw JWT; see `VikunjaNetworking`'s
    `PasswordSessionCredential`) or the API token string itself.
    `OIDCAuthenticating` is the one-method contract for driving a provider's
    login page in a system browser session (`VikuAuth`'s `OIDCAuthCoordinator`
    is the only implementation) — declared here rather than in `VikuAuth` so
    a Feature can pattern-match its `OIDCAuthError.canceled` case without
    importing `VikuAuth`, the same relationship `VikunjaError` has to
    `VikunjaNetworking`. `TaskRepositoryProtocol` and `ProjectRepositoryProtocol`
    now cover full CRUD; `TaskRepositoryProtocol` also has
    `searchTasks(query:)` (account-wide, not project-scoped — for the relation
    picker). `LabelRepositoryProtocol` covers label CRUD plus attach/detach
    against a task; `TaskRelationRepositoryProtocol` is just add/remove a
    relation of a given `RelationKind`; `TaskCommentRepositoryProtocol` is
    fetch/add/update/delete for one task's comments (only fetch and add are
    wired into `Features/Tasks` today — see below).
    `TaskAttachmentRepositoryProtocol` is fetch/upload/download/delete for one
    task's file attachments. `AccountStoreProtocol` is
    full multi-account CRUD (`fetchAccounts`/`addAccount`/`updateAccount`/
    `removeAccount`/`setActiveAccount`/`token(forAccountID:)`), not just a
    single saved connection.
  - `Capabilities/` — `VikunjaServerInfo`, `CapabilityProvider`, `VikunjaFeature`:
    the runtime feature-detection layer (see below). `VikunjaFeature.localAuth`/
    `.openIDConnect` gate the password/OIDC credential modes; `VikunjaServerInfo`
    carries `localAuthEnabled` and `oidcProviders: [OIDCProvider]`.
    `OIDCProvider` (key/name/authURL/clientID/scope) mirrors one entry of
    `/info`'s `auth.openid_connect.providers` — everything a client needs to
    build an OIDC authorization request itself, without a discovery document.
  - `Errors/` — `VikunjaError`, the domain-level error type everything surfaces,
    plus `VikunjaError+DisplayMessage.swift`: the single canonical user-facing
    copy for every case, shared by every screen (and by `ConnectionEditorCore`
    itself). Adding a case is a one-file edit here.
  - `Support/` — shared `@Observable`/plain collaborators that back more than
    one feature's view models, so recurring behavior lives here instead of
    being copied per screen. `ConnectionEditorCore` +
    `PasswordLoginCoordinator` (the add/edit-connection flow, shared by
    `Onboarding` and `Settings`). `AccountTaskLoader` — fetch every project
    then every project's tasks concurrently, drop a failing project, return
    `(tasks, projectsByID)`; used by the Today and Calendar screens.
    `TaskListMutator` — the optimistic-with-rollback task-list mutations
    (`persistToggleDone`, `delete`, `move`) with the success-toast wording and
    the "haptic on completion" policy in one place; every task-list view model
    (`TodayViewModel`, `CalendarViewModel`, `ProjectOverviewViewModel`,
    `SearchViewModel`) composes one. It takes an `errorMessage` closure for
    turning a thrown error into user copy; every feature passes the same
    `{ ($0 as? VikunjaError)?.displayMessage ?? $0.localizedDescription }`,
    routed through the canonical `VikunjaError.displayMessage`.

- **`VikunjaNetworking`** — the only module that knows Vikunja speaks HTTP/JSON.
  Depends on `VikunjaCore`.
  - `Client/` — generic transport: `APIClient` protocol, `Endpoint` struct
    (with an `Endpoint.encoding(path:method:body:)` helper that JSON-encodes a
    body, and `Endpoint.multipart(path:method:form:)` for a file upload —
    `Endpoint.contentType` overrides the default `application/json` so
    `MultipartFormData` can carry its boundary), and the concrete
    `URLSessionAPIClient` actor (maps HTTP status codes to `VikunjaError`).
    `APIClient.data(_:)` returns the response body untouched, for the one
    endpoint that serves raw bytes rather than JSON (an attachment download).
  - `Endpoints/VikunjaEndpoints.swift` — the single file that knows Vikunja's actual
    REST routes (`/api/v1/...`). This is where a real API change gets fixed.
    Covers `/info`, login (username/password and the OIDC callback exchange —
    `oidcCallback(providerKey:code:scope:redirectURL:)`,
    `POST /api/v1/auth/openid/{provider}/callback`, mirroring Vikunja's Go
    `openid.Callback` struct; `redirectURL` must exactly match the URI used in
    the authorization request that produced `code`, since Vikunja forwards it
    verbatim to the provider's token endpoint), full task + project CRUD (**create is `PUT`**, update
    is `POST` — Vikunja's convention, not a typo), label CRUD plus task/label
    association (`/tasks/{id}/labels`), task relation add/remove
    (`/tasks/{id}/relations`), task comment CRUD (`/tasks/{id}/comments`),
    task attachment list/upload/download/delete (`/tasks/{id}/attachments` —
    **upload is `PUT`** with a `multipart/form-data` body, field name `files`;
    download is a raw-bytes `GET` with an optional `?preview_size=`), and
    account-wide task search (`GET /api/v1/tasks?s=`
    — note `/tasks`, **not** the older `/tasks/all`; see the doc comment on
    `searchTasks` for the version nuance).
  - `DTOs/` — `Codable` structs mirroring the raw JSON, tolerant of optional/missing
    fields. Field names are best-effort and **must be verified against a live
    instance's swagger docs (`/api/v1/docs`)** before pointing this at a real server.
    `RelatedTaskDTO` mirrors one entry of `TaskDTO.relatedTasks` (JSON key
    `related_tasks`), a `[String: [RelatedTaskDTO]]` keyed by relation kind
    (`"subtask"`, `"blocked"`, `"blocking"`, ...). `LabelDTO`, `TaskLabelDTO`
    (attach-label body), `CreateTaskRelationDTO` (add-relation body),
    `CommentDTO` (a task comment; the body arrives as the rich-text editor's
    HTML — see `Mappers/` below). `TaskAttachmentDTO` (with a nested `FileDTO`
    for name/mime/size) and `AttachmentUploadResultDTO` (the `success`/`errors`
    partial-success envelope the upload returns). `JSONValue`
    is a shape-agnostic JSON box used only for `TaskDTO` fields whose real
    structure isn't verified (`reminders`, `assignees`) — see the next bullet.
    `TaskDTO` carries a large tail of fields it **never** populates from the
    domain model (`doneAt`, `startDate`, `reminders`, `percentDone`,
    `hexColor`, ...); they exist purely so an update can round-trip the
    server's current state untouched.
  - `Mappers/` — DTO → domain model translation. `TaskRelationMapper` maps one
    `RelatedTaskDTO` to a `TaskRelation`; `TaskMapper` reads `subtasks`/
    `dependsOn`/`blocks`/`otherRelations` out of `TaskDTO.relatedTasks` by kind
    (unrecognized kind strings are dropped, not fatal). `LabelMapper` for
    `Label`; `CommentMapper` for `TaskComment`; `AttachmentMapper` for
    `TaskAttachment`; `MaxFileSizeParser` turns `/info`'s `max_file_size`
    string (`"20MB"`, `"20 MiB"`, a plain byte count, ...) into
    `VikunjaServerInfo.maxFileSizeBytes`. Two things about updates:
    - Vikunja manages relations and labels through their own endpoints rather
      than the task update body, so `TaskMapper`'s update-response mapping
      doesn't carry them back — see `TaskDetailViewModel.persist(previous:)` in
      `Features/Tasks` for how callers preserve the previously-loaded
      relations/labels across an update instead of losing them.
    - Vikunja's task update is a **full replace**: any field the request body
      omits is reset to zero/null server-side. `VikunjaTaskRepository.update`
      therefore `GET`s the current task first and `TaskMapper.merge(_:onto:)`
      overwrites only the fields `VikunjaTask` tracks, leaving everything else
      (including fields the domain model doesn't represent) exactly as the
      server last reported it.
  - `Repositories/` — concrete implementations of `VikunjaCore`'s protocols
    (`VikunjaTaskRepository`, `VikunjaProjectRepository`, `VikunjaLabelRepository`,
    `VikunjaTaskRelationRepository`, `VikunjaTaskCommentRepository`,
    `VikunjaTaskAttachmentRepository`, `VikunjaCapabilityProvider`,
    `VikunjaAuthService`,
    `VikunjaInstanceClientFactory`). These are what eventually get injected
    into Features. `VikunjaInstanceClientFactory` builds one of these per
    screen call — see `InstanceClientFactoryProtocol` — from a `baseURL` plus
    a `tokenProvider` closure; there's no long-lived per-account client.
    `PasswordSessionRefresher` (also here, not `AccountStoreProtocol`-conforming
    itself) is the `tokenProvider` every factory call actually passes: a
    drop-in for `AccountStoreProtocol.token(forAccountID:)` that passes an
    API-token account straight through, and for a password *or* OIDC account
    decodes the stored opaque `PasswordSessionCredential`, checks its JWT's
    `exp`, and refreshes it (via whichever of Vikunja's two renewal endpoints
    the account's server supports, detected from whether a refresh token was
    captured at login) before it expires — single-flighted per account so
    concurrent callers don't race duplicate refreshes.

- **`VikuAuth`** — multi-account/instance storage plus OIDC browser
  authentication. Depends on `VikunjaCore` and `openid/AppAuth-iOS` (the
  project's first third-party dependency).
  - `KeychainAccountStore` — implements `AccountStoreProtocol`: the account list,
    each account's bearer token (keyed by account id, in its own Keychain item so
    removing one account never touches another's secret), and the active-account
    pointer, all in the Keychain, never `UserDefaults`. Adding an account makes it
    the active one; updating one can rotate its token or leave it untouched;
    removing one deletes both its metadata and its token item.
  - `Keychain` — internal `Security`-framework wrapper (generic password items);
    not part of the module's public API.
  - `OIDCAuthCoordinator` — implements `OIDCAuthenticating`. Presents a
    provider's authorization page via `ASWebAuthenticationSession` (AppAuth's
    `OIDExternalUserAgentIOS`) and returns only the raw authorization `code` —
    it never contacts a token endpoint itself, since Vikunja's backend does
    that exchange server-side (`AuthServiceProtocol.loginWithOIDC`), so
    `OIDServiceConfiguration`'s required `tokenEndpoint` is filled with a
    value that's never dereferenced. Translates AppAuth's user-cancel error
    (`OIDErrorCodeUserCanceledAuthorizationFlow`) into `OIDCAuthError.canceled`
    so callers can treat a dismissed browser session as "nothing happened"
    rather than a failure. The request-building logic is a `nonisolated
    static` function so it's unit-testable without UIKit; the whole class
    body besides that is `#if canImport(UIKit)`-gated (an inert
    `.unsupportedPlatform` throw otherwise), same pattern as
    `HapticFeedbackCenter` — `swift test` alone only exercises the macOS-host
    no-op branch, so changes here need a real `xcodebuild`
    iOS-Simulator build (or a device run) to actually compile-check.

- **`VikuNavigation`** — pure SwiftUI/Observation, depends only on
  `VikunjaCore` (for the domain values `AppRoute` carries). The shared
  navigation primitives. Two mechanisms, one per concern (architecture audit
  F-12 collapsed five ad-hoc styles into these):
  - `AppRoute` — an app-wide `Hashable` enum of the destinations that cross a
    feature boundary: `taskDetail(VikunjaTask, Project)`,
    `projectOverview(Project)`. Cases carry `VikunjaCore` domain values only.
  - `AppRouter` — `@Observable`, `@MainActor`, wraps one tab's
    `NavigationPath` (`push(_ route: AppRoute)` / `push(_ route: some Hashable)`
    for a feature-local route on the same path / `pop` / `popToRoot`). The app
    target (`MainTabView`) creates one per tab, binds the tab's
    `NavigationStack(path:)` to it, and puts it in that stack's environment;
    any screen — however deep, across module boundaries — reads
    `@Environment(AppRouter.self)` and calls `push`. An `AppRoute` resolves to
    a concrete screen in exactly one place: the app target's
    `.appDestinations(...)` modifier (`Viku/Navigation/AppDestinations.swift`),
    applied once per tab stack. Because `.navigationDestination(for:)` keys off
    the stable value in the path, the pushed screen and its view model survive
    re-renders — this replaced the `(T) -> AnyView` destination closures and
    the `...DestinationBox` identity workarounds.
  - `Router<Route: Hashable>` — the same generic `NavigationPath` wrapper,
    kept for intra-feature routes whose payload is feature-private (`Projects`'
    `ProjectsRoute.projectOverview(ProjectNode)` carries the loaded subtree —
    pushed onto the tab's `AppRouter` path, resolved by `ProjectsRootView`'s
    own `.navigationDestination(for: ProjectsRoute.self)`) or whose whole stack
    is self-contained (`Settings` still owns its `NavigationStack` +
    `Router<SettingsRoute>`).

- **`VikuDesignSystem`** — pure SwiftUI, depends only on `VikunjaCore` (for
  `ToastStyle`/`ToastPresenting` — see `ToastCenter` below; every other token
  is dependency-free). The shared design tokens and views every Feature should
  build on (colors, typography, spacing; more token categories and shared
  views land here over time).
  - `VikuColor` — `brandPrimary`; `VikuColor.Priority` (`urgent`/`high`/
    `medium`/`low`); `Surface` (`card`/`field`/`page` grouped-content
    backgrounds, backed by adaptive iOS system colors — see
    `Color+Platform.swift`); `textSecondary`/`textTertiary` (a darker, more
    legible gray scale than the system `.secondary`/`.tertiary`); `Semantic`
    (`success`/`danger` plus darker `successText`/`dangerText` for text drawn
    on a tinted banner); and `SwatchPalette` (preset hex strings offered when
    picking a color for a label or project the user is creating). Values that
    originate as `oklch(...)` in the design source are pre-converted to sRGB
    hex once (via a private `Color(hex:)` initializer) rather than converted at
    runtime. `Color(vikuHex:)` (public) parses an API `hex_color` string
    off a `Project`/`Label`, returning `nil` for unset/malformed so callers
    fall back to a token.
  - `VikuFont` — wraps the system Dynamic Type text styles under our own
    names, so a future custom typeface or weight change happens in one place.
  - `VikuSpacing` — spacing scale on a 4pt grid (`xxs` through `xxl`).
  - `VikuRadius` — corner-radius scale (`sm`/`md`/`lg`) for fields, cards,
    buttons, sheet corners.
  - `DueDateFormatter` (`Date/`) — `compact(_:relativeTo:)`, the shared
    one-token due-date phrasing (`Today`/`Tomorrow`/`Yesterday` →
    abbreviated weekday within a week → `Sep 6`, adding the year only when it
    differs from the reference date). Every compact task row uses it
    (`Features/Home`, `Features/Projects`, `Features/Search`, and the Today
    widget's `.upcoming` label) instead of `Text(date, style: .date)`, whose
    full localized date wraps a dense row onto several lines. Those rows also
    pin the date/relations glyph to their natural width so a long project name
    is what truncates, keeping the metadata line to one line.
  - **Project picker** (`ProjectPicker/`) — `ProjectPickerSheet`, the shared
    "pick a project" `.sheet` used by every screen that chooses one (quick-add,
    create/edit-project parent, "move task to project"). A native
    `.insetGrouped` `List` in the style of Notes' "Move to Folder": rows on a
    card surface above the sheet, native separators, a disclosure chevron that
    expands/collapses a project's subprojects to arbitrary depth, and a tinted
    `folder.fill`/`list.bullet.rectangle.fill` glyph (`ProjectPickerIcon`, also
    reused by the collapsed fields that open the sheet) instead of a color dot.
    Takes a flat `[Project]` (the caller filters archived); `ProjectPickerTree`
    (internal, unit-tested) builds the tree, does search filtering, and handles
    `excludingSubtreeOf:` — this replaced the two-level `ProjectGroup` grouping
    that used to be recomputed on five separate view models.
  - **Task row** (`Components/`) — `VikuTaskRow`, the one compact task row
    every list screen uses (`Features/Home`'s Today, `Features/Projects`'
    overview, `Features/Search`). Circular completion checkbox, strikethrough
    title, a one-line metadata row (project dot + name, due date or an
    "Overdue" label, a `link` glyph when the task `hasRelations`), up to two
    label pills + a "+N" overflow pill, trailing priority dot. Takes a
    `VikunjaTask` + its `Project?` + `onToggle`/`onOpen` + a `@ViewBuilder
    contextMenu` (its items differ per screen). `showsProjectBadge: false`
    (a project's own overview passes this) drops the dot + name, keeping just
    the color for the checkbox; in that mode a relations-only task moves its
    `link` glyph up beside the title so it isn't stranded on an otherwise
    empty metadata line. `.vikuCardRow(index:count:)` (`Components/CardList.swift`)
    is the matching modifier for the "run of rows reads as one rounded card"
    recipe inside a `.plain` `List` (inner padding, card background,
    hand-drawn dividers, per-position corner rounding, stripped list-row
    insets/separator/background). `VikuColor.Priority.dot(for:)` is the single
    priority-to-color mapping these rows use. `Features/Calendar` still keeps
    its own trimmed copy (`CalendarTaskRow`) for now — it renders outside a
    `List`.
  - **Toasts** (`Toast/`) — the app-wide toast system. `ToastCenter` is an
    `@Observable`/`@MainActor` queue (one toast on screen at a time; a second
    `show` while one is up waits its turn) that implements `VikunjaCore`'s
    `ToastPresenting` protocol; `ToastView`/`ToastHostModifier` are the actual
    rendering, attached once via `View.toastHost(_:)`. The split exists so a
    ViewModel can depend on the plain `ToastPresenting` protocol (constructor
    injection, like a repository) without ever importing
    `VikuDesignSystem` or SwiftUI — the same relationship
    `VikunjaNetworking` has to `VikunjaCore`, just for a UI-facing protocol
    instead of a data one. `AppContainer` owns the single `ToastCenter`
    instance (`container.toastCenter`); `RootView` attaches
    `.toastHost(container.toastCenter)` at the top of the view hierarchy so a
    toast floats above onboarding, every tab, and any sheet. To show a toast
    from a ViewModel: take `toastPresenter: ToastPresenting` via constructor
    injection (pass `container.toastCenter` from the relevant
    `make...ViewModel` factory), then call
    `toastPresenter.show("Task created", style: .success)` — no setup beyond
    that one constructor parameter.
  - **Haptics** (`Haptics/`) — the app-wide Taptic Engine, built on the same
    split as toasts. `VikunjaCore` owns the vocabulary: `HapticStyle`
    (`.success`/`.warning`/`.error` outcomes, `.selection` ticks,
    `.light`/`.medium`/`.heavy`/`.soft`/`.rigid` impacts) and the
    `HapticFeedbackPresenting` protocol (`play(_:)` + an optional
    `prepare(_:)` warm-up), plus `NoopHapticFeedback` for previews/tests.
    `VikuDesignSystem`'s `HapticFeedbackCenter` implements it over UIKit's
    feedback generators (kept alive between calls so `prepare` actually helps;
    inert no-op where UIKit is unavailable). `AppContainer` owns the single
    instance (`container.hapticCenter`). Wired in so far: completing a task
    (not un-completing it) plays `.success` from every `toggleDone` —
    `TodayViewModel`, `ProjectOverviewViewModel`, `SearchViewModel`,
    `TaskDetailViewModel` — and switching the active tab plays `.selection`
    (`MainTabView`, via `.vikuHaptic(_:trigger:)` on the `TabView`).
    **Two ways to fire one:**
    - From a ViewModel's own logic (an optimistic toggle rolled back, a
      create succeeded): take `hapticPresenter: HapticFeedbackPresenting` via
      constructor injection (defaulted to `NoopHapticFeedback()` so tests
      needn't pass it), pass `container.hapticCenter` from the relevant
      `make...ViewModel` factory (exactly like `toastPresenter:`), call
      `hapticPresenter.play(.success)`.
    - From a pure SwiftUI view reacting to state: `View.vikuHaptic(_:trigger:)`
      (or the `condition:` overload), a thin wrapper over `.sensoryFeedback`
      that reuses `HapticStyle` — no injection needed.

- **`VikuUI`** — pure SwiftUI, depends only on `VikuDesignSystem`. The shared
  view primitives every Feature builds on that aren't design tokens:
  - `ScreenLoadState<Value>` — the request-lifecycle enum
    (`idle`/`loading`/`loaded(Value)`/`failure(String)`) every screen's view
    model exposes. Content-in-view-model screens use `ScreenLoadState<Void>`
    (`.loaded` shorthand, phase-based `Equatable`); `Search` carries its
    results in `ScreenLoadState<[VikunjaTask]>`. `isLoading`/`isLoaded`/
    `value`/`failureMessage` helpers.
  - `VikuStatusView(systemImage:title:message:iconSize:fillsHeight:retry:)` —
    the one empty/error state (icon + title + message + optional "Try Again")
    every list screen and the task-detail screen render.
  - `View.vikuSectionHeader()` — the small/bold/uppercase list section-label
    style ("SUBPROJECTS", "OVERDUE", "RESULTS").

`AppContainer` owns the single `OIDCAuthCoordinator` instance too
(`container.oidcAuthCoordinator`, typed `OIDCAuthenticating`) plus
`container.oidcRedirectURI` — derived from the app's *existing*
`viku://`/`viku-dev://` deep-link scheme (`VikuWidgetConfig.urlScheme`), so
OIDC needed no separate URL-scheme registration. Both are passed into
`makeInstanceSetupViewModel()`/`makeConnectionFormViewModel(...)` alongside
the other constructor-injected dependencies.

- **`Features/Onboarding`** — the "connect to your instance" screen. Depends on
  `VikunjaCore` + `VikuDesignSystem`.
  - `ViewModels/InstanceSetupViewModel.swift` — `@Observable`, `@MainActor`.
    Normalizes the typed URL via `InstanceURL`, probes it via
    `InstanceClientFactoryProtocol.makeCapabilityProvider(baseURL:).serverInfo()`
    (confirms it's a real Vikunja instance; the API token itself isn't validated
    against the server yet), then persists via `AccountStoreProtocol`. Takes
    `AccountStoreProtocol` + `InstanceClientFactoryProtocol` +
    `OIDCAuthenticating` + an `oidcRedirectURI: URL` by constructor injection —
    no concrete `VikunjaNetworking`/`VikuAuth` types. Three ways to connect:
    - **API token** (`credentialMode == .apiToken`) — the default, always
      available.
    - **Username/password** (`.password`, plus TOTP retry) — enabled only once
      a debounced probe (`checkLocalAuthAvailability()`, fired from the view as
      the user types the URL) confirms `CapabilityProvider.supports(.localAuth)`;
      snaps back to `.apiToken` if it stops being available mid-edit
      (`updateLocalAuthAvailable`). Login goes through `PasswordLoginCoordinator`
      (`VikunjaCore/Support/`), a small state machine
      (`.idle/.authenticating/.awaitingTOTP/.success/.failure`) shared with
      `Settings`' `ConnectionFormViewModel`.
    - **OIDC** (`oidcProviders: [OIDCProvider]`, populated by that same probe) —
      renders as a separate "or continue with…" section below
      `CredentialModePicker` rather than a third segment (the picker is
      hardcoded to exactly two — see `VikuDesignSystem`), since there can be
      several providers at once. `credentialMode` itself never becomes
      `.oidc`; tapping a provider button calls `signInWithOIDC(_:)` directly,
      bypassing `canSave`/`saveConnection()` entirely. That method calls
      `OIDCAuthenticating.authenticate(provider:redirectURI:)` for a code,
      then `AuthServiceProtocol.loginWithOIDC` to exchange it, then persists
      the account with `authMethod: .oidc` — same shape as the password path.
      `OIDCAuthError.canceled` (the user dismissed the browser) resets to
      `.idle` with no error banner; other `OIDCAuthError` cases get a friendly
      message via a private `message(for:)` overload, same pattern as
      `VikunjaError`.
  - `Models/InstanceSetupValidationState.swift` — view-specific state
    (`idle`/`validating`/`success`/`failure(message)`), not a domain model.
  - `Views/InstanceSetupView.swift` — the onboarding form; reports the saved
    account back via an `onConnectionSaved` callback rather than knowing what
    happens next.

- **`Features/Home`, `Features/Projects`, `Features/Search`, `Features/Settings`**
  — one per main tab. All depend on `VikunjaCore` + `VikuNavigation` +
  `VikuDesignSystem`, with real content behind each. Each follows the same
  shape: `Views/<Name>View.swift`, `Views/<Name>RootView.swift` (public entry
  point). For `Home`/`Calendar`/`Search` the hosting `NavigationStack` +
  `AppRouter` live in the app target (`MainTabView`) and the `RootView` is just
  the tab's root content — a `HomeRoute`/`CalendarRoute`/`SearchRoute` enum is
  no longer needed and was deleted. `Projects` keeps `Navigation/ProjectsRoute.swift`
  (`projectOverview(ProjectNode)` — a feature-private payload) and its
  `RootView` applies the matching `.navigationDestination(for:)`; `Settings`
  keeps its own `NavigationStack` + `Router<SettingsRoute>`. Only `<Name>RootView`
  is public; the content view stays internal to the package. Every feature's
  view models track their request
  lifecycle with `VikuUI`'s shared `ScreenLoadState<Void>` and surface error
  copy through `VikunjaCore`'s canonical `VikunjaError.displayMessage` (both
  used to be per-feature copies under `Models/` / `Support/`).
  - `Home` is the "Today" screen, fully built: `TodayViewModel` fetches every
    project (`ProjectRepositoryProtocol.fetchProjects`) and then every
    project's tasks concurrently (`TaskRepositoryProtocol.fetchTasks`,
    dropping a project whose fetch fails rather than failing the whole
    screen), flattening them into one account-wide list — unlike `Projects`'
    screens, nothing here scopes the fetch to a single project. `TodayView`
    groups the merged tasks by due date into Overdue/Today/Upcoming sections
    (ascending by due date within a section) behind an
    All/Overdue/Today/Upcoming filter chip row; tasks with no due date never
    appear here, only inside their own project. Each row shows the task's
    project (color dot + name, looked up from `projectsByID` since a task
    only carries its `projectID`), an "Overdue" label or due date, a link
    icon when the task `hasRelations`, and up to two label pills. The
    completion toggle is optimistic with rollback
    (`TodayViewModel.toggleDone`); tapping a row calls
    `router.push(.taskDetail(task, project))` on the `AppRouter` from the
    environment (see the `VikuNavigation` section). Supports pull-to-refresh.
  - `Settings` is fully built as multi-account management, not just a
    single reset action: `SettingsView` is a landing screen showing the
    active connection's name with a "Connections" row that pushes
    `ConnectionsListView`/`ConnectionsListViewModel` — every saved
    `InstanceAccount`, with a checkmark on the active one;
    `setActive(_:)` calls `AccountStoreProtocol.setActiveAccount` and fires
    an `onActiveAccountChanged` callback. Tapping an account (or a toolbar
    "+") pushes `ConnectionFormView`/`ConnectionFormViewModel` in `.edit`/
    `.create` mode (`ConnectionFormMode`) — the same normalize-URL-then-probe-
    `/api/v1/info` flow, and the same API-token/password/OIDC credential
    choice, as `Onboarding`'s `InstanceSetupViewModel` (`signInWithOIDC(_:)`
    here switches on `mode` to either `addAccount` or `updateAccount` — the
    latter lets an existing connection switch its `authMethod`, e.g. an
    API-token account moving to OIDC), plus
    `deleteConnection()` (refuses, with a toast, to delete the last remaining
    account) and, in `.edit` mode, an async `load()` that fills in the
    existing token from the Keychain after the name/URL render immediately
    (API-token accounts only — a password/OIDC account's stored credential is
    opaque). Saving or deleting fires `onActiveAccountChanged` too, since either can
    change which account is active or edit the active one's own address.
    `SettingsView` also has a "Manage Labels" row that pushes
    `ManageLabelsView`/`ManageLabelsViewModel` (route `.manageLabels`): the
    account-wide label list (`LabelRepositoryProtocol.fetchLabels`, sorted by
    title) with per-row swatch + title, swipe-to-delete behind a
    `confirmationDialog` (`deleteLabel` — optimistic removal with rollback),
    and create / rename+recolor through `LabelEditorSheet` — a compact
    `.sheet` (not a route) in `.create`/`.edit(Label)` mode
    (`LabelEditorMode`) with a title field and preset `VikuColor.SwatchPalette`
    swatches only, no free-form picker. `createLabel`/`updateLabel` surface a
    toast; `updateLabel` is optimistic with rollback. This is label
    management only — nothing here attaches a label to a task (that's
    `Features/Tasks`' `LabelPickerSheet`). `AppContainer.makeManageLabelsViewModel(account:)`
    wires the `LabelRepository` through `InstanceClientFactoryProtocol`.
  - `Projects` is fully built: `ProjectsListViewModel` loads the flat project
    list and arranges it into a parent/child tree by `parentProjectID`, then
    fetches each project's own tasks concurrently to populate
    `taskSummaries` (`ProjectTaskSummary`: done/total counts, dropped rather
    than failing the screen if a project's fetch fails) for a per-row
    completion indicator; `ProjectsView` renders the tree as an indented,
    per-project expand/collapsible list (rows start **collapsed** —
    `expandedProjectIDs` is empty until the user taps a disclosure chevron,
    nothing auto-expands on load). `ProjectsRootView` applies
    `.navigationDestination(for: ProjectsRoute.self)` (`projectOverview(ProjectNode)`,
    carrying the loaded subtree) onto the tab's app-owned `NavigationStack`.
    A toolbar "+" opens
    `CreateProjectSheetView`/`CreateProjectViewModel` — a compact sheet for
    title + color swatch + parent project (parent defaults to "None"/root, or
    is preset when opened from within a project), creating via
    `ProjectRepositoryProtocol.create` and surfacing a success toast.
    Selecting a project pushes `ProjectOverviewViewModel`/
    `ProjectOverviewView` — subprojects as a horizontal card row (each with
    its own recursively-fetched completion count), the project's own tasks
    grouped into Overdue/Pending/Completed sections (ascending by due date)
    behind an All/Pending/Overdue/Completed filter. A task row's completion
    toggle persists optimistically; a long-press context menu offers
    "Delete", which goes through a confirmation dialog to
    `ProjectOverviewViewModel.delete` (`TaskRepositoryProtocol.delete` +
    toast). Selecting a task calls `router.push(.taskDetail(task, project))` on
    the environment `AppRouter`; the app target's `.appDestinations(...)`
    resolves it to `Features/Tasks`' `TaskDetailView` (built via
    `AppContainer.makeTaskDetailViewModel`). `Projects` never imports `Tasks`.
    `CreateProjectViewModel` is still supplied as a factory closure by
    `AppContainer`, keeping repository wiring decoupled the same way networking
    is. `Home`, `Calendar`, and `Search` navigate to `TaskDetailView` the same
    way.

- **`Features/Tasks`** — a single task's detail screen
  (`TaskDetailView`/`TaskDetailViewModel`), the quick-add task flow
  (`QuickAddSheetView`/`QuickAddTaskViewModel`), and the duplicate-task sheet
  (`DuplicateTaskSheetView`/`DuplicateTaskViewModel`). Depends on `VikunjaCore` +
  `VikuDesignSystem` + `VikuNavigation` (for `AppRouter`/`AppRoute` — see
  below); it owns no `NavigationStack`/`Router`. `TaskDetailView` is always
  pushed as a leaf screen onto whichever feature's stack opened it, and both
  sheets are `.sheet`s (quick-add from whoever owns the FAB — `MainTabView`;
  duplicate from `TaskDetailView`'s own menu). A tapped relation, the project
  pill, and a just-created duplicate all navigate by
  `router.push(...)` on the `@Environment(AppRouter.self)` — pushing
  `AppRoute.taskDetail` / `AppRoute.projectOverview` onto the hosting stack,
  resolved by the app target's `.appDestinations(...)`. This replaced the
  `projectDestination: (Project) -> AnyView` closure, the two
  `.navigationDestination(item:)` blocks, and the `ProjectDestinationBox`
  wrapper (architecture audit F-12).
  - **Detail screen**: an inline-editable title and description (see below),
    completion toggle, due date, priority, labels, subtasks (read-only
    checklist), a combined "Relations" section covering `dependsOn`/`blocks`
    plus every `otherRelations` kind (with a "Blocked" banner when any
    `dependsOn` relation is incomplete), and a "Comments" section (see
    below). `TaskDetailViewModel.task` starts as whatever was passed in at
    navigation time (no blank/spinner flash) and `load()` refreshes it from
    the server; the screen also supports pull-to-refresh. All edits are
    optimistic with rollback: `toggleDone()`/`setDueDate()`/`setPriority()`/
    `setTitle()`/`setDescription()` go through `persist(previous:)`, which
    carries the previously-loaded relations/labels onto the server's
    response since Vikunja's task-update endpoint doesn't return them (see
    the `Mappers/` note above) — without that, editing would make those
    sections vanish. Title and description are edited inline (not a
    separate sheet) and committed via a nav bar checkmark, not the keyboard's
    return key, matching Notes/Reminders.
  - **Labels**: `LabelPickerSheet` (a `.searchable` list) toggles membership
    via `LabelRepositoryProtocol.addLabel`/`removeLabel`, and can
    create-and-attach a new label on the fly (`createAndAddLabel`); `allLabels`
    is loaded lazily.
  - **Relations**: a two-step sheet — pick a `RelationKind`, then pick the
    other task. The task picker searches account-wide
    (`TaskRepositoryProtocol.searchTasks`) and, before the user types,
    suggests the current task's own project's other tasks (most relations are
    intra-project). Tapping an existing relation row resolves the full task +
    its project (`loadRelatedTask`) then `router.push(.taskDetail(...))` — the
    app target's `.appDestinations(...)` builds the nested `TaskDetailView`
    (via `AppContainer.makeTaskDetailViewModel`), so the recursion goes through
    one shared resolver instead of a per-VM factory.
  - **Comments**: `loadComments()` runs alongside `load()` but reports into
    its own `commentsLoadState`, so a comments-fetch failure doesn't block the
    rest of the screen. `addComment(_:)` posts via
    `TaskCommentRepositoryProtocol.addComment` and appends the server's
    response (no optimistic placeholder, since a comment's id/author/
    timestamps only exist once the server assigns them). Comment bodies
    arrive as the Vikunja rich-text editor's HTML output; `CommentTextFormatter`
    strips that down to plain text since this feature has no rich-text
    renderer yet. A comment row's context menu offers "Edit Comment"
    (`editComment(_:newText:)` — `EditCommentSheet`, prefilled with the
    plain-text body, persists via `TaskCommentRepositoryProtocol.updateComment`
    and swaps in the server's response; no optimistic placeholder, same as
    `addComment`) and "Delete Comment" (`deleteComment(_:)`, optimistic removal
    with rollback behind a confirmation dialog).
  - **Attachments**: `loadAttachments()` runs alongside `load()` on its own
    `attachmentsLoadState`, same as comments. An "Add" button opens a
    `.fileImporter`; the picked file is read into memory (`PickedFile`) and
    sent via `TaskAttachmentRepositoryProtocol.uploadAttachment`, appending
    the server's created attachment (no optimistic placeholder — id/size/
    uploader only exist once stored) with `isUploadingAttachment` driving a
    progress row. Tapping a row downloads the bytes (`attachmentData(for:)`),
    writes them to a temp file (`AttachmentPreviewFile` — the download is
    bearer-authed, so QuickLook can't be handed the remote URL) and previews
    with `.quickLookPreview`. A row's context menu offers "Delete Attachment"
    (`deleteAttachment(_:)`, optimistic removal with rollback behind a
    confirmation dialog). No rich-text/thumbnail handling yet.
  - `TaskDetailViewModel` takes `task` + `project` + **six** repository
    protocols (`TaskRepositoryProtocol`, `LabelRepositoryProtocol`,
    `TaskRelationRepositoryProtocol`, `TaskCommentRepositoryProtocol`,
    `TaskAttachmentRepositoryProtocol`, `ProjectRepositoryProtocol`) + a
    `ToastPresenting` + a `HapticFeedbackPresenting` (`.success` on
    completing the task), all via constructor injection.
  - **Quick-add** (`QuickAddTaskViewModel`): title + project + priority only
    (matching the mockup's `AddTaskSheet`). Presented globally from the tab
    bar FAB, so it picks its starting project from context: a
    `preselectedProjectID` (`MainTabView`'s `QuickAddOverlay` snapshots
    `QuickAddContext.preselectedProjectID` in the FAB tap handler — a stack of
    the project ids of the project-scoped screens currently visible; a project
    overview (`ProjectOverviewViewModel`) or a task detail
    (`TaskDetailViewModel`) pushes its project id while on screen via
    `markVisible()`/`markHidden()`, see `QuickAddContextTracking` in
    `VikunjaCore`. `QuickAddOverlay` is split out of `MainTabView` and the
    snapshot taken outside `body` on purpose — the FAB/sheet `@State` and any
    `@Observable` context read must not re-evaluate `MainTabView`'s body,
    which would rebuild every tab's `NavigationStack` and view models and
    blank whatever screen is behind the sheet), else `accountDefaultProjectID`
    — the account's Vikunja default project (`settings.default_project_id`
    from `GET /api/v1/user`), which `AppContainer.refreshDefaultProject` caches
    on device in `DefaultProjectStore` (`UserDefaults`, keyed by account id)
    once per launch and on account switch, and passes in synchronously via
    `makeQuickAddTaskViewModel` — so opening the sheet never hits the network
    for it. `load()` uses the fallback only if that project is one of the
    loaded, non-archived projects. `UserRepositoryProtocol` is now used by
    `AppContainer` (the launch refresh), not by this view model. Creates via
    `TaskRepositoryProtocol.create` and shows a success toast.
  - **Duplicate** (`DuplicateTaskViewModel`/`DuplicateTaskSheetView`): a
    client-side task copy, opened from `TaskDetailView`'s overflow menu.
    Deliberately *not* Vikunja's own server-side duplicate (2.2.0+ only, and
    clones verbatim with no chance to edit first). The sheet is the same
    compact bottom-sheet as quick-add (shared controls in
    `Views/TaskFormControls.swift` — `FieldLabel`/`ProjectField`/
    `PriorityChipRow`/`SaveErrorBanner`), pre-filled from the source task:
    editable title (defaulting to `"… (copy)"`), project, priority, plus
    "Copy labels"/"Copy relations" toggles shown only when the source has
    either. `duplicate()` calls `TaskRepositoryProtocol.create` (carrying
    over description + due date silently), then best-effort replays the
    source's labels (`LabelRepositoryProtocol.addLabel`) and its
    "Relations"-section relations — `dependsOn`/`blocks`/`otherRelations`,
    **not** subtasks — via `TaskRelationRepositoryProtocol.addRelation`;
    comments and attachments aren't copied. Built by
    `TaskDetailViewModel.makeDuplicateTaskViewModel()`, which reuses the
    detail view model's own repositories, so `AppContainer` needs no factory
    for it. `duplicate()` returns the created task **and its project** (from
    the loaded list, falling back to the source task's own project);
    `DuplicateTaskSheetView`'s `onDuplicated` callback hands that back to the
    host, and `TaskDetailView` navigates to the new task by
    `router.push(.taskDetail(...))` — the same path a tapped relation row
    takes. Success plays a `.success` haptic + toast.

Features should only ever import `VikunjaCore`/`VikuNavigation`/
`VikuDesignSystem` and depend on `VikunjaCore`'s protocols — never import
`VikunjaNetworking` or `VikuAuth` directly. The `AppContainer` composition
root (`Viku/AppContainer.swift`) is the only place expected to know about
concrete `VikunjaNetworking`/`VikuAuth` types and wire them into the
protocol-typed dependencies Features receive. It exposes one `make…ViewModel`
factory per screen; a screen scoped to one instance takes `account:` and each
factory builds its repositories through `InstanceClientFactoryProtocol` with a
`tokenProvider` closure that re-reads that account's bearer token from
`AccountStoreProtocol` **per request** (so a rotated/removed token is never
cached) — `Settings`' account-management factories
(`makeConnectionsListViewModel`, `makeConnectionFormViewModel`) are the
exception, since they operate across every saved account rather than one.
Every factory passes the single `container.toastCenter` wherever a
`ToastPresenting` is needed. This is what keeps a Vikunja API change contained
to `VikunjaNetworking` instead of rippling into UI code.

- **`VikuWidgetKit`** — the Today home-screen widget. Not a `Feature`: it's
  the widget extension's own composition root, so it's the one other module
  besides `AppContainer` allowed to import `VikunjaNetworking`/`VikuAuth`.
  Depends on `VikunjaCore` + `VikunjaNetworking` + `VikuAuth` +
  `VikuDesignSystem`.
  - `Config/VikuWidgetConfig` — the identifiers the app target and the
    extension must agree on (App Group, `keychain-access-group`,
    `KeychainAccountStore` service, widget `kind`, URL scheme, refresh
    interval). Mirrored in the two targets' entitlements. The App Group,
    keychain group, keychain service, and URL scheme are all derived from
    `bundleIDPrefix`, which is split per build configuration (`#if DEBUG` →
    `…viku.dev`, else `…viku`) so a Debug ("dev") and a Release install
    on the same device never share storage or claim the same `viku://`
    scheme. The entitlements / `Info.plist` get the matching value from the
    project-level `VIKU_ID_PREFIX` / `VIKU_URL_SCHEME` build settings via
    `$(…)` expansion — keep those aligned with the `#if DEBUG` branch.
  - `Data/TodaySnapshotLoader` — one refresh: resolve the active account +
    token, fetch every project's tasks concurrently (dropping a project whose
    fetch fails, exactly like `TodayViewModel`), bucket them via
    `VikunjaCore.TodayDigest`, and write the result to the App Group cache.
    Returns a `TodayWidgetState` (`.notConnected`/`.needsAuth`/`.unavailable`/
    `.content`). **The app also runs this loader** (via
    `AppContainer.refreshTodayWidgetSnapshot()`, on launch + backgrounding) so
    the App Group cache is always populated with the app's own credentials —
    when the widget process can't read the shared keychain (the iOS Simulator,
    an un-provisioned build) it renders that cache instead of
    `.notConnected`. Takes `VikunjaCore` protocols for testing;
    `VikuWidgetEnvironment` wires the concrete types.
  - `Data/TodaySnapshotCache` — best-effort JSON in the App Group container;
    every op degrades to `nil`/no-op.
  - `Model/TodayWidgetContent` — flat, `Codable`, capped at
    `VikuWidgetConfig.taskLimit`; deliberately not `VikunjaTask`.
  - `WidgetKit/` (guarded `#if canImport(WidgetKit)`) — `TodayTimelineProvider`
    (`.after(30 min)` reload policy), `TodayWidget` (`StaticConfiguration`,
    small/medium/large), `TodayWidgetView` (design-system tokens only),
    `ToggleTaskDoneIntent` (`AppIntent` — complete a task from the widget).
  - The `@main WidgetBundle`, Info.plist and entitlements live in
    `Viku-widgets/` (a `PBXFileSystemSynchronizedRootGroup`, like `Viku/`).
    The `Viku-widgets` app-extension target embeds `VikuWidgetKit`, is
    embedded into the `Viku` app, and shares its App Group + keychain group
    (`Viku/Viku.entitlements` ↔ `Viku-widgets/Viku-widgets.entitlements`).
    `AppContainer` builds its `KeychainAccountStore` with
    `accessGroup: VikuWidgetConfig.keychainAccessGroup` and runs
    `migrateToAccessGroup()` from `RootView`'s `.task` (via
    `AppContainer.bootstrap()`). The app nudges the widget via
    `WidgetCenter.shared.reloadAllTimelines()` on `scenePhase == .background`
    (`VikuApp.swift`). Background/history: `Viku-widgets/WIDGET_SETUP.md`.

`VikunjaCore.TodayDigest`/`TaskDueBucket` is the shared due-date bucketing rule
— `Features/Home`'s `TodaySection.sections` and the widget both build on it, so
the "Today" grouping stays identical in both places.

**Multi-instance credential sharing**: `KeychainAccountStore(accessGroup:)`
stores the account index, the active-account pointer, and each account's token
in a shared `keychain-access-group` so the widget process can read them;
`migrateToAccessGroup()` is a one-time move of pre-existing items from the
app's private group (safe to call every launch). Passing `accessGroup: nil`
keeps the single-process behavior. That shared group (and the App Group and
`service`) is per-build-config — Debug and Release use disjoint
`…viku.dev.*` / `…viku.*` identifiers, so dev and prod installs on one
device don't see each other's accounts. No migration between the two: switching
config starts from an empty account list.

**Top-level navigation** (`Viku/RootView.swift`, `Viku/Navigation/`): `RootView`
switches between `InstanceSetupView` (no saved account yet) and `MainTabView`
(the active account, once one exists). It re-reads the active account from
`AccountStoreProtocol` on launch and again whenever `Settings`' connection
screens report `onAccountsChanged` (switching accounts, deleting the active
one, or editing its own address); `MainTabView` is rendered `.id(connectedAccount)`
so any of those changes tears down and rebuilds the whole tab shell against
the new account rather than trying to mutate view models built against the
old `baseURL` in place. Deleting the last saved account surfaces here too:
the re-read comes back `nil` and `RootView` falls back to onboarding.
`MainTabView` is the floating, Liquid Glass tab bar —
the default look for `TabView` on iOS 26+ — with one `Tab` per `AppTab` case
(`.home`, `.projects`, `.calendar`, `.settings`, plus `.search` using iOS 26's
dedicated `.search` tab role, which renders as a separated glass pill). Each
tab except `Settings` wraps its feature `<Name>RootView` in an app-owned
`NavigationStack(path:)` bound to a per-tab `@State` `AppRouter` (placed in
that stack's environment) plus the shared `.appDestinations(container:account:)`
resolver; `Settings` keeps its own stack + `Router<SettingsRoute>`. Also a
`QuickAddOverlay` (owning a `QuickAddButton` — a bare circular FAB matching the
design mockup — and its `.sheet`) placed via
a plain `.overlay(alignment: .bottomTrailing)`, not `.tabViewBottomAccessory`:
that API always paints a system glass background behind its content and
centers it over the tab bar, which can't be suppressed or anchored to a
corner. `QuickAddOverlay` is a child view specifically so the FAB/sheet
`@State` never re-evaluates `MainTabView`'s body — doing so rebuilds every
tab's `NavigationStack` + view models and blanks the screen behind the sheet.
For the same reason the per-tab root view models (`todayViewModel`/
`projectsViewModel`/`calendarViewModel`/`searchViewModel`) and the per-tab
`AppRouter`s are `@State`, built once in `MainTabView.init` (view models) or as
initializers (routers), not inside `body`: `body` *does* re-run on every tab switch
(anything that reads `selection` — e.g. the `.onChange` haptic tick — makes it),
and rebuilding a view model there would hand each tab a fresh empty one and
flash a spinner on switch. `MainTabView` is keyed `.id(connectedAccount)`, so an
account switch still rebuilds them.
The FAB presents `Tasks`' `QuickAddSheetView` as a `.sheet`
(`container.makeQuickAddTaskViewModel(preselectedProjectID:account:)`); it
stays global rather than moving per-screen — the sheet defaults its project
from
`AppContainer.quickAddContext` (a `QuickAddContext`, conforming to
`VikunjaCore`'s `QuickAddContextTracking`): a visible project-scoped screen (a
project overview or a task detail) claims it, everything else leaves it `nil`
so the sheet falls back to the account's default project. `AppTab` and `MainTabView`
live in the app target, not a package,
because the `Tab(role:)` / `tabBarMinimizeBehavior` APIs require the iOS 26
SDK, while packages floor at `.iOS(.v17)`.

**Multi-instance / multi-version handling**: since self-hosted instances can be on
very different Vikunja versions with different features enabled, `CapabilityProvider`
hits `GET /api/v1/info` once per session, caches the result, and exposes
`supports(_:)`. Code should branch on capabilities rather than hardcoding server
version comparisons.

`Viku/` is the composition root: `VikuApp.swift` builds the `AppContainer`,
`RootView.swift` switches between onboarding and the main tab bar, and
`Navigation/` holds `AppTab` and `MainTabView` (see above).

## Rules for new code

These are binding for anything added under `Features/`, `VikuAuth`, or
`AppContainer` — not just aspirational. See `ARCHITECTURE.md` for the "why"
behind each one.

- **Never import `VikunjaNetworking` from a Feature.** Features depend only on
  `VikunjaCore` protocols and models. Only the composition root (`AppContainer`)
  is allowed to know about concrete `VikunjaNetworking`/`VikuAuth` types and
  wire them in.
- **Views use `VikuDesignSystem` tokens, not hardcoded values.** Colors go
  through `VikuColor`, fonts through `VikuFont`, spacing through
  `VikuSpacing`, corner radii through `VikuRadius` — no raw
  `Color(...)`/`Font(...)` literals or magic-number padding in `Features/*`
  views. Add a new token there first if the one you need doesn't exist yet,
  rather than inlining a one-off value.
- **ViewModels take their dependency as a protocol via constructor injection**
  (e.g. `init(repository: TaskRepositoryProtocol)`), never a concrete networking
  class. A screen that needs several takes one protocol parameter each (e.g.
  `TaskDetailViewModel`'s six repositories), plus `ToastPresenting` for
  user-facing feedback. Views contain no business logic and no networking
  knowledge.
- **Each `Features/<Name>` module follows the same internal shape**:
  `Models/` (view-specific state only), `ViewModels/`, `Views/`, and
  `Navigation/` only when the feature has a route with feature-private payload
  or a self-contained stack (`ProjectsRoute`, `SettingsRoute`).
- **Navigation is exactly two mechanisms, never a third (architecture audit
  F-12).** Anything crossing a feature boundary is an `AppRoute` case pushed
  via `@Environment(AppRouter.self)` and resolved only by the app target's
  `.appDestinations(...)`. Anything staying inside one feature is a
  `Router<Route>` / `.navigationDestination(for: Route.self)` on that feature's
  stack. **No `(T) -> AnyView` destination closures, no `AnyView`-keyed
  `.navigationDestination(item:)`, no per-feature `NavigationLink(destination:)`
  into another feature.** A new cross-feature destination means a new `AppRoute`
  case + a new branch in `AppDestinations.swift` — nowhere else. `MainTabView`
  owns the per-tab `NavigationStack` + `AppRouter` (`Settings` is the one
  feature that still owns its own stack).
- **No third-party DI framework.** Dependency wiring is a plain `AppContainer`
  with constructor injection.
- **Credentials (JWT, API tokens) live in the Keychain, never `UserDefaults`.**
- **Branch on `CapabilityProvider.supports(_:)`, never on ad-hoc version
  comparisons scattered through feature code.** Version-specific logic, if
  needed, stays inside `VikunjaNetworking` (e.g. a second `Mapper` selected by
  `serverInfo.version`).
- **Tests**: `VikunjaCore` tests need no networking. `VikunjaNetworking` tests use
  real JSON fixtures (contract tests) rather than hand-written minimal payloads.
  `Features/*` tests use fake implementations of `VikunjaCore` protocols, not HTTP
  mocks.

## Conventions

- English only — no Spanish in code, comments, strings, or test fixtures (this is
  an open-source project).
- **Commit messages: STRICT format** — Conventional Commits style, single line only.
  Format: `type(scope): description` (e.g., `feat(projects): add edit functionality`).
  RULES:
  - ONE line only. NO body, NO blank lines, NO trailers of any kind.
  - NO `Co-Authored-By`, NO `Claude-Session`, NO multi-line footers.
  - NO HEREDOC, NO git commit with `<<'EOF'` — use `-m` with quoted string only.
  - Keep subject under 72 characters.
  - Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`.
  - Small/atomic commits — check `git log` for established granularity (roughly one
    type/file-group per commit).
- Swift 6 language mode / strict concurrency in both packages
  (`swift-tools-version: 6.0`). Types crossing the `APIClient` boundary as a
  `Response` generic must be `Sendable`.
- Packages declare `iOS(.v17)` as their platform floor (for portability); the app
  target itself currently deploys at `IPHONEOS_DEPLOYMENT_TARGET = 26.2`, well
  above that floor.
- **Tests that build a `now` fixture and then add hours to stay "later today" must
  anchor `now` to noon, never use `Date()` directly.** Otherwise the suite flakes
  when it happens to run late at night: `now + a few hours` crosses midnight,
  flips the expected due-date bucket, and the assertion fails in CI without any
  code change. Pattern (see `TodayDigestTests.swift`,
  `TodaySnapshotLoaderTests.swift`, `CalendarSnapshotLoaderTests.swift`):
  ```swift
  private static let calendar = Calendar.current
  private static let now = calendar.date(
      bySettingHour: 12, minute: 0, second: 0, of: Date(),
  ) ?? Date()
  ```
