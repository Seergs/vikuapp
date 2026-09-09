# Architecture

This is the design doc behind this project's structure. It predates most of the
code and is kept here as a reference for *why* things are laid out the way they
are, not just *what* is where — see `CLAUDE.md` for the current, code-derived
summary.

## Context

This app is a native iOS client (Swift/SwiftUI) for [Vikunja](https://vikunja.io),
the open-source task manager people commonly self-host. Since every user points
the app at their own instance (their own URL, their own backend version, their own
configuration), the app needs:

1. A clear module/folder structure under **MVVM**.
2. A network abstraction layer so that a change in Vikunja's API doesn't force
   changes to views/view models — only to the networking layer.
3. A way to coexist with instances on different backend versions, each with its
   own set of enabled/disabled features.

Decisions locked in from the start: **SwiftUI only**, **Swift Package Manager,
multi-module**, **no local persistence for now** (everything is re-fetched from the
server; offline support is a later phase).

**Implementation status**: `VikunjaCore`, `VikunjaNetworking`, `VikuAuth`,
`VikuNavigation`, `VikuDesignSystem` (colors — brand/priority/surface/
semantic/swatch — plus typography, spacing, radius, and the toast system),
`VikuUI` (`ScreenLoadState`, `VikuStatusView`, section-header style),
`Features/Onboarding`, the `AppContainer` composition root, and the top-level
navigation shell (onboarding → floating tab bar, one `NavigationStack` per tab)
are built (see `Packages/` and `Viku/`). `Features/Projects` is built end to
end: a collapsible parent/child project tree with a per-row task-completion
tally, project creation (title + color + parent), a project overview
(subprojects + tasks grouped by status), task completion toggle, and task
deletion. It pushes into `Features/Tasks`'s task detail screen — inline
title/description editing, completion, due date, priority, label editing
(add/remove/create), relation editing (`dependsOn`/`blocks` + other kinds, via
a kind-then-task picker), a comment thread (read + post), file attachments
(upload via file importer, QuickLook preview, delete), and tap-through to a
related task's own detail screen — built as a leaf screen with no navigation
stack of its own. `Features/Tasks` also owns the quick-add task sheet reachable
from the tab bar's FAB. `Features/Home` is a "Today" screen built end to end:
every project's tasks, merged and grouped by due date, with the same
completion toggle and tap-through into `Features/Tasks`. `Features/Settings`
is fully built as multi-account management — list, add, edit, delete, and
switch the active connection, all through `AccountStoreProtocol`. Task and
project mutation (create/update/delete), label CRUD + association, relation
add/remove, and task comment fetch/add are all wired through `VikunjaNetworking`
end to end. `Features/Search` is still a placeholder screen.

---

## 1. Module structure (Swift Package Manager)

A thin Xcode project (just the app shell / composition root) plus several local
Swift Packages. Layer boundaries are enforced by the compiler, not by discipline —
if `Features/Tasks` tries to import `VikunjaNetworking` directly, it won't build.

```
vikunja-ios/
├── Viku.xcodeproj          # shell: app entry point + composition root
├── Viku/
│   ├── VikuApp.swift       # @main, builds the AppContainer and injects it
│   ├── AppContainer.swift     # composition root: builds concrete implementations
│   │                           # and injects them as protocols into each feature
│   ├── RootView.swift         # onboarding vs. main tab bar
│   └── Navigation/
│       ├── AppTab.swift               # the tab enum (iOS-26-only Tab APIs live here,
│       ├── MainTabView.swift          # not in a package, since packages floor at iOS 17)
│       └── QuickAddButton.swift       # bare circular FAB → presents Tasks' quick-add sheet
│
└── Packages/
    ├── VikunjaCore/               # 100% pure Swift, no networking, no UI
    │   └── Sources/VikunjaCore/
    │       ├── Domain/            # domain models (Task, Project, User, Label,
    │       │                      # TaskRelation, RelationKind, TaskComment,
    │       │                      # ToastStyle, InstanceAccount, InstanceURL...)
    │       ├── Protocols/         # Task/Project/Label/TaskRelation/TaskComment
    │       │                      # RepositoryProtocol, AuthServiceProtocol,
    │       │                      # AccountStoreProtocol,
    │       │                      # InstanceClientFactoryProtocol, ToastPresenting
    │       ├── Capabilities/      # VikunjaServerInfo, CapabilityProvider
    │       └── Errors/            # VikunjaError (domain-level, not HTTP)
    │
    ├── VikunjaNetworking/         # the ONLY place that knows a REST API exists
    │   └── Sources/VikunjaNetworking/
    │       ├── Client/            # APIClient protocol + URLSessionAPIClient
    │       ├── Endpoints/         # every /api/v1 route (task/project/label CRUD,
    │       │                      # relations, comments, search) in one file
    │       ├── DTOs/              # Codable models mirroring the server's JSON
    │       ├── Mappers/           # DTO -> domain model (VikunjaCore), incl.
    │       │                      # TaskMapper.merge for safe partial updates
    │       └── Repositories/      # implement VikunjaCore's protocols
    │                              # (incl. VikunjaInstanceClientFactory)
    │
    ├── VikuAuth/               # multi-account/instance + Keychain
    │   └── Sources/VikuAuth/
    │       ├── KeychainAccountStore.swift   # implements Core's AccountStoreProtocol
    │       └── Keychain.swift               # internal Keychain Services wrapper
    │
    ├── VikuNavigation/         # pure SwiftUI/Observation, no networking, no deps
    │   └── Sources/VikuNavigation/
    │       ├── AppRouter.swift    # AppRouter (one per tab stack, in the environment) + AppRoute
    │       ├── Router.swift       # generic Router<Route: Hashable>, wraps NavigationPath (intra-feature)
    │       └── DeepLink.swift     # DeepLink enum + DeepLinkRouter (external entry points — §2c)
    │
    ├── VikuDesignSystem/       # color/typography/spacing/radius tokens; toast + haptics systems (growing set)
    │   └── Sources/VikuDesignSystem/
    │       ├── Toast/             # ToastCenter (implements Core's ToastPresenting), ToastView, toastHost(_:)
    │       └── Haptics/           # HapticFeedbackCenter (implements Core's HapticFeedbackPresenting), View.vikuHaptic(_:trigger:)
    │
    ├── VikuUI/                 # shared non-token view primitives; depends only on VikuDesignSystem
    │   └── Sources/VikuUI/
    │       ├── ViewState/        # ScreenLoadState<Value> (idle/loading/loaded(Value)/failure)
    │       └── Components/       # VikuStatusView (empty/error state), View.vikuSectionHeader()
    │
    └── Features/
        ├── Onboarding/            # "connect to your instance" — built end to end
        ├── Home/                  # "Today" tab — built end to end (every project's tasks, by due date)
        ├── Projects/              # projects tab — built end to end (list, tree, overview, create, delete)
        ├── Search/                # search tab (iOS 26 `.search` role) — placeholder
        ├── Settings/              # settings tab — built end to end (multi-account: list/add/edit/delete/switch)
        ├── Tasks/                 # task detail (pushed by Home/Projects as a leaf) + quick-add sheet
        └── ...
```

### Dependency rules

This is what protects the app when Vikunja's API changes:

- `VikunjaCore` → depends on nothing.
- `VikuNavigation` → depends only on `VikunjaCore` (its `AppRoute` cases carry
  domain values); pure SwiftUI/Observation otherwise.
- `VikunjaNetworking` and `VikuAuth` → depend on `VikunjaCore` (they implement
  its protocols), but **nothing else depends on them except the composition root**.
- `VikuDesignSystem` → depends on `VikunjaCore` too, for the same reason:
  `ToastCenter` implements Core's `ToastPresenting` protocol (and
  `HapticFeedbackCenter` implements `HapticFeedbackPresenting`), so a ViewModel
  can take a toast or haptic dependency via constructor injection without
  importing `VikuDesignSystem` or SwiftUI. Every other token in the package
  stays dependency-free.
