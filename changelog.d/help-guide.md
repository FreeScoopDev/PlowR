### Added
- Help in the app: Settings → Help has the Help Guide (every topic, with its steps, no network needed), Help on the Web and Contact Support, and Clients, Routes, Schedule and a route's ⋯ menu have a Help item that lists that screen's topics. Until now the guide was only on getplowr.app and nothing in the app pointed to it.

### Internal
- The help has one source, `PlowR/Help/HelpGuide.json`: the app bundles it, `scripts/help_guide.py` makes the website's `docs/help.html` from it, and the 1.8 tips will take their copy from it, so the help is written once and can't drift between the site and the app. The page records the JSON's hash and its own, and `HelpGuideTests` (in the required test check) fails a PR that edits one without the other. The same tests hold the copy to the service-language rule, which the Swift-only guard can't read.
