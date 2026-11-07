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
/// oldest, and ServiceLog.mergeDuplicates merges the copies.
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
    /// A route stop's arrival and departure as GPS saw them (`SiteTimes`):
    /// the phone crossing an area about 100 m around the stop's pin. nil
    /// when it wasn't seen (location off or approximate, already inside when
    /// the stop began, not seen leaving before the next stop was reached or
    /// done, the next stop too close to tell apart, or not a route stop).
    var arrivedAt: Date? = nil
    var leftAt: Date? = nil
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
    /// The invoice this work went on; empty while it's unbilled. Whether it's
    /// billed is `ServiceLog.isUnbilled`: the invoice may have been deleted.
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
}

enum ServiceRecordSource: String {
    case route, visit, manual
    /// A visit completed without a Service Log record (before the log
    /// existed, or on an older PlowR), copied in. Whether it was billed
    /// wasn't tracked, so it's never counted as owed.
    case beforeLog
}

extension ServiceRecord {
    /// Every stored field of a record but its ID, as it was at one moment:
    /// what Undo after Complete Stop puts back on a record completing filled
    /// in (ActiveRouteStore.undoLastCompletion). A field added to the model
    /// must be added here too, or an undo leaves completing's value in it.
    struct Fields: Equatable {
        var operatorID, sourceKey, sourceRaw, clientID, propertyID, clientName, propertyAddress: String
        var startedAt: Date?
        var performedAt: Date
        var arrivedAt, leftAt: Date?
        var minutes: Double
        var servicesData: Data
        var notes, routeID, routeName, runID, stopID, visitID: String
        var isBillable: Bool
        var invoiceID: String
        var createdAt: Date

        init(of record: ServiceRecord) {
            operatorID = record.operatorID
            sourceKey = record.sourceKey
            sourceRaw = record.sourceRaw
            clientID = record.clientID
            propertyID = record.propertyID
            clientName = record.clientName
            propertyAddress = record.propertyAddress
            startedAt = record.startedAt
            performedAt = record.performedAt
            arrivedAt = record.arrivedAt
            leftAt = record.leftAt
            minutes = record.minutes
            servicesData = record.servicesData
            notes = record.notes
            routeID = record.routeID
            routeName = record.routeName
            runID = record.runID
            stopID = record.stopID
            visitID = record.visitID
            isBillable = record.isBillable
            invoiceID = record.invoiceID
            createdAt = record.createdAt
        }

        /// Puts these values back on `record`, writing only the ones that
        /// differ: an unchanged field isn't sent to iCloud again.
        func restore(to record: ServiceRecord) {
            func put<T: Equatable>(_ path: ReferenceWritableKeyPath<ServiceRecord, T>, _ value: T) {
                if record[keyPath: path] != value { record[keyPath: path] = value }
            }
            put(\.operatorID, operatorID)
            put(\.sourceKey, sourceKey)
            put(\.sourceRaw, sourceRaw)
            put(\.clientID, clientID)
            put(\.propertyID, propertyID)
            put(\.clientName, clientName)
            put(\.propertyAddress, propertyAddress)
            put(\.startedAt, startedAt)
            put(\.performedAt, performedAt)
            put(\.arrivedAt, arrivedAt)
            put(\.leftAt, leftAt)
            put(\.minutes, minutes)
            put(\.servicesData, servicesData)
            put(\.notes, notes)
            put(\.routeID, routeID)
            put(\.routeName, routeName)
            put(\.runID, runID)
            put(\.stopID, stopID)
            put(\.visitID, visitID)
            put(\.isBillable, isBillable)
            put(\.invoiceID, invoiceID)
            put(\.createdAt, createdAt)
        }
    }
}
