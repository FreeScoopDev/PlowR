### Fixed
- **Saving a job photo no longer needs a permission the app never asked for.** The photo share sheet offers Save Image, which needs `NSPhotoLibraryAddUsageDescription`; without it iOS stops the app. The string is now in `Info.plist`.

### Internal
- **The widget extension has its own privacy manifest.** Apple checks every bundle separately (ITMS-91053), and the widget reads the app group's `UserDefaults`. Both manifests now declare reason `1C8F.1` for that shared app group, alongside the app's existing `CA92.1`. The app manifest's comment no longer claims elevation lookups are rounded; only weather lookups are.
- **Uploads stop asking the export-compliance question.** `ITSAppUsesNonExemptEncryption` is `NO`: PlowR only uses HTTPS.
- **The location permission text lives in one place, and says what it's for.** The same keys were set both in `Info.plist` and as build settings with different wording, and the build settings won, so the text in `Info.plist` never shipped. The build settings are gone. The When In Use text now names the route map, arrival times and local weather, which is what it's used for. Verified in a built Release app.
