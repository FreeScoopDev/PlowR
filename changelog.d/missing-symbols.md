### Fixed
- The Documents tab, New Route, Create Route and the Schedule's Invoice
  action had no icon: their SF Symbols (doc.stack.fill, map.badge.plus,
  doc.text.badge.plus) don't exist on iOS 26, and the first two not on
  iOS 27 either. A missing symbol shows nothing instead of failing the
  build, so it went unnoticed until the simulator run for the App Review
  screenshot.

### Internal
- An SF Symbols guard (in the required guard job) fails any symbol name
  that iOS 26.0, the deployment target, doesn't have, checked against a
  list taken from the iOS SDK's own symbol data.
