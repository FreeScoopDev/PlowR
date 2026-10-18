### Changed
- Job-site arrivals and departures now come from Apple's `CLMonitor` instead of
  region monitoring, which iOS has marked deprecated. Each arrival and
  departure is iOS's own time for the crossing, not the moment PlowR got
  round to it, which could be minutes later when the phone was locked or
  PlowR was suspended. iOS also says where the phone is as soon as an area
  is placed, so a crew already at the next house along is known to be there
  ("arrival not caught") rather than guessed from timing, and a crew that
  pulls in within a minute of the stop beginning now gets its arrival. A
  route running when the update installs carries on: its areas move over.

### Fixed
- An arrival or departure from before a stop was completed, handed over late
  (a stop completed from Control Center with the phone locked), no longer
  cancels or stands in for the departure after completing it.
- When iOS reports that approximate location stops it watching job sites,
  the route screen shows the Precise Location note; other reasons (too many
  areas, location denied) are logged instead of passing silently.

### Internal
- `SiteMonitor` keeps one `CLMonitor` ("PlowRSites"), opened once protected
  data is available, and holds a `CLServiceSession` only while areas are
  watched (Always or While Using, whichever is already allowed, so it never
  asks). Delete Account & Data removes the monitor's areas and PlowR's record
  of them on both paths.
