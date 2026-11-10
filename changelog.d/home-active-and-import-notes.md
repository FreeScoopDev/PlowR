### Fixed
- Home's "Nothing on today" card counts active clients only. A business whose clients were all marked inactive was offered New Route and Schedule Visit, though nobody could be put on a route (inactive clients come off routes); it now sees Add Client again. The free plan's 10-client limit, first-run setup, the Get Started checklist's "client added" (it records progress made) and the Clients list's empty state (it lists inactive clients in their own section) count as before.

### Changed
- Import from Spreadsheet puts the notes column in the client's Route Notes, so a gate code or special instruction in the file shows at their stops, as it does when typed into New Client. It used to go to the private notes, which stops never show. A company column's "Company: …" line is about the client, not the stop, so it stays in the private notes. The mapping choice is now named Route Notes. Clients imported before this are not changed, and Undo This Import works as before.
- No CloudKit schema change.
