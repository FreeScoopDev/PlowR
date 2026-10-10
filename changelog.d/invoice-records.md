### Fixed
- Revising a paid invoice no longer bills the client again: the revision
  takes the original's payments (one marked paid before payments were kept
  carries what it came to), so it's paid until its lines change, and the
  original is kept as void ("Revised as INV-0042-R1"). Before, the revision
  was a new unpaid draft for the full amount and Money Owed counted it.
- An invoice that was sent or paid toward is a record: it can't be deleted
  (Void instead) or edited under its number (Revise instead). Deleting an
  invoice used to delete its payments, and Reset to Draft and Overwrite
  Original wiped them, so money received vanished from the books; those
  are gone. A draft never sent, and a proposal, can still be deleted.
- Invoice numbers never come round twice: a voided invoice keeps its
  number, and a number two devices gave out before syncing is fixed when
  they sync (an unsent draft takes the next number; two sent invoices are
  noted, never renumbered).
- A paid invoice's PDF says PAID with the balance due $0.00, a receipt,
  instead of TOTAL DUE; a voided one says VOID and why.

### Added
- Void, for an invoice taken back: kept on record with its number and
  payments, marked void, owing nothing.
