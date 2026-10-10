### Fixed
- A contract payment invoiced on two devices before they synced (Make
  Invoices on both) is pointed out: each invoice's page says another bills
  the same payment, and the Dashboard lists it under Finances, so one can be
  deleted or voided. The client would otherwise be billed twice. PlowR
  doesn't remove either itself, since the other device may already have
  sent its copy or recorded a payment on it.
- An invoice paid more than its total is listed on the Dashboard too,
  opening its payments: most likely one payment recorded on two devices,
  or a real credit owed to the client. Until it's sorted out, the extra
  counts as money received.
