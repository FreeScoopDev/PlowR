import Foundation
import SwiftData

/// The route recap's Record Expected Services: the stops completed this run
/// with nothing recorded, and the expected services to record for each.
///
/// Since the route screen's "Done:" button (OneTapServices) a stop completed
/// with it records its expected services, but one completed from Siri,
/// Control Center or with Complete Without Services still ends with a record
/// saying "No services", and nothing for Bill Unbilled Work to bill. The
/// recap offers to record them, naming each stop and its services first:
/// nothing is recorded without the confirmation that names it.
///
/// The decision is here, as plain values, so it can be tested without a
/// screen; reading the database and recording are in `RecapServiceRecorder`.
nonisolated enum RecapServices {

    /// What the plan needs to know about one stop of the run, as it is now.
    struct StopFacts: Equatable {
        var stopID: UUID
        var clientName: String
        /// The run has a record of the stop's completion: one with its times.
        /// A stop passed (Below Trigger), skipped or not reached has none.
        var completedThisRun: Bool
        /// Its client is on file: not a custom stop, client not deleted.
        var hasClient: Bool
        /// Its expected services (`StopServices.expected`).
        var expected: [String]
        /// Its place's measured zones (`Place.zones`): a per-square-foot
        /// service is offered only where they give it a price
        /// (`OneTapServices.priced`).
        var zones: [InvoiceLines.Zone]
        /// `ServiceLog.hasNothingRecorded`, the question the one tap asks: no
        /// services on the stop, no lines on its record, no invoice.
        var nothingRecorded: Bool
        /// Its record's `invoiceID` is empty. A record billed on an invoice
        /// made for its visit beforehand would add to invoiced work.
        var notOnInvoice: Bool
    }

    /// A stop that qualifies, and the services to record for it.
    struct Planned: Equatable, Identifiable {
        var stopID: UUID
        var clientName: String
        /// In the catalog's order (`ServiceLog.activeServices`).
        var serviceIDs: [String]
        var names: [String]
        var id: UUID { stopID }
    }

    /// The services to record for `stop`, or nil when it doesn't qualify:
    /// completed this run, with a client, nothing recorded, not on an
    /// invoice, and expected services in the business's active catalog with
    /// a price at its place: what the one tap would record
    /// (`OneTapServices.toRecord`).
    static func plan(_ stop: StopFacts, active: [StopRecording.Service]) -> Planned? {
        guard stop.completedThisRun, stop.hasClient, stop.nothingRecorded, stop.notOnInvoice else { return nil }
        let services = OneTapServices.toRecord(expected: stop.expected, active: active, zones: stop.zones)
        guard !services.isEmpty else { return nil }
        return Planned(stopID: stop.stopID, clientName: stop.clientName,
                       serviceIDs: services.map(\.id), names: services.map(\.name))
    }

    /// The stops that qualify, in the order given.
    static func plan(_ stops: [StopFacts], active: [StopRecording.Service]) -> [Planned] {
        stops.compactMap { plan($0, active: active) }
    }

    /// "N Stops", "1 Stop".
    static func stops(_ count: Int) -> String { "\(count) Stop\(count == 1 ? "" : "s")" }

    /// The recap's button.
    static func buttonTitle(count: Int) -> String { "Record Expected Services for \(stops(count))" }

    /// The confirmation's button.
    static func confirmTitle(count: Int) -> String { "Record for \(stops(count))" }

    /// One stop's line in the confirmation: its services as an English list.
    static func servicesText(_ planned: Planned) -> String { OneTapServices.englishList(planned.names) }

    /// The confirmation's note: how they're priced and what's never changed.
    static let confirmNote = "Each is recorded at your catalog prices for that client's property, as unbilled work."
        + " Nothing already recorded or invoiced is changed."

    /// After Confirm, the stops that no longer qualified, by client; nil when
    /// every one was recorded.
    static func notRecordedMessage(_ clientNames: [String]) -> String? {
        guard !clientNames.isEmpty else { return nil }
        let one = clientNames.count == 1
        return "Not recorded for \(OneTapServices.englishList(clientNames)):"
            + " \(one ? "its record" : "their records") changed."
    }

    /// After Confirm, when the save failed and nothing was recorded.
    static let saveFailedMessage = "Couldn't save, so nothing was recorded. Try again."

    /// What to tell the user after Confirm, if anything.
    static func afterConfirm(saveFailed: Bool, notRecorded: [String]) -> String? {
        saveFailed ? saveFailedMessage : notRecordedMessage(notRecorded)
    }

    /// The confirmation's Confirm, once: a second tap before the sheet has
    /// closed would find every stop already recorded and report them all
    /// as "Not recorded".
    struct ConfirmOnce {
        private(set) var done = false

        /// Runs `action` the first time only.
        mutating func run(_ action: () -> Void) {
            guard !done else { return }
            done = true
            action()
        }
    }
}

