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
    func scheduleWeatherAlert(for forecasts: [DayForecast]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weather_alert"])

        guard let alertDay = adverseForecastDay(from: forecasts) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Weather Alert"
        let dayName = alertDay.date.formatted(.dateTime.weekday(.wide))
        content.body = "\(alertDay.description) expected \(dayName). Review your schedule."
        content.sound = .default

        guard let alertDate = Calendar.current.date(byAdding: .day, value: -1, to: alertDay.date) else { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: alertDate)
        components.hour = 18
        components.minute = 0
        guard let fireDate = Calendar.current.date(from: components), fireDate > Date() else { return }

        _ = fireDate
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: "weather_alert", content: content, trigger: trigger))
    }

    /// Schedule or cancel a repeating daily 9 AM overdue invoice reminder.
    func scheduleOverdueReminder(count: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["overdue_invoices"])
        guard count > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Overdue Invoices"
        content.body = Self.overdueBody(count: count)
        content.sound = .default

        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: "overdue_invoices", content: content, trigger: trigger))
    }
}
