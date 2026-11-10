### Added
- Call from the route screen. The current stop now has a Call button when the client has a phone number, so you can ring about a locked gate without leaving the route or hunting for the number. It doesn't show on a device that can't place calls, such as a Mac.
- Directions on the client page. The Contact menu now has a Directions choice, so you can drive to a client for an estimate or a one-off job without starting a route. It goes to their pin, or their address if they have no pin, and offers Apple Maps, plus Google Maps and Waze if you have them. Both work on every plan, including read only, since they only look at a record.

### Fixed
- Calling a number saved with an extension ("555-010-0123 ext. 45") dialed the extension as part of the number, which reached nobody, and a number from abroad lost its "+". Call now dials the number itself and keeps the "+", from every Call button in the app.
- Google Maps directions to an address with "&" or "#" in it ("Smith & Sons", "Unit #4") were cut off at that character. The whole address now reaches Google Maps.
- With Waze installed, a stop with an address but no pin offered Waze, which did nothing when tapped. Waze is now offered only where it can be sent somewhere.

### Internal
- The map links and the choice of which maps apps to offer now live in one place, shared by the route screen and the client page.
