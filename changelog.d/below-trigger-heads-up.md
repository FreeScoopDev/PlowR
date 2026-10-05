### Changed
- After Below Trigger moves on to the next stop, the next client is offered the "on my way" text, as after Done (unless they'd rather not be texted). Joe asked for it: a stop below the trigger is still the crew heading to the next client.

### Internal
- Tests turn off SwiftData's autosave on every database they make. An autosave left pending fired after a test had let its store go, and SwiftData trapped in `ModelContext.autosave`, failing every test in the run ("Test crashed with signal trap"): intermittent locally on iOS 26.5, and twice in a row on CI.
