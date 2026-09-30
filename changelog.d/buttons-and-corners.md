### Changed
- The big buttons in the route flow (Start Route, Done — Notify Next Client, Mark Stop Complete, Complete Route, Review & End Route, Send Message and Skip) are Apple's standard large buttons, like End Route. End Route already was; the others were custom filled rectangles, greyed by hand when they couldn't be used.
- Cards, tiles and panels use three corner sizes (8, 12 and 14 points) instead of five, with the smoother continuous corners iOS uses. A route screen card no longer holds a button with a different curve, and the Dashboard's profile card matches its other cards. The business logo in Settings and the chart bars keep their own.
- Weather is coloured the same on every screen. Thunder was purple on the Dashboard and route screen but yellow in the Schedule's forecast. Snow in lower case ("Heavy snow") and freezing rain now count as snow everywhere.
- The Schedule's Overdue header matches the day and Upcoming headers above and below it. The photo gallery's empty screen is the system's, like every other empty screen. Short "No …" lines no longer end with a full stop on some screens and not others.

### Internal
- `primaryActionStyle(_:)` / `secondaryActionStyle()` (Views/Shared) are the app's big buttons. `WeatherKind` (Views/Shared) is the one reading of a weather description, with a background colour and an icon colour, and replaces three copies. Corner radii are `PlowRLayout` values.
