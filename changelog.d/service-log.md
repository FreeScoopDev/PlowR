### Added
- A Service Log: PlowR now keeps a record of each job, with the client, the address the work was at, when it started and finished, minutes on site, the services done and their prices at the time, and notes. A record is written when a route stop is completed (on screen, from Siri or from Control Center) and when a scheduled visit is marked complete. Until now, finishing a stop only added to the client's running totals, and the services ticked on a stop were wiped the next time its route started, so there was no way to tell what was done at a client on a given day. Nothing shows the log yet; the client's Service History, billing unbilled work and proof-of-service reports will be built on it.

### Changed
- Finishing a route stop also completes that client's scheduled visit for the day when it is their only one. Running a route used to leave the day's visits "due", so they showed as overdue and could be ticked off again, which would have logged the same job twice. With two or more visits that day, neither is touched: PlowR can't tell which one the stop was.
- Deleting a client and choosing to delete everything also deletes their Service Log; keeping their records keeps it.

### Internal
- `ServiceRecord` is a new SwiftData model, synced by CloudKit: its record type has to be deployed to the Production schema before a TestFlight or App Store build can sync it.
- Each run of a route has an ID (kept in the route checkpoint), so running a route again makes new records instead of overwriting last run's, and a relaunch mid-route keeps writing to the same run.
- The after-hours price multiplier and a client's pricing zones each have one home (`ScheduledVisit.priceMultiplier`, `Client.pricingZones`), and `InvoiceLines.propertyPrice` takes the multiplier.
