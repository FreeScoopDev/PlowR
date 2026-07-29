import Foundation
import SwiftData

@Model
final class PaymentMethod {
    var id: UUID = UUID()
    var operatorID: String = ""
    var label: String = ""
    var value: String = ""
    /// "link" = URL-based (Venmo, PayPal, Square, Cash App)
    /// "check" = payable-to name
    /// "text" = handle/email/phone (Zelle)
    /// "cash" = no value needed
    var methodType: String = "link"
    var isActive: Bool = true
    var sortOrder: Int = 0

    var isURLBased: Bool { methodType == "link" }
    var isCheck: Bool { methodType == "check" }
    var isCash: Bool { methodType == "cash" }

    init(operatorID: String, label: String, value: String, methodType: String, sortOrder: Int = 0) {
        self.operatorID = operatorID
        self.label = label
        self.value = value
        self.methodType = methodType
        self.sortOrder = sortOrder
    }
}
