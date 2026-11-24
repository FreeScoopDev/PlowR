//
//  WorkLogTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The Work Log's rules: each period's dates, grouping by day, the billing
/// and service filters, the recorded value and the totals.
@MainActor
struct WorkLogTests {
    /// An in-memory database with CloudKit off and autosave off.
    typealias Harness = ActiveRouteStoreTests.Harness
    private let day: TimeInterval = 86_400

    private func calendar(firstWeekday: Int = 1) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, hour: Int = 0,
                      minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private func job(_ h: Harness, at date: Date, _ lines: [(id: String, name: String, price: Double)],
                     minutes: Double = 0, source: ServiceRecordSource = .manual, billable: Bool = true,
                     operatorID: String = "op") -> ServiceRecord {
        let record = ServiceRecord(operatorID: operatorID, sourceKey: "manual:\(UUID().uuidString)", source: source)
        record.clientID = h.client.id.uuidString
        record.propertyID = h.client.id.uuidString
        record.clientName = h.client.name
        record.performedAt = date
        record.minutes = minutes
        record.isBillable = billable
        record.lines = lines.map { ServiceRecord.Line(serviceID: $0.id, name: $0.name, unitType: "flat", price: $0.price) }
        h.context.insert(record)
        return record
    }

    // MARK: - Periods

    @Test func todayAndYesterdayRunMidnightToMidnight() throws {
        let cal = try calendar()
        let midnight = try date(cal, 2026, 11, 24)
        let today = WorkLog.Period.today.interval(now: midnight, calendar: cal)
        #expect(today.start == midnight)
        #expect(today.end == (try date(cal, 2026, 11, 25)))
        let lateToday = WorkLog.Period.today.interval(now: try date(cal, 2026, 11, 24, hour: 23, minute: 59), calendar: cal)
        #expect(lateToday == today)
        let yesterday = WorkLog.Period.yesterday.interval(now: midnight, calendar: cal)
        #expect(yesterday.start == (try date(cal, 2026, 11, 23)))
        #expect(yesterday.end == midnight)                 // the end is excluded: midnight is today's
    }

    @Test func weeksFollowTheFirstWeekday() throws {
        let sundayFirst = try calendar(firstWeekday: 1)
        let mondayFirst = try calendar(firstWeekday: 2)
        let sundayNoon = try date(sundayFirst, 2026, 11, 22, hour: 12)   // a Sunday
        let week = WorkLog.Period.thisWeek.interval(now: sundayNoon, calendar: sundayFirst)
        #expect(week.start == (try date(sundayFirst, 2026, 11, 22)))
        #expect(week.end == (try date(sundayFirst, 2026, 11, 29)))
        let mondayWeek = WorkLog.Period.thisWeek.interval(now: sundayNoon, calendar: mondayFirst)
        #expect(mondayWeek.start == (try date(mondayFirst, 2026, 11, 16)))
        #expect(mondayWeek.end == (try date(mondayFirst, 2026, 11, 23)))
        let lastMondayWeek = WorkLog.Period.lastWeek.interval(now: sundayNoon, calendar: mondayFirst)
        #expect(lastMondayWeek.start == (try date(mondayFirst, 2026, 11, 9)))
        #expect(lastMondayWeek.end == mondayWeek.start)
    }

    @Test func lastWeekCrossesAMonthAndAYearEnd() throws {
        let mondayFirst = try calendar(firstWeekday: 2)
        let wednesday = try date(mondayFirst, 2026, 12, 2, hour: 9)
        let lastWeek = WorkLog.Period.lastWeek.interval(now: wednesday, calendar: mondayFirst)
        #expect(lastWeek.start == (try date(mondayFirst, 2026, 11, 23)))
        #expect(lastWeek.end == (try date(mondayFirst, 2026, 11, 30)))

        let sundayFirst = try calendar(firstWeekday: 1)
        let newYear = try date(sundayFirst, 2027, 1, 2, hour: 9)          // a Saturday
        let thisWeek = WorkLog.Period.thisWeek.interval(now: newYear, calendar: sundayFirst)
        #expect(thisWeek.start == (try date(sundayFirst, 2026, 12, 27)))
        let lastYearsWeek = WorkLog.Period.lastWeek.interval(now: newYear, calendar: sundayFirst)
        #expect(lastYearsWeek.start == (try date(sundayFirst, 2026, 12, 20)))
        #expect(lastYearsWeek.end == thisWeek.start)
    }

    @Test func thisMonthIsBillUnbilledWorksMonth() throws {
        let cal = try calendar()
        let now = try date(cal, 2026, 11, 1)                              // midnight on the 1st
        let month = WorkLog.Period.thisMonth.interval(now: now, calendar: cal)
        let billing = try #require(WorkBilling.Period.thisMonth.range(now: now, calendar: cal))
        #expect(month.start == billing.lowerBound)
        #expect(month.end == billing.upperBound)
        #expect(month.start == now)
        #expect(month.end == (try date(cal, 2026, 12, 1)))
    }

