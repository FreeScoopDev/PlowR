### Added
- Below trigger. The storm card goes by the forecast for your area, but less can fall at a client's place than their contract's trigger. Now:
  - **On the storm card**, a client can be marked below trigger for that day: they're left out of the text, and their stops start skipped (shown "Below Trigger") on the route's page, where they can be included anyway.
  - **At the stop on a route**, Below Trigger (shown for a client with a snow contract in force) saves a check with a note and photos, then moves on to the next stop without crediting a visit or billing one. The check keeps the time and the GPS arrival if one was caught.
  - **On the contract's page**, any day the contract covers can be marked below trigger, or unmarked, from the office or after the fact.
  - **The Service Report** lists the days below the trigger with their photos and estimated weather, saying for each whether it was checked at the property on a route (PlowR's record of being there) or marked by hand.
  Marks sync between devices; deleting a client keeps or deletes them with the client's other records.

### Internal
- New CloudKit record and field to deploy: `CD_TriggerCheck`, `CD_StopPhoto.checkID` (run Set Up iCloud Schema from a debug build, then deploy).
