import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Add to PlowR: a request from the business's request link, routed to the
/// New Lead screen, checked against clients PlowR has, and saved as a lead.
@MainActor
struct LeadIntakeTests {
    let container: ModelContainer
    let context: ModelContext
    let now = Date(timeIntervalSince1970: 1_791_382_500)          // Oct 7 2026, 14:15 GMT

    init() throws {
        container = try ModelContainer(for: Schema(PlowRApp.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                          cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
        context = container.mainContext
    }

    private let request = RequestLink.Request(
        name: "Kim Doe", phone: "+1 603 555 0199", email: "kim@example.com", address: "12 Main St, Claremont, NH",
        service: "Lawn Care", when: .seasonal, notes: "Back gate.")

    private func route(_ url: URL, role: String = UserRole.business, checking: Bool = false, signedIn: Bool = true,
                       removal: Bool = false) -> IncomingLinks.Route? {
        IncomingLinks.route(for: url, role: role, isChecking: checking, isSignedIn: signedIn, removalPending: removal)
    }

    @Test func aLinkOpensTheRightThing() throws {
        let link = try #require(RequestLink.url(for: request))
        #expect(route(link) == .request(request))
        let appLink = try #require(URL(string: link.absoluteString.replacingOccurrences(of: "https://getplowr.app/lead/", with: "plowr://lead")))
        #expect(route(appLink) == .request(request))
        #expect(route(try #require(URL(string: "https://getplowr.app/lead/#n=Kim"))) == .damaged)
        #expect(route(try #require(URL(string: "plowr://activeRoute"))) == nil)
    }

    // At launch the link comes before Apple's sign-in check answers: it
    // waits for it, and a signed-out business is asked to sign in, the link
    // kept for when they have.
    @Test func aLinkWaitsForSignIn() throws {
        let link = try #require(RequestLink.url(for: request))
        #expect(route(link, checking: true, signedIn: false) == .wait)
        #expect(route(link, checking: false, signedIn: false) == .signIn)
        #expect(route(link, role: UserRole.client, signedIn: false) == .notBusiness)
        #expect(route(link, role: "", signedIn: false) == .notBusiness)
        #expect(route(link, removal: true) == .unavailable)
    }

    @Test func aReturningClientIsFoundByPhone() {
        let kim = Client(name: "Kimberly Doe", phone: "(603) 555-0199", address: "", operatorID: "op")
        let theirs = Client(name: "Kim", phone: "603-555-0199", address: "", operatorID: "someone else")
        context.insert(kim)
        context.insert(theirs)
        #expect(LeadIntake.existingClient(for: request, operatorID: "op", in: context) === kim)
        #expect(LeadIntake.existingClient(for: request, operatorID: "nobody", in: context) == nil)
    }

    @Test func savedAsALeadWithWhatTheyAsked() throws {
        let client = LeadIntake.save(request, operatorID: "op", in: context, now: now,
                                     locale: Locale(identifier: "en_US"), timeZone: .gmt)
        #expect(client.name == "Kim Doe" && client.phone == "+1 603 555 0199" && client.email == "kim@example.com")
        #expect(client.tags == ["Requested Oct 7"] && client.customerSince == nil)
        #expect(!LeadIntake.isRequestTag("Requested quote") && !LeadIntake.isRequestTag("Requested 2 quotes"))
        // The date is written the phone's way; whichever it is, the tag is known.
        for id in ["en_US", "en_GB", "fr_CA", "de_DE", "ja_JP", "es_US"] {
            let locale = Locale(identifier: id)
            let tag = LeadIntake.tag(for: now, locale: locale, timeZone: .gmt)
            #expect(LeadIntake.isRequestTag(tag, locale: locale), "\(id): \(tag)")
            #expect(!LeadIntake.isRequestTag("Requested quote", locale: locale), "\(id)")
        }
        #expect(client.notes == "Requested service through your request link on Oct 7, 2026.\nService: Lawn Care\nHow often: For the season\n\nBack gate.")
        #expect(!context.hasChanges)
        let stage = Pipeline.stage(of: client, facts: Pipeline.Facts(in: context), now: now)
        #expect(stage == .lead)
    }

    // A lead's pin is looked up as an import's are: once, retried while the
    // map can't be reached, marked if the map doesn't know the address.
    @Test func theNewLeadIsPutOnTheMap() async throws {
        let found = LeadIntake.save(request, operatorID: "op", in: context, now: now)
        var nowhere = request
        nowhere.phone = "603-555-0100"
        nowhere.address = "0 Nowhere"
        let lost = LeadIntake.save(nowhere, operatorID: "op", in: context, now: now)
        let notALead = Client(name: "Pat", phone: "", address: "9 Elm St", operatorID: "op")   // added by hand
        notALead.tags = ["Requested quote"]                                                       // a tag of their own
        context.insert(notALead)
        try context.save()
        var asked: [String] = []
        let pins = ImportPins(lookUp: { address in
            asked.append(address)
            return address == "0 Nowhere" ? .failed(.notFound) : .found(latitude: 43, longitude: -72)
        }, pause: { _ in })
        await pins.startAfterImport(in: context, operatorID: "op")
        #expect(found.latitude == 43 && lost.needsAddressFix && notALead.latitude == 0)
        #expect(Set(asked) == [request.address, "0 Nowhere"])
    }
}
