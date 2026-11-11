### Changed
- The starter services a business adds from Settings or setup are all flat
  rate now: Snow Plowing $50, Salting / Ice Melt $25, Lawn Mowing $45,
  Fertilization $60 and Mulching $75 were per square foot. They're
  placeholders to edit in the service catalog, and per square foot is
  still a choice there. A business that hadn't measured its clients'
  areas recorded those services at $0 with no warning. Existing catalogs,
  records and invoices are untouched (no migration), and there is no
  CloudKit change.

### Fixed
- The route screen's **Done:** button, the text offered after leaving a
  stop and the Route Recap's **Record Expected Services** no longer name or
  record a per-square-foot service where the property has no measured
  area: it would have been a $0 line. It stays in **Record Services**,
  which asks for its price. If that leaves nothing, the button is the
  ordinary Complete and the recap doesn't offer the stop. Completing also
  checks again, so an area removed after the button was drawn can't
  record one at $0.
