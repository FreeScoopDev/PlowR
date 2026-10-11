### Internal
- The 1.7 design's building blocks, in `DesignSystem.swift`: the Evergreen &
  Copper colors (light and dark), one set of status colors (done, scheduled,
  owed, overdue, lead, void) and service colors (snow, lawn, landscaping)
  meant for every screen, text roles for Barlow headings and numbers that
  scale with the user's text size, a spacing scale and tap-target sizes, and
  one SF Symbol per idea. Nothing on screen changes yet: screens move over
  one at a time. A test checks every text color against its background at
  the 4.5:1 readability standard, in light and dark mode, since the point is
  reading it early in the morning and late at night.
