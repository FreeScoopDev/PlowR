### Fixed
- A stop's departure time is no longer taken from leaving the next stop. A
  stop completed while still inside its job-site area waits for the crew to
  leave it; when the next stop was within about 200 m, the two areas
  overlapped, and leaving the next stop also "left" the first one, so the
  first stop's Service Report showed the time the crew left the next one and
  overstated time there. Now that wait ends when the next stop's area
  overlaps it, and whenever a later stop is completed or passed (the crew was
  there, so they had already left), and the report says "Departure not
  caught" rather than give a time GPS didn't see.
- The route screen says when Precise Location is off. With approximate
  location iOS watches no job-site areas, so no arrival or departure was ever
  recorded and nothing said why. A note with a Settings button now explains
  it, and the Service Report's "not caught" explanation names approximate
  location and stops too close together among the reasons.

### Internal
- A job-site area iOS fails to watch is logged (`SiteMonitor`, category
  `SiteMonitor`) instead of being ignored. Temporary full accuracy was
  considered and left out: it ends when the app leaves the screen, and the
  areas exist to work with PlowR closed.
