### Added
- Texts sent to a client from PlowR are on their Timeline: a text from their page or a route stop, the heads-up to the next client, Message All, and invoice reminders. Each is kept once Messages says it was sent, never for one cancelled or that failed, with the time and the text as PlowR drafted it (it can be changed in Messages before sending). A heads-up sent with a location link is kept without the link: the privacy policy says location isn't stored, so only "with a location link" is noted. Before, a text left no trace in PlowR, so "did I tell them we were coming?" meant searching Messages.
- Deleting a client deletes the texts kept for them, as it does their photos. The privacy policy lists texts sent to clients among the data kept in the user's iCloud.

### Internal
- New CloudKit record type to deploy: `CD_SentText`.
