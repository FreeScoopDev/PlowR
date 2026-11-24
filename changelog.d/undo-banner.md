### Added
- Undo after deleting, skipping or completing a visit on the Schedule. A toast
  in the route screen's Undo look shows for 10 seconds above the tab bar.
  Until then a deleted visit (or the series' visits the choice deleted) is
  only hidden, and deleted when the toast goes, another action replaces it, or
  the app goes to the background: undoing changes nothing and syncs nothing,
  and the visit keeps its ID, so its calendar event and anything linked to it
  stay. Undoing Complete takes back the Service Log record and the series'
  next visit it added, and is refused if either was changed since. The delete
  confirmation stays.
