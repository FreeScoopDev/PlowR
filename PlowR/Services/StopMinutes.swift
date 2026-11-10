import Foundation

/// Which minutes a route stop's completion counts, and from when.
///
/// A stop's minutes used to run from when it became the current stop (the
/// route started, or the stop before it was completed), so they included the
/// drive there. When GPS caught the arrival at the stop (`SiteTimes.arrivedAt`)
/// they run from the arrival instead. An arrival is never made up: with none
/// caught, or one that can't belong to this stop's wait, the old rule stands.
nonisolated enum StopMinutes {
    /// Where a record's minutes were counted from.
    enum Basis: Equatable {
        /// From GPS's arrival at the stop to its completion.
        case fromArrival
        /// From when the stop became the current stop, so the drive there is in.
        case includesTravel
    }

    /// The minutes of a completion and their basis. From `arrivedAt` when it
    /// is there and lies within `startedAt...finishedAt` (an arrival before
    /// the stop began belongs to something else, one after the completion is
    /// not an arrival at it); otherwise from `startedAt`. Never negative.
    static func counted(startedAt: Date, arrivedAt: Date?, finishedAt: Date) -> (minutes: Double, basis: Basis) {
        if let arrivedAt, arrivedAt >= startedAt, arrivedAt <= finishedAt {
            return (max(0, finishedAt.timeIntervalSince(arrivedAt) / 60), .fromArrival)
        }
        return (max(0, finishedAt.timeIntervalSince(startedAt) / 60), .includesTravel)
    }

    /// How close a record's minutes must be to arrival-to-completion to read
    /// as counted from the arrival (seconds).
    static let tolerance: TimeInterval = 1

    /// Which basis a record's minutes have, derived (nothing is stored): nil
    /// for a record that isn't a route stop's. `.fromArrival` when it has an
    /// arrival and its minutes equal completion minus arrival, within a
    /// second; otherwise `.includesTravel`. A record from before this basis
    /// was kept counted from `startedAt`, so it reads `.includesTravel`
    /// unless the two happen to agree (then there was no travel to include).
    /// Minutes edited by hand that no longer match read `.includesTravel`,
    /// and so does a record whose Done time was moved on the job's page
    /// (its minutes stay): a known limit of deriving it.
    static func basis(source: ServiceRecordSource, arrivedAt: Date?, performedAt: Date,
                      minutes: Double) -> Basis? {
        guard source == .route else { return nil }
        if let arrivedAt,
           abs(minutes * 60 - performedAt.timeIntervalSince(arrivedAt)) <= tolerance {
            return .fromArrival
        }
        return .includesTravel
    }

    /// The recap's On Route time, in whole minutes: from the run's start to
    /// its last recorded completion. The stops' own minutes used to be added
    /// up for it, which was about the same while each ran from the stop
    /// before; counted from an arrival they leave the driving out. Never
    /// less than those minutes' sum (`stopMinutes`), which is also the
    /// answer when the start or the completions aren't known (a run of
    /// stops with no client keeps no records).
    static func onRoute(runStartedAt: Date?, completions: [Date], stopMinutes: Int) -> Int {
        guard let runStartedAt, let last = completions.max(), last > runStartedAt else { return stopMinutes }
        return max(stopMinutes, Int((last.timeIntervalSince(runStartedAt) / 60).rounded()))
    }
}
