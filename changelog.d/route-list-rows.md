### Changed
- The Routes list shows more about each route: a map icon (orange while it's running), how many stops it has and about how long they take, and when it last ran ("Last run yesterday", "Last run Sep 21") or "Running · 2 of 4 done". It used to show only the name and a stop count beside a grey bar that nearly disappeared in dark mode.

### Internal
- `RouteFacts` works out a route's estimated time and last run once, for the Routes list and a route's page. The last run comes from the Service Log. `IconBadge` (Views/Shared) is the tinted icon square.