/// The recap's Record Expected Services plan and what it was worked out
/// from, so a redraw with nothing changed doesn't read the database again
/// (as `MainButtonMemo` does for the route screen's button). Not observed:
/// it only saves work, and changes nothing the screen shows.
@MainActor
final class RecapPlanMemo {
    /// Everything the plan depends on. Invoices and the clients' expected
    /// services and areas live in the database: `dataVersion` changes with
    /// every save and synced change.
    struct Key: Hashable {
        var runID: UUID?
        /// Each of the run's records: ID, invoice, lines and start.
        var records: [String]
        /// Each stop: ID, place and the services recorded on it.
        var stops: [String]
        /// Each active service's ID, name and unit type.
        var catalog: [String]
        var dataVersion: Int
    }

    private var last: (key: Key, plan: [RecapServices.Planned])?
    /// How many times the plan was worked out (for tests).
    private(set) var computed = 0

    func plan(for key: Key, compute: () -> [RecapServices.Planned]) -> [RecapServices.Planned] {
        if let last, last.key == key { return last.plan }
        let plan = compute()
        computed += 1
        last = (key, plan)
        return plan
    }
}

/// Reads a run's stops for `RecapServices` and records what its confirmation
/// named. The recap screen calls only this, so it holds no rule.
@MainActor
enum RecapServiceRecorder {

    /// What happened on Confirm.
    struct Outcome: Equatable {
        /// Recorded, with the services that made it onto each record.
        var recorded: [RecapServices.Planned] = []
        /// Client names of the stops that no longer qualified: left as they were.
        var notRecorded: [String] = []
        /// The save failed: nothing was recorded (rolled back).
        var saveFailed = false
    }

    /// `stop`'s facts on run `run`, read now. The record is found by run and
    /// stop (`ServiceLog.runRecord`): another run's record is never this one.
    static func facts(for stop: RouteStop, client: Client?, run: UUID,
                      in context: ModelContext) -> RecapServices.StopFacts {
        let record = ServiceLog.runRecord(run: run, stop: stop.id, in: context)
        var nothingRecorded = false
        if let client, let record {
            // The run's record is found first, so its start is only a fallback.
            nothingRecorded = ServiceLog.hasNothingRecorded(for: stop, of: client, run: run,
                                                            startedAt: record.startedAt ?? record.performedAt,
                                                            in: context)
        }
        return RecapServices.StopFacts(
            stopID: stop.id, clientName: client?.name ?? stop.clientName,
            completedThisRun: record?.startedAt != nil,
            hasClient: client != nil,
            expected: StopServices.expected(for: stop, client: client),
            zones: client.map { Place.zones(of: $0, propertyID: stop.propertyID) } ?? [],
            nothingRecorded: nothingRecorded,
            notOnInvoice: record?.invoiceID.isEmpty ?? false)
    }

    /// The stops of run `run` that qualify, with what to record for each.
    static func plan(stops: [RouteStop], catalog: [ServiceItem], operatorID: String, run: UUID?,
                     in context: ModelContext) -> [RecapServices.Planned] {
        guard let run else { return [] }
        let active = ServiceLog.activeServices(catalog, operatorID: operatorID)
        // Nothing expected in the catalog: no stop can qualify, nothing to read.
        guard !active.isEmpty else { return [] }
        let clients = clientsByID(in: context)
        return RecapServices.plan(stops.map { facts(for: $0, client: client(of: $0, in: clients), run: run, in: context) },
                                  active: active)
    }

