### Added
- **Settings → Show Get Started** brings the Get Started card back to Home after it was hidden. Hide was one tap with no way back, so a new business that hid it by accident lost its checklist for good. The row shows only while the card is hidden and has steps left, and the Hide button now tells VoiceOver it can be shown again from Settings.

### Changed
- Deleting a visit from the Schedule asks first, naming the client and the day. One swipe used to delete it, with no way to get it back. A repeating visit with more to come offers **Delete This Visit Only** or **Delete This & All Future Visits**, the same two choices the visit editor gives for a change; the second ends the series there, so completing an earlier visit doesn't add the deleted ones back. Completed visits after it are records and stay. Deleting the last visit of a repeating series ends the series there too, so it doesn't grow back.
- **Mark Paid** from a client's page (the small Paid button) or the Documents list's menu asks first: "Mark INV-0042 Paid?", with the payment it will record ("Records a payment of $120.00 today"). A mini button brushed in passing used to mark an invoice paid with nothing to show it. What Mark Paid records is unchanged.
- A short success buzz when a visit is completed or skipped from the Schedule, an invoice is marked sent or paid, and a route is made from the Schedule, so a tap that worked can be felt in gloves. Every haptic in the app now goes through one helper.
- The Complete, Skip and Invoice swipes on the Schedule, and Skip Today / Include Today on a route's page, use the app's status colours (done, owed, scheduled) instead of the system's green, orange and blue, in deeper shades so their white labels stay readable in light and dark mode.

### Fixed
- A PDF that couldn't be written (a full phone, say) still opened the share sheet, offering a file that wasn't there or an older copy of it. Invoices, proposals, contracts, Service Reports and proof-of-service PDFs are now offered only once written; otherwise PlowR says "Couldn't Make the PDF" with the reason, and logs it.
