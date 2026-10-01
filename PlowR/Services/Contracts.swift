import Foundation
import SwiftData
import SwiftUI

/// Contracts: agreements with a client for a period (Contract). The one
/// place for where a contract stands, what it says in a line, and making,
/// signing, cancelling and deleting one.
enum Contracts {
    enum Pricing: String, CaseIterable, Identifiable {
        /// One amount for the whole period, up front or in installments.
        case season
        /// A set price for each visit, instead of the catalog's.
        case perVisit
        /// One amount each month of the period.
        case monthly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .season: "Season Price"
            case .perVisit: "Per Visit"
            case .monthly: "Monthly"
            }
        }

        /// What the price field is.
        var priceLabel: String {
            switch self {
            case .season: "Season Total"
            case .perVisit: "Price per Visit"
            case .monthly: "Per Month"
            }
        }
    }

    enum Status: Equatable {
        case draft
        /// Signed, and its period hasn't started yet.
        case upcoming
        case active
        case ended
        case cancelled

        var title: String {
            switch self {
            case .draft: "Draft"
            case .upcoming: "Signed"
            case .active: "Active"
            case .ended: "Ended"
            case .cancelled: "Cancelled"
            }
        }

        /// Signed and not over: the client has agreed to it.
        var isInForce: Bool { self == .upcoming || self == .active }

        /// Green in force, blue a draft, grey over (the status colours).
        var chipColor: Color {
            switch self {
            case .draft: .blue
            case .upcoming, .active: .green
            case .ended, .cancelled: .gray
            }
        }
    }

    static func pricing(of contract: Contract) -> Pricing {
        Pricing(rawValue: contract.pricingRaw) ?? .season
    }

    /// Where it stands on `now`. Dates are whole days: it's active through
    /// its end date.
    static func status(of contract: Contract, now: Date = .now, calendar: Calendar = .current) -> Status {
        if contract.cancelledAt != nil { return .cancelled }
        guard contract.signedAt != nil else { return .draft }
        let today = calendar.startOfDay(for: now)
        if today > calendar.startOfDay(for: contract.endDate) { return .ended }
        if today < calendar.startOfDay(for: contract.startDate) { return .upcoming }
        return .active
    }

    /// Its price in a line: "$900 season, 3 payments", "$55 per visit",
    /// "$160 a month".
    static func priceSummary(of contract: Contract) -> String {
        let price = contract.price.formatted(.currency(code: "USD"))
        switch pricing(of: contract) {
        case .season:
            return contract.installments > 1 ? "\(price) season, \(contract.installments) payments" : "\(price) season"
        case .perVisit: return "\(price) per visit"
        case .monthly: return "\(price) a month"
        }
    }

    /// A client's contracts, the ones in force first, then the newest.
    static func sorted(_ contracts: [Contract], now: Date = .now) -> [Contract] {
        contracts.sorted {
            let (a, b) = (status(of: $0, now: now).isInForce, status(of: $1, now: now).isInForce)
            return a != b ? a : $0.startDate > $1.startDate
        }
    }

    /// Whether `client` has a contract in force (signed, not over).
    static func hasContractInForce(_ client: Client, now: Date = .now) -> Bool {
        (client.contracts ?? []).contains { status(of: $0, now: now).isInForce }
    }

    // MARK: - Making and changing one

    /// Whether these services include a snow one: only then does a
    /// contract keep a snow trigger.
    static func coversSnow(_ serviceIDs: Set<String>, catalog: [ServiceItem]) -> Bool {
        let snow = ServiceCatalog.standardCategories.first?.key ?? "snow"
        return catalog.contains { serviceIDs.contains($0.id.uuidString) && $0.category == snow }
    }

    /// The name a contract gets when none is typed: its months.
    static func name(from start: Date, to end: Date) -> String {
        let format = Date.FormatStyle.dateTime.month(.abbreviated).year()
        return "\(start.formatted(format)) – \(end.formatted(format))"
    }

    /// What the contract's edit screen has on it. Once signed, its terms
    /// (start, places, services, pricing, price, payments) are what the
    /// client agreed and are locked: only its name, notes, trigger and end
    /// date (not before today) change. A bigger change is a new contract.
    struct Draft: Equatable {
        /// Editing a signed contract: its terms are locked.
        var isSigned = false
        var name = ""
        var startDate: Date
        var endDate: Date
        var placeIDs: Set<String> = []
        var serviceIDs: Set<String> = []
        var pricing: Pricing = .season
        var priceText = ""
        var installments = 1
        var triggerInches: Double = 0
        var notes = ""
        /// Visits it books (ContractSchedule): weekdays, 1 = Sunday … 7 =
        /// Saturday; none books nothing. Not locked by signing: a lawn day
        /// can move mid-season (then Book Visits again).
        var scheduleWeekdays: Set<Int> = []
        var scheduleIntervalWeeks = 1
        /// Where a new one came from: the proposal it was made from, or the
        /// contract it renews.
        var sourceProposalID = ""
        var renewedFromID = ""

        /// A new contract for `client`: six months from today (its last day
        /// the day before the six months are up), at their own address, with
        /// their usual services.
        init(for client: Client, now: Date = .now, calendar: Calendar = .current) {
            startDate = calendar.startOfDay(for: now)
            endDate = calendar.date(byAdding: DateComponents(month: 6, day: -1), to: startDate) ?? startDate
            placeIDs = [client.id.uuidString]
            serviceIDs = Set(client.expectedServiceIDs)
        }

        init(_ contract: Contract) {
            isSigned = contract.signedAt != nil
            // A name made from its dates is made again from the dates saved.
            name = contract.name == Contracts.name(from: contract.startDate, to: contract.endDate) ? "" : contract.name
            startDate = contract.startDate
            endDate = contract.endDate
            // Only places that still exist: a removed property's is dropped,
            // so the contract is set to apply somewhere real.
            placeIDs = Set(contract.placeIDs.filter { id in
                contract.client.map { Place.of($0, propertyID: id) != nil } ?? true
            })
            serviceIDs = Set(contract.serviceIDs)
            pricing = Contracts.pricing(of: contract)
            priceText = contract.price > 0 ? StopRecording.money(contract.price) : ""
            installments = max(1, contract.installments)
            triggerInches = contract.triggerInches
            notes = contract.notes
            scheduleWeekdays = Set(contract.scheduleWeekdays)
            scheduleIntervalWeeks = max(1, contract.scheduleIntervalWeeks)
        }

        var price: Double { InvoiceLines.price(typed: priceText, default: 0) }

        /// Why it can't be saved yet, or nil when it can.
        func problem(now: Date = .now, calendar: Calendar = .current) -> String? {
            if placeIDs.isEmpty { return "Choose where it applies." }
            if serviceIDs.isEmpty { return "Choose the services it covers." }
            if endDate < startDate { return "It has to end after it starts." }
            if isSigned, calendar.startOfDay(for: endDate) < calendar.startOfDay(for: now) {
                return "A signed contract can't end before today. To end it now, cancel it."
            }
            if price <= 0 { return "Enter its price." }
            if pricing == .season, installments > 1,
               let last = calendar.date(byAdding: .month, value: installments - 1, to: calendar.startOfDay(for: startDate)),
               last > calendar.startOfDay(for: endDate) {
                return "Its \(installments) monthly payments run past its end. Fewer payments, or a later end."
            }
            return nil
        }

        /// The earliest end date the screen offers: its start, or for a
        /// signed contract today, whichever is later.
        func earliestEnd(now: Date = .now, calendar: Calendar = .current) -> Date {
            isSigned ? max(startDate, calendar.startOfDay(for: now)) : startDate
        }

        /// The name it's saved with: the one typed, or its dates.
        func resolvedName() -> String {
            let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return typed.isEmpty ? Contracts.name(from: startDate, to: endDate) : typed
        }
    }

    /// `draft` saved to `contract`, or as a new draft contract of `client`.
    /// A signed contract's terms stay as they were agreed.
    @discardableResult
    static func save(_ draft: Draft, to contract: Contract?, of client: Client, in context: ModelContext) -> Contract {
        let target: Contract
        if let contract {
            target = contract
        } else {
            target = Contract(name: "", startDate: draft.startDate, endDate: draft.endDate,
                              operatorID: client.operatorID)
            context.insert(target)
            target.client = client
        }
        target.clientID = client.id.uuidString
        target.clientName = client.name
        target.name = draft.resolvedName()
        // Ending earlier takes off the visits it booked after its new last day.
        if target.signedAt != nil, draft.endDate < target.endDate {
            ContractSchedule.removeVisits(of: target, after: draft.endDate, in: context)
        }
        target.endDate = draft.endDate
        // Visits switched off: the ones it booked after today come off too.
        if !target.scheduleWeekdays.isEmpty, draft.scheduleWeekdays.isEmpty {
            ContractSchedule.removeVisits(of: target, after: .now, in: context)
        }
        target.scheduleWeekdays = draft.scheduleWeekdays.sorted()
        target.scheduleIntervalWeeks = max(1, draft.scheduleIntervalWeeks)
        target.notes = draft.notes
        if target.signedAt == nil {
            target.startDate = draft.startDate
            target.placeIDs = draft.placeIDs.sorted()
            target.serviceIDs = draft.serviceIDs.sorted()
            target.pricingRaw = draft.pricing.rawValue
            target.price = InvoiceLines.roundedToCent(draft.price)
            target.installments = draft.pricing == .season ? max(1, draft.installments) : 1
        }
        if contract == nil {
            target.sourceProposalID = draft.sourceProposalID
            target.renewedFromID = draft.renewedFromID
        }
        let catalog = (try? context.fetch(FetchDescriptor<ServiceItem>())) ?? []
        target.triggerInches = coversSnow(Set(target.serviceIDs), catalog: catalog) ? max(0, draft.triggerInches) : 0
        try? context.save()
        return target
    }

    /// The client signed it: it stands from now.
    static func sign(_ contract: Contract, in context: ModelContext, now: Date = .now) {
        contract.signedAt = now
        try? context.save()
    }

    /// Ended early. What's already been done or billed stays; the visits it
    /// booked after today come off the Schedule.
    static func cancel(_ contract: Contract, in context: ModelContext, now: Date = .now) {
        contract.cancelledAt = now
        ContractSchedule.removeVisits(of: contract, after: now, in: context)
        try? context.save()
    }

    /// Deletes a contract never signed. A signed one is cancelled instead,
    /// so the record of what was agreed stays.
    static func deleteDraft(_ contract: Contract, in context: ModelContext) {
        guard contract.signedAt == nil else { return }
        contract.client = nil
        context.delete(contract)
        try? context.save()
    }

    // MARK: - From a proposal, and renewing

    /// A new contract from a proposal: the services on it that are in the
    /// catalog (matched by name; none matched, none chosen, so they're
    /// picked by hand), its total before tax as the season price (a
    /// contract's payments carry no tax of their own), at their own address.
    /// It stays a draft to check and sign.
    static func draft(from proposal: Proposal, client: Client, catalog: [ServiceItem],
                      now: Date = .now) -> Draft {
        var draft = Draft(for: client, now: now)
        let names = Set(proposal.sortedLineItems.map { $0.serviceName.lowercased() })
        let matched = catalog.filter { $0.operatorID == client.operatorID && names.contains($0.name.lowercased()) }
        draft.serviceIDs = Set(matched.map(\.id.uuidString))
        draft.pricing = .season
        draft.priceText = proposal.discountedTotal > 0 ? StopRecording.money(proposal.discountedTotal) : ""
        draft.notes = proposal.notes
        draft.sourceProposalID = proposal.id.uuidString
        return draft
    }

    /// The same contract for its next season: the same months a whole
    /// number of years on (the first year it starts after this one ends,
    /// and doesn't end before today), so a winter contract renews into
    /// next winter and a year's into the next year, leap years or not. At
    /// its price raised by `increasePercent` (to the cent), with the same
    /// places, services, payments, visits and notes. A draft to check and
    /// sign. A name made from its dates is made again from the new ones.
    static func renewal(of contract: Contract, increasePercent: Double = 0, now: Date = .now,
                        calendar: Calendar = .current) -> Draft {
        var draft = Draft(contract)
        draft.isSigned = false
        let oldStart = calendar.startOfDay(for: contract.startDate)
        let oldEnd = calendar.startOfDay(for: contract.endDate)
        let today = calendar.startOfDay(for: now)
        var years = 1
        func shifted(_ date: Date) -> Date { calendar.date(byAdding: .year, value: years, to: date) ?? date }
        while years < 100, shifted(oldStart) <= oldEnd || shifted(oldEnd) < today { years += 1 }
        draft.startDate = shifted(oldStart)
        draft.endDate = shifted(oldEnd)
        draft.serviceIDs = Set(contract.serviceIDs)
        draft.pricing = pricing(of: contract)
        let raised = InvoiceLines.roundedToCent(contract.price * (1 + max(0, increasePercent) / 100))
        draft.priceText = StopRecording.money(raised)
        draft.installments = max(1, contract.installments)
        draft.renewedFromID = contract.id.uuidString
        return draft
    }

    /// Whether Renew is offered: it was signed (it's what the client
    /// agreed), it wasn't cancelled (terms retired on purpose aren't brought
    /// back), and it hasn't been renewed already.
    static func canRenew(_ contract: Contract, among contracts: [Contract]) -> Bool {
        contract.signedAt != nil && contract.cancelledAt == nil && contract.client != nil
            && !contracts.contains { $0.renewedFromID == contract.id.uuidString }
    }

    /// The contract made from `proposal`, if one was: the proposal is then
    /// spoken for, and isn't made into another or converted to an invoice.
    static func madeFrom(_ proposal: Proposal, among contracts: [Contract]) -> Contract? {
        contracts.first { $0.sourceProposalID == proposal.id.uuidString }
    }

    // MARK: - Work under a contract

    /// Whether `contract` covers `day` at the place with `placeID` (Place.id).
    /// Signed; within its dates; and, cancelled, up to the day it was.
    static func covers(_ contract: Contract, placeID: String, on day: Date, calendar: Calendar = .current) -> Bool {
        guard contract.signedAt != nil, contract.placeIDs.contains(placeID) else { return false }
        let day = calendar.startOfDay(for: day)
        guard day >= calendar.startOfDay(for: contract.startDate),
              day <= calendar.startOfDay(for: contract.endDate) else { return false }
        if let cancelled = contract.cancelledAt, day > calendar.startOfDay(for: cancelled) { return false }
        return true
    }

    /// The contract covering a client's place on a day: the newest signed
    /// one if two overlap. The one rule, for the Service Log and for Record
    /// Services alike.
    static func contract(coveringPlace placeID: String, of clientID: String, on day: Date,
                         among contracts: [Contract], calendar: Calendar = .current) -> Contract? {
        contracts
            .filter { $0.clientID == clientID && covers($0, placeID: placeID, on: day, calendar: calendar) }
            .max { ($0.signedAt ?? .distantPast) < ($1.signedAt ?? .distantPast) }
    }

    /// The contract covering a job in the Service Log: at its place, on the
    /// day it started (a route that runs past midnight is the day's work).
    static func contract(covering record: ServiceRecord, among contracts: [Contract],
                         calendar: Calendar = .current) -> Contract? {
        contract(coveringPlace: record.propertyID.isEmpty ? record.clientID : record.propertyID,
                 of: record.clientID, on: record.startedAt ?? record.performedAt, among: contracts,
                 calendar: calendar)
    }

    /// What a job charges under `contract`. Its services stay as they were
    /// recorded (the record of what was done); only what's billed changes:
    /// - Season price or monthly: the services it covers charge nothing;
    ///   the contract's own payments are what's owed for them.
    /// - Per visit: they're one line at the contract's price.
    /// Services it doesn't cover are extras, charged as recorded. With no
    /// contract, everything is charged as recorded.
    static func charge(of lines: [ServiceRecord.Line], under contract: Contract?) -> [ServiceRecord.Line] {
        guard let contract else { return lines }
        let covered = Set(contract.serviceIDs)
        let extras = lines.filter { $0.serviceID.isEmpty || !covered.contains($0.serviceID) }
        guard extras.count < lines.count else { return lines }
        switch pricing(of: contract) {
        case .season, .monthly:
            return extras
        case .perVisit:
            let visit = ServiceRecord.Line(serviceID: "", name: "\(contract.name): visit", unitType: "flat",
                                           price: contract.price)
            return [visit] + extras
        }
    }

    /// Every contract there is, looked up once, for billing many jobs.
    static func all(in context: ModelContext) -> [Contract] {
        (try? context.fetch(FetchDescriptor<Contract>())) ?? []
    }
}
