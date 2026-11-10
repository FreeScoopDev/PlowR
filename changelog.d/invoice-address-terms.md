### Added
- Business Profile has a **Mailing Address** and **Payment Terms** (Due on receipt, Net 7, 15, 30, 45 or 60). An invoice said "Make check payable to" but never where to mail the check, since the profile had no address; and every new invoice was due in 30 days, though many small businesses bill due on receipt or in 15 days. The address prints in the header of every document (invoices, proposals, contracts, Service Reports) and as "Mail to:" under a check payment. New invoices (Record Services, Bill Unbilled Work, Convert to Invoice, a revision, the builder, a contract payment when it's sent) are due on the business's terms; a profile that never chose stays at Net 30. An invoice's PDF states its terms beside the due date, worked out from that invoice's own dates, so changing the setting later never restates an invoice already made, and saved invoices keep their due dates. First-run setup asks for the address (optional); terms are left at Net 30 until changed.

### Changed
- Marking a draft invoice sent never leaves it due before the day it's sent: a due-on-receipt draft made Monday and sent Thursday is due Thursday, not overdue the moment it goes out. This also moves a hand-picked due date that has already passed when the draft is sent; a due date on or after the send day is left alone.

### Internal
- Two new CloudKit fields, `CD_BusinessProfile.CD_address` and `CD_BusinessProfile.CD_paymentTermsDays`, must be deployed to the Production schema at the next release, before the build reaches users.
- `SetupPermissions.State` and `Request` are `nonisolated`, which removes the two Release-build warnings in `SetupFlowView.swift`; a Release build has none again.
