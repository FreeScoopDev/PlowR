# PlowR — project memory

Read this first. It exists so each session doesn't re-derive the same facts.
Written 2026-09-10 from the repo as it stood then. Correct it when it goes
stale — a wrong note is worse than none. Wockett's `~/Desktop/PoCSquat/CLAUDE.md`
is the older sibling; the "Verifying claims" and "Working with Joe" sections
there apply here verbatim and aren't repeated.

## What this is

**PlowR** — iOS route and client management for snow removal, lawn care, and
landscaping crews. Two roles: the business running routes, and clients who
find a business and request work. Solo project; Joe is not a developer by trade
and asks for the reasoning, not just the command.

| Thing | Name |
| --- | --- |
| GitHub repo | `FreeScoopDev/PlowR` |
| Local folder | `~/Desktop/PlowR` |
| App target / scheme | `PlowR` |
| Widget + Live Activity + Control Center | `PlowRWidgets` (scheme `PlowRWidgetsExtension`) |
| Unit tests | `PlowRTests` (Swift Testing, `@Test`, not XCTest) |
| Bundle IDs | `Scoops.PlowR`, `Scoops.PlowR.PlowRWidgets` |
| App group | `group.com.Scoops.PlowR` |
| CloudKit container | `iCloud.com.Scoops.PlowR` |
| Web | `getplowr.app` (privacy policy + terms in `docs/`, GitHub Pages) |

Zero third-party dependencies — every import is an Apple framework. Keep it
that way unless there's a strong reason; adding the first one is a real decision.

Deployment target is **iOS 26.5**. Swift language mode is 5, so the Swift 6
strict-concurrency diagnostics show as warnings, not errors — `WeatherService`
currently has three.

## Architecture in one paragraph

SwiftData with a CloudKit-backed `ModelContainer`, eleven `@Model` types
registered in `PlowRApp.init`. `AuthManager` (Sign in with Apple, Keychain) is
injected as an environment object. Services under `PlowR/Services/` own the
platform work: `LocationManager` (geofencing per stop), `RouteSessionManager`
(active route state, Live Activity via `RouteActivityAttributes`),
`NotificationService` (weather alerts, overdue invoices), `CalendarService`
(EventKit — writes to a "PlowR" calendar), `WeatherService` (Open-Meteo),
`ElevationService` (Open-Topo-Data), `RouteOptimizer` (nearest-neighbor over
`MKDirections` or haversine), `WidgetDataStore` (app-group `UserDefaults`,
key `todayRoute`, read by the widget). Views are grouped by feature under
`PlowR/Views/`. `Intents/PlowRIntents.swift` holds the Siri/Shortcuts intents.

## Non-obvious things

- **Version and build live in `project.pbxproj`**, project-level build settings —
  PlowR has *not* adopted Wockett's `Versions.xcconfig`. `MARKETING_VERSION` is
  `1.1.0` on the app target. The `PlowRTests` target still carries a stale
  `MARKETING_VERSION = 1.0`; harmless, but don't read the wrong one.
- **`GENERATE_INFOPLIST_FILE = YES`** for the app, *and* there is a
  `PlowR/Info.plist` with hand-written keys (usage strings, `UIBackgroundModes`,
  `NSSupportsLiveActivities`, URL schemes). Both feed the built plist. Before
  saying a key is missing, check both — and preferably the built artifact.
- **CI is red and has been since at least 2026-08-27.** `.github/workflows/tests.yml`
  runs `xcodebuild test` on `macos-26`; the host app dies with "Test crashed
  with signal trap before establishing connection." That is the signature of
  the CloudKit trap Wockett hit: `ModelContainer(for:configurations:)` with a
  `cloudKitDatabase:` config returns fine under `try?`, then CoreData sets
  CloudKit up asynchronously and traps when there is no iCloud account (every
  CI runner). `PlowRApp.makeContainer` has no test-mode skip. Not yet confirmed
  on PlowR — confirm by adding the skip and watching CI go green, not by
  reasoning about it further.
- **The `ModelContainer` fallback chain archives the store rather than
  deleting it** (`default.store.<timestamp>.bak` in Application Support) when
  the schema is incompatible. That is deliberate: a user's data survives a bad
  migration. Don't "simplify" it to a delete.
- **Delete Account & Data** (Settings) is an App Review 5.1.1(v) requirement.
  It removes all SwiftData records, the encrypted work-orders file, and
  Keychain credentials. Any new persistent store must be added to that path or
  the deletion is incomplete and review can fail on it.
- **`PlowRTests/PlowRTests.swift` contains a placeholder `example()` test.**
  It passes and guards nothing. Either give it a real assertion or delete it;
  don't count it as coverage.

## Conventions

- **Service language is industry-agnostic** (since 1.1.0): snow, lawn, and
  landscaping share the same screens. Don't reintroduce "plow" into user-facing
  copy for a generic action.
- **Accent colour is adaptive navy**, defined once in `PlowRApp.swift` and
  applied with `.tint()`. There is no `DesignSystem.swift` yet; if a second
  shared token appears, that's the moment to create one rather than a third
  literal.
- **The widget reads only the app group `UserDefaults`.** Anything it needs to
  show has to be written by `WidgetDataStore` from the app side; the widget
  never touches SwiftData.
- **`CHANGELOG.md` entry ships with the change**, in the same commit, explaining
  *why*. Keep a Changelog format. `[Unreleased]` currently holds the 5.1.1
  compliance work that hasn't been cut to a version.

## Process

`main` on GitHub; PRs and CI on GitHub Actions (`Tests` workflow, `macos-26`,
`iPhone 17` simulator). GitHub Pages deploys `docs/` on every push to `main` —
that workflow is separate from `Tests` and passing.

Run the tests locally before pushing:

    xcodebuild test -project PlowR.xcodeproj -scheme PlowR \
      -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
      CODE_SIGNING_ALLOWED=NO

Check for the literal `** TEST SUCCEEDED **`; a piped `| tail` reports `tail`'s
exit code, not xcodebuild's.

He pushes; Claude never pushes. Read-only git with `--no-optional-locks` unless
asked to commit. Tracking lives in Notion, "Scoops Dev Command Center" — the
PlowR app page is `3c832dff-f55d-8115-bd62-e51380e7cfe4`.
