### Added
- On a route's page, swipe a stop right (or press and hold it) to **Skip Today**: it's left out of the run you're about to start and stays on the route for next time. The Start button says how many stops today's run has ("Start Route · 3 of 5 Stops"). Press and hold a stop for **Start From Here**, which starts the route at that stop and leaves the ones before it out.
- While the route runs, skipped stops aren't part of it: stop numbers, progress, the Live Activity, the widget, Siri and Control Center count only today's stops, and so does the route's progress on the Dashboard and Routes list. The choice survives the app being closed mid-route, and is cleared when the route starts, so it never carries over to the next run. The load-out and Message All on a route's page count only today's stops, so a skipped client isn't texted "we'll be there today".

### Fixed
- Optimize Order in a route's ••• menu is unavailable while an optimize is running or with fewer than two located stops. Message All Clients had been disabled in its place.

### Internal
- `ActiveRouteStore.start(_:skipping:)` and `skippedStopIDs`, kept in the route checkpoint (older checkpoints leave nothing out). `sortedStops` is this run's stops, so everything that reads the run follows. `TodaysRun` is the route page's plan for the run it's about to start. `RouteRunSummary(route:store:)` gives the Dashboard and Routes list the same stops for count and time.
