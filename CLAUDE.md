# PlowR — project memory

Read this first. It exists so each session doesn't re-derive the same facts.
Written 2026-09-10, refreshed 2026-09-26. Correct it when it goes stale — a
wrong note is worse than none.

**This repo is public.** Nothing goes into a commit, a PR description or this
file that shouldn't be on the open internet: no credentials, no account or
team IDs beyond what ships in the app, no Notion/Slack/Claude links, and no
references to other projects. PlowR stands on its own.

## What this is

**PlowR** — iOS route and client management for snow removal, lawn care, and
landscaping crews. Two roles: the business running routes, and clients who
find a business and request work. Solo project; Joe is not a developer by trade
and asks for the reasoning, not just the command.

| Thing | Name |
| --- | --- |
| GitHub repo | `FreeScoopDev/PlowR` |
| Joe's folder | `~/Desktop/Apps/PlowR` (read-only for Claude, see Process) |
| Claude's worktree | `~/Desktop/Apps/PlowR-claude` |
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

- **Version and build live in `project.pbxproj`**, project-level build settings.
  There is no `Versions.xcconfig` yet. `MARKETING_VERSION` is
  `1.1.0` on the app target. The `PlowRTests` target still carries a stale
  `MARKETING_VERSION = 1.0`; harmless, but don't read the wrong one. Nothing
  bumps the build number any more: the Archive-only `agvtool` Run Script that
  rewrote `project.pbxproj` on every local archive was removed in #2.
- **`GENERATE_INFOPLIST_FILE = YES`** for the app, *and* there is a
  `PlowR/Info.plist` with hand-written keys (usage strings, `UIBackgroundModes`,
  `NSSupportsLiveActivities`, URL schemes). Both feed the built plist. Before
  saying a key is missing, check both — and preferably the built artifact.
- **Tests must never touch real CloudKit.** A `ModelContainer` with a
  `cloudKitDatabase:` config returns fine under `try?`, then CoreData sets
  CloudKit up asynchronously and *traps* when there is no iCloud account —
  every CI runner. No `catch` can reach it. `PlowRApp.isRunningUnderTests`
  skips CloudKit mirroring; without it the host app dies with "Test crashed
  with signal trap before establishing connection." That kept CI red from
  2026-08-27 until #1 (2026-09-26).
- **The `ModelContainer` fallback chain archives the store rather than
  deleting it** (`default.store.<timestamp>.bak` in Application Support) when
  the schema is incompatible. That is deliberate: a user's data survives a bad
  migration. Don't "simplify" it to a delete.
- **Delete Account & Data** (Settings) is an App Review 5.1.1(v) requirement.
  It removes all SwiftData records, the encrypted work-orders file, and
  Keychain credentials. Any new persistent store must be added to that path or
  the deletion is incomplete and review can fail on it.

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

**Joe merges; Claude does the git work.** Claude works only in its own
worktree (`git worktree add ~/Desktop/Apps/PlowR-claude -b <branch>
origin/main`), never in `~/Desktop/Apps/PlowR`: git there is read-only with
`--no-optional-locks`, and no `switch`, `pull`, `merge` or `commit`. If Joe's
folder needs updating, give Joe the command.

1. `git fetch`, then branch from `origin/main`, never a local `main`. One
   change per branch, prefixed `feat/`, `fix/`, `chore/`, `docs/` or `test/`.
   Never stack a PR on another branch.
2. Make the change with its `CHANGELOG.md` line and run the tests.
3. Merge `origin/main` in, push the branch, open the PR. The description says
   how each claim is known (see Verifying claims).
4. Fix any red check. Give Joe the link; Joe clicks **Squash and merge**.
   Claude never merges, never pushes to `main`, never force-pushes.

CI today is GitHub Actions (`Tests` workflow, `macos-26`, `iPhone 17`
simulator); it is moving to Xcode Cloud. `docs/ci.md` has the workflow
settings, their current status and the setup steps. GitHub Pages deploys
`docs/` to getplowr.app on every push to `main`; `docs/_config.yml` keeps
`ci.md` off the site.

Run the tests locally before pushing:

    xcodebuild test -project PlowR.xcodeproj -scheme PlowR \
      -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
      -resultBundlePath /tmp/plowr.xcresult CODE_SIGNING_ALLOWED=NO

The verdict is the exit code, the literal `** TEST SUCCEEDED **`, and the
bundle's result together. Count tests from the bundle
(`xcrun xcresulttool get test-results summary --path /tmp/plowr.xcresult`),
never from the log. A piped `| tail` reports `tail`'s exit code, not
xcodebuild's. `-only-testing:` with a Swift Testing function name can match
nothing and still pass; filter to the suite and check the count.

Tracking lives in Notion (the PlowR app page in Joe's workspace).

## Verifying claims

State how each claim is known. They are not equivalent:

| Level | Worth |
| --- | --- |
| Read the source | A hypothesis. Say so. |
| Inspected the built artifact or live state | Real, for what ships or what is |
| Ran it | Real, for behaviour |
| Broke it on purpose and watched it fail | The only proof a guard guards anything |

An assertion that cannot fail is worse than none, because it is counted as
coverage. Before claiming a test guards something, break the thing and watch
it go red. Before reporting a finding, try to disprove it.

## Working with Joe

- Give the reasoning alongside the instruction.
- Anything Joe has to do is numbered steps: where to click, what to type,
  what Joe should see, and what to do if it doesn't appear.
- If a risk can be removed on Claude's side, remove it rather than handing
  Joe a rule to remember.
