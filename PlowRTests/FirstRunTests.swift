import AuthenticationServices
import Foundation
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
}
