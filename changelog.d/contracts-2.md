### Added
- Work under a contract (contracts, step 2). A job at a place and on a day a signed contract covers is billed by the contract:
  - **Season price or monthly:** the services it covers aren't billed by the visit. The job shows **Covered by Contract** in Service History and the export, and Bill Unbilled Work leaves it off. The contract's own payments are what's owed for it (next step).
  - **Per visit:** the services it covers are one line at the contract's price ("Winter: visit, $55") when Bill Unbilled Work bills them.
  - Services it doesn't cover are extras, billed as recorded.
  
  Record Services shows the contract covering the stop, and its Save & Invoice follows it too: nothing to invoice for work a season or monthly contract covers, the contract's price for a per-visit one. Service History rows and the export's new Charged column show what each job bills; covered work shows what it came to, in grey. What was done stays recorded as it was; only what's billed follows the contract. A contract covers its places from its start to its last day, or to the day it was cancelled, going by the day a job started (a route past midnight is the day's work), and a contract has to name at least one service. Before, a season client's every visit showed as money owed on top of the season price.
