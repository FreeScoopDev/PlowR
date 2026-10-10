import Foundation
import SwiftData
import Testing
import WeatherKit
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

    private func snowService(_ h: Harness, operatorID: String = "op", active: Bool = true,
                             category: String = ServiceCatalog.snowKey) -> ServiceItem {
        let service = ServiceItem(name: "Clearing", category: category, unitType: "flat", pricePerUnit: 50,
                                  operatorID: operatorID)
        service.isActive = active
        h.context.insert(service)
        return service
    }

    /// Every contract's client active.
    private func book(_ contracts: [Contract], services: [ServiceItem]) -> StormWatch.Book {
        StormWatch.Book(contracts: contracts, services: services,
                        activeClientIDs: Set(contracts.map(\.clientID)), operatorID: "op")
    }

    private func storm(_ days: [DayForecast], _ contracts: [Contract], offersSnow: Bool = true) -> StormWatch.Storm? {
        let services: [ServiceItem] = offersSnow ? [snowServiceDetached()] : []
        return StormWatch.storm(in: days, book: book(contracts, services: services), now: now, calendar: calendar)
    }

    /// A snow service not in any store (the book only reads its fields).
    private func snowServiceDetached() -> ServiceItem {
        ServiceItem(name: "Clearing", category: ServiceCatalog.snowKey, unitType: "flat", pricePerUnit: 50,
                    operatorID: "op")
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
        let triggers = StormWatch.triggers(on: day(1, snow: nil).date, book: book(contracts, services: []),
                                           calendar: calendar)
        #expect(triggers.map(\.clientName) == ["Twice"])
        #expect(triggers.first?.inches == 3)
        // Their lowest trigger sets the storm, not the default.
        #expect(storm([day(1, snow: 1.5)], contracts) == nil)
        #expect(storm([day(1, snow: 3)], contracts)?.met.map(\.clientName) == ["Twice"])
    }

    @Test func everySnowfallIsReachedByAnyMeasurableForecast() throws {
        let h = try Harness(stopCount: 0)
        let snow = snowService(h)
        let every = contract(h, "Every", trigger: 0)
        every.serviceIDs = [snow.id.uuidString]
        let four = contract(h, "Four", trigger: 4)
        let found = try #require(StormWatch.storm(in: [day(1, snow: 2)], book: book([every, four], services: [snow]),
                                                  now: now, calendar: calendar))
        #expect(found.met.map(\.clientName) == ["Every"])
        #expect(found.met.first?.label == "Every snowfall")
        #expect(found.notMet.map(\.clientName) == ["Four"])
        // A trace isn't snowfall.
        #expect(StormWatch.storm(in: [day(1, snow: 0.04)], book: book([every], services: [snow]),
                                 now: now, calendar: calendar) == nil)
        #expect(StormWatch.storm(in: [day(1, snow: 0.1)], book: book([every], services: [snow]),
                                 now: now, calendar: calendar) != nil)
        // A contract with no snow service and no trigger isn't a snow contract.
        let lawn = contract(h, "Lawn", trigger: 0)
        #expect(StormWatch.triggers(on: now, book: book([lawn], services: [snow]), calendar: calendar).isEmpty)
    }

    @Test func aDeletedOrInactiveClientsContractIsntWaitingOnAStorm() throws {
        let h = try Harness(stopCount: 0)
        let gone = contract(h, "Gone", trigger: 1)
        let resting = contract(h, "Resting", trigger: 1)
        let active = contract(h, "Active", trigger: 3)
        var b = book([gone, resting, active], services: [])
        b.activeClientIDs = [active.clientID]
        #expect(StormWatch.triggers(on: now, book: b, calendar: calendar).map(\.clientName) == ["Active"])
        // Nor lowers the threshold.
        #expect(StormWatch.storm(in: [day(1, snow: 2)], book: b, now: now, calendar: calendar) == nil)
    }

    @Test func onlyAnActiveSnowServiceOfTheBusinessCountsAsOfferingSnow() throws {
        let h = try Harness(stopCount: 0)
        #expect(StormWatch.offersSnow([snowService(h)], operatorID: "op"))
        #expect(!StormWatch.offersSnow([snowService(h, category: "lawn")], operatorID: "op"))
        #expect(!StormWatch.offersSnow([snowService(h, active: false)], operatorID: "op"))
        #expect(!StormWatch.offersSnow([snowService(h, operatorID: "other")], operatorID: "op"))
    }

    // Snowfall in the wrong unit would fire the storm card at the wrong depth.
    @Test func aForecastDayIsConvertedFromWeatherKitsUnits() {
        let day = WeatherService.day(date: now, high: Measurement(value: 0, unit: .celsius),
                                     low: Measurement(value: -10, unit: .celsius), condition: .snow,
                                     precipitation: Measurement(value: 1, unit: .centimeters),
                                     snowfall: Measurement(value: 10.16, unit: .centimeters), calendar: calendar)
        #expect(abs((day.snowfallInches ?? 0) - 4) < 0.0001)                    // 10.16 cm of snow = 4 in
        #expect(abs(day.maxTempF - 32) < 0.0001 && abs(day.minTempF - 14) < 0.0001)
        #expect(abs(day.precipitationMm - 10) < 0.0001)
        #expect(day.weatherCode == 73 && day.description == "Snow")
    }

    @Test func currentConditionsAreConvertedFromWeatherKitsUnits() {
        let current = WeatherService.condition(temperature: Measurement(value: 0, unit: .celsius),
                                               windSpeed: Measurement(value: 10, unit: .metersPerSecond),
                                               windDirection: Measurement(value: 180, unit: .degrees),
                                               condition: .windy)
        #expect(abs(current.temperatureF - 32) < 0.0001)
        #expect(abs(current.windSpeedMph - 22.369) < 0.01)
        #expect(current.windDirectionLabel == "S" && current.description == "Windy")
    }

    // A WeatherKit day starts at midnight where the place is; a phone further
    // west must still file it under that day.
    @Test func aDayIsThePlacesDayOnAPhoneToTheWest() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let midnightThere = try #require(newYork.date(from: DateComponents(year: 2027, month: 1, day: 14)))
        let day = WeatherService.calendarDay(of: midnightThere, calendar: losAngeles)
        #expect(losAngeles.component(.day, from: day) == 14)
    }

    // WeatherKit's conditions become the codes the alerts already know.
    @Test func weatherKitConditionsMapToTheCodesAlertsUse() {
        #expect(weatherCode(for: .clear) == 0)
        #expect(weatherCode(for: .heavySnow) == 75 && weatherCode(for: .blizzard) == 75)
        #expect(weatherCode(for: .rain) == 63 && weatherCode(for: .heavyRain) == 65)
        #expect(weatherCode(for: .cloudy) == 3)
        // The borderline ones, decided: ice and drifting snow alert; hail with storms.
        #expect(weatherCode(for: .freezingDrizzle) == 66 && weatherCode(for: .freezingRain) == 66)
        #expect(weatherCode(for: .sleet) == 67 && weatherCode(for: .wintryMix) == 67)
        #expect(weatherCode(for: .blowingSnow) == 75)
        #expect(weatherCode(for: .flurries) == 71 && weatherCode(for: .sunFlurries) == 71)
        #expect(weatherCode(for: .hail) == 95 && weatherCode(for: .thunderstorms) == 95)
        #expect(weatherCode(for: .drizzle) == 53)                                // not an alert, as before
        // Their own labels, not "Overcast" or "Fog".
        #expect(WeatherService.condition(temperature: Measurement(value: 70, unit: .fahrenheit),
                                         windSpeed: Measurement(value: 0, unit: .milesPerHour),
                                         windDirection: Measurement(value: 0, unit: .degrees),
                                         condition: .smoky).description == "Smoky")
    }

    @Test func attributionShowsWithAnyWeather() {
        #expect(WeatherAttribution.isNeeded(current: false, forecast: true))   // the storm card on its own
        #expect(WeatherAttribution.isNeeded(current: true, forecast: false))
        #expect(!WeatherAttribution.isNeeded(current: false, forecast: false))
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
        #expect(request.content.body.hasPrefix("When PlowR last checked, about 4 in of snow was forecast"))
        #expect(request.content.body.contains("That reaches 2 clients' contract triggers."))
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.day == 12 && trigger.dateComponents.hour == 18)    // this evening
        // One client.
        var one = storm
        one.met.removeLast()
        #expect(StormWatch.alertBody(one).contains("That reaches 1 client's contract trigger."))
    }

    private func adverse(_ offset: Int, code: Int) -> DayForecast {
        let base = day(offset, snow: nil)
        return DayForecast(date: base.date, maxTempF: 30, minTempF: 20, weatherCode: code,
                           precipitationMm: code >= 51 && code < 1000 ? 5 : 0)
    }

    @Test func aFlurryShowsOnTheCardButAlertsOnlyOnAnAdverseDay() throws {
        let flurry = StormWatch.Storm(day: day(1, snow: nil).date, inches: 0.3, met: [], notMet: [])
        // Overcast with a flurry: no evening alert.
        #expect(NotificationService.shared.weatherAlertRequest(
            for: [adverse(0, code: 0), adverse(1, code: 3)], storm: flurry, now: now, calendar: calendar) == nil)
        // Snow showers forecast that day: the storm speaks for it.
        let request = try #require(NotificationService.shared.weatherAlertRequest(
            for: [adverse(0, code: 0), adverse(1, code: 85)], storm: flurry, now: now, calendar: calendar))
        #expect(request.content.body.hasPrefix("When PlowR last checked"))
        // An inch alerts whatever the code.
        var inch = flurry
        inch.inches = StormWatch.defaultThreshold
        #expect(NotificationService.shared.weatherAlertRequest(
            for: [adverse(0, code: 0), adverse(1, code: 3)], storm: inch, now: now, calendar: calendar) != nil)
    }

    @Test func aStormTodayLeavesTomorrowsAlertToTheForecast() throws {
        let today = StormWatch.Storm(day: now, inches: 4, met: [], notMet: [])
        let request = try #require(NotificationService.shared.weatherAlertRequest(
            for: [adverse(0, code: 0), adverse(1, code: 73)], storm: today, now: now, calendar: calendar))
        #expect(request.content.body.hasPrefix("Snow expected"))
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.day == 12 && trigger.dateComponents.hour == 18)
    }

    @Test func anEarlierAdverseDayKeepsItsAlertOverALaterStorm() throws {
        // Freezing rain tomorrow, the storm the day after: tonight's warning stays.
        let later = StormWatch.Storm(day: day(2, snow: nil).date, inches: 4, met: [], notMet: [])
        let forecasts = [adverse(0, code: 0), adverse(1, code: 67), adverse(2, code: 75)]
        let request = try #require(NotificationService.shared.weatherAlertRequest(
            for: forecasts, storm: later, now: now, calendar: calendar))
        #expect(request.content.body.hasPrefix("Freezing Rain expected"))
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.day == 12)
        // The same day: the storm speaks for it.
        let same = StormWatch.Storm(day: day(1, snow: nil).date, inches: 4, met: [], notMet: [])
        let sameDay = try #require(NotificationService.shared.weatherAlertRequest(
            for: forecasts, storm: same, now: now, calendar: calendar))
        #expect(sameDay.content.body.hasPrefix("When PlowR last checked"))
    }
}
