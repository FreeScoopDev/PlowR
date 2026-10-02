import Foundation
import SwiftData
import UIKit

/// The Service Report: the work done at one of a client's places over a
/// period, visit by visit, with what PlowR recorded about each, the
/// services, notes and photos. What a contractor hands an insurer or a
/// lawyer after a slip-and-fall claim, or a client who disputes a bill.
/// Read from the Service Log (ServiceRecord) and the job photos (StopPhoto).
///
/// Every statement in it is only what PlowR actually recorded, said for
/// what it is, because a document for a claim is worthless the moment one
/// line of it is shown to overstate:
/// - A visit's times are printed only for a route stop, which PlowR timed:
///   "started" is when the stop became the current one (the route started,
///   or the stop before it was completed), so it includes the travel there;
///   "completed" is when it was marked done. A visit completed from the
///   Schedule, or logged by hand, has no time PlowR recorded, and says so.
/// - Each visit says where its record came from (route, Schedule, by hand),
///   and that times can be edited in PlowR.
/// - A photo shows when it was taken only when PlowR knows it (taken with
///   its camera, or a library photo's EXIF time), and its date when that
///   isn't the visit's day. Older photos were stamped when they were saved,
///   not taken, so they show no time.
/// - The address is the one the work was recorded at, not today's.
enum ProofOfService {
    static let title = "SERVICE REPORT"

    /// A period to report on.
    struct Period: Hashable, Identifiable {
        var label: String
        var start: Date
        var end: Date
        var id: String { "\(label)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)" }
    }

    /// The periods offered for a place: each signed contract covering it
    /// that has begun (its season so far, to the day it ended or was
    /// cancelled), the last 30 days, and this year.
    static func periods(for client: Client, placeID: String, now: Date = .now,
                        calendar: Calendar = .current) -> [Period] {
        let contracts = (client.contracts ?? [])
            .filter { $0.signedAt != nil && $0.placeIDs.contains(placeID) && $0.startDate <= now }
            .sorted { $0.startDate > $1.startDate }
            .map { contract in
                Period(label: contract.name, start: contract.startDate,
                       end: min(contract.endDate, contract.cancelledAt ?? contract.endDate, now))
            }
        let today = calendar.startOfDay(for: now)
        let thirty = Period(label: "Last 30 Days", start: calendar.date(byAdding: .day, value: -29, to: today) ?? today, end: now)
        let year = Period(label: "This Year",
                          start: calendar.dateInterval(of: .year, for: now)?.start ?? today, end: now)
        return contracts + [thirty, year]
    }

    /// A place work can be reported on: one of the client's (active or not),
    /// or one only their records name now (removed since), with the address
    /// the work was recorded at.
    struct ReportPlace: Identifiable, Equatable {
        let id: String
        let label: String
        let address: String
        /// Its pin, for the weather; none for a place only records name.
        var latitude: Double = 0
        var longitude: Double = 0
    }

    /// The client's places, then any their records name that isn't one any
    /// more: a property made inactive or removed after the season is the one
    /// a claim is most likely about.
    static func places(of client: Client, in context: ModelContext) -> [ReportPlace] {
        var places = Place.all(of: client).map {
            ReportPlace(id: $0.id, label: $0.isMain ? "Main Address" : $0.label, address: $0.address,
                        latitude: $0.latitude, longitude: $0.longitude)
        }
        for property in Place.ordered(client.properties ?? []) where !places.contains(where: { $0.id == property.id.uuidString }) {
            let place = Place.of(property)
            places.append(ReportPlace(id: place.id, label: "\(place.label) (inactive)", address: place.address,
                                      latitude: place.latitude, longitude: place.longitude))
        }
        let records = ServiceLog.records(ofClient: client.id.uuidString, in: context)
        for record in records {
            let id = Place.id(of: client, propertyID: record.propertyID)
            guard !places.contains(where: { $0.id == id }) else { continue }
            places.append(ReportPlace(id: id, label: "\(record.propertyAddress.isEmpty ? "Former property" : record.propertyAddress) (removed)",
                                      address: record.propertyAddress))
        }
        return places
    }

    /// One visit: a job in the Service Log and its photos.
    struct Visit: Identifiable {
        let record: ServiceRecord
        let photos: [StopPhoto]
        var id: UUID { record.id }
    }

    /// A day marked below the contract's snow trigger (TriggerCheck), and
    /// its photos.
    struct Check: Identifiable {
        let check: TriggerCheck
        let photos: [StopPhoto]
        var id: UUID { check.id }
    }

