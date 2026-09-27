//
//  ModelContainerTests.swift
//  PlowRTests
//

import Testing
@testable import PlowR

// Pins the CloudKit skip in PlowRApp.makeContainer. The host app has already
// built its container by the time this runs, so it reads what that launch did.
//
// If the skip itself is removed, this assertion never gets a chance to fail:
// CoreData traps on its CloudKit queue a few seconds after launch and the whole
// run dies with "Test crashed with signal trap before establishing connection."
// That crash is the red signal for that regression. What this test catches is
// the quieter one: the fallback bookkeeping going wrong while the app still
// launches. (A plain `#expect(isRunningUnderTests)` was tried and dropped: if
// detection breaks, the app traps before that assertion can run, so it could
// never fail on its own.)
struct ModelContainerTests {

    // The launch under test must have used the local store, never CloudKit.
    // isCloudKitAvailable is only set false on the local-store path.
    @Test func launchUnderTestUsedTheLocalStore() {
        #expect(!PlowRApp.isCloudKitAvailable)
    }
}
