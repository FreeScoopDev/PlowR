### Added
- **Receipt photos on expenses.** An expense's editor has a Receipt section: Take Photo or Choose Photo, a thumbnail that opens the photo full screen (pinch or double-tap to zoom), Replace Receipt, and Remove Receipt (asked first). Expenses with a receipt show a paperclip in the list, and the Expenses file's Receipt column says Yes. An accountant wants the receipt, not just the amount. Receipts are stored the way client photos are: inside PlowR's database (synced with iCloud, erased by Delete Account & Data), never as loose files or in the photo library, and a picked photo is kept without its location. They don't appear in a client's photos or the Service Report.

### Changed
- The camera permission message now says it's also for receipts.

### Internal
- No CloudKit schema change: `receiptData` and `receiptCapturedAt` shipped with the expenses change. `Expense.setReceipt` sets and clears both together; the list's mark and the export read only `receiptCapturedAt`, so neither loads photos. The client gallery and the receipt share `PhotoCapture.saving(camera:)` / `saving(library:)` (JPEG from the camera; a library photo's location stripped off the main thread) and the zoomable photo view (`ZoomableImage`).