    /// `plan`, worked out again only when something it depends on has
    /// changed since `memo` last did (`RecapPlanMemo.Key`): the recap
    /// redraws as GPS records departures and as its sheets come and go.
    /// `records`: the run's records; `dataVersion` counts the database's
    /// saves and synced changes.
    static func plan(stops: [RouteStop], catalog: [ServiceItem], operatorID: String, run: UUID?,
                     records: [ServiceRecord], in context: ModelContext, memo: RecapPlanMemo,
                     dataVersion: Int) -> [RecapServices.Planned] {
        let key = RecapPlanMemo.Key(
            runID: run,
            records: records.map {
                "\($0.id)|\($0.invoiceID)|\($0.servicesData.hashValue)|\($0.startedAt?.timeIntervalSince1970 ?? -1)"
            }.sorted(),
            stops: stops.map { "\($0.id)|\($0.propertyID)|\($0.completedServiceIDs.joined(separator: ","))" },
            catalog: ServiceLog.activeServices(catalog, operatorID: operatorID).map { "\($0.id)|\($0.name)|\($0.unitType)" },
            dataVersion: dataVersion)
        return memo.plan(for: key) {
            plan(stops: stops, catalog: catalog, operatorID: operatorID, run: run, in: context)
        }
    }

    /// Records `confirmed`, as the confirmation named it, for each stop that
    /// still qualifies with the same services; any other is left exactly as
    /// it is and reported. Lines are written as completing a stop writes
    /// them (`ServiceLog.fillLines`), so nothing else on the record changes.
    /// Saved at once.
    static func record(_ confirmed: [RecapServices.Planned], stops: [RouteStop], catalog: [ServiceItem],
                       operatorID: String, run: UUID?, in context: ModelContext,
                       save: (ModelContext) throws -> Void = { try $0.save() }) -> Outcome {
        var outcome = Outcome()
        var written: [(stop: RouteStop, record: ServiceRecord, servicesBefore: [String], linesBefore: Data)] = []
        let active = ServiceLog.activeServices(catalog, operatorID: operatorID)
        let clients = clientsByID(in: context)
        for planned in confirmed {
            guard let run, let stop = stops.first(where: { $0.id == planned.stopID }),
                  let client = client(of: stop, in: clients),
                  // Asked again now: Record Services, iCloud or an invoice may
                  // have changed it since the confirmation was drawn.
                  let now = RecapServices.plan(facts(for: stop, client: client, run: run, in: context), active: active),
                  now.serviceIDs == planned.serviceIDs,
                  let record = ServiceLog.runRecord(run: run, stop: stop.id, in: context) else {
                outcome.notRecorded.append(planned.clientName)
                continue
            }
            written.append((stop, record, stop.completedServiceIDs, record.servicesData))
            stop.completedServiceIDs = planned.serviceIDs
            ServiceLog.fillLines(of: record, from: stop, client: client, in: context)
            // Only what made it onto the record counts as recorded on the stop.
            let added = record.lines.map(\.serviceID).filter { planned.serviceIDs.contains($0) }
            stop.completedServiceIDs = added
            var recorded = planned
            recorded.serviceIDs = added
            recorded.names = record.lines.filter { added.contains($0.serviceID) }.map(\.name)
            outcome.recorded.append(recorded)
        }
        guard !outcome.recorded.isEmpty else { return outcome }
        do {
            try save(context)
        } catch {
            // Only this action's own writes are taken back, to the exact
            // bytes they were (a record with no lines holds empty data, not
            // "[]": Undo compares the bytes). Not `rollback()`, which would
            // also drop whatever else is waiting to be saved, such as a GPS
            // departure whose save failed and that no second exit brings back.
            for (stop, record, servicesBefore, linesBefore) in written {
                stop.completedServiceIDs = servicesBefore
                record.servicesData = linesBefore
            }
            outcome.notRecorded += outcome.recorded.map(\.clientName)
            outcome.recorded = []
            outcome.saveFailed = true
        }
        return outcome
    }

    private static func clientsByID(in context: ModelContext) -> [UUID: Client] {
        // Fetched and matched by UUID: a #Predicate on `id` clashes with SwiftData's own id.
        let all = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        return Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func client(of stop: RouteStop, in clients: [UUID: Client]) -> Client? {
        stop.isCustomStop ? nil : clients[stop.clientID]
    }
}
