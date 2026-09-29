### Fixed
- **The home-screen widget no longer says "Stop 9 of 8".** After the last stop, until the route was ended, it counted one stop past the end and showed "All stops complete" as the next client. It now says "All 8 stops done" with no next stop.

### Internal
- **The widget and the app share one data type** (`TodayRouteWidgetData`, compiled into both targets). The widget declared its own copy, so renaming a field in the app would have turned the widget into "No Active Route" with nothing to catch it.
