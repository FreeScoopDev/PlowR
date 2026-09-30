import Foundation
import SwiftData

/// One piece of work done at a property: the Service Log. Written when a
/// route stop or a scheduled visit is completed (ServiceLog), and kept.
///
/// Before this, finishing a stop only added to the client's running totals,
/// and the services ticked on a stop were wiped the next time its route
/// started, so what was done at a client on a given day was lost.
///
/// The client's name as it was when the work was done, and the address the
/// work was at (the stop's or the visit's) are copies: history keeps them,
/// like past visits do. The client and property are referred to by ID, as
/// invoices do, so a record outlives its client when the user keeps records
/// on delete.
///
/// CloudKit can't enforce a unique source key: two devices that record the
/// same work before syncing each make a record. ServiceLog always updates the
/// oldest; merging the copies is a later step of the plan.
@Model
final class ServiceRecord {
    var id: UUID = UUID()
    var operatorID: String = ""
    /// What the record is of, so saving the same work again updates it
    /// instead of adding another: `stop:<run>:<stop>` or `visit:<visit>`.
    var sourceKey: String = ""
    var sourceRaw: String = ServiceRecordSource.manual.rawValue

    var clientID: String = ""
    /// The property the work was at. Until properties exist this is the
    /// client's ID: a client's main property will be given the client's ID.
    var propertyID: String = ""
    var clientName: String = ""
    var propertyAddress: String = ""

    var startedAt: Date? = nil
    var performedAt: Date = Date()
    var minutes: Double = 0.0
    /// JSON-encoded [ServiceRecord.Line]: the services and their prices then.
    var servicesData: Data = Data()
    var notes: String = ""

    var routeID: String = ""
    var routeName: String = ""
    /// The run of the route (ActiveRouteStore.runID) that did the work, so a
    /// second pass on the same day is a new record, not an overwrite.
    var runID: String = ""
    var stopID: String = ""
    var visitID: String = ""

    /// False for a comped client's work: it never goes on a bill.
    var isBillable: Bool = true
    /// The invoice this work went on; empty while it's unbilled.
    var invoiceID: String = ""
    var createdAt: Date = Date()

    init(operatorID: String, sourceKey: String, source: ServiceRecordSource) {
        self.operatorID = operatorID
        self.sourceKey = sourceKey
        self.sourceRaw = source.rawValue
    }

    /// A service done, with its price at the time: prices change, history doesn't.
    nonisolated struct Line: Codable, Equatable {
        var serviceID: String
        var name: String
        var unitType: String
        var price: Double
    }

    var source: ServiceRecordSource {
        get { ServiceRecordSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var lines: [Line] {
        get { (try? JSONDecoder().decode([Line].self, from: servicesData)) ?? [] }
        set { servicesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var isUnbilled: Bool { isBillable && invoiceID.isEmpty }
}

enum ServiceRecordSource: String {
    case route, visit, manual
}
