### Added
- Pipeline: clients who aren't customers yet, and where each stands. A client with no work, proposal or invoice is a lead; one sent a proposal is quoted; work booked or done (a visit scheduled, a stop on a route, a job, an invoice) makes them a customer, and they leave the Pipeline. The stage is worked out from what's on file, so it never needs updating by hand. A lead or quote that went nowhere can be marked lost (swipe in the Pipeline, or on the client's page), and reopened; a proposal made after that puts them back in Quoted.
- Follow Up: a proposal with no reply for 5 days or more is flagged in the Pipeline and on the Dashboard, and a notification at 9 AM on the day it reaches 5 days says who to follow up with (worked out again whenever the app opens or closes, so a quote answered, marked lost or booked loses its reminder). The Dashboard shows leads, quotes and follow-ups when there are any, and the Clients list links to the Pipeline. Before, a quote that got no answer was easy to forget.

### Internal
- New CloudKit field to deploy: `CD_Client.lostAt`.
