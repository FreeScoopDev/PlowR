### Added
- Record Services can save to the Service Log without making an invoice. Its Save menu has "Save", "Save & Draft Invoice" and "Save & Mark Invoice Sent". Save needs something to save: a service, a custom item, a photo or a note. It can also empty a saved job, for services recorded at the wrong stop. Before, the only way to save was to make an invoice, so recording a comped client's work, or work billed later, meant making an invoice nobody wanted.

### Changed
- The Service Log keeps the prices typed in Record Services and its custom items, priced the same way as the invoice, so the log and the bill agree. Before, the log re-priced the services from the catalog and left the custom items out.
- A job's invoice is noted on its Service Log record, however the invoice was made: from Record Services, from a scheduled visit's Invoice action (before or after the work is done), or by converting a visit's proposal. A revision (from the client's page or the invoice's page) takes over the work and the visit from the invoice it revises, so deleting the superseded original neither unbills the work nor lets the visit be invoiced again. Deleting the revision hands both back to the original. Deleting an invoice makes the work unbilled again (so does an invoice deleted on another device), and a scheduled visit linked to it can be invoiced again. Invoicing the day's visit from Record Services links the visit to the invoice, so the Schedule no longer offers to invoice it a second time. Reopening Record Services for invoiced work says which invoice it's on, even before the work is recorded (a visit invoiced ahead), and doesn't offer to invoice it again. Its services are then locked to the invoice: edit the invoice to change them.
- Record Services shows services recorded earlier that have since been switched off or deleted from the catalog, under "Also Recorded", and keeps them when saving.
- Photos taken in Record Services are linked to the job's Service Log record.
- The route screen's button now reads "Record Services", since saving no longer means invoicing.

### Fixed
- Skip in Record Services no longer silently throws away photos just taken. It now asks first when there are unsaved photos, or changed services, prices, custom items or notes. Swiping the sheet away is blocked until then.

### Internal
- Revising an invoice was written out twice, in the client's page and the invoice's page; both now use `ServiceLog.revise`.
- `StopRecording` prices the sheet once for both the Service Log and the invoice, and `ServiceLog.saveRecording` / `invoice` / `delete` hold the save logic so it's tested outside the view.
- Record Services and stop completion find a job's record by route run and stop first, and otherwise by the day the stop was started, never the time of saving. A route that runs past midnight therefore still makes one record. The day's visit belongs to one stop per run: a client on a route twice gets a second record for the second stop. The sheet loads everything the record has, so saving can't erase services that came from a visit completed in the Schedule.
- `StopPhoto.recordID` is a new field: it has to be deployed to the CloudKit Production schema with `ServiceRecord`.
