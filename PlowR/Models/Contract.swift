import Foundation
import SwiftData

/// An agreement with a client for a period, at one or more of their places:
/// the services it covers and how it's priced (Contracts). A season's
/// snow clearing, weekly mowing, a monthly fee.
@Model
final class Contract {
    var id: UUID = UUID()
    var operatorID: String = ""
    /// Copies of its client's ID and name: a signed contract kept for the
    /// records outlives a client deleted with Keep Records, as invoices do.
    var clientID: String = ""
    var clientName: String = ""
    var name: String = ""
    var startDate: Date = Date()
    /// The last day it covers.
    var endDate: Date = Date()
    /// The places it covers (Place.id: the client's ID for their own address).
    var placeIDs: [String] = []
    /// The catalog services it covers.
    var serviceIDs: [String] = []
    /// Contracts.Pricing.
    var pricingRaw: String = "season"
    /// The season's total, the price per visit, or the monthly amount.
    var price: Double = 0
    /// How many payments a season price is split into (1: all up front).
    var installments: Int = 1
    /// Visits it books itself: weekdays (1 = Sunday … 7 = Saturday), every
    /// `scheduleIntervalWeeks` weeks. None: it books nothing.
    var scheduleWeekdays: [Int] = []
    var scheduleIntervalWeeks: Int = 1
    /// Work starts at this depth of snow (inches); 0: no trigger.
    var triggerInches: Double = 0
    var notes: String = ""
    /// Signed: the agreement stands. Nil: still a draft.
    var signedAt: Date?
    var cancelledAt: Date?
    /// The contract this one renewed, if any.
    var renewedFromID: String = ""
    /// The proposal it was made from, if any.
    var sourceProposalID: String = ""
    var createdAt: Date = Date()
    var client: Client?

    init(name: String, startDate: Date, endDate: Date, operatorID: String) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.operatorID = operatorID
    }
}
