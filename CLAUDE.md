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

For comprehensive architecture details, design rationale, and implementation patterns, see `ARCHITECTURE.md`.

The app uses MVVM with protocol-oriented layering, split across Swift Packages under `Packages/`. Key modules:
- `VikunjaCore`: domain models and protocol contracts, no networking or UI
- `VikunjaNetworking`: HTTP/JSON transport layer
- `VikuAuth`: account storage and OIDC authentication
- `VikuNavigation`: cross-feature routing via `AppRoute` and `AppRouter`
- `VikuDesignSystem`: shared design tokens and reusable views
- `VikuUI`: shared view primitives and state patterns
- `Features/*`: feature packages (Onboarding, Home, Projects, Tasks, Settings, Calendar, Search)
- `VikuWidgetKit`: home-screen widget extension

The dependency graph is enforced by the compiler: Features depend only on `VikunjaCore`, `VikuNavigation`, and `VikuDesignSystem` (never on `VikunjaNetworking` or `VikuAuth`). Only `AppContainer` knows about concrete networking/auth types and wires them into protocol-typed dependencies.

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
- **Commit messages: Conventional Commits format** `type(scope): description`
  (e.g., `feat(projects): add edit functionality`). Single line, no body or blank lines.
  Keep under 72 characters. Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`.
  Atomic commits, one logical change per commit. One type/file-group per commit roughly.
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
