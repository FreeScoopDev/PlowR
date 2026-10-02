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
    /// A contract client and their trigger.
    struct Trigger: Equatable, Identifiable {
        var clientID: String
        var clientName: String
        var inches: Double
        var id: String { clientID }
    }

    struct Storm: Equatable {
        var day: Date
        /// The forecast snowfall that day.
        var inches: Double
        /// Clients whose trigger the forecast reaches, and those it doesn't.
        var met: [Trigger]
        var notMet: [Trigger]
    }

    /// Without a contract trigger, the forecast that counts as a storm for a
    /// business with snow services.
    static let defaultThreshold = 1.0
    /// Today and the next two days.
    static let daysAhead = 3

    /// The storm in `days`, if any. Contracts count when signed, with a
    /// trigger, and in force that day; each client once, at their lowest
    /// trigger. A business with no contract trigger counts a storm from
    /// `defaultThreshold`, and only if it offers a snow service at all.
    static func storm(in days: [DayForecast], contracts: [Contract], operatorID: String, offersSnow: Bool,
                      now: Date = .now, calendar: Calendar = .current) -> Storm? {
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
            let triggers = triggers(on: day.date, contracts: contracts, operatorID: operatorID, calendar: calendar)
            let threshold = triggers.map(\.inches).min() ?? (offersSnow ? defaultThreshold : .infinity)
            guard inches >= threshold else { continue }
            return Storm(day: day.date, inches: inches,
                         met: triggers.filter { inches >= $0.inches },
                         notMet: triggers.filter { inches < $0.inches })
        }
        return nil
    }

    /// Whether the business offers an active snow service.
    static func offersSnow(_ services: [ServiceItem], operatorID: String) -> Bool {
        let snow = ServiceCatalog.standardCategories.first?.key ?? "snow"
        return services.contains { $0.operatorID == operatorID && $0.isActive && $0.category == snow }
    }

    /// The clients with a contract trigger in force on `day`, by name.
    static func triggers(on day: Date, contracts: [Contract], operatorID: String,
                         calendar: Calendar = .current) -> [Trigger] {
        var lowest: [String: Trigger] = [:]
        for contract in contracts where contract.operatorID == operatorID && contract.triggerInches > 0 {
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

    /// The alert's line: "About 4 in of snow forecast Tuesday. 7 clients'
    /// contract triggers are at or below it."
    static func alertBody(_ storm: Storm) -> String {
        let day = storm.day.formatted(.dateTime.weekday(.wide))
        var body = "About \(amount(storm.inches)) of snow forecast \(day) for your area."
        let count = storm.met.count
        if count > 0 {
            body += " \(count) client\(count == 1 ? "'s" : "s'") contract trigger\(count == 1 ? " is" : "s are") at or below it."
        }
        return body + " Review your routes."
    }
}
