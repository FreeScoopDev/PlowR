### Fixed
- Settings → PlowR Pro → See PlowR Pro closed Settings instead of opening
  the subscribe screen (seen in the simulator before release). The screen
  was attached to the whole Form section, and SwiftUI hands a section's
  modifiers to each of its rows, so the presentations collided. They now
  hang off one row, and the same is done for the snow trigger's gate on a
  contract.
