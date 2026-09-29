### Fixed
- **Cancelling a text no longer counts as sending it.**
  - Messaging a route's clients one at a time: cancelling one client's text opened the next client's, with no way to stop and no record of who had been sent it. Now each client drops out of the selection as their text goes, and a cancelled or failed text stops the run and says how many were sent. The clients not texted yet stay selected, so Send carries on with them, and while the screen is open no one is texted twice. Each text now has to be sent or cancelled; it can't be swiped away.
  - A group text that's cancelled leaves the Message Clients screen open. It used to close it as if the text had gone.
  - The notify prompt: cancelling the text marked the stop done and moved on as if the text had gone. Now it goes back to the prompt, where Skip moves on without a text.
  - A client's "last message sent" was set even when the text was cancelled.
