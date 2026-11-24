### Changed
- One name per action, so the words learned on one screen work on the next: adding a client is **New Client** everywhere (Clients' empty list, Home's Nothing on today, the visit form), scheduling a visit is **Schedule Visit** (its screen is titled Schedule Visit too), and **Mark Sent**, **Add Custom Item** and **Import from Spreadsheet** replace "Mark as Sent", "Add Custom Line Item" and "Import from a Spreadsheet". On an invoice or proposal, the main button reads **Convert to Invoice** and **Payments**, as they do elsewhere; **Remind** keeps its short label beside Revise and reads "Send Reminder" to VoiceOver.
- The Documents tab's badge counts only overdue invoices, what needs doing now. It counted drafts too, so it stayed lit while a draft sat unfinished and stopped meaning anything.
- Home's "+ N more" under today's visits opens the Schedule on today, where the rest are.
- Schedule's Past Due shows the first three and a **Show All** button for the rest, instead of hiding everything after the third.
- Deleting the last visit of a repeating series from the Schedule ends the series, and its confirmation now says so and points to Skip for missing one week.
- An empty day on the Schedule has a **Schedule Visit** button that opens a visit on that day; touching and holding the day still does too.

### Fixed
- VoiceOver named icon-only buttons by their pictures or not at all: the client page's call, email and document share buttons, removing a line from a proposal or a photo from a stop, the photo viewer's share and delete, the Clients and Documents filters, Schedule's add and weather refresh, Payment Methods' add, a contract's share and removing an area from a property scan now say what they do.
- Schedule's visits open as buttons, so VoiceOver says a visit can be opened; swipe actions are unchanged.
- Buttons too small to hit in gloves now take a tap anywhere in a 44 pt square while looking as before: the client page's document buttons (Share, Paid, Revise, Edit, now on a line of their own under the document so they fit at every text size), Past Due's Complete, the stop recorder's remove-photo ✕, the client page's call and email, and Schedule's weather refresh.

### Internal
- Home's Hide and Settings' Show Get Started read and write the hidden flag only through `FirstRun` (`hideChecklist`, `isChecklistHidden`). The swipe colours that match a fill or text colour on purpose say so in `DesignSystem.swift`.
