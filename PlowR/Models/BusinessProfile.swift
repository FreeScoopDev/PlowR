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
    var accentColorHex: String = "1E3A8A"
    var colorPDFs: Bool = true

    init(operatorID: String) {
        self.operatorID = operatorID
    }
}