- `VikuUI` → depends only on `VikuDesignSystem` (its `VikuStatusView` uses the
  tokens). Holds the cross-feature view primitives that aren't tokens
  (`ScreenLoadState<Value>`, `VikuStatusView`, `View.vikuSectionHeader()`), so
  they live in one place instead of being copied per feature.
- `Features/*` → depend on `VikunjaCore` (protocols + models), `VikuNavigation`,
  `VikuDesignSystem`, and `VikuUI` as each needs. None **ever** import
  `VikunjaNetworking` directly.
  Views use `VikuDesignSystem` tokens (`VikuColor`, `VikuFont`,
  `VikuSpacing`, `VikuRadius`) instead of hardcoding colors, fonts,
  spacing, or corner radii — that's what keeps the app visually consistent as
  `VikuDesignSystem` grows.
- The app / composition root → the only place that knows both `VikunjaCore`'s
  protocols and `VikunjaNetworking`/`VikuAuth`'s concrete implementations, and
  wires them together. It's also the only place that knows about every Feature's
  root view at once (to build the tab bar) — Features never reference each other.

If Vikunja changes its API tomorrow (renames a field, changes an endpoint, adds a
resource), the change stays contained to `VikunjaNetworking`. Features and their
view models never notice, because they only know about protocols and domain
models.

