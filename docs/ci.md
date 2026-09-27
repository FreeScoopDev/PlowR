# CI — what runs, where, and why

Written 2026-09-26. Correct it when it goes stale.

Xcode Cloud is configured in App Store Connect and **cannot be expressed as a
file in this repo**. Xcode Cloud has no workflow-as-code format. Without this
document, the definition of what gates `main` lives in one web UI and nowhere
else.

This repo is public, so this file holds settings only. It has no account IDs,
no links into App Store Connect, and no internal channel or tool references
beyond names that reveal nothing.
It is also excluded from the getplowr.app website by `docs/_config.yml`,
because GitHub Pages publishes everything else in `docs/`.

## Status

| | |
| --- | --- |
| GitHub Actions `Tests` (`.github/workflows/tests.yml`) | **Removed 2026-09-27.** It ran the same tests on a macOS runner and was replaced by `CI Tests` below. |
| Xcode Cloud `CI Tests` | **Created 2026-09-26** (steps 1–13). Green on its first run (#7); failed a deliberate break (#8) as it should. The only test check on PRs. |
| Xcode Cloud `Release Flow` | **Created 2026-09-26** (steps 14–19). Never started yet. First used for PlowR's first Release Flow build. |
| Branch protection on `main` | **Active since 2026-09-27.** Ruleset "Protect main": no deletion, no force-push, changes only through a PR (squash merge, 0 approvals), required checks `PlowR \| CI Tests \| Test - iOS`, `Service-language guard` and `SwiftLint` (added 2026-09-27). No bypass list. Check with `gh api repos/FreeScoopDev/PlowR/rules/branches/main`, not the settings page. |

Update this table as each row changes.

## Xcode Cloud

Two workflows, both on `https://github.com/FreeScoopDev/PlowR.git` /
`PlowR.xcodeproj`, scheme `PlowR`.

**The 25 compute hours a month belong to the developer membership, not to one
app.** Keep PR runs to the unit tests (plus a short UI smoke suite once one
exists) and keep one change per PR.

### `CI Tests` — the workflow that will gate `main`

| | |
| --- | --- |
| Start condition | **Pull Request Changes**, source `Any Branch`, target `main`, starts if any file changes |
| Auto-cancel | On. A newer push to the same branch cancels the running build. |
| Action | **Test - iOS**, scheme `PlowR`, **Required to Pass**, Test Option `Test (Use Scheme Setting)`, 1 destination: **iPhone 17** simulator, latest iOS |
| Environment | Xcode **26.6 (17F113)**, macOS **Tahoe 26.5.1**, pinned, not `Latest Release` |
| Clean | **Off**, so caches are restored and runs stay fast |
| Notifies | Slack `#plowr-ci`, all successes and failures |

It posts the `PlowR | CI Tests | Test - iOS` check. "Use Scheme Setting" means
**the `PlowR` scheme decides which test targets run.** Adding a target to the
scheme's Test action changes CI coverage with no edit here.

### `Release Flow` — the only release path

| | |
| --- | --- |
| Start condition | **Manual Start** only, restricted to **`main`**. Pull Request and Tag **Not Enabled**. |
| Action | **Archive - iOS**, scheme `PlowR`, Distribution Preparation **TestFlight and App Store** |
| Environment | Xcode **26.6 (17F113)**, macOS **Tahoe 26.5.1**, pinned |
| Clean | **On**. Slower, but a release build must not depend on a cache. |
| Post-action | **TestFlight Internal Testing** to the internal tester group |
| Notifies | Slack `#plowr-releases`, all successes and failures |

**Why "TestFlight and App Store" and not "TestFlight (Internal Testing
Only)":** Apple never accepts an internal-only build for App Store review or
external testing. The check that matters: a Release Flow build must be offered
under **Add Build** on an App Store version page.

**Why `main` only:** with `Any Branch`, a mis-click in the Start dialog can
archive a feature branch straight to TestFlight.

### Xcode Cloud behaviour to know

- **One build-number counter for the whole app.** Every `CI Tests` run uses up
  a number, just as an archive does. Never predict the next build number; read
  it off the finished archive. Xcode Cloud ignores `CURRENT_PROJECT_VERSION`.
