### Fixed
- **Cancelling a text no longer counts as sending it.**
  - Messaging a route's clients one at a time: cancelling one client's text opened the next client's, with no way to stop and no record of who had been sent it. Now a cancelled or failed text stops the run and says how many were sent, and the clients not texted yet stay selected, so Send carries on with them.
  - The notify prompt: cancelling the text marked the stop done and moved on as if the text had gone. Now it goes back to the prompt, where Skip moves on without a text.
  - A client's "last message sent" was set even when the text was cancelled.
