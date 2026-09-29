### Internal
- Changelog entries now go in their own file in `changelog.d/`, gathered into `CHANGELOG.md` when a version is cut. Every open PR edited the same line of `[Unreleased]`, so the second to land conflicted, and a conflicted PR cannot merge until someone fixes it. `changelog.d/README.md` has the format.
