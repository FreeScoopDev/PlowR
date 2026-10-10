#!/usr/bin/env bash
# Thin wrapper. The implementation is shared with Joe's other apps and lives in
# ~/.claude/toolkit/bin/test.sh, driven by this repo's .claude/app.json.
# CI does not use this script, so a clone without the toolkit still builds.
set -euo pipefail
TOOLKIT="${APP_TOOLKIT:-$HOME/.claude/toolkit}"
if [[ ! -x "$TOOLKIT/bin/test.sh" ]]; then
  echo "Shared toolkit not found at $TOOLKIT (set APP_TOOLKIT to override)." >&2
  exit 1
fi
# Apple's local StoreKit test store works here but not on Xcode Cloud, where
# it finds no products: SubscriptionStoreKitTests run only when this is set.
# xcodebuild hands TEST_RUNNER_-prefixed variables to the tests, unprefixed.
export TEST_RUNNER_PLOWR_STOREKIT_TESTS=1
exec "$TOOLKIT/bin/test.sh" "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" "$@"