---

## 2. MVVM per feature

Each `Features/<Name>` folder follows the same internal shape:

```
Features/Tasks/Sources/Tasks/
├── Models/            # (view-specific state, if needed — not domain models)
├── ViewModels/
│   └── TaskListViewModel.swift
├── Views/
│   ├── TasksRootView.swift   # public: the tab's root content + any
│   │                         #   .navigationDestination(for: TasksRoute.self)
│   ├── TaskListView.swift    # internal: content, reads @Environment(AppRouter.self)
│   └── TaskRowView.swift
└── Navigation/
    └── TasksRoute.swift      # feature-local route enum (feature-private payload only)
```

- **Model**: comes from `VikunjaCore.Domain` (e.g. `VikunjaTask`, `Project`). No
  network models here — those are DTOs and stay locked inside `VikunjaNetworking`.
  A feature that also needs view-only state keeps *feature-specific* state in its
  own `Models/` — never a domain model. State primitives shared across features
  are not copied per feature: the request-lifecycle enum is `VikuUI`'s
  `ScreenLoadState<Value>`, and user-facing error copy is `VikunjaCore`'s
  canonical `VikunjaError.displayMessage`.
- **ViewModel**: `@Observable` (or `ObservableObject` if the iOS minimum requires
  it), receives a protocol via **constructor injection**, never a concrete
  networking class:

  ```swift
  // VikunjaCore/Protocols/TaskRepositoryProtocol.swift
  public protocol TaskRepositoryProtocol {
      func fetchTasks(projectID: Project.ID) async throws -> [VikunjaTask]
      func update(_ task: VikunjaTask) async throws -> VikunjaTask
  }

  // Features/Tasks/ViewModels/TaskListViewModel.swift
  @Observable
  final class TaskListViewModel {
      private let repository: TaskRepositoryProtocol
      init(repository: TaskRepositoryProtocol) { self.repository = repository }
      ...
  }
  ```

- **View**: pure SwiftUI, only reads state from the ViewModel and sends it
  intents. Zero business logic, zero networking knowledge.
- **Navigation**: one mechanism for anything that crosses a feature boundary,
  one for anything that doesn't (architecture audit F-12 collapsed five ad-hoc
  styles into these two).
  - **Cross-feature**: `VikuNavigation.AppRoute` — an app-wide `Hashable` enum
    (`taskDetail(VikunjaTask, Project)`, `projectOverview(Project)`; cases
    carry `VikunjaCore` domain values only) — pushed onto
    `VikuNavigation.AppRouter`, an `@Observable`/`@MainActor` wrapper around
    one tab's `NavigationPath`. The app target creates one `AppRouter` per tab,
    binds the tab's `NavigationStack(path:)` to it, and puts it in that stack's
    environment; any screen — however deep, across module boundaries — reads
    `@Environment(AppRouter.self)` and calls `push`. A single
    `.appDestinations(...)` modifier in the app target (`Viku/Navigation/
    AppDestinations.swift`) is the only place an `AppRoute` resolves to a
    concrete screen. Because `.navigationDestination(for:)` keys off the stable
    value in the path, the pushed screen and its view model survive re-renders
    — this replaced the `(T) -> AnyView` destination closures and the
    `...DestinationBox` identity workarounds.
  - **Intra-feature**: `VikuNavigation.Router<Route>` — the same generic
    `@Observable`/`@MainActor` `NavigationPath` wrapper — typed to a `Route`
    enum for destinations whose payload is feature-private (e.g. `Projects`'
    `ProjectsRoute.projectOverview(ProjectNode)` carries the loaded subtree) or
    whose whole stack is self-contained (`Settings`). A feature-local route is
    still pushed onto the tab's `AppRouter` path (`push(_ route: some Hashable)`)
    and resolved by that feature's own `.navigationDestination(for: Route.self)`
    on the same stack; `Settings` keeps its own `NavigationStack` + `Router`.

