# Help page screenshots (PlowR)

`docs/help.html` is made from `PlowR/Help/HelpGuide.json` by `scripts/help_guide.py`: each topic's `shots` list names its screenshots (`file` in `docs/help/`, `alt`). This file lists them so a session on a Mac can take them in one pass. It is excluded from the website (`docs/_config.yml`).

## How to take them

- **Demo data:** run a Debug build on an iPhone 17 simulator with `-PlowRDemo YES` (a seeded business). Add `-PlowRDemoTab N` to open a tab (0 Home, 1 Clients, 2 Routes, 3 Documents, 4 Schedule), `-PlowRDemoRoute YES` to start the sample route, and `-PlowRDemoPro YES` for PlowR Pro. Use `-PlowRDemoNew YES` for the sign-up and setup screens. Example: `xcrun simctl launch booted Scoops.PlowR -PlowRDemo YES -PlowRDemoTab 2`.
- **Appearance:** Light (the site follows the reader's setting; light screenshots read well on both).
- **Status bar:** `xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`
- **Capture:** `xcrun simctl io booted screenshot raw-ID.png`
- **Shrink** (keeps the page light): `sips -Z 1300 -s format jpeg -s formatOptions 80 raw-ID.png --out docs/help/ID.jpg`
- **Place it:** add `{ "file": "ID.jpg", "alt": "ALT" }` to the topic's `shots` in `PlowR/Help/HelpGuide.json`, then run `python3 scripts/help_guide.py`. Never edit `docs/help.html` itself: `HelpGuideTests` fails a page that isn't what the JSON makes.
- **Done when** every image loads and `python3 scripts/help_guide.py --check` passes. Check the page at phone width before opening the pull request.
- Show no real names, phone numbers or addresses: demo data only.

## The list


### Getting started

| File | Screen |
| --- | --- |
| `help/start-how-will-you-be-using.jpg` | "How will you be using PlowR?" |
| `help/start-welcome-to-plowr-setup.jpg` | "Welcome to PlowR" setup |
| `help/start-what-do-you-do.jpg` | "What do you do?" |
| `help/start-home-get-started-card.jpg` | Home, Get Started card |

### Adding clients

| File | Screen |
| --- | --- |
| `help/clients-clients-tab-menu.jpg` | Clients tab, + menu |
| `help/clients-new-client-form.jpg` | "New Client" form |
| `help/clients-client-page.jpg` | client page |
| `help/clients-import-from-spreadsheet.jpg` | "Import from Spreadsheet" |
| `help/clients-import-preview.jpg` | import preview |
| `help/clients-request-link-screen.jpg` | Request Link screen |
| `help/clients-new-lead-from-a-request.jpg` | "New Lead" from a request |

### Building a route with expected services

| File | Screen |
| --- | --- |
| `help/routes-new-route-sheet.jpg` | "New Route" sheet |
| `help/routes-add-stops-client-picker.jpg` | "Add Stops" client picker |
| `help/routes-route-page.jpg` | route page |
| `help/routes-stop-sheet-expected-services.jpg` | Stop sheet, Expected Services |
| `help/routes-only-on-this-route-choice.jpg` | "Only on This Route" choice |
| `help/routes-schedule-tab.jpg` | Schedule tab |
| `help/routes-add-visit-recurrence.jpg` | "Add Visit", Recurrence |

### Running a route and texting clients

| File | Screen |
| --- | --- |
| `help/run-start-route-on-home.jpg` | "Start Route" on Home |
| `help/run-route-screen-current-stop.jpg` | route screen, current stop |
| `help/run-record-services.jpg` | "Record Services" |
| `help/run-notify-next-client.jpg` | "Notify Next Client?" |
| `help/run-messages-compose.jpg` | Messages compose |
