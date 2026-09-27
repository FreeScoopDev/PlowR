# Changelog

All notable changes to PlowR are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- **Privacy Policy link** in Settings → Legal — satisfies App Store Review Guideline 5.1.1 requirement for an in-app privacy policy link
- **Delete Account & Data** in Settings — permanently removes all local SwiftData records, the encrypted client work orders file, and Keychain credentials, then signs out; satisfies App Store Review Guideline 5.1.1(v) account deletion requirement
- **Privacy policy page** (`docs/privacy-policy.html`) hosted at `freescoopdev.github.io/PlowR/privacy-policy.html` — covers all data use cases including Sign In with Apple, CloudKit sync, location/geofencing, camera/OCR, Open-Meteo, Open-Topo-Data, contacts picker, and calendar

### Fixed
- **CI has been red since 2026-08-27** because the host app died before the test runner could connect to it. `PlowRApp.makeContainer` built its `ModelContainer` with `cloudKitDatabase:` unconditionally, and the `try?` around it cannot catch a CloudKit failure: CoreData accepts the configuration, then sets CloudKit up asynchronously on `com.apple.coredata.cloudkit.queue` and **traps** rather than throwing. GitHub runners are signed out of iCloud and the workflow builds with `CODE_SIGNING_ALLOWED=NO`, so there is no iCloud entitlement at all — the app trapped a few seconds after launch, surfacing as "Test crashed with signal trap before establishing connection." CloudKit mirroring is now skipped when `XCTestConfigurationFilePath` is set, falling through to the existing local store. This is the same guard, for the same reason, as Wockett's `AppModelContainer`, where it was diagnosed first. Tests should not be syncing to a real iCloud database regardless. **Unverified locally — `xcodebuild` is not reachable from this environment, so the confirmation is CI going green, not reasoning.**

### Internal
- **Product → Archive no longer edits the project.** The PlowR target had an Archive-only Run Script that ran `agvtool next-version -all` in the project folder, so every local archive rewrote `CURRENT_PROJECT_VERSION` in the tracked `project.pbxproj` (1 → 2 on all four build configurations, observed on a test archive of `main` on 2026-09-26) and left a diff nobody had typed. Wockett removed the same mechanism on 2026-09-15 after it was twice mistaken for a hand edit. Xcode Cloud, which PlowR is moving to, numbers builds itself and ignores the file's value, so the script had no job left. An archive of this branch leaves every tracked file unchanged and takes its build number from `CURRENT_PROJECT_VERSION` as written.
- **The placeholder `example()` test is gone; a real one replaces it.** It asserted nothing and was counted as a passing test. `ModelContainerTests` now checks that a launch under test used the local store rather than CloudKit (`PlowRApp.isCloudKitAvailable` is false), pinning the CI fix above. Verified by breaking it on purpose: with the fallback no longer recording itself, the test fails. A second assertion, that the test run is detected at all, was tried and dropped. If detection breaks, the app traps on launch before any assertion runs, so that check could never fail on its own. The crash is already the red signal for that regression.
- **`docs/ci.md` documents PlowR's CI and the one-time Xcode Cloud setup.** Xcode Cloud workflows live only in App Store Connect, so without this file the definition of what gates `main` would exist nowhere in the repo. Two workflows: `CI Tests` on PRs to `main`, and `Release Flow` (manual start, `main` only, distribution "TestFlight and App Store", TestFlight internal post-action). Both are pinned to Xcode 26.6 / macOS 26.5.1. The file includes numbered setup steps. The distribution setting is spelled out because the alternative, "TestFlight (Internal Testing Only)", produces builds Apple never accepts for App Store review. `docs/_config.yml` keeps the file off the getplowr.app website, which GitHub Pages builds from `docs/`.
- **CLAUDE.md refreshed and made self-contained.** It gave the old `~/Desktop/PlowR` folder (now `~/Desktop/Apps/PlowR`), still said CI was red and the placeholder test existed, and told sessions to follow process rules kept in another project's file. It now carries its own process (Claude works in its own worktree and opens PRs, and Joe merges), its own verification rules, and a rule for a public repo: no credentials, internal IDs or references to other projects in commits, PRs or this file. The Notion page ID it held was removed on the same grounds.

## [1.1.0] - 2026-08-22

### Added
- **Live Activity** on Lock Screen and Dynamic Island during active routes — shows route name, stop progress, and next client name in real time
- **Home screen widget** (small + medium sizes) with three states: active route with progress bar and next stop details, route complete summary, and idle placeholder; tapping opens directly to Routes tab
- **Control Center button** (iOS 18+) — mark the current stop complete from Control Center without unlocking the app
- **Haptic feedback** throughout the active route flow: starting, advancing stops, opening the notify prompt, and completing the full route
- **Dashboard weather** — current conditions shown on the home screen using the device's last known location, no extra permission needed
- **Local weather alert notifications** — fires at 6 PM the evening before any forecast day with snow, heavy rain, or thunderstorms
- **Overdue invoice reminder notifications** — daily 9 AM alert when outstanding overdue invoices exist
- **Calendar sync** — scheduled visits are automatically added to a "PlowR" calendar in Calendar.app with a 1-hour alarm; removals sync on delete
- **Siri Shortcuts** — "Complete current stop" and "Notify next client" intents available in Shortcuts and via voice
- **Route optimization — two modes**: Driving Distance (real MKDirections nearest-neighbor routing) and Quick Optimize (instant straight-line haversine)
- **Geofencing** — automatically detects when you drive away from a stop and prompts you to notify the next client
- **App Store review prompt** — appears after completing 2 or more routes with at least 5 stops
- **Camera scan-to-client** — scan a business card or handwritten note with the camera to auto-fill a new client using Vision OCR
- **Inactive client support** — clients can be marked inactive and are hidden from route building but preserved in history
- **Mass message sending** — compose and send a message to all clients on the current route at once
- **Route recap screen** — full summary of completed stops, services rendered, and total time shown at route end
- **Dashboard action tiles** — quick-tap shortcuts for common actions directly from the home screen

### Changed
- Service language and icons are now industry-agnostic, covering snow removal, lawn care, and landscaping throughout the app
- Route optimize button now offers a choice of optimization method rather than running automatically

### Fixed
- Share sheet no longer appears multiple times on repeated taps
- Swipe-to-delete now works correctly in lists where it was previously unresponsive
- Saving forms now dismisses the sheet as expected instead of requiring a manual close
- Three tester-reported stability issues resolved (stop advance crash, address field blur, schedule date persistence)

### Security
- Apple Sign In user ID moved from UserDefaults to Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- Client work orders (address, phone, notes) migrated from UserDefaults to an encrypted file (`completeFileProtection`) in Application Support
- Location-sharing toggle in notify prompt now defaults to off; preference is remembered across prompts
- Weather API calls now use rounded coordinates (~1 km precision) rather than precise GPS to minimize location data transmitted to Open-Meteo
- App data store recovery path now archives (renames) the stale database instead of deleting it silently, preventing unrecoverable data loss
- Dashboard now shows a warning banner if iCloud sync is unavailable so operators know data is stored locally only
- Camera usage description updated to accurately disclose both photo capture and business card OCR scan uses
- `PrivacyInfo.xcprivacy` manifest added, declaring UserDefaults (required-reason CA92.1) and precise-location data transmitted to Open-Meteo for weather
