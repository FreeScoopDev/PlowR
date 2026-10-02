### Added
- GPS arrival and departure on route stops. During a route, PlowR watches an area about 100 m around the current stop's pin and records when the phone came into it and went out of it, and puts both on the job when the stop is completed. A crew still in the driveway when they tap Complete gets their departure added when they drive off (for up to two hours, even after End Route or with the app closed: iOS wakes PlowR for it). The Service Report prints them under the route's own times: "Arrived 4:58 AM · Left 5:24 AM (GPS, within about 100 m)". Only what GPS saw is printed: a crew already inside the area when the stop began (the next house along) has no arrival, and the report says "Arrival not caught" rather than make one up.

### Changed
- The job-site areas are kept by the app, not the route screen, so they follow the route when Siri or Control Center completes a stop with the screen closed, and iOS can relaunch the app for a crossing. The location permission's wording and the privacy policy now say arrival and departure times are recorded; only the times are kept, never the location.

### Internal
- New CloudKit fields to deploy: `CD_ServiceRecord.arrivedAt`, `CD_ServiceRecord.leftAt` (run Set Up iCloud Schema from a debug build, then deploy).
