### Added
- The same job recorded on two devices before they synced (two phones on one account, one offline) shows once in the Service History. The copies are merged at the first launch or iCloud sync after they're a day old. The oldest stays, taking anything only the other had:
  - an invoice, together with the services it billed; an invoice with no services keeps the services the job has
  - the services recorded on the route, over a visit's expected ones
  - notes, the route's times, and photos
  Two copies on different invoices are left alone, because that double bill is real and should stay visible.

### Internal
- Each visit carries a synced `serviceLogged` mark (a new field: deploy it to the CloudKit Production schema with the other Service Log fields). It's set when a visit's work goes into the log, so the copy of completed visits into the log (earlier-visits.md) skips them and never remakes a job the user deleted.
- `ServiceLog.mergeDuplicates` runs at launch and after every iCloud import. It leaves a copy alone for its first day (`mergeAfter`), so a route still writing to it on another device doesn't lose a photo or a stop's times to a deleted record. The oldest record wins, with ties broken by ID, the same everywhere `record(forKey:)` looks.
- The merge takes a route's services over a visit record's even if someone edited the visit record's services by hand: it can't tell the two apart.
