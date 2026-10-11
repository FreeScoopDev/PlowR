### Fixed
- Half a cent now always rounds up, as it should. Most cent amounts can't
  be stored exactly in the number type PlowR used, so a true half cent was
  held as just under half and rounded down: 5% tax on $2.90 billed 14 cents
  instead of 15, and $1.005 became $1.00. About 1 tax amount in 1,200 was a
  cent short. Every total, tax, payment, report and export goes through the
  one rounding rule, so all of them are fixed.
  An invoice made before this version whose tax or a line came to exactly
  half a cent shows 1 cent more than before (only test builds have these).
