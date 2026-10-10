### Fixed
- Revising a paid invoice no longer bills the client again: the revision
  takes the original's payments (one marked paid before payments were kept
  carries what it came to), so it's paid until its lines change, and the
  original is kept as void ("Revised as INV-0042-R1"). Before, the revision
  was a new unpaid draft for the full amount and Money Owed counted it.
- An invoice that was sent or paid toward is a record: it can't be deleted
  (Void instead) or edited under its number once sent (Revise instead). A
  revision not yet sent can still be edited; one of a paid invoice is paid
  until its lines change. Deleting a revision before it's sent puts the
  original back as it was. Deleting an
  invoice used to delete its payments, and Reset to Draft and Overwrite
  Original wiped them, so money received vanished from the books; those
  are gone. A draft never sent, and a proposal, can still be deleted.
- Invoice numbers never come round twice: a voided invoice keeps its
  number, and a number two devices gave out before syncing is fixed when
  they sync: the invoice that went out keeps it and an unsent one takes
  the next (a revision its next revision number); two that both went out
  are never renumbered, and the invoice's page says so.
- A paid invoice's PDF says PAID with the balance due $0.00, a receipt,
  instead of TOTAL DUE; a voided one says VOID and why.

### Added
- Void, for an invoice taken back: kept on record with its number and
  payments (one marked paid keeps what it came to as a payment), marked
  void, owing nothing. Its jobs and visit can be billed again and a
  contract payment invoiced again. A voided invoice doesn't show as paid
  on the client's Timeline.
