### Added
- A Tax Exempt switch on a client's page. Their new invoices and proposals,
  contract payments included, start at 0% tax instead of the Sales Tax Rate
  in Business Profile. A church, a town or a school otherwise got the
  business's rate on every invoice, to be cleared by hand each time.
  Documents already made keep their rate, and any document's rate can still
  be changed.
- A duplicate of an exempt client's document starts at 0% too, and the
  clients CSV export has a Tax Exempt column.

### Internal
- `Client.taxExempt` is a new iCloud field: deploy the schema before the
  next release.