- **Pinned toolchains get retired.** Pinning makes a toolchain change a dated,
  deliberate edit instead of a silent one. The cost: Apple periodically
  removes old macOS images. When that happens, the parent `PlowR | CI Tests`
  status fails within seconds and no `… | Test - iOS` check-run ever appears,
  because nothing compiled. Fix: Manage Workflows → Environment, on **both**
  workflows, pick the newest macOS offered, Rebuild.
- **Sometimes Xcode Cloud never hears about a PR.** No status appears, not
  even `pending`. Re-fire with `gh pr close <N> && gh pr reopen <N>`. First
  check that the PR's base is `main`: a PR stacked on another branch gets no
  run, by design.
- **Tests must never touch real CloudKit.** `PlowRApp.isRunningUnderTests`
  skips CloudKit mirroring. Without it the host app traps a few seconds after
  launch ("Test crashed with signal trap before establishing connection").

## Setting it up (one time, Joe)

Written from Apple's documentation, not yet walked through for PlowR. If a
screen doesn't match a step, stop and tell Claude what you see.

**Before you start**

1. In Terminal, check that your PlowR folder is on an up-to-date `main`:
   `git -C ~/Desktop/Apps/PlowR status -sb`. You should see
   `## main...origin/main` with no `[behind N]`. If you see `behind`, run
   `git -C ~/Desktop/Apps/PlowR pull --ff-only` first.
2. Open https://appstoreconnect.apple.com → **Apps**. Check that **PlowR**
   is listed. If it isn't, stop and tell Claude. Xcode Cloud needs the app
   record first.
3. In Slack, create two channels, **#plowr-ci** and **#plowr-releases**.

**Create `CI Tests` (in Xcode — Apple requires the first workflow to be made there)**

4. Open `~/Desktop/Apps/PlowR/PlowR.xcodeproj` in Xcode.
5. Menu **Product → Xcode Cloud → Create Workflow…**. If the menu isn't
   there, open the Report navigator (⌘9), choose the **Cloud** tab and click
   **Get Started**.
6. Choose the product **PlowR** and click **Next**. Xcode proposes a
   default workflow. Click **Edit Workflow**.
7. **General**: set Name to `CI Tests`.
8. **Environment**: set Xcode Version to **26.6 (17F113)** and macOS Version
   to **Tahoe 26.5.1**, not "Latest Release". If 26.5.1 isn't listed, pick
   the newest macOS offered and tell Claude which one.
9. **Start Conditions**: delete the default "Branch Changes" condition. Add
   **Pull Request Changes** with Source `Any Branch`, Target `main`, "Start a
   build for any changes". Turn **Auto-cancel Builds** on.
10. **Actions**: delete the default Archive action. Add **Test**: platform
    iOS, scheme `PlowR`, Test Option **Use Scheme Setting**, destination
    **iPhone 17** / Latest iOS. Tick **Required to pass**.
11. **Post-Actions**: add **Notify → Slack** → `#plowr-ci` → Success and
    Failure. If Xcode asks you to authorize Slack, accept for Slack only.
12. Click **Save**, then **Next**. Xcode asks to **Grant Access** to GitHub.
    Click it. On GitHub, set the Xcode Cloud app's repository access so it
    includes **FreeScoopDev/PlowR**. Save.
13. Back in Xcode, click **Complete**. Don't start a build by hand. Tell
    Claude, who opens a small PR to trigger the first run.

**Create `Release Flow` (in App Store Connect)**

14. App Store Connect → Apps → **PlowR** → **Xcode Cloud** tab → **Manage
    Workflows** → **+**.
15. Name `Release Flow`. Environment: same pins as step 8. Clean: **On**.
16. Start Conditions: remove any defaults. Add **Manual Start**, restricted
    to branch **`main`**.
17. Actions: add **Archive**, platform iOS, scheme `PlowR`, Distribution
    Preparation **TestFlight and App Store**. Double-check this one; see
    "Why" above.
18. Post-Actions: add **TestFlight Internal Testing** → your internal tester
    group. Add **Notify → Slack** → `#plowr-releases` → Success and Failure.
19. Click **Save**. Don't press Start. Release Flow is first used in a
    release, whenever the first PlowR release is decided.

**What Claude does after**

- Watched the first `CI Tests` run (PR #7, green). Proved it gates by
  opening a throwaway PR that broke the app on purpose (#8): `Test - iOS`
  reported 1 test failure and `CI Tests` failed. Then removed
  `.github/workflows/tests.yml`.