    @Test func customRunsFromItsFirstDayThroughItsLast() throws {
        let cal = try calendar()
        let afternoon = try date(cal, 2026, 11, 10, hour: 15)
        let sameDay = WorkLog.Period.custom.interval(now: .now, calendar: cal, custom: (afternoon, afternoon))
        #expect(sameDay.start == (try date(cal, 2026, 11, 10)))
        #expect(sameDay.end == (try date(cal, 2026, 11, 11)))
        let span = WorkLog.Period.custom.interval(now: .now, calendar: cal,
                                                  custom: (afternoon, try date(cal, 2026, 11, 12, hour: 1)))
        #expect(span.start == (try date(cal, 2026, 11, 10)))
        #expect(span.end == (try date(cal, 2026, 11, 13)))
        // A last day before the first is the first day alone.
        let backwards = WorkLog.Period.custom.interval(now: .now, calendar: cal,
                                                       custom: (afternoon, try date(cal, 2026, 11, 3)))
        #expect(backwards == sameDay)
    }

    // MARK: - Days

    @Test func daysAreNewestFirstWithNewestJobsFirst() throws {
        let h = try Harness(stopCount: 1)
        let cal = try calendar()
        let mondayMorning = job(h, at: try date(cal, 2026, 11, 23, hour: 8), [])
        let mondayEvening = job(h, at: try date(cal, 2026, 11, 23, hour: 18), [])
        let sundayMidnight = job(h, at: try date(cal, 2026, 11, 22), [])
        let tuesday = job(h, at: try date(cal, 2026, 11, 24, hour: 7), [])
        let days = WorkLog.days([mondayMorning, sundayMidnight, tuesday, mondayEvening], calendar: cal)
        #expect(days.map(\.day) == [try date(cal, 2026, 11, 24), try date(cal, 2026, 11, 23), try date(cal, 2026, 11, 22)])
        #expect(days.map { $0.records.map(\.id) } == [[tuesday.id], [mondayEvening.id, mondayMorning.id],
                                                      [sundayMidnight.id]])
    }

    // MARK: - Filters

    private func signedSeason(_ h: Harness, services: [String]) -> Contract {
        var draft = Contracts.Draft(for: h.client, now: h.clock.addingTimeInterval(-10 * day))
        draft.pricing = .season
        draft.priceText = "900"
        draft.serviceIDs = Set(services)
        let contract = Contracts.save(draft, to: nil, of: h.client, in: h.context)
        Contracts.sign(contract, in: h.context, now: h.clock.addingTimeInterval(-10 * day))
        return contract
    }

    @Test func billingFiltersUseTheServiceLogsStatus() throws {
        let h = try Harness(stopCount: 1)
        let at = h.clock.addingTimeInterval(-day)
        _ = signedSeason(h, services: ["plow"])
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0001"
        h.context.insert(invoice)

        let invoiced = job(h, at: at, [("salt", "Salt", 20)])
        invoiced.invoiceID = invoice.id.uuidString
        let deletedInvoice = job(h, at: at, [("salt", "Salt", 20)])
        deletedInvoice.invoiceID = UUID().uuidString                    // its invoice was deleted
        let covered = job(h, at: at, [("plow", "Plow", 60)])
        let comped = job(h, at: at, [("salt", "Salt", 20)], billable: false)
        let beforeLog = job(h, at: at, [("salt", "Salt", 20)], source: .beforeLog)
        let unbilled = job(h, at: at, [("salt", "Salt", 20)])
        try h.context.save()

        let all = [invoiced, deletedInvoice, covered, comped, beforeLog, unbilled]
        let invoiceIDs = ServiceLog.invoiceIDs(in: h.context)
        let contracts = Contracts.all(in: h.context)
        func shown(_ billing: WorkLog.BillingFilter) -> Set<UUID> {
            Set(WorkLog.filter(all, operatorID: "op", service: nil, billing: billing,
                               invoiceIDs: invoiceIDs, contracts: contracts).map(\.id))
        }
        #expect(shown(.all) == Set(all.map(\.id)))
        #expect(shown(.notBilled) == [deletedInvoice.id, unbilled.id])
        #expect(shown(.invoiced) == [invoiced.id])
        // The row's chip says the same as Service History's.
        for record in all {
            #expect(WorkLog.status(of: record, invoiceIDs: invoiceIDs, contracts: contracts)
                    == ServiceLog.billingStatus(of: record, in: h.context))
        }
        #expect(WorkLog.status(of: covered, invoiceIDs: invoiceIDs, contracts: contracts) == .covered)
        #expect(WorkLog.status(of: comped, invoiceIDs: invoiceIDs, contracts: contracts) == .noCharge)
        #expect(WorkLog.status(of: beforeLog, invoiceIDs: invoiceIDs, contracts: contracts) == .notTracked)
    }

    @Test func serviceFilterMatchesIDsAndCustomLinesByName() throws {
        let h = try Harness(stopCount: 1)
        let older = job(h, at: h.clock.addingTimeInterval(-2 * day), [("plow", "Plow", 40)])
        let newer = job(h, at: h.clock.addingTimeInterval(-day), [("plow", "Clear Drive", 45), ("", "Gate repair", 30)])
        let salted = job(h, at: h.clock, [("salt", "Salt", 15), ("", "Mailbox fix", 20)])
        let records = [older, newer, salted]

        let services = WorkLog.services(in: records)
        // The newest name, sorted by name; two custom lines stay two services.
        #expect(services.map(\.name) == ["Clear Drive", "Gate repair", "Mailbox fix", "Salt"])
        let plow = try #require(services.first { $0.name == "Clear Drive" }).key
        let custom = try #require(services.first { $0.name == "Gate repair" }).key
        func shown(_ service: WorkLog.ServiceKey?) -> [UUID] {
            WorkLog.filter(records, operatorID: "op", service: service, billing: .all,
                           invoiceIDs: [], contracts: []).map(\.id)
        }
        #expect(shown(plow) == [older.id, newer.id])
        #expect(shown(custom) == [newer.id])
        #expect(shown(nil) == records.map(\.id))
    }

    @Test func anotherBusinesssRecordsAreLeftOut() throws {
        let h = try Harness(stopCount: 1)
        let mine = job(h, at: h.clock, [("plow", "Plow", 40)])
        let theirs = job(h, at: h.clock, [("plow", "Plow", 40)], operatorID: "other")
        #expect(WorkLog.filter([mine, theirs], operatorID: "op", service: nil, billing: .all,
                               invoiceIDs: [], contracts: []).map(\.id) == [mine.id])
    }

    @Test func fetchTakesTheBusinesssRecordsFromTheStartUpToTheEnd() throws {
        let h = try Harness(stopCount: 1)
        let cal = try calendar()
        let interval = WorkLog.Period.today.interval(now: try date(cal, 2026, 11, 24, hour: 9), calendar: cal)
        let atStart = job(h, at: interval.start, [("plow", "Plow", 40)])
        let lastSecond = job(h, at: interval.end.addingTimeInterval(-1), [("plow", "Plow", 40)])
        _ = job(h, at: interval.end, [("plow", "Plow", 40)])                         // tomorrow's
        _ = job(h, at: interval.start.addingTimeInterval(-1), [("plow", "Plow", 40)]) // yesterday's
        _ = job(h, at: interval.start.addingTimeInterval(3_600), [("plow", "Plow", 40)], operatorID: "other")
        try h.context.save()
        let fetched = try h.context.fetch(FetchDescriptor<ServiceRecord>(
            predicate: WorkLog.predicate(operatorID: "op", interval: interval)))
        #expect(Set(fetched.map(\.id)) == [atStart.id, lastSecond.id])
    }

    @Test func valueIsGreyWhenNotChargedAsInServiceHistory() throws {
        let h = try Harness(stopCount: 1)
        let billable = job(h, at: h.clock, [("plow", "Plow", 40)])
        let unbillable = job(h, at: h.clock, [("plow", "Plow", 40)], billable: false)
        #expect(!ServiceRecordRow.valueIsGrey(billable, status: .notBilled))
        #expect(!ServiceRecordRow.valueIsGrey(billable, status: .invoiced))
        #expect(ServiceRecordRow.valueIsGrey(billable, status: .covered))
        #expect(ServiceRecordRow.valueIsGrey(unbillable, status: .noCharge))
    }

    // MARK: - Value and totals

    @Test func valueIsTheRecordedTotalOrTheChosenServicesLines() throws {
        let h = try Harness(stopCount: 1)
        let record = job(h, at: h.clock, [("plow", "Plow", 40), ("salt", "Salt", 12.5),
                                          ("", "Gate repair", 7.25), ("salt", "Salt", 2.5)])
        #expect(WorkLog.value(of: record, service: nil) == ServiceLog.total(of: record))
        #expect(WorkLog.value(of: record, service: nil) == 62.25)
        let keys = Dictionary(uniqueKeysWithValues: WorkLog.services(in: [record]).map { ($0.name, $0.key) })
        #expect(WorkLog.value(of: record, service: keys["Salt"]) == 15)
        #expect(WorkLog.value(of: record, service: keys["Gate repair"]) == 7.25)
        #expect(WorkLog.value(of: record, service: keys["Plow"]) == 40)
    }

    @Test func totalsAddUpTheList() throws {
        let h = try Harness(stopCount: 1)
        let a = job(h, at: h.clock, [("plow", "Plow", 40), ("salt", "Salt", 10)], minutes: 30)
        let b = job(h, at: h.clock, [("plow", "Plow", 45.5)], minutes: 15.5)
        let c = job(h, at: h.clock, [], minutes: 0)
        #expect(WorkLog.Totals([a, b, c], service: nil) == WorkLog.Totals(count: 3, minutes: 45.5, value: 95.5))
        let plow = try #require(WorkLog.services(in: [a, b]).first { $0.name == "Plow" }).key
        #expect(WorkLog.Totals([a, b], service: plow) == WorkLog.Totals(count: 2, minutes: 45.5, value: 85.5))
        #expect(WorkLog.Totals([], service: nil) == WorkLog.Totals(count: 0, minutes: 0, value: 0))
    }
}