This keeps "V" and "VM" cleanly separated from "M", and the Model never knows HTTP
exists — only `VikunjaNetworking` does.

**A feature with no top-level screen of its own**: `Features/Tasks` as actually
built is a task-detail screen (always pushed as a leaf onto whichever feature's
stack opened it) plus a quick-add sheet (presented as a `.sheet` by
`MainTabView`'s FAB). It owns no `NavigationStack`/`Router`; `TaskDetailView`
navigates to a related task, its project pill, or a just-created duplicate by
pushing an `AppRoute` onto the hosting stack's `AppRouter` — it never imports
`Projects` or knows what screen a route resolves to. No feature ever imports
another feature's package.

---

## 2b. Top-level navigation: onboarding → floating tab bar

`Viku/RootView.swift` is the only place that switches between the two
top-level app states: no saved account (`InstanceSetupView`, from
`Features/Onboarding`) and an active account (`MainTabView`). It holds this as
plain `@State private var connectedAccount: InstanceAccount?` — two states don't
need a dedicated enum. It re-reads the active account from
`AccountStoreProtocol` on launch (async Keychain lookup, so a `ProgressView`
covers the gap rather than flashing onboarding first) and again whenever
`MainTabView` reports `onAccountsChanged` — fired by `Features/Settings`'
connection screens after switching accounts, deleting the active one, or
editing its own address. `MainTabView` is rendered keyed by
`.id(connectedAccount)`, so any of those changes tears the whole tab shell
down and rebuilds it against the new account, since every tab's view models
were constructed against the old account's `baseURL` and don't observe
changes to it. Deleting the last saved account surfaces here too: the re-read
comes back `nil` and `RootView` falls back to onboarding.

`MainTabView` (`Viku/Navigation/MainTabView.swift`) is the floating, Liquid
Glass bottom tab bar — the default rendering for `TabView` built with the modern
`Tab(value:)` API on iOS 26+, no extra styling code required. It owns one
`NavigationStack` + `AppRouter` per tab (held in `@State`, so switching tabs
never resets where you were in another one — the same pattern Apple's own
Music/App Store apps use — and rebuilt on account switch via
`.id(connectedAccount)`), each hosting a Feature's stack-less `<Name>RootView`
and the shared `.appDestinations(...)` resolver. `Settings` is the exception:
`SettingsRootView` still owns its own `NavigationStack` + `Router<SettingsRoute>`
(a fully self-contained stack).

```swift
TabView(selection: $selection) {
    Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: .home) {
        NavigationStack(path: $homeRouter.path) {
            HomeRootView(viewModel: todayViewModel)
                .appDestinations(container: container, account: account)
        }
        .environment(homeRouter)
    }
    Tab(AppTab.projects.title, systemImage: AppTab.projects.systemImage, value: .projects) {
        NavigationStack(path: $projectsRouter.path) {
            ProjectsRootView(/* view-model + make…ViewModel closures from AppContainer */)
                .appDestinations(container: container, account: account)
        }
        .environment(projectsRouter)
    }
    Tab(AppTab.settings.title, systemImage: AppTab.settings.systemImage, value: .settings) {
        SettingsRootView(/* account + make…ViewModel closures from AppContainer */)
    }
    Tab(value: AppTab.search, role: .search) {   // separated glass pill, iOS 26 search role
        NavigationStack(path: $searchRouter.path) {
            SearchRootView(viewModel: searchViewModel)
                .appDestinations(container: container, account: account)
        }
        .environment(searchRouter)
    }
}
.tabBarMinimizeBehavior(.onScrollDown)
.overlay(alignment: .bottomTrailing) {           // bare circular FAB, not a system accessory
    QuickAddOverlay(container: container, account: account)   // owns the FAB + its sheet's @State
}
```

The FAB is a plain `.overlay`, **not** `.tabViewBottomAccessory`: that API
always paints a system glass background behind its content and centres it over
the tab bar — neither suppressible nor corner-anchorable — so it can't match
the mockup's bare floating button. It presents `Features/Tasks`'
`QuickAddSheetView`.

The FAB stays global (one instance on the tab shell) but the sheet defaults
its project from context. `AppContainer` owns a `QuickAddContext` (an
`@Observable` conforming to `VikunjaCore`'s `QuickAddContextTracking`, injected
the same way `ToastCenter`/`ToastPresenting` is): a visible project-scoped
screen — a `ProjectOverview` or a `TaskDetail` — pushes its own project id
there via `markVisible()`/`markHidden()` (`onAppear`/`onDisappear`), and every
other screen leaves it untouched. It's a stack, not one value, so a task
detail pushed onto its project's overview (two active scopes for the same
project, enter/exit events in either order) stays correct;
`preselectedProjectID` is the innermost still-active scope. `MainTabView`'s
`QuickAddOverlay` — a child view split out so the FAB/sheet `@State` never
re-evaluates `MainTabView`'s body (which would rebuild every tab's
`NavigationStack` and view models and blank the screen behind the sheet) —
snapshots that id in the tap handler (not in `body`, so the `@Observable`
read doesn't rebuild the sheet's view model when a scope enters/leaves the
stack) and hands it to `makeQuickAddTaskViewModel`; when it's
`nil`, the quick-add sheet falls back to the account's Vikunja default project
(`settings.default_project_id` from `GET /api/v1/user`, via
`UserRepositoryProtocol`). That request is **not** made when the sheet opens —
`AppContainer.refreshDefaultProject` fetches it once per launch (and on
account switch, from `RootView`) and caches it on device in
`DefaultProjectStore` (`UserDefaults`, keyed by account id);
`makeQuickAddTaskViewModel` reads that cache synchronously and passes it as
`accountDefaultProjectID`.

