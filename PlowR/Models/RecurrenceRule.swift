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
/// A new series is counted from its first visit, which fixes its time of day and
/// day of month: it doesn't slide to 3 AM after a daylight-saving change, or
/// from the 31st to the 28th after February. A series that runs out is continued
/// from its latest visits instead (see `continuationDate`).
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

    /// When a series should get another visit, after the one on `completed` is
    /// completed: only when nothing after it is still scheduled, and then one
    /// step after the series' latest visit, whatever that visit's state. So a
    /// series created up front isn't given a duplicate, a skipped last visit
    /// doesn't end the series, and a visit already in the series, skipped or
    /// not, is never created again.
    ///
    /// It steps from the latest visits, not the first, because they say what
    /// the series is now: "This & All Future" changes the time of later visits
    /// only, and "This Visit Only" can move the first. A one-off move of the
    /// last visit shouldn't move the series either, so:
    /// - the time of day is the one most of the latest three visits share
    ///   (ignoring days the clocks changed, where 2:30 AM became 3:00), and
    ///   the latest visit's on a three-way split;
    /// - a weekly or two-weekly series stays on the weekday most of its visits
    ///   fall on;
    /// - a monthly series keeps the day of month most of its visits fall on, so
    ///   February's 28th doesn't pull a 31st series along.
    ///
    /// The steps mirror `stream(from:)`, which creates a series; change both together.
    func continuationDate(afterCompleting completed: Date, series: [SeriesVisit],
                          calendar: Calendar) -> Date? {
        guard !series.contains(where: { $0.isScheduled && $0.date > completed }) else { return nil }
        let dates = (series.map(\.date) + [completed]).sorted()
        guard let latest = dates.last else { return nil }
        let timeSource = usualTimeOfDay(dates, calendar: calendar) ?? latest
        let step = max(1, interval)
        let day: Date?
        switch type {
        case .daily:    day = calendar.date(byAdding: .day, value: step, to: latest)
        case .biweekly:
            day = nextOnUsualWeekday(after: latest, dates: dates, stepDays: 14, calendar: calendar)
        case .weekly where weekdays.isEmpty:
            day = nextOnUsualWeekday(after: latest, dates: dates, stepDays: 7 * step, calendar: calendar)
        case .weekly:
            day = nextWeekday(after: latest, days: weekdays.filter { (1...7).contains($0) }.sorted(),
                              everyWeeks: step, timeFrom: timeSource, calendar: calendar)
        case .monthly:
            day = monthStep(after: latest, months: step,
                            dayOfMonth: usualDayOfMonth(dates, calendar: calendar), calendar: calendar)
        }
        guard let next = day.flatMap({ atTimeOfDay(of: timeSource, on: $0, calendar: calendar) }),
              calendar.startOfDay(for: next) > calendar.startOfDay(for: latest),
              isOnOrBeforeEnd(next, calendar: calendar) else { return nil }
        return next
    }

    // MARK: - Private

    /// Every occurrence from `start` on, lazily, ending at the end date. Fixed
    /// steps are counted from `start` (k × step); weekday rules walk the chosen
    /// days, taking the time of day from `start`. The steps mirror
    /// `continuationDate`, which extends a series; change both together.
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

    /// A day the clocks changed on: not 24 hours long.
    private func isClockChangeDay(_ date: Date, calendar: Calendar) -> Bool {
        guard let day = calendar.dateInterval(of: .day, for: date) else { return false }
        return day.duration != 86_400
    }

    /// The time of day most of the latest three visits share, not counting days
    /// the clocks changed, as a date carrying it; the latest's on a three-way split.
    private func usualTimeOfDay(_ dates: [Date], calendar: Calendar) -> Date? {
        let recent = Array(dates.filter { !isClockChangeDay($0, calendar: calendar) }.suffix(3))
        guard let latest = recent.last else { return nil }
        // Hour and minute only: an edited visit keeps the time picker's seconds.
        func clock(_ d: Date) -> [Int] {
            let c = calendar.dateComponents([.hour, .minute], from: d)
            return [c.hour ?? 0, c.minute ?? 0]
        }
        var counts: [[Int]: Int] = [:]
        for d in recent { counts[clock(d), default: 0] += 1 }
        let most = counts.values.max() ?? 0
        guard most > 1 else { return latest }
        return recent.last { counts[clock($0)] == most } ?? latest
    }

    /// The next date after `latest` for a weekly or two-weekly series without
    /// chosen weekdays. It steps from the latest visit on the weekday most of
    /// the series' visits fall on, counting each visit after that one as an
    /// occurrence already used: they're that visit's successors, moved. So a
    /// one-off move of the last visit, by any number of days either way, keeps
    /// the weekday and, for two-weekly, the fortnight. (Editing all future
    /// visits changes their time, not their day, so a weekday only changes by
    /// one-off moves.) `dates` is sorted.
    private func nextOnUsualWeekday(after latest: Date, dates: [Date], stepDays: Int,
                                    calendar: Calendar) -> Date? {
        let days = dates.map { calendar.component(.weekday, from: $0) }
        var counts: [Int: Int] = [:]
        for d in days { counts[d, default: 0] += 1 }
        let most = counts.values.max() ?? 0
        guard let usual = days.last(where: { counts[$0] == most }),
              let anchorIndex = days.lastIndex(of: usual) else {
            return calendar.date(byAdding: .day, value: stepDays, to: latest)
        }
        let used = dates.count - 1 - anchorIndex
        var next = calendar.date(byAdding: .day, value: stepDays * (used + 1), to: dates[anchorIndex])
        while let candidate = next, calendar.startOfDay(for: candidate) <= calendar.startOfDay(for: latest) {
            next = calendar.date(byAdding: .day, value: stepDays, to: candidate)
        }
        return next
    }

    /// The day of month most of `dates` fall on; on a tie, the earliest one's.
    private func usualDayOfMonth(_ dates: [Date], calendar: Calendar) -> Int {
        let days = dates.map { calendar.component(.day, from: $0) }
        var counts: [Int: Int] = [:]
        for d in days { counts[d, default: 0] += 1 }
        let most = counts.values.max() ?? 0
        return days.first { counts[$0] == most } ?? days.first ?? 1
    }

    /// `months` months after `date`'s month, on `dayOfMonth` or the month's last day if shorter.
    private func monthStep(after date: Date, months: Int, dayOfMonth: Int, calendar: Calendar) -> Date? {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let target = calendar.date(byAdding: .month, value: months, to: monthStart),
              let length = calendar.range(of: .day, in: .month, for: target)?.count else { return nil }
        return calendar.date(byAdding: .day, value: min(dayOfMonth, length) - 1, to: target)
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
