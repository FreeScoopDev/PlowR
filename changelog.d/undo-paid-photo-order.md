### Added
- Undo after Mark Paid, deleting a client photo, and Optimize Order on a
  route's page, in the same 10-second toast as the Schedule's. Mark Paid still
  asks first; the toast then names the invoice and the amount recorded, so
  it's clear what happened, and Undo removes only the payment that Mark Paid
  made (the invoice owes that amount again; earlier payments stay). It is
  refused if the invoice's payments changed since. After the toast, the
  payment can still be removed on the invoice's Payments screen. A deleted
  photo is only hidden until the toast goes, so Undo changes nothing and the
  photo is never uploaded again. Undoing Optimize puts the old stop order
  back, unless a stop was moved, added or removed since.
