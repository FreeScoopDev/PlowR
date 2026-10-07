### Fixed
- Every screen that takes a photo now uses one shared camera screen, which checks for a camera first. If a device without one (some iPads, a Mac) ever reaches it, it says "This device doesn't have a camera" instead of closing the app. Until now each screen checked on its own, and two had forgotten (fixed in the camera crash fix).

### Internal
- `CameraPicker` (`Views/Shared`) replaces the three separate camera wrappers; `CameraPicker.isAvailable` replaces the per-screen checks. A new **Camera guard** step in the Service-language guard job fails a PR that opens or checks for the camera anywhere else.
