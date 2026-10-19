import AuthenticationServices
import CoreData
import Foundation
import StoreKit
import SwiftData
import Testing
@testable import PlowR

/// A new business's first run: who gets setup, what setup saves, and the
/// Dashboard's Get Started steps.
@MainActor
struct FirstRunTests {
    /// An in-memory store; the container is returned to keep it alive.
    private func store() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(
            for: Schema(PlowRApp.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        context.autosaveEnabled = false
        return (container, context)
    }

    /// Only a business with nothing yet: anyone already using PlowR (a
    /// profile or a client, made here or synced in) skips it.
    @Test func setupIsForANewBusinessOnly() {
        #expect(FirstRun.needsSetup(hasProfile: false, clientCount: 0, completed: false))
        #expect(!FirstRun.needsSetup(hasProfile: true, clientCount: 0, completed: false))
        #expect(!FirstRun.needsSetup(hasProfile: false, clientCount: 3, completed: false))
        #expect(!FirstRun.needsSetup(hasProfile: false, clientCount: 0, completed: true))
    }

    @Test func setupSavesTheBusinessServicesAndTax() throws {
        let (container, context) = try store()
        defer { _ = container }
        var answers = FirstRun.Answers()
        answers.companyName = "  Upper Valley Snow & Lawn "
        answers.logoData = Data([1, 2, 3])
        answers.categories = ["lawn", ServiceCatalog.snowKey]
        answers.taxRate = "6,25"
        FirstRun.save(answers, operatorID: "op", in: context)

        let profile = try #require(try context.fetch(FetchDescriptor<BusinessProfile>()).first)
        #expect(profile.operatorID == "op")
        #expect(profile.companyName == "Upper Valley Snow & Lawn")
        #expect(profile.logoData == Data([1, 2, 3]))
        #expect(profile.defaultTaxRate == 6.25)
        let services = try context.fetch(FetchDescriptor<ServiceItem>()).filter { $0.operatorID == "op" }
        let categories = Set(services.map(\.category))
        #expect(categories == ["lawn", ServiceCatalog.snowKey])
        #expect(Set(services.map(\.name)).count == services.count)     // none added twice
    }

    /// A skipped step leaves its part as it was: an existing name and rate stay.
    @Test func skippedStepsChangeNothing() throws {
        let (container, context) = try store()
        defer { _ = container }
        let existing = BusinessProfile(operatorID: "op")
        existing.companyName = "Kept"
        existing.defaultTaxRate = 7
        context.insert(existing)
        FirstRun.save(FirstRun.Answers(), operatorID: "op", in: context)
        let profiles = try context.fetch(FetchDescriptor<BusinessProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.companyName == "Kept")
        #expect(profiles.first?.defaultTaxRate == 7)
        #expect(try context.fetch(FetchDescriptor<ServiceItem>()).isEmpty)
    }

    @Test func theChecklistTicksOffWhatsDone() {
        let profile = BusinessProfile(operatorID: "op")
        profile.companyName = "Named"
        let draft = Proposal(operatorID: "op", client: Client(name: "A", phone: "", address: "", operatorID: "op"))
        draft.invoiceNumber = "INV-0001"
        var list = FirstRun.checklist(profile: profile, clients: 1, routes: 0, documents: [draft], alertsUndecided: false)
        #expect(list.profileDone && list.clientAdded && !list.routeMade && !list.invoiceSent)
        #expect(list.doneCount == 2 && !list.isComplete)
        draft.invoiceSentAt = .now
        list = FirstRun.checklist(profile: profile, clients: 1, routes: 1, documents: [draft], alertsUndecided: false)
        #expect(list.isComplete)
        // Alerts not yet asked about keep it open.
        list = FirstRun.checklist(profile: profile, clients: 1, routes: 1, documents: [draft], alertsUndecided: true)
        #expect(!list.isComplete)
    }

    @Test func noProfileOrAnUnnamedOneIsNotDone() {
        #expect(!FirstRun.checklist(profile: nil, clients: 0, routes: 0, documents: [], alertsUndecided: false).profileDone)
        #expect(!FirstRun.checklist(profile: BusinessProfile(operatorID: "op"), clients: 0, routes: 0, documents: [],
                                    alertsUndecided: false).profileDone)
    }

    /// Cancel is the user's choice; any other failure is explained.
    @Test func cancellingSignInIsNotAFailure() {
        #expect(SignInFailure.isCancel(ASAuthorizationError(.canceled)))
        #expect(!SignInFailure.isCancel(ASAuthorizationError(.failed)))
    }
    /// Setup with every step skipped makes no profile: an empty one could
    /// stand in for the real one still on its way from iCloud.
    @Test func skippingEverythingMakesNoProfile() throws {
        let (container, context) = try store()
        defer { _ = container }
        FirstRun.save(FirstRun.Answers(), operatorID: "op", in: context)
        #expect(try context.fetch(FetchDescriptor<BusinessProfile>()).isEmpty)
    }

    /// A profile that arrived from iCloud while setup was open keeps its name.
    @Test func setupNeverOverwritesWhatsThere() throws {
        let (container, context) = try store()
        defer { _ = container }
        let synced = BusinessProfile(operatorID: "op")
        synced.companyName = "From iCloud"
        context.insert(synced)
        var answers = FirstRun.Answers()
        answers.companyName = "Typed"
        answers.taxRate = "5"
        FirstRun.save(answers, operatorID: "op", in: context)
        let profiles = try context.fetch(FetchDescriptor<BusinessProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.companyName == "From iCloud")
        #expect(profiles.first?.defaultTaxRate == 5)       // it had none
    }

    /// A standard service already there isn't added again.
    @Test func standardServicesAreAddedOnce() throws {
        let (container, context) = try store()
        defer { _ = container }
        var answers = FirstRun.Answers()
        answers.categories = [ServiceCatalog.snowKey]
        FirstRun.save(answers, operatorID: "op", in: context)
        let first = try context.fetch(FetchDescriptor<ServiceItem>()).count
        #expect(first > 0)
        FirstRun.save(answers, operatorID: "op", in: context)
        #expect(try context.fetch(FetchDescriptor<ServiceItem>()).count == first)
    }

    /// Another business's records on the device don't count.
    @Test func onlyThisBusinessesRecordsCount() {
        let theirs = BusinessProfile(operatorID: "other")
        let theirClient = Client(name: "T", phone: "", address: "", operatorID: "other")
        #expect(FirstRun.needsSetup(profiles: [theirs], clients: [theirClient], operatorID: "op", completed: false))
        let mine = Client(name: "M", phone: "", address: "", operatorID: "op")
        #expect(!FirstRun.needsSetup(profiles: [theirs], clients: [mine], operatorID: "op", completed: false))
    }

    /// Get Started is for a business that went through setup here, not for
    /// one that's used PlowR for a year and updated.
    @Test func getStartedIsForNewBusinesses() {
        let open = FirstRun.Checklist(profileDone: false, clientAdded: true, routeMade: false, invoiceSent: false,
                                      alertsUndecided: false)
        #expect(FirstRun.showsChecklist(completedSetup: true, hidden: false, checklist: open))
        #expect(!FirstRun.showsChecklist(completedSetup: false, hidden: false, checklist: open))
        #expect(!FirstRun.showsChecklist(completedSetup: true, hidden: true, checklist: open))
    }
}