`AppTab`, `MainTabView`, `QuickAddOverlay`, and `QuickAddButton` live in the app target, not a
package, because `Tab(role:)` and `.tabBarMinimizeBehavior` are iOS-26-only
APIs, while every package floors at `.iOS(.v17)` for portability (see
`CLAUDE.md` § Conventions). `AppTab` is also the one enum allowed to know about
every Feature's tab at once — Features themselves never reference each other.

No root-level account switcher exists outside Settings — switching, adding,
editing, and removing connections is a `Features/Settings` concern
(`ConnectionsListView`/`ConnectionFormView`, see §5) rather than top-level
navigation state; `RootView` only reacts to the *result* via
`onAccountsChanged`.

---

## 2c. External entry points: deep links and App Intents

Several things outside the app need to open it straight to the quick-add task
sheet: the Today widget's "add" button, a Lock Screen accessory widget, a Siri
phrase / the Shortcuts app, and a Control Center control. Rather than each one
knowing how to drive navigation, they all converge on one small primitive.

**`DeepLink` + `DeepLinkRouter` (`VikuNavigation`).** `DeepLink` is a
dependency-free enum of external destinations (`.quickAdd(projectID:)` today).
`DeepLinkRouter` is an `@Observable`/`@MainActor` box holding one pending
`DeepLink` — set by whoever received the external trigger, drained by the screen
that acts on it. It lives in `VikuNavigation` (next to `AppRouter`) for
two reasons: it's a navigation primitive, and `VikuWidgetKit` has to import
it so a widget-side App Intent can construct a `DeepLink` without depending on
the app target.

**Feeding the router:**

