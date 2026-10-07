import Foundation
import SwiftData
import Testing
import CoreImage
import UIKit
@testable import PlowR

/// The business's own Request Service link, from its profile and catalog.
@MainActor
struct RequestLinkSettingsTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try ModelContainer(for: Schema(PlowRApp.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                          cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
        context = container.mainContext
    }

    private func service(_ name: String, order: Int, active: Bool = true, operatorID: String = "op") -> ServiceItem {
        let item = ServiceItem(name: name, category: "custom", unitType: "flat", pricePerUnit: 50, operatorID: operatorID)
        item.sortOrder = order
        item.isActive = active
        item.operatorID = operatorID
        context.insert(item)
        return item
    }

    private func profile(name: String = "Pat's Lawn & Snow", phone: String = "(603) 555-0100") -> BusinessProfile {
        let profile = BusinessProfile(operatorID: "op")
        profile.companyName = name
        profile.phone = phone
        context.insert(profile)
        return profile
    }

    @Test func theFormOffersTheCatalogInOrderOnce() {
        let catalog = [service("Mowing", order: 2), service("Plowing", order: 1), service("mowing", order: 3),
                       service("Old Thing", order: 0, active: false), service("Theirs", order: 0, operatorID: "x")]
        #expect(RequestLinkSettings.offerable(catalog, operatorID: "op") == ["Plowing", "Mowing"])
        #expect(RequestLinkSettings.offerable([], operatorID: "op") == RequestLinkSettings.fallbackServices)
    }

    @Test func aChoiceIsKeptAndTheDefaultIsCapped() {
        let catalog = (0..<20).map { service("S\($0)", order: $0) }
        let pat = profile()
        #expect(RequestLinkSettings.services(for: pat, catalog: catalog, operatorID: "op").count == RequestLink.Limit.services)
        pat.requestServices = ["S3"]
        pat.requestServicesChosen = true
        #expect(RequestLinkSettings.services(for: pat, catalog: catalog, operatorID: "op") == ["S3"])
        pat.requestServices = []
        #expect(RequestLinkSettings.services(for: pat, catalog: catalog, operatorID: "op").isEmpty)  // none, by choice
    }

    // A business with no catalog is offered the general list, none ticked:
    // a form never offers a service the business doesn't do.
    @Test func withNoCatalogNothingIsOfferedUntilChosen() throws {
        let pat = profile()
        #expect(RequestLinkSettings.services(for: pat, catalog: [], operatorID: "op").isEmpty)
        let link = try #require(RequestLinkSettings.link(for: pat, catalog: [], operatorID: "op"))
        #expect(RequestLink.business(from: link)?.services == [])
    }

    // A service renamed, removed or turned off in the catalog leaves the
    // form too, so the form never offers what the screen doesn't show.
    @Test func aServiceLeavingTheCatalogLeavesTheForm() throws {
        let mowing = service("Mowing", order: 0), plowing = service("Plowing", order: 1)
        let pat = profile()
        pat.requestServices = ["Mowing", "Plowing"]
        pat.requestServicesChosen = true
        plowing.isActive = false
        #expect(RequestLinkSettings.services(for: pat, catalog: [mowing, plowing], operatorID: "op") == ["Mowing"])
        let link = try #require(RequestLinkSettings.link(for: pat, catalog: [mowing, plowing], operatorID: "op"))
        #expect(RequestLink.business(from: link)?.services == ["Mowing"])
        // Chosen from the general list, then a catalog made: none of the list stays.
        let kim = profile(name: "Kim's", phone: "6035550101")
        kim.requestServices = ["Lawn Care"]
        kim.requestServicesChosen = true
        #expect(RequestLinkSettings.services(for: kim, catalog: [mowing], operatorID: "op").isEmpty)
    }

    @Test func togglingKeepsCatalogOrderAndTheCap() {
        let offerable = (0..<14).map { "S\($0)" }
        #expect(RequestLinkSettings.toggled("S5", chosen: ["S9", "S1"], offerable: offerable) == ["S1", "S5", "S9"])
        #expect(RequestLinkSettings.toggled("s1", chosen: ["S9", "S1"], offerable: offerable) == ["S9"])
        #expect(RequestLinkSettings.toggled("S13", chosen: Array(offerable.prefix(12)), offerable: offerable).count == 12)
    }

    @Test func aLinkNeedsANameAndAPhone() {
        #expect(RequestLinkSettings.missing(nil) == [.name, .phone])
        #expect(RequestLinkSettings.missing(profile(name: "", phone: "555")) == [.name, .phone])
        #expect(RequestLinkSettings.missing(profile(name: "Pat's", phone: "")) == [.phone])
        #expect(RequestLinkSettings.link(for: profile(name: "Pat's", phone: ""), catalog: [], operatorID: "op") == nil)
        #expect(RequestLinkSettings.missing(profile()) .isEmpty)
    }

    @Test func theLinkCarriesWhatWasChosen() throws {
        let catalog = [service("Mowing", order: 0), service("Plowing", order: 1)]
        let pat = profile()
        pat.email = "pat@example.com"
        pat.requestServices = ["Plowing"]
        pat.requestServicesChosen = true
        pat.requestWelcome = "Tell us about your property."
        let link = try #require(RequestLinkSettings.link(for: pat, catalog: catalog, operatorID: "op"))
        #expect(RequestLink.business(from: link) == RequestLink.Business(
            name: "Pat's Lawn & Snow", phone: "(603) 555-0100", email: "pat@example.com",
            services: ["Plowing"], welcome: "Tell us about your property."))
        #expect(RequestLinkSettings.invitation(businessName: pat.companyName, link: link).hasSuffix(link.absoluteString))
    }

    // A real link fits a QR code; one past what a QR code holds gives none.
    // The QR code reads back as the link, is the size asked for, and has a
    // white quiet zone round it so it scans from a print or a truck.
    @Test func theLinkMakesAQRCodeThatScans() throws {
        let link = try #require(RequestLinkSettings.link(for: profile(), catalog: [], operatorID: "op"))
        let image = try #require(QRCode.image(for: link.absoluteString, size: 512, border: true))
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.width == 512 && cgImage.height == 512)
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil))
        let found = detector.features(in: CIImage(cgImage: cgImage)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(found == [link.absoluteString])
        // Every pixel within 4 modules of each edge is white (the quiet zone),
        // and the code starts right after it: the top-left finder pattern's
        // dark ring is at module 4, white just before it.
        let data = try #require(cgImage.dataProvider?.data as Data?)
        let bytesPerPixel = cgImage.bitsPerPixel / 8, rowBytes = cgImage.bytesPerRow
        let modules = QRCodeWidth.modules(for: link.absoluteString) + 8
        let perModule = 512.0 / Double(modules)
        func white(_ x: Int, _ y: Int) -> Bool { data[y * rowBytes + x * bytesPerPixel] > 200 }
        let ring = Int((4 * perModule).rounded(.down)) - 1
        for edge in 0...ring {
            for along in stride(from: 0, to: 512, by: 3) {
                #expect(white(edge, along) && white(511 - edge, along) && white(along, edge) && white(along, 511 - edge),
                        "quiet zone at \(edge), \(along)")
            }
        }
        func pixel(_ module: Double) -> Int { Int(module * perModule) }
        #expect(!white(pixel(4.5), pixel(7.5)) && white(pixel(3.5), pixel(7.5)))
        // The bottom-left finder too (a QR code has them top-left, top-right and bottom-left).
        #expect(!white(pixel(4.5), pixel(Double(modules) - 7.5)) && white(pixel(3.5), pixel(Double(modules) - 7.5)))
        #expect(QRCode.image(for: String(repeating: "x", count: 5_000), size: 512) == nil)
    }
}

/// How many modules wide the bare QR code for some text is (without its margin).
private enum QRCodeWidth {
    static func modules(for text: String) -> Int {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(text.utf8), forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        return Int(filter?.outputImage?.extent.width ?? 0) - 2
    }
}
