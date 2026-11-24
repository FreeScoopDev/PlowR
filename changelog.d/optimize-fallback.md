### Fixed
- Optimize (Driving Distances) asks Maps for far fewer drive times: only the five nearest remaining stops at each step, one at a time, using the lighter travel-time request. Asking about every stop took about 190 requests for 20 stops, Maps throttled most of them, and the stops it couldn't time were scored in a different unit from the ones it could, so the order could come out worse than Quick Optimize. A stop without a drive time is now estimated in seconds from its straight-line distance, so every leg compares fairly; after Maps throttles or fails three times in a row, the rest of the run uses estimates instead of asking again.
- After optimizing, if some drive times were estimated, the route page says how many legs used straight-line distance.
- Leaving the route page while it optimizes no longer reorders the stops afterwards, and if the stops change during the run (another edit, iCloud), the order is left alone and the page says to try again.

### Internal
- The driving-distance ordering moved out of the route page into `RouteOptimizer.drivingOrder`, with the travel-time source passed in, and is unit tested.
