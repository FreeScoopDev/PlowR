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
| Claude's worktrees | `~/Desktop/Apps/PlowR-claude/<branch>`, one per branch (shared PROCESS.md, step 1) |
| App target / scheme | `PlowR` |
| Widget + Live Activity + Control Center | `PlowRWidgets` (scheme `PlowRWidgetsExtension`) |
| Unit tests | `PlowRTests` (Swift Testing, `@Test`, not XCTest) |
| Bundle IDs | `Scoops.PlowR`, `Scoops.PlowR.PlowRWidgets` |
| App group | `group.com.Scoops.PlowR` |
| CloudKit container | `iCloud.com.Scoops.PlowR` |
| Web | `getplowr.app` (privacy policy + terms in `docs/`, GitHub Pages) |

Zero third-party dependencies — every import is an Apple framework. Keep it
that way unless there's a strong reason; adding the first one is a real decision.

Deployment target is **iOS 26.0** (was 26.5 until 2026-09-29; nothing needed more). Swift language mode is 5, so the Swift 6
strict-concurrency diagnostics show as warnings, not errors. Since
2026-10-06 a Release build has none; keep it at none. Two causes, two fixes:
passing a function by name (`map(Type.init)`, `map(render)`) is checked as
having no actor, so write a closure (`map { Type($0) }`) instead; and code
with no actor (nonisolated helpers such as `StopRecording`, the
`WeatherService` actor, ActivityKit with the Live Activity's attributes)
can only call what's marked `nonisolated`, as `PlowRColor` is. Since the
same day a Release build has no warnings at all: the APIs iOS 26 deprecated
(`CLGeocoder`, `MKPlacemark` and `placemark`, `UIScreen.main`) were replaced.
Look addresses up with `AddressPin` (`MKGeocodingRequest`), and read a map
item's `location` and `address`.

## Architecture in one paragraph

SwiftData with a CloudKit-backed `ModelContainer`, the `@Model` types listed
in `PlowRApp.models` (a count here went stale twice). `AuthManager` (Sign in with Apple, Keychain) is
injected as an environment object. Services under `PlowR/Services/` own the
platform work: `LocationManager` (the route screen's GPS and ETAs), `SiteMonitor` (job-site
areas, see below), `ActiveRouteStore`
(the in-progress route: current stop, stop timer, checkpoint that survives a
relaunch; Live Activity and widget via `SystemRouteSurfaces`),
`RouteSessionManager` (what Siri and Control Center hand the route screen:
a text to open, a message to show),
`NotificationService` (weather alerts, overdue invoices), `CalendarSync`
(Settings switch, off by default: keeps a "PlowR" calendar in step with the
schedule through EventKit; `VisitCalendar` works out the changes),
`WeatherService` (Open-Meteo),
`ElevationService` (Open-Topo-Data), `RouteOptimizer` (nearest-neighbor over
`MKDirections` or haversine), `WidgetDataStore` (app-group `UserDefaults`,
key `todayRoute`, read by the widget). Views are grouped by feature under
`PlowR/Views/`. `Intents/PlowRIntents.swift` holds the Siri/Shortcuts intents.

## Non-obvious things

- **`Versions.xcconfig` owns the version numbers** for every target (app,
  widget, tests). The project's Debug and Release configurations are based on
  it and no target sets its own values, so bump `MARKETING_VERSION` there and
  nowhere else. `CURRENT_PROJECT_VERSION` must stay defined (the generated
  Info.plist reads it), but Xcode Cloud's Release Flow ignores it and numbers
  builds itself; only a manual archive uses it. Nothing bumps it automatically
  (the Archive-only `agvtool` script was removed in #2).
- **`GENERATE_INFOPLIST_FILE = YES`** for the app, *and* there is a
  `PlowR/Info.plist`. Both feed the built plist. Since the Xcode 27 upgrade the
  usage strings, `NSSupportsLiveActivities` and `ITSAppUsesNonExemptEncryption`
  are `INFOPLIST_KEY_*` build settings (Debug and Release, both), and the file
  keeps only what has no build setting: `UIBackgroundModes`, URL schemes,
  `LSApplicationQueriesSchemes`, the icon name. Before saying a key is missing,
  check both — and preferably the built artifact.
- **Tests must never touch real CloudKit.** A `ModelContainer` with a
  `cloudKitDatabase:` config returns fine under `try?`, then CoreData sets
  CloudKit up asynchronously and *traps* when there is no iCloud account —
  every CI runner. No `catch` can reach it. `PlowRApp.isRunningUnderTests`
  skips CloudKit mirroring; without it the host app dies with "Test crashed
  with signal trap before establishing connection." That kept CI red from
  2026-08-27 until #1 (2026-09-26). Every test database also turns off
  autosave (`mainContext.autosaveEnabled = false`): a pending autosave fired
  after a test had let its store go and trapped in `ModelContext.autosave`,
  intermittently crashing the test host mid-run and taking the remaining
  tests with it (#99). A new test container needs that line too.
- **`ICloudStatus` asks CloudKit for the account's status** (the Dashboard
  card, Settings > Data & Backup). `PlowRApp.isCloudKitAvailable` only says
  whether the iCloud database opened, and it opens fine for a user who isn't
  signed in to iCloud. `ICloudStatus.accountStatus()` never asks CloudKit
  under tests, for the reason above; tests pass in a stand-in `check` and
  their own `NotificationCenter`. Unverified: whether the "local" fallback
  (`localConfiguration`, CloudKit setting left automatic) really stays off
  iCloud on a signed build, so the card says sync "may be off".
- **The `ModelContainer` fallback chain archives the store rather than
  deleting it** (`default.store.<timestamp>.bak` and the photo folder, beside
  the store: the app-group container on a signed build), and only when the
  store can't be migrated even with iCloud off: a Core Data migration error, not a full disk or a locked file (`StoreArchive.verdict`). Any
  other failure stops the app with the data in place. That is deliberate: a
  user's data survives a bad migration, and a store that merely failed to open
  is never hidden behind an empty app. Don't "simplify" it to a delete, or to
  archiving on any failure.
- **SwiftLint gates merges.** The `SwiftLint` job in `guards.yml` fails on any
  error-severity violation (force unwrap, force cast, `try!`) and is a required
  check on `main`. It was report-only until the 35 force-unwraps were removed
  (#17). The annotations stop at 10; the log's `Found N violations, M serious`
  line has the full count. **Blind spot:** `force_unwrapping` does not flag a
  force-unwrapped initializer call such as `URL(string: "…")!` (verified
  2026-09-27), so the gate isn't a guarantee that no `!` exists. The app and
  widget have none since 2026-09-30 (the six were literal URLs in
  `SettingsView` and `ActiveRouteView`); check by hand with
  `git grep -nE '\)!([^=]|$)' -- 'PlowR/*.swift' 'PlowRWidgets/*.swift'`,
  which should print nothing. `PlowRTests` is outside the lint and keeps its
  own. Never add a `swiftlint:disable` to get past it:
  remove the unwrap. Never run `scripts/lint.sh --fix` without
  `scripts/test.sh` after it.
- **The camera opens only through `CameraPicker`** (`Views/Shared`), and a
  Camera button shows only when `CameraPicker.isAvailable`: opening it on a
  device without one (some iPads, a Mac) throws. The `Camera guard` step,
  inside the required `Service-language guard` job, fails a camera opened or
  checked anywhere else, so a red check there may be about the camera.
- **A route in progress lives in `ActiveRouteStore`, never in a view.** Only
  `start(_:)` and `end()` begin and finish it; the route screen can disappear or
  be killed without losing the stop. `MainTabView` shows the route screen
  whenever `isActive`. A checkpoint (route ID, current stop's ID and index, stop
  start time) is saved in `UserDefaults` on every change and restored at launch
  in `PlowRApp.init`, before any view. The current stop is tracked by ID, not
  position, because iCloud can reorder or delete stops (or the whole route)
  from another device; `validate()` runs on every store save, on remote
  changes and when the app becomes active, and ends a route that no longer
  exists. UI completions pass the stop that was on screen
  (`completeCurrentStop(expecting:)`); if sync changed it, nothing is recorded
  (`.stopChanged`), so a visit is never credited to the wrong client. Tests of
  "after a relaunch" must build the before-store with `makeClosedAppStore()`:
  a configured store observes saves and fixes its own checkpoint, which hid
  two bugs. Siri's Complete Current Stop and Control Center's Complete Stop go
  through the store too (`CompleteStopAction`), so they work without the route
  screen, and they complete only the stop the user saw: Siri the current one
  unless iCloud changed it unseen (`stopChangedUnseen`, kept in the checkpoint,
  since iOS can end the app before the user looks), Control Center the one its
  control showed: the control shows the current stop's client, drawn from the
  widget data, its intent carries that stop (`stopID`), and the app reloads
  the control whenever the data changes. "Seen" is a stand-in:
  the route screen was up with the app in front, not proof that anyone
  looked. Only a business (`userRole == "operator"`) completes stops from
  outside. Siri's Notify Next Client only opens a text to the current
  stop's client and completes nothing (`NotifyNextAction`): it leaves a
  request in `RouteSessionManager.textRequest`, and the route screen opens
  it once nothing else is up, if `NotifyNextAction.stopToOpen` says it's
  still for the current stop and under two minutes old.
- **Job-site areas (geofences) belong to `SiteMonitor`, made at launch**,
  not to a screen: iOS relaunches the app for a crossing and hands it to the
  location manager that exists then. `ActiveRouteStore` decides what's watched
  (the current stop, and completed stops awaiting a departure,
  `SiteDepartures`, for two hours and past End Route) and what a crossing
  means (`SiteTimes`: arrival and departure, put on the stop's
  `ServiceRecord` as `arrivedAt` and `leftAt`). Only what GPS saw is kept: an
  entry within a minute of the stop beginning or of its area being placed
  (the pin moved, location allowed only then), or an exit with no entry, is
  "arrival not caught", never a made-up time. `LocationManager` must not place
  or clear areas: replacing an area makes iOS work out afresh whether the
  phone is inside it, and a crossing then is missed.
- **Below a contract's snow trigger** (`TriggerCheck`, `TriggerChecks`): a
  day a client's place got less snow than their trigger, though the forecast
  (the storm card, `StormWatch`) said a storm. Marked by hand (storm card,
  contract page) or checked at the stop (Below Trigger on the route screen,
  which calls `ActiveRouteStore.passCurrentStop(expecting:)`: moves on like
  completing, but records no visit, time or Service Log record). A marked
  stop starts skipped on its route's page (`TodaysRun.belowTrigger`). The
  Service Report lists the days, saying which kind each is.
- **A control that acts in the app needs its intent in both targets.**
  Control Center's `CompleteStopControlIntent` is compiled into the app and
  the widget extension, with `openAppWhenRun`, so the system runs it in the
  app, where the route is; each target defines `complete(shownStop:)` for
  itself (the extension's does nothing). What the user saw has to travel in
  the intent's parameters: read in the app, it's whatever the app just
  changed. Returning an `OpenURLIntent` from an intent that lived only in the
  extension opened nothing on iOS 26 ("Failed to fetch metadata for
  OpenURLIntent", simulator, 2026-09-29).
- **A route stop keeps its own copy of the client's name, phone, address and
  pin** (`RouteStop`), and `ClientStops` keeps it in step: every screen that
  changes those on a client calls `ClientStops.update(for:)`, and
  `ClientStops.updateAll(in:)` runs at launch, whenever iCloud brings changes
  and whenever the app comes back to the front, for stops that fell behind
  (a client edited on a device with an older PlowR, or a stop made there
  from an old copy). Visits from today on follow the same way
  (`ClientVisits`, called from `ClientStops`); earlier days' visits are a
  record. A new place that edits a client's details must still call
  `update(for:)`, or its routes lag until the next sweep. Stop notes and
  run results are the stop's own.
- **Deleting a client or marking them inactive goes through
  `ClientRemoval`**: both take the client's stops off every route (Joe's
  call: inactive clients come off routes, and aren't put back when made
  active again; clients already inactive came off once, at the first launch
  of that version, `ClientRemoval.takeInactiveClientsOffRoutes`). A delete
  also removes their visits still ahead, their photos (only the client's
  page shows photos) and the texts kept for their Timeline (`TextLog`), and keeps or deletes their invoices, proposals and
  past visits as the user chooses. "Past" goes by date, not status: running
  a route doesn't mark a visit complete. Kept documents and visits carry the
  client's ID and a copy of their name.
- **PlowR Pro (the subscription) has one rule book: `Access`.** Pro
  (Apple's free trial, paid, billing grace) is everything; free is 10
  clients (active, not lost) and one route (the business's oldest); a
  business that cancels keeps the free tier with 10 or fewer clients, and
  is read only with more: see, export and record payments, nothing new, no
  documents, no routes. Nothing is ever deleted or hidden by the plan, and
  exporting and recording payments are never locked (Joe, 2026-10-09).
  Every gate asks `@Environment(\.access)`, set once in `MainTabView` (a
  screen hosted outside it, like `LeadRequestWindow`, must pass it too);
  never re-derive a rule in a view. A gate is a `ProGate` check
  (`addClient`, `bringBack`, `createRoute`, `startRoute`, `proFeature`)
  run as `$gate.unless(check) { action }` with `.proGateSheet($gate)`, which
  says why and opens the paywall: a new way to add a client, bring one
  back (Mark Active, Reopen, a visit for an inactive client), make or start
  a route, or open a Pro tool must go through one. `Subscription` reads the plan from
  StoreKit (product `Scoops.PlowR.pro.monthly`), follows
  `Transaction.updates` from `PlowRApp.init`, re-reads when the app comes
  back (an expiry sends no update) and keeps the last plan in standard
  preferences (`subscriptionPlan`), so Delete Account & Data removes it. A
  refunded purchase counts as never made. A purchase made in the app counts
  for up to five minutes before StoreKit's lists show it
  (`Subscription.purchased`): they reach a just-made purchase a moment
  late, and someone who has just paid mustn't read as unsubscribed. The
  app's tests never ask the real App Store (`Subscription.shared` reads nothing under tests);
  `SubscriptionStoreKitTests` uses Apple's local test store from
  `PlowRTests/PlowR.storekit`, the same file the PlowR scheme's Run action
  uses; it runs only from `scripts/test.sh` (`PLOWR_STOREKIT_TESTS`),
  because on Xcode Cloud the test store finds no products (#133's first
  CI run), so CI never covers StoreKit itself. With the Run action's
  copy, running from Xcode can buy, renew and expire with no App Store
  Connect. The paywall is Apple's `SubscriptionStoreView`
  (`ProPaywallView`), which shows the price and trial itself: never write
  the price into PlowR's copy.
- **Delete Account & Data** (Settings) is an App Review 5.1.1(v) requirement.
  It removes all SwiftData records, the encrypted work-orders file, the route
  checkpoint and Live Activities (`ActiveRouteStore.eraseAll()`), the widget's
  saved route, the "PlowR" calendar (`CalendarSync.eraseAll()`), and Keychain
  credentials. Any new persistent store must be added to that path or
  the deletion is incomplete and review can fail on it.
- **Delete Account & Data has two paths.** *Delete Everything*
  (`AccountEraser.eraseAll`) deletes every record through SwiftData, and the
  deletes reach iCloud and the user's other devices (confirmed on a
  device with a control, 2026-10-07). *Remove from This Device* (`removeFromThisDevice`) deletes no
  record: it erases what's device-only, then `DeviceSync` turns sync off here
  and deletes the database's files at the next launch, before it opens.
  iCloud sync follows the device's iCloud account, not PlowR's sign-in, so a
  wiped copy on a syncing device comes straight back. With sync off the
  database opens with `offlineConfiguration` (`cloudKitDatabase: .none`):
  SwiftData's default, which `localConfiguration` uses, is `.automatic` and
  can pick the entitlements' container. Sync is turned off only by Remove
  from This Device, never by itself, so a device with sync off holds only
  what was made on it since, none of it in iCloud, and turning sync back on
  can only add; Delete Everything isn't offered while it's off.
- **Calendar events are matched to visits by their `plowr://visit/<id>`
  link**, not by an ID saved on the visit (`externalCalendarID` is unused): an
  event's ID is only good on the device that made it, and visits sync.
  `CalendarSync` runs after every store save, so no screen calls it. Until
  2026-09-28 PlowR asked for write-only access, which can't create a calendar
  or move an event into one, so calendar sync never added an event (seen on
  a simulator). Two devices can each make a "PlowR" calendar before iCloud
  brings the other's: every PlowR calendar is treated as one.

## Conventions

- **Service language is industry-agnostic** (since 1.1.0): snow, lawn, and
  landscaping share the same screens. Don't reintroduce "plow" into user-facing
  copy for a generic action. The `Service-language guard` job in
  `.github/workflows/guards.yml` fails a PR that puts snow-only wording or a
  snowflake icon on a shared screen (dashboard, active route, routes,
  schedule, clients, documents, contracts except their snow trigger,
  settings except the service catalog, Live Activity, intents, widgets, tab
  bar), and fails if a path it lists is gone.
  Run it locally with `bash -e`, as GitHub runs it (zsh doesn't split its
  path list, and without `-e` a grep that finds nothing hides a failure).
  Snow-only features go in their own files.
- **Colours come from `PlowR/DesignSystem.swift`** (`PlowRColor`). The accent is
  adaptive navy (`PlowRColor.accent`, applied once with `.tint()` in
  `PlowRApp`); the fixed navy is `navyUIColor` (PDFs) and `navy` (SwiftUI,
  the client avatar), and `navyHex` is `BusinessProfile`'s default. The enum
  is `nonisolated` because SwiftData's generated code reads it off the main
  actor. The file is compiled into the app and the widget extension
  (membership exception in `project.pbxproj`). Add a token the moment a value
  is needed in a second place, instead of copying it.
  Status colours (`.red` overdue, `.orange` outstanding, `.purple` comped,
  `.green` done) are system colours on purpose.
- **The widget reads only the app group `UserDefaults`.** Anything it needs to
  show has to be written by `WidgetDataStore` from the app side; the widget
  never touches SwiftData.
- **The changelog entry ships with the change**, in the same commit, explaining
  *why*. Since 2026-09-27 it goes in its own file in `changelog.d/`, not in
  `CHANGELOG.md`. `changelog.d/README.md` has the format. The PR that cuts a
  version gathers the files into `CHANGELOG.md`. Two open PRs that both edited
  `[Unreleased]` conflicted every time, and a conflicted PR cannot auto-merge.

## Process

@~/.claude/toolkit/PROCESS.md

The process is shared by every app and lives in the toolkit
(`FreeScoopDev/app-toolkit`, checked out at `~/.claude/toolkit`): every
change, auto-merge, `changelog.d/`, the release PR and Joe's release steps,
git rules, verifying claims and working with Joe. **If you cannot see its
"Every change: no Joe step" section, the import did not load: read
`~/.claude/toolkit/PROCESS.md` now, before any git work.** Change the process
there, not here.

PlowR's specifics:

- **Worktrees**: one per branch, at `~/Desktop/Apps/PlowR-claude/<branch>`
  with the slash as a dash (`PlowR-claude/fix-route-store`), removed after the
  merge. Since 2026-10-09, so several sessions can work on PlowR at once; the
  single `PlowR-claude` worktree was retired. Joe's folder is
  `~/Desktop/Apps/PlowR`.
- **Required checks** on `main` (`.claude/app.json` → `requiredChecks`, ruleset
  since 2026-09-27): `PlowR | CI Tests | Test - iOS`, `Service-language guard`,
  `SwiftLint`, and `Critic verdict` (since 2026-10-09). `~/.claude/toolkit/bin/repo-check.sh .` confirms GitHub still
  matches.
- **CI** is Xcode Cloud: `CI Tests` runs the `PlowR` scheme's tests on every PR
  to `main`. GitHub Actions runs only the Linux guards in
  `.github/workflows/guards.yml` and the critic-verdict check in
  `.github/workflows/critic-verdict.yml`; nothing there builds the app. `docs/ci.md`
  has the workflow settings and setup steps.
- **GitHub Pages** deploys `docs/` to getplowr.app on every push to `main`;
  `docs/_config.yml` keeps `ci.md` off the site.
- **Tracking** lives in Notion (the PlowR app page in Joe's workspace).

Run the tests locally before pushing:

    scripts/test.sh              # full scheme, same as CI
    scripts/test.sh --unit-only  # faster; NOT what CI runs
    scripts/lint.sh              # SwiftLint with the exclusions proved in effect

These are thin wrappers around the toolkit's `bin/`, configured by
`.claude/app.json`. CI does not use them, so a clone without the toolkit still
builds and passes CI.
