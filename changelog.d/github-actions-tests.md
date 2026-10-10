### Internal
- Pull requests run the full test suite on GitHub Actions again
  (`.github/workflows/tests.yml`, macOS runner, free for a public repo).
  Xcode Cloud's monthly hours, shared by every app on the membership, ran
  out and cancelled every PR's test run. Xcode Cloud keeps Release Flow. The
  new job reports alongside `CI Tests` until its run time is known; then it
  becomes the required check (docs/ci.md).
