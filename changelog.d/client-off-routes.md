### Changed
- **Marking a client Inactive takes them off their routes.** Inactive clients were already left out of new routes, but stayed on the routes they were on. If they're on any, PlowR now says which and asks first. Marking them active again doesn't put them back. Clients already marked Inactive come off their routes once, the first time this version opens.

### Fixed
- **Deleting a client takes them off their routes and the schedule.** Their route stops stayed, though the prompt said they'd be removed, and so did their visits. The prompt now says which routes they're on, and that their upcoming visits and their photos go with them (photos are shown only on the client's page). It asks whether to keep their invoices, proposals and past visits for your records or delete everything, and offers to mark them Inactive instead.
