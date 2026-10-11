### Added
- Export Data has an Invoice Lines file: every service on every invoice
  billed, one row each, with its place, quantity, unit price and line
  total, before the invoice's discount and tax. A bookkeeper needs it to
  split income by service; the Invoices file only had each invoice's
  totals. Drafts aren't in it, nor a revised invoice (its revision has its
  lines), so nothing counts twice; a void invoice that kept money it was
  paid is.

### Changed
- The Invoices file has a Tax Rate % column beside Tax, so the rate
  charged can be checked against what a state requires.

### Fixed
- The Payments file lists all the money PlowR counts as received. An
  invoice marked paid without a payment recorded for it (or paid before
  payments were kept) is now a "Marked Paid" row on the day it was marked
  paid. They were left out, so the file added up to less than Money In.
