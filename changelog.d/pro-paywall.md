### Added
- PlowR Pro can be bought: a subscribe screen (Apple's own subscription
  view, so the price, the free trial and the renewal terms are always
  right and in the form App Review expects) with what Pro adds, Restore
  Purchases and links to the Terms and Privacy Policy; and Settings →
  PlowR Pro, which says the plan in words, opens the subscribe screen, and
  offers Manage Subscription and Restore Purchases. Nothing is gated yet.
- Delete Account & Data says deleting doesn't cancel a subscription (App
  Review checks this).

### Internal
- A StoreKit configuration file lets the simulator buy, renew and expire
  PlowR Pro when run from Xcode, before the product exists in App Store
  Connect, and lets tests buy, expire and refund it against Apple's local store.
- A purchase counts the moment it's made: StoreKit's list of current
  subscriptions takes a moment to include a new one, so PlowR could have
  told someone who had just paid that they weren't subscribed.