- **URL scheme.** The app registers its scheme (an `Info.plist`
  `CFBundleURLTypes` entry — the one reason the otherwise-generated Info.plist
  is checked in — set from the `$(VIKU_URL_SCHEME)` build setting, so it's
  `viku` in Release and `viku-dev` in Debug to keep a dev and a prod
  install from clashing). `RootView`'s `.onOpenURL` parses `<scheme>://quick-add`
  into a `DeepLink` (parsing stays in the app target, since the scheme string is
  `VikuWidgetKit`'s `VikuWidgetConfig.urlScheme`) and calls
  `router.open(_:)`. Both widgets reach it via `.widgetURL` — the same mechanism
  the Today widget already used for `<scheme>://today`.
- **App Intents.** `OpenQuickAddIntent` (`openAppWhenRun = true`) calls
  `DeepLinkRouter.shared.open(.quickAdd(...))` from its `perform()`.

**Draining the router.** `MainTabView`'s `QuickAddOverlay` — the same child view
that owns the FAB and its sheet (§2b) — observes `router.pending` via
`.onChange` (a link that lands while the shell is up) plus `.task` (a link
already parked at cold launch, before the tab shell existed), presents the
quick-add sheet, and clears the router. This stays in `QuickAddOverlay` rather
than `MainTabView` for the same reason the FAB state does: reading the router in
`MainTabView`'s body would rebuild every tab's `NavigationStack`.

**Two decisions worth recording:**

- **A process-wide singleton (`DeepLinkRouter.shared`), not an App Intents
  `@Dependency`.** `@Dependency` + `AppDependencyManager` registration races the
  intent's `perform()` when `openAppWhenRun` cold-launches the app, and failed
  in practice. `AppContainer` holds `DeepLinkRouter.shared`, so the intent
  (whose `perform()` runs in the app's process) and the UI observe one instance.
- **The Siri-facing `OpenQuickAddIntent` lives in the app target; the Control
  Center control uses a separate `QuickAddControlIntent` in `VikuWidgetKit`.**
  An App Intent type registered in *both* the app and the widget extension (via
  a shared framework) breaks Siri's App Shortcut dispatch — Siri matches the
  phrase, then can't launch the app. So the intent behind the
  `AppShortcutsProvider` (`VikuShortcuts`, which has to be in the app target
  anyway) stays app-only, and the control gets its own hidden
  (`isDiscoverable = false`) intent. Both do the same one line against
  `DeepLinkRouter.shared`.

Siri phrases are localized in `AppShortcuts.xcstrings` — Siri matches phrases in
its own language, not by the words the user speaks, so an English-only phrase
list is invisible to a non-English Siri.

---

## 3. Network abstraction layer (protection against API changes)

Three layers, each with a single responsibility:

**a) `APIClient` — generic transport, knows nothing about Vikunja**

```swift
public protocol APIClient: Sendable {
    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> Response
    func send(_ endpoint: Endpoint) async throws // no response body
}
```

The concrete implementation (`URLSessionAPIClient`, an `actor`) is built with a
base URL and an optional `@Sendable () async -> String?` token provider,
attaches the bearer header per request, and maps raw HTTP status codes to
domain-level `VikunjaError`. An `Endpoint` is a plain struct (path, method,
query, body `Data`), with an `Endpoint.encoding(path:method:body:)` helper that
JSON-encodes an `Encodable` body — adding/changing a route means touching the
single `VikunjaEndpoints` file.

**b) DTOs + Mappers — the buffer against JSON changes**

DTOs (`TaskDTO`, `ProjectDTO`, ...) are a *tolerant* mirror of the real JSON
(optional fields where the server added them recently, explicit `CodingKeys`). A
`Mapper` converts a DTO into a `VikunjaCore` domain model. If Vikunja renames or
adds a field, you touch the DTO and the mapper; the domain model and everything
upstream (ViewModels, Views) stays untouched.

One quirk this layer absorbs: Vikunja's task-update endpoint is a **full
replace** — any field missing from the request body is reset server-side, not
left alone. So `VikunjaTaskRepository.update` first `GET`s the current task and
`TaskMapper.merge(_:onto:)` overlays only the fields `VikunjaTask` actually
tracks, carrying every other field (including ones the domain model doesn't
model at all — `percent_done`, `reminders`, ...) through untouched. `TaskDTO`
deliberately holds that long tail of never-mapped fields for this reason.
Relations and labels aren't in the task body at all — they have their own
endpoints (`/tasks/{id}/relations`, `/tasks/{id}/labels`) behind
`TaskRelationRepositoryProtocol` / `LabelRepositoryProtocol` — so a caller that
edits a task has to re-attach the relations/labels it already loaded onto the
update response itself (see `Features/Tasks`). Comments are the same shape
again: their own endpoint (`/tasks/{id}/comments`) behind
`TaskCommentRepositoryProtocol`, mapped by `CommentMapper`. Vikunja stores a
comment's body as its rich-text editor's HTML output — `CommentDTO.comment` is
carried through as-is; rendering it as plain text is a `Features/Tasks`
concern (`CommentTextFormatter`), not something this layer strips.

**c) `Repository` — implements `VikunjaCore`'s protocols**

```swift
final class VikunjaTaskRepository: TaskRepositoryProtocol {
    private let client: APIClient
    func fetchTasks(projectID: Project.ID) async throws -> [VikunjaTask] {
        let dtos: [TaskDTO] = try await client.send(.tasks(projectID: projectID))
        return dtos.map(TaskMapper.toDomain)
    }
}
```

This is the piece injected into the `AppContainer` and handed to Features **as a
protocol**. If the API changes, worst case you rewrite `APIClient`, `Endpoint`s,
DTOs, and `Mapper`s — zero changes in `VikunjaCore` or `Features`.

---

## 4. Different instances, different server versions

