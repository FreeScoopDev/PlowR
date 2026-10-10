### Internal
- PlowR Pro groundwork: one place (`Access`) holds the subscription rules
  Joe set for the App Store launch, and `Subscription` reads the plan from
  StoreKit. Pro (trial, paid or Apple's billing grace period) is everything;
  free is 10 clients and one route; cancelling with 10 or fewer clients is
  the free tier, with more it's read only. Recording payments and exporting
  are never locked, and nothing is deleted or hidden. One place, so every
  screen, Siri action and import that's gated next asks the same question.
  No screen changes yet.
