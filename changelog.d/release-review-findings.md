### Fixed
- Directions to a stop with no pin now reach the whole address when it has an "&" in it ("Smith & Sons, 5 Elm St"): the link left `&`, `=` and `+` unencoded, so Maps got the address cut short at the "&".
- The "Always" location permission text no longer says PlowR prompts you to notify the next client in the background. Since 1.8 that offer shows only while the route screen is up, so the text now says it offers to text the next client when PlowR is open; App Review checks that a permission string matches what the app does.
- PDFs and CSVs written for sharing (proposals, invoices, contracts, proof of service, the season report, CSV exports) are now encrypted while the phone is locked (complete file protection), like the work-orders file: they hold clients' names, addresses and money.

### Internal
- A Release build has no warnings again: four notification observers captured `self` in a way Swift 6 flags. Each main-actor closure now takes its own weak `self`; the observers stay on `queue: nil`, so the #194 deadlock doesn't come back.