Solved with **runtime feature detection**, not hand-rolled `if version > X` checks
scattered everywhere. Vikunja exposes a public `GET /api/v1/info` endpoint that
returns the server version and flags like `caldav_enabled`, `totp_enabled`,
`max_file_size`, registration limits, etc. — this maps directly onto the design:

```swift
// VikunjaCore/Capabilities/VikunjaServerInfo.swift
public struct VikunjaServerInfo: Sendable {
    public let version: String
    public let caldavEnabled: Bool
    public let totpEnabled: Bool
    public let registrationEnabled: Bool
    // ... remaining flags exposed by /info
}

public protocol CapabilityProvider {
    var serverInfo: VikunjaServerInfo { get async throws }
    func supports(_ feature: VikunjaFeature) -> Bool
}
```

- When connecting to an instance (or logging in), the app hits `/info` once and
  the `CapabilityProvider` caches the result in memory for that session (a
  longer-lived per-account `SessionManager` is still future work — see §5).
- Features query `capabilityProvider.supports(.totp)` to show/hide UI, instead of
  hardcoding version comparisons spread across the codebase.
- For differences in **JSON shape** between old/new backend versions (not just
  feature on/off flags), the buffer is the tolerant DTOs from section 3b: optional
  fields plus defaults, and if needed, a mapper that branches by version
  (`if serverInfo.version < "0.24" { ... }`) — but that logic stays **locked inside
  `VikunjaNetworking`**, never leaking into a Feature.
- If Vikunja ever ships a truly incompatible change (a new API shape, not just new
  fields), the pattern scales by adding a second `Mapper` (`TaskMapperV2`) selected
  at runtime based on `serverInfo.version` — still without touching anything
  outside `VikunjaNetworking`.

---

## 5. Multi-account / multi-instance (Mastodon-app style)

Each user can have 1+ configured instances (their own self-hosted one, a work
instance, the public Vikunja instance, etc). `InstanceAccount` and
`AccountStoreProtocol` live in `VikunjaCore` — not `VikuAuth` as originally
sketched here — because `AccountStoreProtocol` needs to reference
`InstanceAccount` in its signature, and `VikunjaCore` depends on nothing:

```swift
public struct InstanceAccount: Identifiable, Codable {
    public let id: UUID
    public var displayName: String
    public var baseURL: URL
    public var createdAt: Date
    // the token itself does NOT live here — it's in the Keychain, referenced by `id`
}
```

- Only API token auth is modeled for now (`AuthServiceProtocol.loginWithAPIToken`,
  not the password/JWT flow) — no `authMethod` field on `InstanceAccount` until a
  second auth method actually needs one.
