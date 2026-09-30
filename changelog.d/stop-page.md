### Added
- Tap a stop on a route's page to open it, before the route runs. It shows the services the stop is expected to need, the notes and equipment shown there during the route, and its target time, with buttons to call or text the client and get directions. When you change the expected services, PlowR asks whether the change is for this route only, or for all routes from now on. All routes changes the client's usual services, and every route's stop for them then follows, replacing any list set for one route. A client can need one service on one route and another on another. Before, a route's stops could only be looked at, and their services were always the client's.
- The route screen's current stop shows its expected services and target time. Record Services offers them as one tap ("Add Expected: …"). Nothing is ticked for you: a skipped stop mustn't record, or bill, work that wasn't done.

### Changed
- A route's page, and the route screen's current stop, show each stop's target time: its own, set on the stop's page or from the client's goal when the route was built, or else the client's goal now. The route's page used to show only the client's goal, and the stop's own target appeared nowhere.

### Internal
- `RouteStop.expectedServiceIDs` and `hasOwnServices` are new fields: deploy them to the CloudKit Production schema. `StopServices` is the rule for which list a stop uses, and for where a change applies. Duplicating a route copies both fields. `RouteStop.appleMapsDirectionsURL` is shared by the route screen and a stop's page.
