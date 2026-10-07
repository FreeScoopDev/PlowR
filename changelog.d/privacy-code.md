### Added
- Delete My Data for clients (the client side's menu): removes their saved service requests and the name, phone and email kept for their next request, after asking. Before, a client had no way to remove their contact details, and could swipe away saved requests only from All Requests (shown with more than three); only a business had Delete Account & Data.

### Changed
- Sign in with Apple asks only for your name, no longer your email. PlowR never used the email; it dropped it on arrival. Not asking at all is the honest version, and what the privacy policy can then say.
- The app's privacy manifest declares Coarse Location as well as Precise: weather requests send coordinates rounded to about 1 km (Open-Meteo), and a property's measured corners go precisely (Open Topo Data). Both for app functionality, not linked to the user, not tracking, as the App Store privacy answers will say.
