### Added
- **Bill Unbilled Work** (Documents → +, or a client's Service History). Pick This Month, Last Month or All Unbilled, see each client with work not billed yet (how many jobs, since when, how much), untick any to leave out, and create one draft invoice per client. Each invoice lists every service done, oldest job first, with the day under it (and the address, if it wasn't the client's), and uses your default terms. The work is then billed on it, and a scheduled visit among it is linked to it. Deleting the invoice makes the work unbilled again. Seasonal and weekly work is usually billed like this, once a month; until now it had to be invoiced a job at a time.

### Changed
- An invoice made from Record Services now carries your default terms, like one made from the invoice builder or Bill Unbilled Work.
- The Schedule no longer offers to invoice a visit whose work is already on an invoice.

### Internal
- `WorkBilling` finds the work using ServiceLog's billing rule, so no-charge and billing-not-tracked jobs are left out. The same job recorded on two devices before they synced counts once. It's left out if any copy is already invoiced, or if the copies' services differ, until they merge a day later. Billing checks again when you tap Create, so a job billed meanwhile is left off.
- `WorkBilling` saves after each invoice. If one fails, it's undone and billing stops there, and the screen says how many were made. Each invoice on one device takes the next number, and a test checks that they differ. Two devices billing before they sync can still issue the same number, as before.
- Invoices from Record Services and Bill Unbilled Work are both made by `ServiceLog.newDraftInvoice` and linked to their visit by `ServiceLog.link`. `ServiceLog.billingStatus(of:invoiced:)` is the rule on its own, so a bulk check looks the invoices up once. A client's Service History "Not Billed Yet" is `WorkBilling`'s total.
