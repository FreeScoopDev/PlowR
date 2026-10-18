//
//  TimeOnSiteTests.swift
//  PlowRTests
//

import Foundation
import Testing
@testable import PlowR

/// Time on site (GPS's arrival to its departure), the Minutes on Site field,
/// and the Service Report's way in from the client page.
@MainActor
struct TimeOnSiteTests {
    private let zone = TimeZone(identifier: "America/New_York") ?? .current
    private let english = Locale(identifier: "en_US")

    private func at(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2027, month: 1, day: 14, hour: h, minute: m, second: s))
            ?? .distantPast
    }

    private func record(arrived: Date?, left: Date?) -> ServiceRecord {
        let record = ServiceRecord(operatorID: "op", sourceKey: "k", source: .route)
        record.arrivedAt = arrived
        record.leftAt = left
        return record
    }

    /// The narrow space the time formatter puts before AM/PM, as a space.
    private func plain(_ text: String?) -> String? { text?.replacingOccurrences(of: "\u{202F}", with: " ") }

    // MARK: - Time on site

    @Test func timeOnSiteNeedsBothTimes() {
        #expect(ProofOfService.timeOnSite(arrivedAt: at(4, 58), leftAt: at(5, 24)) == TimeInterval(26 * 60))
        #expect(ProofOfService.timeOnSite(arrivedAt: nil, leftAt: at(5, 24)) == nil)
        #expect(ProofOfService.timeOnSite(arrivedAt: at(4, 58), leftAt: nil) == nil)
        #expect(ProofOfService.timeOnSite(arrivedAt: nil, leftAt: nil) == nil)
        #expect(ProofOfService.timeOnSite(of: record(arrived: at(4, 58), left: at(5, 24))) == TimeInterval(26 * 60))
        #expect(ProofOfService.timeOnSite(of: record(arrived: nil, left: at(5, 24))) == nil)
    }

    @Test func aDepartureBeforeTheArrivalIsNoTimeOnSite() {
        // Out of order (a sync merge of two devices' times): not made into a
        // time, negative or otherwise.
        #expect(ProofOfService.timeOnSite(arrivedAt: at(5, 24), leftAt: at(4, 58)) == nil)
        // The same instant is a time: under a minute.
        #expect(ProofOfService.timeOnSite(arrivedAt: at(5, 0), leftAt: at(5, 0)) == TimeInterval(0))
    }

    @Test func durationsAreSaidToTheMinute() {
        #expect(ProofOfService.duration(0) == "under 1 min")
        #expect(ProofOfService.duration(29) == "under 1 min")
        #expect(ProofOfService.duration(30) == "1 min")
        #expect(ProofOfService.duration(26 * 60) == "26 min")
        #expect(ProofOfService.duration(59 * 60 + 29) == "59 min")
        #expect(ProofOfService.duration(59 * 60 + 30) == "1 h 00 min")
        #expect(ProofOfService.duration(65 * 60) == "1 h 05 min")
        #expect(ProofOfService.duration(150 * 60) == "2 h 30 min")
        #expect(ProofOfService.onSiteText(38 * 60) == "38 min on site")
    }

    @Test func theReportGivesTheTimeOnSiteOnlyWhenGPSCaughtBoth() {
        func line(_ record: ServiceRecord) -> String? {
            plain(ProofOfService.siteTimes(of: record, timeZone: zone, locale: english))
        }
        #expect(line(record(arrived: at(4, 58), left: at(5, 24)))
                == "Arrived 4:58 AM · Left 5:24 AM · 26 min on site (GPS, within about 100 m)")
        #expect(line(record(arrived: nil, left: at(5, 24)))
                == "Arrival not caught · Left 5:24 AM (GPS, within about 100 m)")
        #expect(line(record(arrived: at(4, 58), left: nil))
                == "Arrived 4:58 AM · Departure not caught (GPS, within about 100 m)")
        #expect(line(record(arrived: nil, left: nil)) == nil)
    }

    // MARK: - The job's page

    @Test func theJobPageShowsWhatGPSSawAndNothingMore() {
        func rows(_ record: ServiceRecord) -> [String] {
            ProofOfService.siteRows(of: record, timeZone: zone, locale: english)
                .map { "\($0.label): \(plain($0.value) ?? "")" }
        }
        #expect(rows(record(arrived: at(4, 58), left: at(6, 3)))
                == ["Arrived: 4:58 AM", "Left: 6:03 AM", "On Site: 1 h 05 min"])
        #expect(rows(record(arrived: nil, left: at(6, 3))) == ["Arrived: Not caught", "Left: 6:03 AM"])
        #expect(rows(record(arrived: at(4, 58), left: nil)) == ["Arrived: 4:58 AM", "Left: Not caught"])
        // A job GPS never saw (logged by hand, location off) has no rows:
        // nothing says "not caught" about work GPS was never watching.
        #expect(rows(record(arrived: nil, left: nil)).isEmpty)
    }

    // MARK: - Minutes on Site

    @Test func minutesAreReadOrRefused() {
        let us = Locale(identifier: "en_US")
        #expect(ServiceLog.readMinutes("", locale: us) == 0)
        #expect(ServiceLog.readMinutes("   ", locale: us) == 0)
        #expect(ServiceLog.readMinutes("45", locale: us) == 45)
        #expect(ServiceLog.readMinutes(" 45 ", locale: us) == 45)
        #expect(ServiceLog.readMinutes("0", locale: us) == 0)
        #expect(ServiceLog.readMinutes("12.5", locale: us) == 12.5)
        // Was silently 0 before: now the screen says so and won't save.
        #expect(ServiceLog.readMinutes("45 min", locale: us) == nil)
        #expect(ServiceLog.readMinutes("1:30", locale: us) == nil)
        #expect(ServiceLog.readMinutes("abc", locale: us) == nil)
        #expect(ServiceLog.readMinutes("-5", locale: us) == nil)
        #expect(ServiceLog.readMinutes("nan", locale: us) == nil)
        #expect(ServiceLog.readMinutes("inf", locale: us) == nil)
        #expect(ServiceLog.readMinutes("9999", locale: us) == 9999)
        #expect(ServiceLog.readMinutes("10000", locale: us) == nil)
    }

    @Test func aDecimalCommaIsReadWhereTheRegionWritesOne() {
        #expect(ServiceLog.readMinutes("12,5", locale: Locale(identifier: "fr_FR")) == 12.5)
        // Elsewhere a comma separates thousands: not guessed at.
        #expect(ServiceLog.readMinutes("12,5", locale: Locale(identifier: "en_US")) == nil)
    }

    @Test func bothMinutesFieldsReadThroughOneFunction() throws {
        for file in ["ServiceRecordDetailView.swift", "LogWorkView.swift"] {
            let text = try source("ServiceLog/\(file)")
            #expect(text.contains("ServiceLog.readMinutes(minutes)"), "\(file)")
            #expect(text.contains("ServiceLog.unreadableMinutesMessage"), "\(file)")
            #expect(!text.contains("Double(minutes"), "\(file) reads minutes on its own")
        }
        let detail = try source("ServiceLog/ServiceRecordDetailView.swift")
        #expect(detail.contains("cantSaveMessage: cantSaveMessage"))
        // GPS's times are shown, never bound to a control.
        #expect(!detail.contains("$record.arrivedAt") && !detail.contains("$record.leftAt"))
        #expect(!detail.contains("record.arrivedAt =") && !detail.contains("record.leftAt ="))
    }

    // MARK: - The Service Report from the client page

    @Test func theServiceReportIsAProFeature() {
        #expect(ProGate.serviceReport(Access(plan: .pro, clientCount: 50)) == nil)
        #expect(ProGate.serviceReport(Access(plan: .free, clientCount: 3)) == .proFeature("The Service Report"))
        #expect(ProGate.serviceReport(Access(plan: .lapsed, clientCount: 11)) == .readOnly)
    }

    @Test func bothWaysInGoThroughTheGate() throws {
        for file in ["Clients/EditClientView.swift", "ServiceLog/ClientServiceHistoryView.swift"] {
            let text = try source(file)
            #expect(text.contains("$gate.unless(ProGate.serviceReport(access))"), "\(file)")
            #expect(text.contains("ProofOfServiceView(client: client)"), "\(file)")
            #expect(text.contains(".proGateSheet($gate)"), "\(file)")
        }
    }

    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PlowR/Views/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
