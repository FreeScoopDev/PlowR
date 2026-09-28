import Foundation

/// When a repeating visit happens: the one rule both for creating a series and
/// for continuing one.
///
/// There used to be two rules. Add Visit generated a series with its own date
/// arithmetic, which ignored the chosen weekdays (weekly on Mon and Thu from a
/// Wednesday gave 52 Wednesdays). Completing a visit then added "the next one"
/// with the model's rule, even though the series already had it, so every
/// completion left a duplicate. The model's rule also put a visit that wrapped
/// to the next week at midnight, and skipped the week's other days when repeating
/// every 2 or more weeks.
///
/// Weeks run Sunday to Saturday, as in the weekday picker, whatever the device's
/// locale; weekdays are numbered 1 (Sunday) to 7 (Saturday).
///
/// `nonisolated`: plain date arithmetic, used from views, the model and tests.
nonisolated struct RecurrenceRule: Equatable {
    var type: RecurrenceType
    /// Every `interval` days, weeks or months. Ignored for `.biweekly`.
    var interval: Int = 1
    /// For `.weekly`: the days of the week it happens on. Empty means the start date's weekday.
    var weekdays: Set<Int> = []
    /// Last day of the series, inclusive: an occurrence any time that day counts.
    var endDate: Date?

    /// No more than this many visits are created up front.
    static let upFrontLimit = 52
    /// ...and none further ahead than this.
    static let upFrontHorizon = DateComponents(year: 2)

    /// The next occurrence after `date`, at the same time of day, or nil past the end date.
    func next(after date: Date, calendar: Calendar) -> Date? {
        let step = max(1, interval)
        let candidate: Date?
        switch type {
        case .daily:
            candidate = calendar.date(byAdding: .day, value: step, to: date)
        case .monthly:
            candidate = calendar.date(byAdding: .month, value: step, to: date)
        case .biweekly:
            candidate = calendar.date(byAdding: .day, value: 14, to: date)
        case .weekly where weekdays.isEmpty:
            candidate = calendar.date(byAdding: .day, value: 7 * step, to: date)
        case .weekly:
            candidate = nextWeekday(after: date, everyWeeks: step, calendar: calendar)
        }
        guard let candidate, isOnOrBeforeEnd(candidate, calendar: calendar) else { return nil }
        return candidate
    }

    /// `start` and the occurrences after it, up to `limit` dates and not past
    /// `horizon`. Fixed steps are counted from `start` rather than from the
    /// previous date, so a series starting on the 31st isn't pulled to the 28th
    /// for good after February.
    func occurrences(from start: Date, limit: Int = upFrontLimit, horizon: Date? = nil,
                     calendar: Calendar) -> [Date] {
        var dates = [start]
        let step = max(1, interval)
        while dates.count < limit {
            let k = dates.count
            let candidate: Date?
            switch type {
            case .daily:    candidate = calendar.date(byAdding: .day, value: step * k, to: start)
            case .monthly:  candidate = calendar.date(byAdding: .month, value: step * k, to: start)
            case .biweekly: candidate = calendar.date(byAdding: .day, value: 14 * k, to: start)
            case .weekly where weekdays.isEmpty:
                candidate = calendar.date(byAdding: .day, value: 7 * step * k, to: start)
            case .weekly:
                candidate = dates.last.flatMap { nextWeekday(after: $0, everyWeeks: step, calendar: calendar) }
            }
            guard let next = candidate, isOnOrBeforeEnd(next, calendar: calendar) else { break }
            if let horizon, next > horizon { break }
            dates.append(next)
        }
        return dates
    }

    /// Whether completing a visit should add the series' next one: only when the
    /// series has nothing scheduled after it (it has run out). A series created
    /// up front already has its next visit, and one the user deleted stays deleted.
    static func shouldAddNext(afterCompleting date: Date, seriesDates: [Date]) -> Bool {
        !seriesDates.contains { $0 > date }
    }

    // MARK: - Private

    private func nextWeekday(after date: Date, everyWeeks step: Int, calendar: Calendar) -> Date? {
        let days = weekdays.filter { (1...7).contains($0) }.sorted()
        guard let first = days.first else { return nil }
        let weekday = calendar.component(.weekday, from: date)
        let dayStart = calendar.startOfDay(for: date)
        let target: Date?
        if let later = days.first(where: { $0 > weekday }) {
            // Another of the chosen days later this same week.
            target = calendar.date(byAdding: .day, value: later - weekday, to: dayStart)
        } else {
            // The first chosen day of the week `step` weeks on (weeks start on Sunday).
            let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: dayStart)
            target = sunday.flatMap { calendar.date(byAdding: .day, value: 7 * step + (first - 1), to: $0) }
        }
        return target.flatMap { atTimeOfDay(of: date, on: $0, calendar: calendar) }
    }

    private func atTimeOfDay(of source: Date, on day: Date, calendar: Calendar) -> Date? {
        let time = calendar.dateComponents([.hour, .minute, .second], from: source)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                             second: time.second ?? 0, of: day)
    }

    private func isOnOrBeforeEnd(_ date: Date, calendar: Calendar) -> Bool {
        guard let endDate else { return true }
        guard let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) else {
            return date <= endDate
        }
        return date < dayAfterEnd
    }
}
