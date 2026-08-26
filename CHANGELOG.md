# Changelog

All notable changes to PlowR are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
