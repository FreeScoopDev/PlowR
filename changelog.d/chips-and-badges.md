### Changed
- Status labels look the same everywhere: invoice and visit statuses, "Revision", "Invoiced", "After Hours", "Expires in 2d", "N recorded", visit counts and the Dashboard's section counts. Each is a small tinted capsule with the same size, weight and padding. They used to vary from screen to screen, and sometimes on the same screen: regular or bold, small or smaller, tints of 12–15%, and two visit counts as solid blue pills. A status is never cut off; the row's other content makes room.
- A stop's number is drawn one way in every list of stops (route details, building or editing a route, the route screen's Up Next): a small tinted circle, blue, or green once the stop is done. It was a solid circle with a shadow in one place and a bare grey number at two widths in others. The route map's pins are unchanged.
- The Routes list's rows match the Clients and Documents rows: a coloured bar on the left (orange while running, green when done) and the same title and subtitle sizes. The Schedule's bar is now the same height as the others, and the stop names in route lists use the same title size as client names.

### Internal
- `StatusChip`, `AccentBar` and `StopNumberBadge` (Views/Shared) are the one of each.
