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
/// Every date is counted from the series' first visit, which fixes its time of
/// day and day of month: a series doesn't slide to 3 AM after a daylight-saving
/// change, or from the 31st to the 28th after February.
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

    /// A visit already in a series, as far as continuing the series goes.
    struct SeriesVisit: Equatable {
        var date: Date
        /// Still to do (not completed, skipped or cancelled).
        var isScheduled: Bool
    }

    /// `start` and the occurrences after it, up to `limit` dates and not past
    /// `horizon`.
    func occurrences(from start: Date, limit: Int = upFrontLimit, horizon: Date? = nil,
                     calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        for date in stream(from: start, calendar: calendar) {
            if let horizon, date > horizon { break }
            dates.append(date)
            if dates.count >= limit { break }
        }
        return dates
    }

    /// The first occurrence after `latest`, counting from the series' first
    /// visit on `start`; nil past the end date.
    func firstOccurrence(after latest: Date, seriesStart start: Date, calendar: Calendar) -> Date? {
        stream(from: start, calendar: calendar).first { $0 > latest }
    }

    /// When a series should get another visit, after the one on `completed` is
    /// completed: only when nothing after it is still scheduled, and then on the
    /// first occurrence after the series' latest visit, whatever that visit's
    /// state. So a series created up front isn't given a duplicate, a skipped
    /// last visit doesn't end the series, and a visit already in the series,
    /// skipped or not, is never created again.
    func continuationDate(afterCompleting completed: Date, series: [SeriesVisit],
                          calendar: Calendar) -> Date? {
        guard !series.contains(where: { $0.isScheduled && $0.date > completed }) else { return nil }
        let dates = series.map(\.date) + [completed]
        guard let start = dates.min(), let latest = dates.max() else { return nil }
        return firstOccurrence(after: latest, seriesStart: start, calendar: calendar)
    }

    // MARK: - Private

    /// Every occurrence from `start` on, lazily, ending at the end date. Fixed
    /// steps are counted from `start` (k × step); weekday rules walk the chosen
    /// days, taking the time of day from `start`.
    private func stream(from start: Date, calendar: Calendar) -> AnySequence<Date> {
        let step = max(1, interval)
        let days = weekdays.filter { (1...7).contains($0) }.sorted()
        return AnySequence { () -> AnyIterator<Date> in
            var k = 0
            var previous: Date?
            var produced = 0
            return AnyIterator {
                // A safety stop: no series needs more than this many look-aheads.
                guard produced < 20_000 else { return nil }
                let candidate: Date?
                if k == 0 {
                    candidate = start
                } else {
                    switch type {
                    case .daily:    candidate = calendar.date(byAdding: .day, value: step * k, to: start)
                    case .monthly:  candidate = calendar.date(byAdding: .month, value: step * k, to: start)
                    case .biweekly: candidate = calendar.date(byAdding: .day, value: 14 * k, to: start)
                    case .weekly where days.isEmpty:
                        candidate = calendar.date(byAdding: .day, value: 7 * step * k, to: start)
                    case .weekly:
                        candidate = previous.flatMap {
                            nextWeekday(after: $0, days: days, everyWeeks: step, timeFrom: start, calendar: calendar)
                        }
                    }
                }
                k += 1
                guard let date = candidate, isOnOrBeforeEnd(date, calendar: calendar) else { return nil }
                previous = date
                produced += 1
                return date
            }
        }
    }

    private func nextWeekday(after date: Date, days: [Int], everyWeeks step: Int, timeFrom source: Date,
                             calendar: Calendar) -> Date? {
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
        return target.flatMap { atTimeOfDay(of: source, on: $0, calendar: calendar) }
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
