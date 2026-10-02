import Foundation

/// A storm coming for the snow business: the first day, today or in the next
/// two, whose forecast snowfall reaches a trigger, and the clients whose
/// contract trigger it reaches. The Dashboard's storm card and the evening
/// alert both use it.
///
/// It's a forecast for the phone's area (the weather model's estimate for
/// the whole day), not a measurement at each property: every screen says so,
/// and it only offers the route and the texts. Nothing is started or sent
/// by itself.
enum StormWatch {
    /// A contract client and their trigger. 0 is "Every snowfall", as the
    /// contract's own page says it.
    struct Trigger: Equatable, Identifiable {
        var clientID: String
        var clientName: String
        var inches: Double
        var id: String { clientID }

        /// The forecast that reaches it: "every snowfall" is any measurable one.
        var reachedFrom: Double { max(inches, StormWatch.measurable) }
        /// "2 in or more", "Every snowfall".
        var label: String { inches > 0 ? "\(StormWatch.amount(inches)) or more" : "Every snowfall" }
    }

    struct Storm: Equatable {
        var day: Date
        /// The forecast snowfall that day.
        var inches: Double
        /// Clients whose trigger the forecast reaches, and those it doesn't.
        var met: [Trigger]
        var notMet: [Trigger]
        /// Clients marked below their trigger that day (TriggerCheck), at every
        /// place under a snow contract: less fell there than the forecast
        /// said. Neither of the above.
        var markedBelow: [Trigger] = []
        /// Of those, clients with a check made at the stop: the card can't
        /// take that mark off (the contract's page can).
        var checkedAtStop: Set<String> = []
    }

    /// Without a contract trigger, the forecast that counts as a storm for a
    /// business with snow services.
    static let defaultThreshold = 1.0
    /// The least snowfall that counts as any: a tenth of an inch, as shown.
    static let measurable = 0.1
    /// Today and the next two days.
    static let daysAhead = 3

    /// What a storm is measured against: the business's contracts, its
    /// services (which say whether a contract covers snow, and whether the
    /// business offers it at all) and its active clients.
    struct Book {
        var contracts: [Contract]
        var services: [ServiceItem]
        /// Active clients' IDs (uuidString): a deleted or inactive client's
        /// contract, kept as a record, isn't waiting on a storm.
        var activeClientIDs: Set<String>
        var operatorID: String
        /// Days marked below trigger (TriggerCheck).
        var checks: [TriggerCheck] = []
    }

    /// The storm in `days`, if any. A contract counts when it's for snow
    /// (a snow service, or a trigger), signed, in force that day, and for an
    /// active client; each client once, at their lowest trigger. Without any,
    /// a business offering a snow service counts a storm from
    /// `defaultThreshold`; one that doesn't, never.
    static func storm(in days: [DayForecast], book: Book, now: Date = .now,
                      calendar: Calendar = .current) -> Storm? {
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: daysAhead, to: today) else { return nil }
        let ahead = days
            .filter { calendar.startOfDay(for: $0.date) >= today && $0.date < end }
            .sorted { $0.date < $1.date }
        for day in ahead {
            // To a tenth, as it's shown: "1.9 in" must not meet a 2 in trigger
            // while reading "2 in".
            guard let raw = day.snowfallInches, raw > 0 else { continue }
            let inches = (raw * 10).rounded() / 10
            let triggers = triggers(on: day.date, book: book, calendar: calendar)
            let offersSnow = offersSnow(book.services, operatorID: book.operatorID)
            let threshold = triggers.map(\.reachedFrom).min() ?? (offersSnow ? defaultThreshold : .infinity)
            guard inches >= threshold else { continue }
            let checks = book.checks.filter { $0.operatorID == book.operatorID }
            let marked = Set(triggers.map(\.clientID).filter {
                TriggerChecks.isClientMarked($0, on: day.date, contracts: book.contracts, services: book.services,
                                             in: checks, calendar: calendar)
            })
            let open = triggers.filter { !marked.contains($0.clientID) }
            return Storm(day: day.date, inches: inches,
                         met: open.filter { inches >= $0.reachedFrom },
                         notMet: open.filter { inches < $0.reachedFrom },
                         markedBelow: triggers.filter { marked.contains($0.clientID) },
                         checkedAtStop: Set(marked.filter {
                             TriggerChecks.hasStopCheck($0, on: day.date, in: checks, calendar: calendar)
                         }))
        }
        return nil
    }

    /// Whether the business offers an active snow service.
    static func offersSnow(_ services: [ServiceItem], operatorID: String) -> Bool {
        services.contains { $0.operatorID == operatorID && $0.isActive && $0.category == ServiceCatalog.snowKey }
    }

    /// The clients with a contract trigger in force on `day`, by name.
    static func triggers(on day: Date, book: Book, calendar: Calendar = .current) -> [Trigger] {
        var lowest: [String: Trigger] = [:]
        for contract in book.contracts where contract.operatorID == book.operatorID
            && book.activeClientIDs.contains(contract.clientID)
            && (contract.triggerInches > 0
                || Contracts.coversSnow(Set(contract.serviceIDs), catalog: book.services)) {
            guard contract.placeIDs.contains(where: {
                Contracts.covers(contract, placeID: $0, on: day, calendar: calendar)
            }) else { continue }
            let trigger = Trigger(clientID: contract.clientID, clientName: contract.clientName,
                                  inches: contract.triggerInches)
            if let kept = lowest[contract.clientID], kept.inches <= trigger.inches { continue }
            lowest[contract.clientID] = trigger
        }
        return lowest.values.sorted {
            $0.clientName.localizedCaseInsensitiveCompare($1.clientName) == .orderedAscending
        }
    }

    /// "4 in", "1.5 in", "0.6 in".
    static func amount(_ inches: Double) -> String {
        "\(((inches * 10).rounded() / 10).formatted(.number.precision(.fractionLength(0...1)))) in"
    }

    /// "Today", "Tomorrow" or the weekday.
    static func dayName(_ day: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(day, inSameDayAs: tomorrow) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    /// The alert's line. Said as of when PlowR last looked: the alert is set
    /// then, and the forecast can change before it shows.
    static func alertBody(_ storm: Storm) -> String {
        let day = storm.day.formatted(.dateTime.weekday(.wide))
        var body = "When PlowR last checked, about \(amount(storm.inches)) of snow was forecast \(day) for your area."
        let count = storm.met.count
        if count > 0 {
            body += " That reaches \(count) client\(count == 1 ? "'s" : "s'") contract trigger\(count == 1 ? "" : "s")."
        }
        return body + " Open PlowR for the latest."
    }
}
