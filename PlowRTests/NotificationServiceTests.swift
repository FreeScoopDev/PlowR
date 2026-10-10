import Testing
import Foundation
import UserNotifications
@testable import PlowR

struct NotificationServiceTests {

    // MARK: - Helpers

    private func makeDay(code: Int, daysFromNow: Int) -> DayForecast {
        let date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!
        // Wet only on a wet day's code: 0.1 in or more of rain alerts on its own.
        return DayForecast(date: date, maxTempF: 32, minTempF: 20,
                           weatherCode: code, precipitationMm: code >= 51 && code < 1000 ? 5 : 0)
    }

    // WeatherKit's daily condition describes the whole day: a calm label on a
    // day with 0.1 in or more of rain still alerts.
    @Test func aWetDayAlertsWhateverItsLabel() {
        let wet = DayForecast(date: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                              maxTempF: 50, minTempF: 40, weatherCode: 3, precipitationMm: 3)
        let dry = DayForecast(date: wet.date, maxTempF: 50, minTempF: 40, weatherCode: 3, precipitationMm: 1)
        #expect(NotificationService.shared.isAdverse(wet))
        #expect(!NotificationService.shared.isAdverse(dry))
    }

    // MARK: - adverseForecastDay

    // Adverse code on day 1 (tomorrow) — should be returned.
    @Test func adverseForecastDay_adverseOnDayOne_returnsIt() {
        let forecasts = [
            makeDay(code: 0,  daysFromNow: 0),  // today – clear
            makeDay(code: 75, daysFromNow: 1),  // tomorrow – heavy snow ✓
            makeDay(code: 0,  daysFromNow: 2),
        ]
        let result = NotificationService.shared.adverseForecastDay(from: forecasts)
        #expect(result?.weatherCode == 75)
    }

    // Today (index 0) is always skipped even when it carries an adverse code.
    @Test func adverseForecastDay_adverseTodayOnly_returnsNil() {
        let forecasts = [
            makeDay(code: 95, daysFromNow: 0),  // today – thunderstorm (must be skipped)
            makeDay(code: 0,  daysFromNow: 1),
            makeDay(code: 0,  daysFromNow: 2),
        ]
        #expect(NotificationService.shared.adverseForecastDay(from: forecasts) == nil)
    }

    // Only days 1 and 2 are checked; adverse code on day 3+ must be ignored.
    @Test func adverseForecastDay_adverseOnDayThree_returnsNil() {
        let forecasts = [
            makeDay(code: 0,  daysFromNow: 0),
            makeDay(code: 0,  daysFromNow: 1),
            makeDay(code: 0,  daysFromNow: 2),
            makeDay(code: 71, daysFromNow: 3),  // snow – outside the 2-day window
        ]
        #expect(NotificationService.shared.adverseForecastDay(from: forecasts) == nil)
    }

    @Test func adverseForecastDay_allClearForecast_returnsNil() {
        let forecasts = (0..<7).map { makeDay(code: 0, daysFromNow: $0) }
        #expect(NotificationService.shared.adverseForecastDay(from: forecasts) == nil)
    }

    // A crash check: an empty forecast has no day to return, so the
    // expectation can't fail. What it catches is a crash on empty input.
    @Test func adverseForecastDay_emptyForecast_returnsNil() {
        #expect(NotificationService.shared.adverseForecastDay(from: []) == nil)
    }

    // Only code 75 was ever checked; dropping any other code from the list
    // would have passed. Rain, freezing rain, snow, showers and storms.
    @Test(arguments: [61, 63, 65, 66, 67, 71, 73, 75, 77, 85, 86, 80, 81, 82, 95, 96, 99])
    func adverseForecastDay_everyAdverseCodeAlerts(code: Int) {
        let forecasts = [makeDay(code: 0, daysFromNow: 0), makeDay(code: code, daysFromNow: 1)]
        #expect(NotificationService.shared.adverseForecastDay(from: forecasts)?.weatherCode == code)
    }

    // Clear, cloudy and fog never alert.
    @Test(arguments: [0, 1, 2, 3, 45, 48])
    func adverseForecastDay_calmCodesDoNotAlert(code: Int) {
        let forecasts = [makeDay(code: 0, daysFromNow: 0), makeDay(code: code, daysFromNow: 1)]
        #expect(NotificationService.shared.adverseForecastDay(from: forecasts) == nil)
    }

    // MARK: - When alerts fire

    /// A fixed calendar and clock, so the timing tests don't depend on where or when they run.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, code: Int = 0) -> DayForecast {
        let date = calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour)) ?? .distantPast
        return DayForecast(date: date, maxTempF: 30, minTempF: 20, weatherCode: code,
                           precipitationMm: code >= 51 && code < 1000 ? 5 : 0)
    }

    // No test called the scheduling code, so moving the alert from 6 PM to
    // 8 AM passed. Snow on Thursday: the alert is Wednesday at 6 PM.
    @Test func theWeatherAlertFiresAtSixTheEveningBefore() throws {
        let forecasts = [day(2026, 1, 13), day(2026, 1, 14), day(2026, 1, 15, code: 75)]
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 13, hour: 9)))
        let request = try #require(NotificationService.shared.weatherAlertRequest(for: forecasts, now: now, calendar: calendar))
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.day == 14)
        #expect(trigger.dateComponents.hour == 18)
        #expect(trigger.dateComponents.minute == 0)
        #expect(!trigger.repeats)
        #expect(request.identifier == "weather_alert")
    }

    // Past 6 PM the evening before, there's nothing left to warn about in time.
    @Test func noWeatherAlertOnceThatEveningHasPassed() throws {
        let forecasts = [day(2026, 1, 13), day(2026, 1, 14, code: 75)]
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 13, hour: 19)))
        #expect(NotificationService.shared.weatherAlertRequest(for: forecasts, now: now, calendar: calendar) == nil)
    }

    // Removing the guard that cancels at zero also passed: the reminder must
    // only be cancelled, never replaced with "0 invoices past due".
    @Test func noOverdueReminderWhenNothingIsOverdue() {
        #expect(NotificationService.overdueReminderRequest(count: 0) == nil)
    }

    @Test func theOverdueReminderRepeatsDailyAtNine() throws {
        let request = try #require(NotificationService.overdueReminderRequest(count: 3))
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.hour == 9)
        #expect(trigger.dateComponents.minute == 0)
        #expect(trigger.repeats)
        #expect(request.content.body == NotificationService.overdueBody(count: 3))
    }

    // MARK: - overdueBody

    @Test func overdueBody_singleInvoice_usesSingular() {
        #expect(NotificationService.overdueBody(count: 1) == "1 invoice past due — follow up in PlowR.")
    }

    @Test func overdueBody_multipleInvoices_usesPlural() {
        #expect(NotificationService.overdueBody(count: 3) == "3 invoices past due — follow up in PlowR.")
    }
}
