import Foundation
import SwiftData

/// A new business's first minutes (Joe, 2026-10-11: a short setup, then a
/// checklist). Setup is three skippable steps (the business, what it does,
/// its sales tax), a word on alerts and location, and what's free and what
/// Pro adds. The Dashboard's Get Started card follows until its steps are
/// done or it's hidden.
enum FirstRun {
    /// Setup is for a new business only: no profile, no clients, and it
    /// hasn't been through setup on this device. Anyone already using PlowR
    /// (a profile or a client, here or synced from another device) never
    /// sees it.
    static func needsSetup(hasProfile: Bool, clientCount: Int, completed: Bool) -> Bool {
        !completed && !hasProfile && clientCount == 0
    }

    /// Per business, in standard preferences (Delete Account & Data clears them).
    static func completedKey(_ operatorID: String) -> String { "setupCompleted.\(operatorID)" }
    static func checklistHiddenKey(_ operatorID: String) -> String { "getStartedHidden.\(operatorID)" }

    /// What setup collected. Nothing is required: a step skipped leaves its
    /// part as it was.
    struct Answers: Equatable {
        var companyName = ""
        var logoData: Data?
        /// Standard service categories to add (ServiceCatalog.standardCategories' keys).
        var categories: Set<String> = []
        /// As typed; read with Proposal.readTaxRate.
        var taxRate = ""
    }

    /// Saves the answers: the business profile (made if there's none),
    /// the chosen standard services, the default tax rate.
    @MainActor
    static func save(_ answers: Answers, operatorID: String, in context: ModelContext) {
        let profiles = (try? context.fetch(FetchDescriptor<BusinessProfile>())) ?? []
        let profile = profiles.first { $0.operatorID == operatorID } ?? {
            let new = BusinessProfile(operatorID: operatorID)
            context.insert(new)
            return new
        }()
        let name = answers.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { profile.companyName = name }
        if let logo = answers.logoData { profile.logoData = logo }
        if let rate = Proposal.readTaxRate(answers.taxRate), rate > 0 { profile.defaultTaxRate = rate }
        let existing = (try? context.fetch(FetchDescriptor<ServiceItem>())) ?? []
        for category in ServiceCatalog.standardCategories where answers.categories.contains(category.key) {
            let current = (try? context.fetch(FetchDescriptor<ServiceItem>())) ?? existing
            ServiceCatalog.addStandard(category, operatorID: operatorID, existing: current, to: context)
        }
        try? context.save()
    }

    /// The Get Started card's steps, each done or not.
    struct Checklist: Equatable {
        var profileDone: Bool
        var clientAdded: Bool
        var routeMade: Bool
        var invoiceSent: Bool
        /// Notifications not yet asked about: offered as a step.
        var alertsUndecided: Bool

        var isComplete: Bool { profileDone && clientAdded && routeMade && invoiceSent && !alertsUndecided }
        var doneCount: Int { [profileDone, clientAdded, routeMade, invoiceSent].filter { $0 }.count }
    }

    static func checklist(profile: BusinessProfile?, clients: Int, routes: Int, documents: [Proposal],
                          alertsUndecided: Bool) -> Checklist {
        Checklist(profileDone: !(profile?.companyName ?? "").isEmpty,
                  clientAdded: clients > 0,
                  routeMade: routes > 0,
                  invoiceSent: documents.contains { $0.isInvoice && $0.invoiceSentAt != nil },
                  alertsUndecided: alertsUndecided)
    }
}
