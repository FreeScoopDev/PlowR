### Added
- A **Timeline** for each client (client page → Service History → Timeline). It shows everything together, newest first and by month: jobs done, visits coming up, missed or skipped, proposals, invoices made, sent and paid, and the days photos were taken. Jobs, proposals and invoices open when tapped, and photos open the client's gallery. Before, this was spread across the client's page, their Service History, Documents, the Schedule and the photo gallery.

### Internal
- `ClientTimeline.events` gathers the events. A completed visit is represented by its job, so it doesn't appear twice. A visit still scheduled for a day already past shows as missed.
