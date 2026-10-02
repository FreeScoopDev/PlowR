import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    private let adverseCodes: Set<Int> = [
        61, 63, 65, 66, 67,         // rain / freezing rain
        71, 73, 75, 77, 85, 86,     // snow / snow showers
        80, 81, 82,                  // heavy showers
        95, 96, 99                   // thunderstorms
    ]

    /// Returns the first forecast day in the next 2 days (excluding today) that has adverse conditions.
    func adverseForecastDay(from forecasts: [DayForecast]) -> DayForecast? {
        forecasts.dropFirst().prefix(2).first { adverseCodes.contains($0.weatherCode) }
    }

    /// Formats the overdue invoice notification body text.
    static func overdueBody(count: Int) -> String {
        "\(count) invoice\(count == 1 ? "" : "s") past due — follow up in PlowR."
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { _, _ in }
    }

    /// Schedule a weather alert if adverse conditions (snow, heavy rain, storms) are
    /// forecast in the next 2 days. Fires the evening before at 6 PM.
    /// Works for snow removal, lawn care, and any outdoor service industry.
    func scheduleWeatherAlert(for forecasts: [DayForecast], storm: StormWatch.Storm? = nil) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weather_alert"])
        if let request = weatherAlertRequest(for: forecasts, storm: storm) { center.add(request) }
    }

    /// The weather alert for `forecasts`: 6 PM the evening before the first
    /// adverse day in the next two, or nil if there's none or that evening has
    /// passed. A storm (StormWatch) after today speaks for its own day, with
    /// its snowfall and contract triggers; an adverse day before it (freezing
    /// rain tomorrow, the storm the day after) keeps its own alert, the
    /// earlier warning. Under an inch, a storm alerts only on a day already
    /// adverse. A value, so a test can check when it fires.
    func weatherAlertRequest(for forecasts: [DayForecast], storm: StormWatch.Storm? = nil, now: Date = Date(),
                             calendar: Calendar = .current) -> UNNotificationRequest? {
        let today = calendar.startOfDay(for: now)
        let adverse = adverseForecastDay(from: forecasts)
        var upcomingStorm = storm.flatMap { calendar.startOfDay(for: $0.day) > today ? $0 : nil }
        // A flurry reaching an "Every snowfall" contract shows on the card;
        // an evening alert takes a real storm: an inch, or a day the
        // forecast already calls adverse. Otherwise it's ignored for its noise.
        if let small = upcomingStorm, small.inches < StormWatch.defaultThreshold,
           !forecasts.contains(where: { calendar.isDate($0.date, inSameDayAs: small.day)
               && adverseCodes.contains($0.weatherCode) }) {
            upcomingStorm = nil
        }
        if let stormDay = upcomingStorm?.day, let adverseDay = adverse?.date,
           calendar.startOfDay(for: adverseDay) < calendar.startOfDay(for: stormDay) {
            upcomingStorm = nil
        }
        guard let alertDate = upcomingStorm?.day ?? adverse?.date,
              let evenBefore = calendar.date(byAdding: .day, value: -1, to: alertDate) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: evenBefore)
        components.hour = 18
        components.minute = 0
        guard let fireDate = calendar.date(from: components), fireDate > now else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "Weather Alert"
        if let upcomingStorm {
            content.body = StormWatch.alertBody(upcomingStorm)
        } else if let alertDay = adverse {
            let dayName = alertDay.date.formatted(.dateTime.weekday(.wide))
            content.body = "\(alertDay.description) expected \(dayName). Review your schedule."
        }
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: "weather_alert", content: content, trigger: trigger)
    }

    /// Schedule or cancel a repeating daily 9 AM overdue invoice reminder.
    func scheduleOverdueReminder(count: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["overdue_invoices"])
        if let request = Self.overdueReminderRequest(count: count) { center.add(request) }
    }

    /// The daily 9 AM reminder for `count` overdue invoices, or nil when none
    /// are overdue: then the old reminder is only cancelled, never replaced.
    static func overdueReminderRequest(count: Int) -> UNNotificationRequest? {
        guard count > 0 else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "Overdue Invoices"
        content.body = overdueBody(count: count)
        content.sound = .default
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(identifier: "overdue_invoices", content: content, trigger: trigger)
    }
}
