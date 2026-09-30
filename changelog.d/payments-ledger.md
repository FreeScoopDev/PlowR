### Added
- Payments: an invoice can be paid in parts. An invoice's Payment button shows what's been paid and what's still owed, and records a payment: the amount (what's owed, or part of it), how it was paid (cash, check, card, Zelle, the business's own payment methods), the day, and a note such as a check number. Paid in full, the invoice is marked paid on the day the last part came. A payment recorded by mistake can be swiped away, and what it paid is owed again. Mark Paid records the balance by the client's usual payment method. Before, an invoice was paid or not, and a client who paid half showed as owing all of it.
- A partly paid invoice prints its total, what's been paid and the balance due, and shows "$X due" in the documents list and on the client's page.
- An invoice is marked paid whenever its payments cover it: when one is recorded, when it's edited down to what's been paid, and when parts recorded on two devices come together through iCloud (checked at launch, when iCloud brings changes, and when the app comes back). An invoice with nothing left to pay that isn't marked paid shows Mark Paid in its Payments. One paid more than its total says it's overpaid.
- A reminder about a partly paid invoice asks for the balance, not the whole total. Reset to Draft, and overwriting a paid invoice, say which recorded payments they remove.
- Each payment is on the client's Timeline, and Export Data has a Payments file (day, invoice, client, amount, method, note), with Amount Paid and Balance Due added to the Invoices file.

### Changed
- What's owed and what's come in are worked out in one place, so the Dashboard, the client list, a client's page, Client Stats, Documents and the season report agree. Money counts in the month it came, so an invoice paid in parts adds to each month a part came in.

### Internal
- New CloudKit record type to deploy: `CD_Payment` (with its `invoice` relationship). An invoice marked paid on a device with an older PlowR stays paid in full here (`invoicePaidAt` still marks an invoice paid), and taking back a part recorded here doesn't unmark it. A draft that an older PlowR reset keeps its payments and isn't marked paid again. Recording a payment late never moves a client's response earlier, so "Awaiting Response" can't come back from it.
