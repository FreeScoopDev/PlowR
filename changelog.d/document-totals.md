### Fixed
- **Totals agree everywhere, from one formula.** The builder's "Estimated total" left out tax and custom lines, so it was lower than the document it saved. The invoice Edit screen showed a second "Total" with the discount taken off twice. A document's totals now come from one place (`Proposal.totals`), and tax is rounded to the cent once, so the PDF's rows always add up to its total.
- **Tax rates stay as typed.** Opening an invoice's Edit screen and tapping Done saved 8.875 % as 8.9 %, because the field showed one decimal, and the PDF printed "Tax (8.9%)". Rates now show up to three decimals.
- **Mark as Sent on the Edit screen keeps a discount or tax just typed there.** Only Done used to save them.
- **A cleared amount in the builder uses the after-hours price shown beside it,** not the plain catalog price.
- **Payment reminders texted to clients give the amount to the cent.** A $149.50 invoice was texted as $150.
- **The PDF's discount row shows the discount actually taken,** never more than the work it comes off.
