### Fixed
- **Delete Account & Data removes everything PlowR keeps on the device.** It left behind the client-mode name, phone and email, pending notifications (the daily overdue-invoice reminder kept firing), geofences from a route the app was killed during, shared invoice and report PDFs, and archived copies of the database. It now removes all of them, and every preference rather than a list of known ones, so one added later can't be missed. If a step fails, Settings says what wasn't removed and the account stays signed in so it can be tried again; before, every step failed silently and the user was signed out as if it had worked. The iCloud copy and the "PlowR" calendar's events are not covered yet.

### Internal
- **One list of models** builds the database schema and drives Delete Account, so a new model can't be left out of either. `AccountEraserTests` creates one of each and checks all are gone.