- `AccountStoreProtocol` (`VikunjaCore`) is implemented by `KeychainAccountStore`
  in `VikuAuth`: it stores the account list, each account's bearer token
  (keyed by account id, so removing one account never touches another's secret),
  and which account is active — all in the Keychain, never `UserDefaults`. The
  protocol is full CRUD, not just add-on-connect: `fetchAccounts`,
  `activeAccount`, `addAccount(_:token:)` (also makes it active),
  `updateAccount(_:token:)` (metadata in place, optionally rotating the token,
  without changing which account is active), `removeAccount(id:)`,
  `setActiveAccount(id:)`, and `token(forAccountID:)`. `Features/Settings` is
  what actually exercises all of it — list every account, add one, edit one
  (including rotating its token), delete one, and switch which is active; see
  `CLAUDE.md`'s `Features/Settings` entry for the screen-level detail.
- `InstanceClientFactoryProtocol` (`VikunjaCore`, implemented by
  `VikunjaInstanceClientFactory` in `VikunjaNetworking`) builds clients for a
  given instance URL: a `CapabilityProvider` for a URL that doesn't have an
  account yet (so onboarding — and `Settings`' "test connection" — can probe
  `GET /api/v1/info` to confirm an address is a real Vikunja instance before
  the connection is saved), and each repository (`makeTaskRepository`,
  `makeProjectRepository`, `makeLabelRepository`,
  `makeTaskRelationRepository`, `makeTaskCommentRepository`,
  `makeTaskAttachmentRepository`) for an
  already-connected account, taking a `tokenProvider` closure that resolves
  the bearer token per request. This is the seam `AppContainer` wires screen
  dependencies through.
- `InstanceURL.normalize(_:)` (`VikunjaCore`) turns whatever the user typed — a
  bare domain or a full URL, with or without a trailing path — into the
  scheme+host `URL` the networking layer expects as `baseURL`.
- A `SessionManager` that tracks the active account's live `APIClient` +
  `CapabilityProvider` for the rest of the app to use, and OIDC support, are
  still future work. Not needed yet: today every `AppContainer` factory just
  builds a fresh repository per screen call from the account's `baseURL` plus
  a token-provider closure — see §6.

---

## 6. Dependency Injection

No third-party library: a plain `AppContainer` in the `App` target, using
constructor injection. It's the only file in the project that imports both
`Core`'s protocols and `Networking`/`Auth`'s concrete implementations.

```swift
@MainActor
final class AppContainer {
    let accountStore: AccountStoreProtocol          // KeychainAccountStore
    let clientFactory: InstanceClientFactoryProtocol // VikunjaInstanceClientFactory
    let toastCenter = ToastCenter()                  // the app's single toast host
    let hapticCenter = HapticFeedbackCenter()        // the app's single Taptic Engine

    // One factory per screen. Each resolves the account's repositories from the
    // factory (baseURL + a per-request keychain token-provider closure) and
    // passes `toastCenter` wherever a `ToastPresenting` is needed (and
    // `hapticCenter` wherever a ViewModel takes `HapticFeedbackPresenting`).
    func makeTodayViewModel(account: InstanceAccount) -> TodayViewModel { ... }
    func makeProjectsListViewModel(account: InstanceAccount) -> ProjectsListViewModel { ... }
    func makeTaskDetailViewModel(task:project:account:) -> TaskDetailViewModel { ... }
    func makeQuickAddTaskViewModel(account:) -> QuickAddTaskViewModel { ... }
    // account CRUD doesn't take `account:` — it isn't scoped to one instance
    func makeConnectionsListViewModel(onActiveAccountChanged: @escaping () -> Void) -> ConnectionsListViewModel { ... }
    func makeConnectionFormViewModel(mode: ConnectionFormMode, onActiveAccountChanged: @escaping () -> Void) -> ConnectionFormViewModel { ... }
    // ...
}
```

There's no long-lived `SessionManager` yet — a screen's repositories are built
on demand from the active `InstanceAccount`. This keeps zero new external
dependencies, stays testable (tests build view models with fakes conforming to
the same `VikunjaCore` protocols), and reinforces the central idea: anything
"dirty" about networking lives behind a wall of protocols.

---

## 7. Testing

- `VikunjaCore` has no networking → trivial to test in isolation.
- `VikunjaNetworking` is tested with **real JSON fixtures** captured from Vikunja
  instances on different versions (contract tests) — this is what gives an early
  warning if a new server version broke a DTO.
- `VikuNavigation`'s `Router` is tested directly (push/pop/popToRoot against a
  private test route enum), independent of any Feature that uses it.
- `Features/*` test their ViewModels against fake implementations of `Core`'s
  protocols (no need to spin up networking or mock HTTP).

---

## Next steps

The shell is built and wired, and the central slice of Vikunja's model is real
end to end on top of `VikunjaCore`/`VikunjaNetworking`: `Home` (every project's
tasks merged and grouped by due date), `Projects` (list → tree → overview,
plus project creation and task deletion), `Tasks` (a detail screen with
editable title/description/completion/due date/priority/labels/relations plus
a comment thread and file attachments, and a tab-bar quick-add sheet), and
`Settings` (full multi-account management). Task and project
create/update/delete, label CRUD + association, relation add/remove, task
comment fetch/add, and task attachment upload/download/delete all go through
the networking layer.

Open threads:

- **`Search`** is still a placeholder. The natural next slice is a real query
  against `ProjectRepositoryProtocol` / `TaskRepositoryProtocol.searchTasks`
  (both already exist).
- **Subtasks** render read-only on the detail screen (a `TaskRelation` is too
  thin to round-trip through an update without an extra fetch per row) — making
  them togglable/creatable like the other relation kinds is unfinished.
- **Comment rich text**: comment bodies round-trip as plain text
  (`CommentTextFormatter` strips the server's stored HTML on the way in, edits
  send plain text back) — there's no rich-text renderer or editor yet.
- **`SessionManager`** (a single source of truth for the active account's live
  `APIClient` + `CapabilityProvider`) and **OIDC** are still unbuilt — today
  each `AppContainer` factory builds its own repository per screen from the
  account's `baseURL` + a keychain token-provider closure.
- **Offline / local persistence** remains a later phase — everything is still
  re-fetched from the server.
