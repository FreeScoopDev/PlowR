### Fixed
- getplowr.app no longer writes PlowR Pro's price. The home and snow removal pages said "$8.99 a month", but the price differs by country and Apple can change it, which is why the app never writes it either (the App Store's own paywall shows it). They now say Pro is a monthly subscription with a one-month free trial for new subscribers (the trial PlowR's App Store product offers), and that the App Store shows the price before you subscribe.
- The home and snow removal pages say PlowR can order a route's stops by drive time, which is what Optimize Order measures (Apple Maps' driving time between stops), not by driving distance.
- The home and snow removal pages use the shared stylesheet (`assets/site.css`) for the base rules again, keeping only their own colours and layout inline; the launch update had copied the base rules into each page. The snow removal page has a `main` landmark, as the home page does, so screen readers can jump past the header.
- The Support page says importing clients is part of PlowR Pro, and names the Clients tab's Import from Spreadsheet as well as Settings › Import Clients. Someone on the free plan followed the answer to a screen asking them to subscribe.
- The page a lead request link opens has an App Store link for a business that doesn't have PlowR on that device yet.
- The sitemap dates every page at its last change on the site; the help page's date was a month old.
- The launch update had rewritten another change's unreleased changelog entry; it's back as it was, and the launch update's own entry says what it did.
