### Fixed
- In a region that writes decimals with a comma, a price, discount or
  payment typed "12,50" (what the keypad types there) is read as 12.50. It
  was unreadable, so a line silently billed its default price, a discount
  came off as nothing and a payment couldn't be recorded. Tax rates already
  read a decimal comma, but in every region; now prices and rates follow the
  same rule, and only where the region uses a comma, so a US iPad's "1,250"
  isn't taken for 1.25. A figure with both a comma and a dot ("1,250.00") is
  still not read, rather than guessed at.
- A service catalog price that can't be read is no longer saved as $0 over
  the price the service had: Save waits, and the field says why.
