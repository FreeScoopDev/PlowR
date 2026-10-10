### Fixed
- A price, discount or payment typed with a decimal comma ("12,50", what the
  keypad types in many regions) is read as 12.50. It was unreadable, so a
  line silently billed its default price, a discount came off as nothing and
  a payment couldn't be recorded. A service's catalog price typed that way
  was saved as $0, over the price it had. Tax rates already read a decimal
  comma; every number field now reads one the same way. A figure with both a
  comma and a dot ("1,250.00") is still not read, rather than guessed at.
