### Added
- **Can't Service** on the route screen's current stop. A stop the crew couldn't do (a vehicle in the way, a locked gate, the client cancelled) could only be completed, which credited the client a visit and time that never happened, or, under a snow contract, marked Below Trigger. Can't Service asks for a reason (a preset and an optional note), then moves on with no visit, time, services or Service Log record, and nothing billed. Like Below Trigger it can't be undone, ends the last completion's Undo, offers the next client the "on my way" text without completing anything, and isn't offered once work is recorded at the stop. The reason shows under "Not Serviced" in the Route Recap (only for this run) and on the route's page until the route's next run.

### Changed
- The text prompt after completing a stop says **Complete Without Text** instead of **Skip**: the button completes the stop, and "Skip" read as skipping it. Where the prompt completes nothing (the heads-up after Below Trigger or Can't Service, the first stop, Siri's text), it says **No Text**.

### Internal
- Two new CloudKit fields on `RouteStop`, `CD_RouteStop.CD_cantServiceReason` and `CD_RouteStop.CD_cantServiceAt`, must be deployed to the Production schema at the next release, or devices on that release can't sync a stop that sets them.