    /// The days at `placeID` marked below the contract's trigger in
    /// `start…end`, oldest first, one per day: a check at the stop over a
    /// mark by hand (it's PlowR's record of being there), then the earliest.
    static func checks(of client: Client, placeID: String, from start: Date, to end: Date,
                       in context: ModelContext, calendar: Calendar = .current) -> [Check] {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        let inPeriod = TriggerChecks.of(clientID: client.id.uuidString, in: context).filter {
            let day = calendar.startOfDay(for: $0.day)
            return $0.placeID == placeID && day >= first && day <= last
        }
        return Dictionary(grouping: inPeriod) { calendar.startOfDay(for: $0.day) }
            .values.compactMap { sameDay in
                sameDay.min { ($0.isFromStop ? 0 : 1, $0.checkedAt) < ($1.isFromStop ? 0 : 1, $1.checkedAt) }
            }
            .sorted { $0.day < $1.day }
            .map { Check(check: $0, photos: TriggerChecks.photos(of: $0, in: context)) }
    }

    /// What the report says about a day below the trigger, line by line.
    static func lines(of check: Check, timeZone: TimeZone = .current, locale: Locale = .current) -> [String] {
        let check = check.check
        var time = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        time.timeZone = timeZone
        var lines: [String]
        if check.isFromStop {
            lines = ["Checked on a route at \(check.checkedAt.formatted(time)): below the contract's snow trigger, "
                     + "not cleared"]
            lines.append(check.arrivedAt.map { "Arrived \($0.formatted(time)) (GPS, within about 100 m)" }
                         ?? "Arrival not caught (GPS)")
            if !check.routeName.isEmpty { lines.append("Route: \(check.routeName)") }
        } else {
            var when = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute().locale(locale)
            when.timeZone = timeZone
            lines = ["Marked below the contract's snow trigger by hand (\(check.checkedAt.formatted(when))); "
                     + "not a check at the property recorded by PlowR"]
        }
        if !check.note.isEmpty { lines.append("Notes: \(check.note)") }
        return lines
    }

