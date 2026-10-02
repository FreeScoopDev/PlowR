import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import PlowR

/// The storm trigger: a forecast reaching a contract trigger (or, without
/// one, a snow business's default), which clients it reaches, and the
/// evening alert that says so.
@MainActor
struct StormWatchTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: 12, hour: 9)) ?? .distantPast
    }

    private func day(_ offset: Int, snow: Double?) -> DayForecast {
        let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
        return DayForecast(date: date, maxTempF: 30, minTempF: 20, weatherCode: 73, precipitationMm: 5,
                           snowfallInches: snow)
    }

    @discardableResult
    private func contract(_ h: Harness, _ name: String, trigger: Double, signed: Bool = true,
                          from: Int = -30, to: Int = 60, cancelledDaysAgo: Int? = nil,
                          operatorID: String = "op") -> Contract {
        let start = calendar.date(byAdding: .day, value: from, to: now) ?? now
        let end = calendar.date(byAdding: .day, value: to, to: now) ?? now
        let contract = Contract(name: "Season", startDate: start, endDate: end, operatorID: operatorID)
        contract.clientID = "id-\(name)"
        contract.clientName = name
        contract.placeIDs = ["id-\(name)"]
        contract.triggerInches = trigger
        contract.signedAt = signed ? start : nil
        if let cancelledDaysAgo { contract.cancelledAt = calendar.date(byAdding: .day, value: -cancelledDaysAgo, to: now) }
        h.context.insert(contract)
        return contract
    }

    private func storm(_ days: [DayForecast], _ contracts: [Contract], offersSnow: Bool = true) -> StormWatch.Storm? {
        StormWatch.storm(in: days, contracts: contracts, operatorID: "op", offersSnow: offersSnow,
                         now: now, calendar: calendar)
    }

    @Test func aForecastReachingATriggerIsAStormWithTheClientsItReaches() throws {
        let h = try Harness(stopCount: 0)
        let contracts = [contract(h, "Baker", trigger: 2), contract(h, "Adams", trigger: 1),
                         contract(h, "Clark", trigger: 6)]
        let found = try #require(storm([day(0, snow: 0), day(1, snow: 3.96), day(2, snow: 8)], contracts))
        #expect(calendar.isDate(found.day, inSameDayAs: day(1, snow: nil).date))     // the first one
        #expect(found.inches == 4)
        #expect(found.met.map(\.clientName) == ["Adams", "Baker"])
        #expect(found.notMet.map(\.clientName) == ["Clark"])
    }

    @Test func belowEveryTriggerIsNoStorm() throws {
        let h = try Harness(stopCount: 0)
        let contracts = [contract(h, "Baker", trigger: 2)]
        #expect(storm([day(0, snow: 1.5), day(1, snow: nil), day(2, snow: 0)], contracts) == nil)
        // Shown to a tenth and compared as shown: 1.96 reads "2 in" and reaches 2.
        #expect(storm([day(1, snow: 1.96)], contracts) != nil)
        #expect(storm([day(1, snow: 1.94)], contracts) == nil)
    }

    @Test func withoutATriggerASnowBusinessGetsTheDefault() throws {
        #expect(storm([day(1, snow: StormWatch.defaultThreshold)], [])?.met == [])
        #expect(storm([day(1, snow: StormWatch.defaultThreshold - 0.1)], []) == nil)
        // A lawn business never sees a storm.
        #expect(storm([day(1, snow: 12)], [], offersSnow: false) == nil)
    }

    @Test func onlyTheNextFewDaysCount() throws {
        let h = try Harness(stopCount: 0)
        let contracts = [contract(h, "Baker", trigger: 2)]
        #expect(storm([day(-1, snow: 9), day(StormWatch.daysAhead, snow: 9)], contracts) == nil)
        #expect(storm([day(StormWatch.daysAhead - 1, snow: 9)], contracts) != nil)
    }

    @Test func onlyContractsInForceThatDayCountEachClientOnceAtTheirLowest() throws {
        let h = try Harness(stopCount: 0)
        let contracts = [
            contract(h, "Draft", trigger: 1, signed: false),
            contract(h, "Ended", trigger: 1, from: -90, to: -1),
            contract(h, "Starts later", trigger: 1, from: 5),
            contract(h, "Cancelled", trigger: 1, cancelledDaysAgo: 2),
            contract(h, "No trigger", trigger: 0),
            contract(h, "Someone else's", trigger: 1, operatorID: "other"),
            contract(h, "Twice", trigger: 5),
            contract(h, "Twice", trigger: 3)
        ]
        let triggers = StormWatch.triggers(on: day(1, snow: nil).date, contracts: contracts, operatorID: "op",
                                           calendar: calendar)
        #expect(triggers.map(\.clientName) == ["Twice"])
        #expect(triggers.first?.inches == 3)
        // Their lowest trigger sets the storm, not the default.
        #expect(storm([day(1, snow: 1.5)], contracts) == nil)
        #expect(storm([day(1, snow: 3)], contracts)?.met.map(\.clientName) == ["Twice"])
    }

    @Test func amountsAndDays() {
        #expect(StormWatch.amount(4) == "4 in")
        #expect(StormWatch.amount(1.46) == "1.5 in")
        #expect(StormWatch.amount(0.6) == "0.6 in")
        #expect(StormWatch.dayName(now, now: now, calendar: calendar) == "Today")
        #expect(StormWatch.dayName(now.addingTimeInterval(86_400), now: now, calendar: calendar) == "Tomorrow")
    }

    // MARK: - The evening alert

    @Test func aStormTomorrowIsTheEveningAlertWithItsTriggers() throws {
        let storm = StormWatch.Storm(day: day(1, snow: nil).date, inches: 4,
                                     met: [.init(clientID: "a", clientName: "Adams", inches: 2),
                                           .init(clientID: "b", clientName: "Baker", inches: 3)],
                                     notMet: [])
        let request = try #require(NotificationService.shared.weatherAlertRequest(
            for: [], storm: storm, now: now, calendar: calendar))
        #expect(request.content.body.hasPrefix("About 4 in of snow forecast"))
        #expect(request.content.body.contains("2 clients' contract triggers are at or below it"))
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.day == 12 && trigger.dateComponents.hour == 18)    // this evening
        // One client.
        var one = storm
        one.met.removeLast()
        #expect(StormWatch.alertBody(one).contains("1 client's contract trigger is at or below it"))
    }

    @Test func aStormTodayLeavesTheAlertToTheForecast() throws {
        let today = StormWatch.Storm(day: now, inches: 4, met: [], notMet: [])
        // Nothing adverse after today: no alert (its evening has passed).
        #expect(NotificationService.shared.weatherAlertRequest(for: [day(0, snow: 4)], storm: today,
                                                               now: now, calendar: calendar) == nil)
    }
}
