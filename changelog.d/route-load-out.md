### Added
- A route's page shows a load-out before you start: how many stops, about how long they take, each service the stops are expected to need and at how many stops (Clear · 6 stops, Salt · 4 stops), and the equipment notes with the stop each belongs to, so the truck is loaded right before heading out.
- Message All Clients is on a route's page (in the load-out, and in its ••• menu), so you can tell everyone "we'll be at your property today" before starting. It used to be only on the route screen, once the route was running. Its presets gain "Coming Today".

### Changed
- A route's stops section is headed "Stops"; its count and estimated time moved into the load-out.

### Internal
- `RouteFacts.loadOut` counts the stops per expected service (StopServices), in catalog order, active services only.