    /// The jobs at `placeID` (Place.id) whose day (the day each started)
    /// falls in `start…end`, whole days, oldest first, with their photos.
    /// The same job recorded on two devices before iCloud merged them is
    /// listed once (the oldest copy, as the merge keeps).
    static func visits(of client: Client, placeID: String, from start: Date, to end: Date,
                       in context: ModelContext, calendar: Calendar = .current) -> [Visit] {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        let inPeriod = ServiceLog.records(ofClient: client.id.uuidString, in: context).filter { record in
            let day = calendar.startOfDay(for: record.startedAt ?? record.performedAt)
            return Place.id(of: client, propertyID: record.propertyID) == placeID && day >= first && day <= last
        }
        let records = Dictionary(grouping: inPeriod) { $0.sourceKey.isEmpty ? $0.id.uuidString : $0.sourceKey }
            .values.compactMap { ServiceLog.oldest($0) }
            .sorted { ($0.startedAt ?? $0.performedAt) < ($1.startedAt ?? $1.performedAt) }
        let clientID = client.id.uuidString
        let photos = (try? context.fetch(FetchDescriptor<StopPhoto>(predicate: #Predicate { $0.clientID == clientID }))) ?? []
        let byRecord = Dictionary(grouping: photos.filter { !$0.recordID.isEmpty }, by: \.recordID)
        return records.map { record in
            Visit(record: record, photos: StopPhoto.ordered(byRecord[record.id.uuidString] ?? []))
        }
    }

    /// Where a visit's record came from, as the report says it.
    static func source(of record: ServiceRecord) -> String {
        switch record.source {
        case .route: "Tracked on a route"
        case .visit: "Completed from the Schedule"
        case .manual: "Logged by hand"
        case .beforeLog: "Completed from the Schedule (before the Service History)"
        }
    }

    /// A visit's times, only where PlowR recorded them: a route stop's
    /// start (including the travel there) and completion. In the phone's
    /// own clock style.
    static func times(of record: ServiceRecord, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        guard record.source == .route, let started = record.startedAt else { return "Time not recorded by PlowR" }
        var time = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        time.timeZone = timeZone
        var text = "Started \(started.formatted(time)) · Completed \(record.performedAt.formatted(time))"
        if record.minutes >= 1 { text += " · \(Int(record.minutes.rounded())) min, including travel" }
        return text
    }

    /// A route stop's arrival and departure as GPS saw them, if it saw
    /// either; nil if it saw neither.
    static func siteTimes(of record: ServiceRecord, timeZone: TimeZone = .current,
                          locale: Locale = .current) -> String? {
        guard record.arrivedAt != nil || record.leftAt != nil else { return nil }
        var time = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        time.timeZone = timeZone
        let arrived = record.arrivedAt.map { "Arrived \($0.formatted(time))" } ?? "Arrival not caught"
        let left = record.leftAt.map { "Left \($0.formatted(time))" } ?? "Departure not caught"
        return "\(arrived) · \(left) (GPS, within about 100 m)"
    }

    /// What the report says about a visit, line by line (also what tests read).
    static func lines(of visit: Visit, placeAddress: String, timeZone: TimeZone = .current,
                      locale: Locale = .current) -> [String] {
        let record = visit.record
        var lines = [times(of: record, timeZone: timeZone, locale: locale)]
        if let site = siteTimes(of: record, timeZone: timeZone, locale: locale) { lines.append(site) }
        lines.append(source(of: record))
        if !record.propertyAddress.isEmpty, record.propertyAddress != placeAddress {
            lines.append("At \(record.propertyAddress)")
        }
        let services = record.lines.map(\.name)
        lines.append(services.isEmpty ? "No services recorded" : services.joined(separator: ", "))
        if !record.routeName.isEmpty { lines.append("Route: \(record.routeName)") }
        if !record.notes.isEmpty { lines.append("Notes: \(record.notes)") }
        return lines
    }

    /// A photo's caption: before or after, and its time where known, said
    /// for where it came from: "taken" by PlowR's camera, or "file dated"
    /// for a library photo (a date that can be changed), "zone assumed"
    /// when the file gave none. The date and year too when it isn't the
    /// visit's day, so a photo from another storm or another year can't
    /// pass as this visit's.
    static func caption(of photo: StopPhoto, visitDay: Date, timeZone: TimeZone = .current,
                        locale: Locale = .current, calendar: Calendar = .current) -> String {
        let kind = photo.kindLabel
        guard let taken = photo.capturedAt else { return kind }
        var time = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        time.timeZone = timeZone
        var day = Date.FormatStyle.dateTime.month(.abbreviated).day().year().locale(locale)
        day.timeZone = timeZone
        let when = calendar.isDate(taken, inSameDayAs: visitDay)
            ? taken.formatted(time) : "\(taken.formatted(day)) \(taken.formatted(time))"
        switch photo.captureSource {
        case .camera: return "\(kind), taken \(when)"
        case .fileAssumedZone: return "\(kind), file dated \(when) (zone assumed)"
        case .file, nil: return "\(kind), file dated \(when)"
        }
    }

    /// The note at the end: what the times and photos are, and the zone.
    static func note(withWeather: Bool = false, withChecks: Bool = false, timeZone: TimeZone = .current) -> String {
        let zone = timeZone.localizedName(for: .generic, locale: .current) ?? timeZone.identifier
        let weather = withWeather
            ? " Weather figures are estimates from a weather model (Open-Meteo's historical forecast archive, "
                + "open-meteo.com) for the area within about 1 km: whole-day totals, before and after the visit, not "
                + "measurements at the property, and not available before 2022 or for today."
            : ""
        let checksNote = withChecks
            ? " A day below the contract's snow trigger was either checked on a route (Below Trigger saved on the "
                + "route screen at that stop; its GPS arrival, when caught, shows the phone was there) or marked by "
                + "hand, as each says."
            : ""
        return "About this report: it lists what was recorded in PlowR. A route stop's start is when it became the "
            + "current stop (the route started, or the previous stop was completed), so it includes travel; its "
            + "completion is when it was marked done. \"Arrived\" and \"Left\" are when the phone came into and "
            + "went out of an area about 100 m around the property's pin, as iOS reported it, which can be a few "
            + "minutes late; \"not caught\" means it wasn't seen (location off, or already inside when the stop "
            + "began). Visits completed from the Schedule or logged by hand have no "
            + "recorded time. Records can be edited in PlowR after the work. Photos are shown with the visit they "
            + "were saved with. \"Taken\" is when PlowR's camera took it. \"File dated\" is the date stored in a "
            + "photo picked from the library, which can be changed, and \"zone assumed\" means the file gave no "
            + "time zone, so it was read in the phone's. A photo with no time is one whose time PlowR doesn't "
            + "know, and isn't shown to be from that visit.\(checksNote)\(weather) Times are \(zone)."
    }

    /// The report.
    /// `weather`: the estimates (VisitWeather). Not looked up (no pin), the
    /// report leaves weather out; failed, it says so once instead of
    /// showing every day without an estimate.
    static func pdf(client: Client, place: ReportPlace, period: Period, visits: [Visit], checks: [Check] = [],
                    profile: BusinessProfile?, weather: VisitWeather.Lookup = .notLookedUp, now: Date = .now) -> Data {
        PDFPageWriter.document(profile: profile) { page in
            page.header(title: title, subtitle: client.name, profile: profile)
            let day = Date.FormatStyle.dateTime.month(.wide).day().year()
            page.heading("Property")
            page.text(place.address.isEmpty ? place.label : place.address, .systemFont(ofSize: 11), gap: 10)
            page.heading("Period")
            page.text("\(period.label): \(period.start.formatted(day)) to \(period.end.formatted(day))",
                      .systemFont(ofSize: 11), gap: 10)
            page.heading("Summary")
            page.text(visits.count == 1 ? "1 visit recorded" : "\(visits.count) visits recorded", .systemFont(ofSize: 11), gap: 2)
            if !checks.isEmpty {
                page.text(checks.count == 1 ? "1 day below the contract's snow trigger"
                          : "\(checks.count) days below the contract's snow trigger", .systemFont(ofSize: 11), gap: 2)
            }
            if weather == .failed {
                page.text("Weather: couldn't be looked up when this report was made.", .systemFont(ofSize: 11),
                          PDFGenerator.inkMid, gap: 2)
            }
            page.y += 12
            page.heading("Visits")
            if visits.isEmpty {
                page.text("No work recorded at this property in this period.", .systemFont(ofSize: 11), PDFGenerator.inkMid)
            }
            for visit in visits {
                page.keep(70)
                let date = (visit.record.startedAt ?? visit.record.performedAt)
                    .formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                page.text(date, .systemFont(ofSize: 12, weight: .semibold), gap: 2)
                for line in lines(of: visit, placeAddress: place.address) { page.text(line, .systemFont(ofSize: 10.5), gap: 2) }
                if case .days(let days) = weather {
                    let key = VisitWeather.dayString(visit.record.startedAt ?? visit.record.performedAt)
                    page.text(VisitWeather.line(days[key]), .systemFont(ofSize: 10.5), PDFGenerator.inkMid, gap: 2)
                }
                if !visit.photos.isEmpty {
                    page.y += 4
                    // One visit's photos in memory at a time.
                    autoreleasepool {
                        page.photos(visit.photos.compactMap { photo in
                            UIImage(data: photo.imageData).map {
                            (image: $0, caption: caption(of: photo, visitDay: visit.record.startedAt ?? visit.record.performedAt))
                        }
                        })
                    }
                }
                page.y += 10
            }
            if !checks.isEmpty {
                page.y += 6
                page.heading("Below the Contract's Snow Trigger")
            }
            for entry in checks {
                page.keep(60)
                page.text(entry.check.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()),
                          .systemFont(ofSize: 12, weight: .semibold), gap: 2)
                for line in lines(of: entry) { page.text(line, .systemFont(ofSize: 10.5), gap: 2) }
                if case .days(let days) = weather {
                    page.text(VisitWeather.line(days[VisitWeather.dayString(entry.check.day)]), .systemFont(ofSize: 10.5),
                              PDFGenerator.inkMid, gap: 2)
                }
                if !entry.photos.isEmpty {
                    page.y += 4
                    autoreleasepool {
                        page.photos(entry.photos.compactMap { photo in
                            UIImage(data: photo.imageData).map {
                                (image: $0, caption: caption(of: photo, visitDay: entry.check.day))
                            }
                        })
                    }
                }
                page.y += 10
            }
            page.y += 10
            page.keep(60)
            page.text(note(withWeather: weather != .notLookedUp, withChecks: !checks.isEmpty), .systemFont(ofSize: 9),
                      PDFGenerator.inkMid, gap: 2)
            page.text("Prepared with PlowR on \(now.formatted(day)).", .systemFont(ofSize: 9), PDFGenerator.inkMid)
        }
    }

    /// The shared file's name: "Service Report - Pat Smith - Winter 2026–27.pdf".
    static func fileName(client: Client, period: Period) -> String {
        let raw = "\(client.name) - \(period.label)"
        let safe = raw.map { "/\\:?*\"<>|".contains($0) ? "-" : $0 }
        return "Service Report - \(String(safe.prefix(80))).pdf"
    }
}
