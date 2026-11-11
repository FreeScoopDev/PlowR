### Changed
- The route screen's stop card marks an expected per-square-foot service the "Done:" button leaves out for want of a measured area, as in "Mow and Edge (no area measured)". The card listed it while the button didn't name it, with nothing saying why; the mark uses the same rule as the button.
- Labels no longer call mixed minutes "on site": a route stop's minutes run from GPS arrival when PlowR caught it, otherwise from when the stop became current, which includes the drive there. Client Stats' total is now **Total time at stops**, the Season Report's line reads "… total time at stops", and the minutes field on a job's page and in Log Work is **Minutes**. A route stop's job page now says which its minutes are: counted from GPS arrival, or including the drive there.

### Fixed
- Record Expected Services' Confirm runs once: a second tap before its sheet closed found every stop already recorded and showed a "Not Recorded" alert naming them all.

### Internal
- The route recap works out the Record Expected Services list only when the run's records, the stops' services, the catalog or the database change, not on every redraw. The invoice editor is handed the business's payment terms by the screen that opens it instead of reading the profile from the database each time that screen redraws.
- Duplicate Route moved into `ClientStops.duplicate`, tested: a stop's own note that only copies the place's Route Notes isn't carried to the copy; a real one is. `NewClientDraft.notes` is now `routeNotes`, as it feeds Route Notes. The stop page uses `Place.isMain`. New `PlowRSymbol` cases for Route Notes, a stop's own note and services replace the literals; the stop card's two notes share one view on `PlowRLayout` spacing.
- New tests: the one tap with only a per-square-foot service whose area went before the tap records the visit and nothing else, and Undo leaves the stop's services alone; an invoice whose only payment method isn't a check prints no "Mail to". No CloudKit change.
