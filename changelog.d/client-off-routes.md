### Changed
- **Marking a client Inactive takes them off their routes.** Inactive clients were already left out of new routes, but stayed on the routes they were on. If they're on any, PlowR now says which and asks first. Marking them active again doesn't put them back.

### Fixed
- **Deleting a client takes them off their routes and the schedule.** Their route stops stayed, though the prompt said they'd be removed, and so did their visits. The prompt now says which routes they're on and how many visits aren't done yet (those are deleted), and asks whether to keep their invoices, proposals, past visits and photos for your records or delete everything. It also offers to mark them Inactive instead.
