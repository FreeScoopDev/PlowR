//
//  VisitWeatherTests.swift
//  PlowRTests
//

import CoreLocation
import Foundation
import PDFKit
import SwiftData
import Testing
@testable import PlowR

/// The estimated weather on a visit's day, from WeatherKit's daily history,
/// on the Service Report. WeatherKit itself is never called here.
@MainActor
struct VisitWeatherTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h)) ?? .distantPast
    }

    @Test func eachDaysFiguresAreKeptByTheirDayInTheSpan() {
        let span = date(2027, 1, 14)...date(2027, 1, 15)
        let figures = [
            VisitWeather.Figures(date: date(2027, 1, 14), snowfallInches: 3.24, precipitationInches: 0.41,
                                 lowF: 17.6, highF: 29.4),
            VisitWeather.Figures(date: date(2027, 1, 15, 6), snowfallInches: 0, precipitationInches: 0,
                                 lowF: 10.2, highF: 25),
            VisitWeather.Figures(date: date(2027, 1, 16), snowfallInches: 1, precipitationInches: 0.1,
                                 lowF: 20, highF: 30),
        ]
        let days = VisitWeather.days(figures, span: span, calendar: calendar)
        #expect(days["2027-01-14"] == VisitWeather.Day(snowfall: 3.24, precipitation: 0.41, low: 17.6, high: 29.4))
        #expect(days["2027-01-15"]?.snowfall == 0)
        #expect(days["2027-01-16"] == nil)                                        // outside the span asked for
    }

    // Only days the archive really covers: from 2022 to yesterday.
    @Test func onlyDaysTheArchiveCoversAreAskedFor() throws {
        let now = date(2027, 1, 20, 9)
        let span = try #require(VisitWeather.span(of: [date(2021, 12, 30), date(2027, 1, 20, 5), date(2027, 1, 14, 5)],
                                                  now: now, calendar: calendar))
        #expect(span.lowerBound == date(2022, 1, 1))                              // before 2022 it answers zeros
        #expect(span.upperBound == date(2027, 1, 19))                             // today's is partly forecast
        #expect(VisitWeather.span(of: [date(2027, 1, 20, 5)], now: now, calendar: calendar) == nil)
        #expect(VisitWeather.span(of: [date(2021, 6, 1)], now: now, calendar: calendar) == nil)
        #expect(VisitWeather.span(of: [], now: now, calendar: calendar) == nil)
    }

    @Test func theLocationSentIsRoundedToAboutAKilometre() {
        let location = WeatherService.location(latitude: 43.37704, longitude: -72.34512)
        #expect(location.coordinate.latitude == 43.38 && location.coordinate.longitude == -72.35)
    }

    @Test func aDaysLineSaysItsAnEstimate() {
        let line = VisitWeather.line(.init(snowfall: 3.24, precipitation: 0.41, low: 17.6, high: 29.4))
        #expect(line == "Estimated weather that day (whole day, weather model): 3.24 in of snow, 0.41 in of precipitation, low 18°F, high 29°F")
        let none = VisitWeather.line(.init(snowfall: 0, precipitation: 0.04, low: 10, high: 25))
        #expect(none.contains("0.00 in of snow") && !none.contains("no snow"))  // a number, never a denial
        #expect(VisitWeather.line(.init(snowfall: 0.28, precipitation: 0.003, low: 10, high: 25)).contains("a trace of precipitation"))
        #expect(VisitWeather.line(nil) == "Estimated weather that day: no estimate for this day")
    }

    // Under tests WeatherKit is never asked: with no history given, the
    // lookup fails, and says so.
    @Test func aFailedLookupIsSaidSoNotReadAsNoData() async {
        let failed = await VisitWeather.lookUp(latitude: 43.4, longitude: -72.3, visitDays: [date(2027, 1, 14, 5)],
                                               now: date(2027, 2, 1))
        #expect(failed == .failed)
        let refused = await VisitWeather.lookUp(latitude: 43.4, longitude: -72.3, visitDays: [date(2027, 1, 14, 5)],
                                                now: date(2027, 2, 1), history: { _, _, _ in throw URLError(.timedOut) })
        #expect(refused == .failed)
        let noPin = await VisitWeather.lookUp(latitude: 0, longitude: 0, visitDays: [date(2027, 1, 14, 5)],
                                              now: date(2027, 2, 1))
        #expect(noPin == .notLookedUp)
    }

    // What's actually asked for: the rounded place, from the span's first day
    // to the day after its last.
    @Test func theLookupAsksForTheSpanAtARoundedPlace() async {
        var asked: [(Double, Double, Date, Date)] = []
        let lookup = await VisitWeather.lookUp(latitude: 43.37704, longitude: -72.34512,
                                               visitDays: [date(2027, 1, 14, 5), date(2027, 1, 16, 5)],
                                               now: date(2027, 2, 1)) { location, start, end in
            asked.append((location.coordinate.latitude, location.coordinate.longitude, start, end))
            return [VisitWeather.figures(date: Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start,
                                         snowfall: Measurement(value: 2.54, unit: .centimeters),
                                         precipitation: Measurement(value: 0.5, unit: .centimeters),
                                         low: Measurement(value: -5, unit: .celsius),
                                         high: Measurement(value: 5, unit: .celsius))]
        }
        #expect(asked.count == 1)
        #expect(asked.first?.0 == 43.38 && asked.first?.1 == -72.35)
        // From the day before the first visit day to the day after the last.
        let phone = Calendar.current
        #expect(asked.first?.2 == phone.date(byAdding: .day, value: -1, to: phone.startOfDay(for: date(2027, 1, 14, 5))))
        #expect(asked.first?.3 == phone.date(byAdding: .day, value: 1, to: phone.startOfDay(for: date(2027, 1, 16, 5))))
        guard case .days(let days) = lookup, let day = days.values.first else {
            Issue.record("expected days"); return
        }
        #expect(abs(day.snowfall - 1) < 0.0001 && abs(day.high - 41) < 0.0001)   // converted to in and °F
    }

    @Test func theReportShowsWeatherAsItsLookupWent() throws {
        let h = try Harness(stopCount: 0)
        let record = ServiceRecord(operatorID: "op", sourceKey: "stop:x", source: .route)
        record.clientID = h.client.id.uuidString
        record.propertyID = h.client.id.uuidString
        record.startedAt = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 14, hour: 5))
        record.performedAt = record.startedAt?.addingTimeInterval(1_800) ?? .now
        h.context.insert(record)
        let visit = ProofOfService.Visit(record: record, photos: [])
        let period = ProofOfService.Period(label: "January", start: record.performedAt, end: record.performedAt)
        let place = ProofOfService.ReportPlace(id: h.client.id.uuidString, label: "Main Address", address: "0 Main St",
                                               latitude: 43, longitude: -72)
        func text(_ weather: VisitWeather.Lookup) throws -> String {
            let data = ProofOfService.pdf(client: h.client, place: place, period: period, visits: [visit],
                                          profile: nil, weather: weather)
            let document = try #require(PDFDocument(data: data))
            return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        }
        let day = VisitWeather.dayString(record.startedAt ?? .now)
        let shown = try text(.days([day: .init(snowfall: 3.24, precipitation: 0.41, low: 17.6, high: 29.4)]))
        #expect(shown.contains("3.24 in of snow") && shown.contains("Weather data sources"))
        // Apple's attribution on the PDF (the link can wrap across lines).
        #expect(shown.filter { !$0.isWhitespace }.contains(WeatherAttribution.legalPage))
        let failed = try text(.failed)
        #expect(failed.contains("couldn't be looked up") && !failed.contains("Estimated weather that day"))
        let none = try text(.notLookedUp)
        #expect(!none.contains("weather") && !none.contains("Weather data sources"))
    }
}
