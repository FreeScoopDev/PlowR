### Added
- Service History for each client: Edit Client → Service History → All Work lists every job in the Service Log, newest first, with its date, services, total, minutes on site, the route it was done on, and whether it's invoiced, not billed yet or no charge. It also shows how many jobs there are and how much work hasn't been billed yet. Until now the client page only had running totals, so there was no way to see what was done on a given day.
- Log Work, from a client's Service History, records work done off a route or a scheduled visit (a call-out, a job done on the way past), with the same services, prices and custom items as Record Services.
- Each job has its own page: correct the date, minutes, services, prices, notes or whether it's billed, see its photos and where it was recorded from, or delete it. While a job is on an invoice, its services and whether it's billed are fixed, and it can't be deleted until the invoice is, so the log keeps matching the bill.

### Changed
- The client page's "No visits recorded yet" now reads "No route visits recorded yet": those totals count route stops only, and the Service History has the rest.

### Internal
- Record Services, Log Work and a job's page share one services form (`ServiceLinesSections`) and one list of active services for it (`ServiceLog.activeServices`), so the three can't drift apart. (Other screens still filter the catalog their own way.)
- The service-language guard now checks `PlowR/Views/ServiceLog`, where the shared services form moved to.
- A job keeps a service's name as it was when the work was done: a service renamed in the catalog since shows under "Also Recorded", and saving the job doesn't rename it. The minutes on site aren't rounded unless edited, and no job can be dated in the future.
