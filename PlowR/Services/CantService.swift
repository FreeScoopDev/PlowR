import Foundation

/// Can't Service, on a route in progress: a stop the crew couldn't do (a
/// vehicle in the way, a locked gate, the client cancelled). The route moves
/// on with no visit, time, services or Service Log record
/// (`ActiveRouteStore.skipCurrentStop`); the stop keeps the reason until the
/// route's next run. This is the wording and the rules the screens share.
nonisolated enum CantService {
    /// The reasons offered, in order. "Other" takes its note as the reason.
    static let presets = ["Vehicle in the way", "Gate locked", "Client cancelled", "Unsafe conditions", "Other"]
    static let other = "Other"

    /// The reason kept on the stop: the preset, then ": note" when a note was
    /// typed. "Other" with a note keeps the note alone; with none, "Other".
    static func reason(preset: String, note: String) -> String {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty { return preset }
        return preset == other ? note : "\(preset): \(note)"
    }

    /// Whether work is already recorded at a stop this run: services on the
    /// stop, or a Service Log record for it. Then neither Can't Service nor
    /// Below Trigger is offered, so neither stands beside recorded (or
    /// billed) work.
    static func isWorkRecorded(completedServiceIDs: [String], hasRunRecord: Bool) -> Bool {
        !completedServiceIDs.isEmpty || hasRunRecord
    }

    /// The recap's line for a stop not serviced: "Can't service: <reason>",
    /// only for a skip on this run (`at` on or after `runStartedAt`), so a
    /// reason left by an older run, or by an older build that didn't clear
    /// it, never shows. nil otherwise.
    static func recapLine(reason: String, at: Date?, runStartedAt: Date?) -> String? {
        guard !reason.isEmpty, let at, let runStartedAt, at >= runStartedAt else { return nil }
        return "Can't service: \(reason)"
    }

    /// The route page's line under a stop skipped on the route's latest run:
    /// "Couldn't service Nov 10: Gate locked". nil without a reason.
    static func routeLine(reason: String, at: Date?, locale: Locale = .autoupdatingCurrent,
                          calendar: Calendar = .current) -> String? {
        guard !reason.isEmpty, let at else { return nil }
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                     timeZone: calendar.timeZone)
        style = style.month(.abbreviated).day()
        return "Couldn't service \(at.formatted(style)): \(reason)"
    }
}
