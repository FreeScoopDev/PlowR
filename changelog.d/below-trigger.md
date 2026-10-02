### Added
- Below trigger. The storm card goes by the forecast for your area, but less can fall at a client's place than their contract's trigger. Now:
  - **On the storm card**, a client can be marked below trigger for that day (all their places under a snow contract): they're left out of the text, and their stops start skipped (shown "Below Trigger") on the route's page, where they can be included anyway.
  - **At the stop on a route**, Below Trigger saves a check with a note and photos, then moves on to the next stop without crediting a visit or billing one. The check keeps the time and the GPS arrival if one was caught. It's offered where a snow contract covers that stop's place and the stop is snow work, and not once Record Services has saved work there.
  - **On the contract's page**, any day the contract covers can be marked below trigger from the office or after the fact. Taking a mark off never removes a check made at the stop; that one is removed on its own, after asking, with its photos.
  - **The Service Report** lists the days below the trigger with their photos and estimated weather, saying for each whether it was checked on a route (with its GPS arrival, or "arrival not caught") or marked by hand. Check photos read "Below Trigger" there and in the client's photos.
  Marks sync between devices; deleting a client keeps or deletes them with the client's other records.

### Internal
- New CloudKit record and field to deploy: `CD_TriggerCheck`, `CD_StopPhoto.checkID` (run Set Up iCloud Schema from a debug build, then deploy).