/// One profile per business, the same one on every device.
@MainActor
struct BusinessProfilesTests {
    @Test func theSameProfileWhateverTheOrder() {
        let a = BusinessProfile(operatorID: "op"), b = BusinessProfile(operatorID: "op")
        let other = BusinessProfile(operatorID: "other")
        let first = BusinessProfiles.current([a, b, other], operatorID: "op")
        #expect(first === BusinessProfiles.current([other, b, a], operatorID: "op"))
        #expect(first === (a.id.uuidString < b.id.uuidString ? a : b))
    }

    /// The extra is folded in: nothing either had is lost, one is left.
    @Test func duplicatesMergeIntoOne() throws {
        let container = try ModelContainer(
            for: Schema(PlowRApp.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        context.autosaveEnabled = false
        let a = BusinessProfile(operatorID: "op"), b = BusinessProfile(operatorID: "op")
        // a is kept (lowest ID), so b's tax, logo and reasons must be copied.
        a.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        b.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        a.companyName = "Real Name"
        b.defaultTaxRate = 6.25
        b.logoData = Data([9])
        b.customVisitReasons = ["Salt only"]
        let other = BusinessProfile(operatorID: "other")
        [a, b, other].forEach { context.insert($0) }
        let keep = try #require(BusinessProfiles.current([a, b], operatorID: "op"))
        #expect(keep === a)
        #expect(BusinessProfiles.mergeDuplicates(in: context) == 1)
        let left = try context.fetch(FetchDescriptor<BusinessProfile>()).filter { $0.operatorID == "op" }
        #expect(left.count == 1 && left.first === keep)
        #expect(keep.companyName == "Real Name")
        #expect(keep.defaultTaxRate == 6.25)
        #expect(keep.logoData == Data([9]))
        #expect(keep.customVisitReasons == ["Salt only"])
        #expect(try context.fetch(FetchDescriptor<BusinessProfile>()).count == 2)   // "other" untouched
    }
}

/// First-run setup waits for iCloud's first import, watched from launch.
@MainActor
struct CloudImportWaitTests {
    /// The import finished before anyone reached setup: no waiting at all.
    @Test func anImportFinishedEarlierEndsTheWaitAtOnce() {
        let watch = CloudImportWatch()
        watch.record(importEnded: true)
        #expect(CloudImportWait(watch: watch).isReady)
    }

    /// CoreData's CloudKit queue posts the import event; the watch must take
    /// it without making that queue wait for the main thread (a deadlock).
    @Test func theImportEventNeverWaitsForTheMainThread() async throws {
        let center = NotificationCenter()
        let watch = CloudImportWatch()
        watch.start(center: center)
        let posted = PostClock()
        let poster = Thread {
            center.post(name: NSPersistentCloudKitContainer.eventChangedNotification, object: nil)
            posted.mark()
        }
        poster.start()
        Thread.sleep(forTimeInterval: 0.5)          // the main thread, busy
        let mainFreed = Date()
        try await Task.sleep(for: .milliseconds(100))
        let at = try #require(posted.at)
        #expect(at < mainFreed)
        #expect(!watch.importEnded)                 // no event in it: not an import's end
    }

    @Test func noICloudAccountMeansNoWait() async {
        let wait = CloudImportWait(watch: CloudImportWatch())
        await wait.start(for: "op", syncOff: false, underTests: false, accountAvailable: { false })
        #expect(wait.isReady)
    }

    @Test func syncOffMeansNoWait() async {
        let wait = CloudImportWait(watch: CloudImportWatch())
        await wait.start(for: "op", syncOff: true, underTests: false, accountAvailable: { true })
        #expect(wait.isReady)
    }

    /// The limit counts from launch: past it, setup shows at once.
    @Test func theLimitCountsFromLaunch() async {
        let watch = CloudImportWatch()
        let wait = CloudImportWait(watch: watch)
        var slept: TimeInterval?
        await wait.start(for: "op", syncOff: false, underTests: false, accountAvailable: { true },
                         now: { watch.launchedAt.addingTimeInterval(CloudImportWait.limit + 1) },
                         sleep: { slept = $0 })
        #expect(wait.isReady)
        #expect(slept == nil)          // past the limit: no waiting at all
        // Ten seconds in, it waits out the rest, not the whole limit.
        let early = CloudImportWait(watch: watch)
        await early.start(for: "op", syncOff: false, underTests: false, accountAvailable: { true },
                          now: { watch.launchedAt.addingTimeInterval(10) }, sleep: { slept = $0 })
        #expect(slept == CloudImportWait.limit - 10)
    }

    /// Only a finished import ends the wait: not one just started, not an
    /// export or setup event.
    @Test func onlyAFinishedImportCounts() {
        #expect(CloudImportWatch.endsImport(isImport: true, endDate: .now))
        #expect(!CloudImportWatch.endsImport(isImport: true, endDate: nil))
        #expect(!CloudImportWatch.endsImport(isImport: false, endDate: .now))
        let watch = CloudImportWatch()
        watch.record(importEnded: false)
        #expect(!CloudImportWait(watch: watch).isReady)
    }

    /// A wait finished for one business doesn't count for the next, in
    /// either order of reset and finish.
    @Test func aNewBusinessWaitsAfresh() async {
        let wait = CloudImportWait(watch: CloudImportWatch())
        await wait.start(for: "a", syncOff: true)
        wait.reset(for: "b")
        #expect(!wait.isReady)
        await wait.start(for: "b", syncOff: true)
        #expect(wait.isReady)
        wait.reset(for: "b")            // the same business again: still done
        #expect(wait.isReady)
    }

    @Test func trialLengthsReadNaturally() {
        #expect(Subscription.trialLength(value: 1, unit: .month) == "a month")
        #expect(Subscription.trialLength(value: 2, unit: .week) == "2 weeks")
    }
}
