### Fixed
- **A new business profile keeps the app's navy for proposals and invoices.** The colour picker started at system blue, so saving a new profile for the first time wrote blue over the navy default.
- **The profile's accent colour no longer shifts when saved.** It was stored as hex with each channel rounded down, so some colours came back one step darker every time the profile was saved. A colour picked outside the standard range (Display P3) was stored as hex that couldn't be read back, and showed as the default.
