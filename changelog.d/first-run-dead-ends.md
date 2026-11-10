### Changed
- The Clients filter that showed only clients with visits was called "Active", which clashed with the Inactive section below it. It is now called "Has Visits". It selects the same clients as before.

### Fixed
- A new business is no longer offered things it can't use yet. With no clients, Home's empty day now offers Add Client instead of New Route and Schedule Visit, since a route or a visit has nobody to be for. Schedule Visit with no clients now says how to add one, and its client button reads Add Client.
- Searching your clients and finding nobody now says "No clients match" and names what you searched for, instead of showing only the totals above an empty list.
- A client search no longer comes up empty because of a space after the word. The keyboard adds one when you pick a suggested word, so "Smith " found nobody while a Smith was on the list.
- Importing clients from a spreadsheet is a Pro tool, but the empty Clients screen and the Get Started card offered it with no sign of that. The Clients screen now carries the Pro mark and Get Started says "with PlowR Pro" when you're not on Pro, so the upgrade screen is no surprise.

### Internal
- The Pro mark is one shared view (`ProMark`) instead of the same chip written out on each screen.
