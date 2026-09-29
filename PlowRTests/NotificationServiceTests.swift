import Testing
import Foundation
@testable import PlowR

struct NotificationServiceTests {

    // MARK: - Helpers

    private func makeDay(code: Int, daysFromNow: Int) -> DayForecast {
        let date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!
        return DayForecast(date: date, maxTempF: 32, minTempF: 20,
                           weatherCode: code, precipitationMm: 5)
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

    // MARK: - overdueBody

    @Test func overdueBody_singleInvoice_usesSingular() {
        #expect(NotificationService.overdueBody(count: 1) == "1 invoice past due — follow up in PlowR.")
    }

    @Test func overdueBody_multipleInvoices_usesPlural() {
        #expect(NotificationService.overdueBody(count: 3) == "3 invoices past due — follow up in PlowR.")
    }
}
