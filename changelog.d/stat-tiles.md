### Changed
- Every summary of counts and money looks the same: the Dashboard's Outstanding, Overdue and Drafts, the Clients and Documents summaries, the Season Report and the route recap. Each number sits on a soft tint of its colour, and the tiles share their row's width evenly. They used to be drawn four different ways: grey or tinted, with or without a shadow and icon, unboxed on the route recap. A large amount on the Documents screen could be cut off; now it shrinks to fit.
- Outstanding balances are orange everywhere, as elsewhere in the app. They were red on a client's page, the client visit summary and the Season Report, where red means overdue.
- Dashboard Quick Actions is a full 2 × 2 grid. The Settings tile, which sat alone on the last row, is gone: Settings is the gear at the top of the Dashboard.

### Fixed
- The separators between rows on the Dashboard (Today, Routes, Coming Up) now start where the row text starts, as in the rest of iOS. They started 6 to 10 points short.

### Internal
- `PlowRLayout` (DesignSystem.swift) holds the shared corner radii and tile spacing, and `StatTile` / `StatTileRow` (Views/Shared) are the one summary tile.
