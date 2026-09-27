# CI — what runs, where, and why

Written 2026-09-26. Correct it when it goes stale.

Xcode Cloud is configured in App Store Connect and **cannot be expressed as a
file in this repo**. Xcode Cloud has no workflow-as-code format. Without this
document, the definition of what gates `main` lives in one web UI and nowhere
else. It mirrors Wockett's `docs/ci.md`, and the lessons behind each setting
are recorded there.

This file is excluded from the getplowr.app site by `docs/_config.yml`. GitHub
Pages publishes everything else in `docs/`.

## Status

| | |
| --- | --- |
| GitHub Actions `Tests` (`.github/workflows/tests.yml`) | **Live**, green since #1 (2026-09-26). macOS runner, bills at 10×. Deleted once `CI Tests` below posts a green status. |
| Xcode Cloud `CI Tests` | **Not created yet.** Setup steps below. |
| Xcode Cloud `Release Flow` | **Not created yet.** Setup steps below. |
| Branch protection on `main` | None yet. Open decision. |

Update this table as each row changes.

## Xcode Cloud

Two workflows, both on `https://github.com/FreeScoopDev/PlowR.git` /
`PlowR.xcodeproj`, scheme `PlowR`.

**The 25 compute hours a month belong to the developer membership, not to one
app.** PlowR shares them with Wockett. Keep PR runs to the unit tests (plus a
short UI smoke suite once one exists) and keep "one change per PR".

### `CI Tests` — the workflow that will gate `main`

| | |
| --- | --- |
| Start condition | **Pull Request Changes**, source `Any Branches`, target `main`, starts if any file changes |
| Auto-cancel | On. A newer push to the same branch cancels the running build. |
| Action | **Test - iOS**, scheme `PlowR`, **Required to Pass**, Test Option `Test (Use Scheme Setting)`, 1 destination: **iPhone 17** simulator, latest iOS |
| Environment | Xcode **26.6 (17F113)**, macOS **Tahoe 26.5.1**, pinned, not `Latest Release`. Same pins as Wockett. |
| Clean | **Off**, so caches are restored and runs stay fast |
| Notifies | Slack `#ci_tests`, all successes and failures |

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
| Notifies | Slack `#plowr_release_updates`, all successes and failures |

**Why "TestFlight and App Store" and not "TestFlight (Internal Testing
Only)":** Apple never accepts an internal-only build for App Store review.
Wockett lost its whole 1.11 release to that setting. The check that matters: a
Release Flow build must be offered under **Add Build** on an App Store version
page.

### Things Wockett learned the hard way

Details are in Wockett's `docs/ci.md`.

- **One build-number counter for the whole app.** Every `CI Tests` run uses up
  a number, just as an archive does. Never predict the next build number; read
  it off the finished archive. Xcode Cloud ignores `CURRENT_PROJECT_VERSION`.
- **A run that fails within seconds is the environment pin, not the code.**
  Apple retires old macOS images. The parent `PlowR | CI Tests` status fails
  and no `… | Test - iOS` check-run ever appears. Fix: Manage Workflows →
  Environment, on **both** workflows, pick the newest macOS offered, Rebuild.
- **Sometimes Xcode Cloud never hears about a PR.** No status appears, not
  even `pending`. Re-fire with `gh pr close <N> && gh pr reopen <N>`. First
  check that the PR's base is `main`: a PR stacked on another branch gets no
  run by design.
- **Tests must never touch real CloudKit.** `PlowRApp.isRunningUnderTests`
  skips CloudKit mirroring. Without it the host app traps a few seconds after
  launch ("Test crashed with signal trap before establishing connection").

## Setting it up (one time, Joe)

Written from Apple's documentation and Wockett's setup, not yet walked
through for PlowR. If a screen doesn't match a step, stop and tell Claude
what you see.

**Before you start**

1. In Terminal, check that your PlowR folder is on an up-to-date `main`:
   `git -C ~/Desktop/Apps/PlowR status -sb`. You should see
   `## main...origin/main` with no `[behind N]`. If you see `behind`, run
   `git -C ~/Desktop/Apps/PlowR pull --ff-only` first.
2. Open https://appstoreconnect.apple.com → **Apps**. Check that **PlowR**
   is listed. If it isn't, stop and tell Claude. Xcode Cloud needs the app
   record first.
3. In Slack, create a channel **#plowr_release_updates**. `#ci_tests` is
   shared with Wockett, and the PR check messages will say which app they
   are for.

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
11. **Post-Actions**: add **Notify → Slack** → `#ci_tests` → Success and
    Failure. If Slack isn't connected for PlowR yet, Xcode asks you to
    authorize it; accept for Slack only.
12. Click **Save**, then **Next**. Xcode asks to **Grant Access** to GitHub.
    Click it. On GitHub, make sure the Xcode Cloud app's repository list
    includes **FreeScoopDev/PlowR**, not only Wockett. Save.
13. Back in Xcode, click **Complete**. Don't start a build by hand. Tell
    Claude, who opens a small PR to trigger the first run.

**Create `Release Flow` (in App Store Connect)**

14. App Store Connect → Apps → **PlowR** → **Xcode Cloud** tab → **Manage
    Workflows** → **+**.
15. Name `Release Flow`. Environment: same pins as step 8. Clean: **On**.
16. Start Conditions: remove any defaults. Add **Manual Start**, restricted
    to branch **`main`**.
17. Actions: add **Archive**, platform iOS, scheme `PlowR`, Distribution
    Preparation **TestFlight and App Store**. Double-check this one. The
    internal-only option cost Wockett a release.
18. Post-Actions: add **TestFlight Internal Testing** → your internal tester
    group. Add **Notify → Slack** → `#plowr_release_updates` → Success and
    Failure.
19. Click **Save**. Don't press Start. Release Flow is first used in a
    release, whenever the first PlowR release is decided.

**What Claude does after**

- Watches the first `CI Tests` run. Once `PlowR | CI Tests | Test - iOS`
  posts green on a PR, it opens a PR deleting `.github/workflows/tests.yml`
  and updates the Status table above.
