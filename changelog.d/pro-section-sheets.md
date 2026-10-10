### Internal
- PlowR Pro's sheets are presented from a screen's Form, never from a Form
  section: SwiftUI hands a section's modifiers to each of its rows, and in
  the simulator See PlowR Pro closed Settings instead of opening the
  subscribe screen. The same applies to the snow trigger's gate on a
  contract, and the contract page's "Remove this check?" dialog moved off
  its section too. Found before release.
