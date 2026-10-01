//
//  VisitWeatherTests.swift
//  PlowRTests
//

import Foundation
import PDFKit
import SwiftData
import Testing
@testable import PlowR

/// Answers every request with a failure, as no signal or a service down does.
final class FailingWeatherProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// The estimated weather on a visit's day, from Open-Meteo's historical
/// forecast archive, on the Service Report.
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

    private let reply = Data("""
    {"daily": {"time": ["2027-01-14", "2027-01-15", "2027-01-16"],
               "snowfall_sum": [3.24, 0.0, null],
               "precipitation_sum": [0.41, 0.0, 0.1],
               "temperature_2m_min": [17.6, 10.2, 20.0],
               "temperature_2m_max": [29.4, 25.0, 30.0]}}
    """.utf8)

    @Test func eachDaysEstimateIsReadAndADayWithAGapIsLeftOut() throws {
        let days = try VisitWeather.parse(reply)
        #expect(days["2027-01-14"] == VisitWeather.Day(snowfall: 3.24, precipitation: 0.41, low: 17.6, high: 29.4))
        #expect(days["2027-01-15"]?.snowfall == 0)
        #expect(days["2027-01-16"] == nil)                                        // never a made-up zero
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

    @Test func theRequestIsTheSpanAtRoundedCoordinatesInThePhonesZone() throws {
        let url = try #require(VisitWeather.url(latitude: 43.37704, longitude: -72.34512,
                                                span: date(2027, 1, 1)...date(2027, 1, 31), calendar: calendar))
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        #expect(url.host == "historical-forecast-api.open-meteo.com")
        #expect(items["latitude"] == "43.38" && items["longitude"] == "-72.35")
        #expect(items["start_date"] == "2027-01-01" && items["end_date"] == "2027-01-31")
        #expect(items["timezone"] == "America/New_York")                          // days as the report's are
        #expect(items["precipitation_unit"] == "inch" && items["temperature_unit"] == "fahrenheit")
    }

    @Test func aDaysLineSaysItsAnEstimate() {
        let line = VisitWeather.line(.init(snowfall: 3.24, precipitation: 0.41, low: 17.6, high: 29.4))
        #expect(line == "Estimated weather that day (whole day, weather model): 3.24 in of snow, 0.41 in of precipitation, low 18°F, high 29°F")
        let none = VisitWeather.line(.init(snowfall: 0, precipitation: 0.04, low: 10, high: 25))
        #expect(none.contains("0.00 in of snow") && !none.contains("no snow"))  // a number, never a denial
        #expect(VisitWeather.line(.init(snowfall: 0.28, precipitation: 0.003, low: 10, high: 25)).contains("a trace of precipitation"))
        #expect(VisitWeather.line(nil) == "Estimated weather that day: no estimate for this day")
    }

    @Test func aFailedLookupIsSaidSoNotReadAsNoData() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingWeatherProtocol.self]
        let session = URLSession(configuration: configuration)
        let failed = await VisitWeather.lookUp(latitude: 43.4, longitude: -72.3, visitDays: [date(2027, 1, 14, 5)],
                                               now: date(2027, 2, 1), session: session)
        #expect(failed == .failed)
        let noPin = await VisitWeather.lookUp(latitude: 0, longitude: 0, visitDays: [date(2027, 1, 14, 5)],
                                              now: date(2027, 2, 1), session: session)
        #expect(noPin == .notLookedUp)
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
        #expect(shown.contains("3.24 in of snow") && shown.contains("estimates from a weather model"))
        let failed = try text(.failed)
        #expect(failed.contains("couldn't be looked up") && !failed.contains("Estimated weather that day"))
        let none = try text(.notLookedUp)
        #expect(!none.contains("weather") && !none.contains("Open-Meteo"))
    }
}
