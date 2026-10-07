import Foundation
import SwiftData

@Model
final class BusinessProfile {
    var id: UUID = UUID()
    var operatorID: String = ""
    var companyName: String = ""
    var phone: String = ""
    var email: String = ""
    var tagline: String = ""
    var licenseNumber: String = ""
    var logoData: Data?
    var defaultDisclaimer: String = ""
    var accentColorHex: String = PlowRColor.navyHex
    var colorPDFs: Bool = true
    var compactHeader: Bool = false   // smaller document title in PDF output
    var customVisitReasons: [String] = []  // operator-defined reasons shown in Add Visit
    /// The Request Service link (RequestLinkSettings): the services its
    /// form offers, once chosen (until then, the catalog's), and a welcome
    /// line at the top.
    var requestServices: [String] = []
    var requestServicesChosen: Bool = false
    var requestWelcome: String = ""

    init(operatorID: String) {
        self.operatorID = operatorID
    }
}
