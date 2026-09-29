import Foundation
import SwiftData
import SwiftUI

@Model
final class ScheduledVisit {
    var id: UUID = UUID()
    var operatorID: String = ""
    var clientID: String = ""
    var clientName: String = ""
    var clientAddress: String = ""
    var scheduledDate: Date = Date()
    var estimatedMinutes: Int = 0
    var statusRaw: String = VisitStatus.scheduled.rawValue
    var notes: String = ""
    var visitReason: String = ""              // preset or custom reason for the visit
    var expectedServiceIDs: [String] = []    // service catalog item IDs expected this visit
    var completedAt: Date? = nil
    var proposalID: String = ""    // invoice generated from this visit
    var isAfterHours: Bool = false
    var afterHoursMultiplier: Double = 1.5
    /// Unused since calendar sync matches events by link (VisitCalendar); an
    /// event's ID is only good on one device. Kept: it's in the iCloud schema.
    var externalCalendarID: String = ""

    // Recurrence — all visits in a series share seriesID
    var isRecurring: Bool = false
    var recurrenceTypeRaw: String = RecurrenceType.weekly.rawValue
    var recurrenceInterval: Int = 1           // every N units
    var recurrenceWeekdays: [Int] = []        // weekday numbers (1=Sun … 7=Sat) for weekly
    var recurrenceEndDate: Date? = nil
    var seriesID: String = ""                 // groups all visits in a recurring series

    var status: VisitStatus {
        get { VisitStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }

    var recurrenceType: RecurrenceType {
        get { RecurrenceType(rawValue: recurrenceTypeRaw) ?? .weekly }
        set { recurrenceTypeRaw = newValue.rawValue }
    }

    var isPast: Bool { scheduledDate < Date() && status == .scheduled }

    init(operatorID: String, clientID: String, clientName: String,
         clientAddress: String, scheduledDate: Date) {
        self.operatorID = operatorID
        self.clientID = clientID
        self.clientName = clientName
        self.clientAddress = clientAddress
        self.scheduledDate = scheduledDate
        self.seriesID = UUID().uuidString
    }

    /// This series' repeat rule (see RecurrenceRule, the one rule for repeats).
    var recurrenceRule: RecurrenceRule {
        RecurrenceRule(type: recurrenceType, interval: recurrenceInterval,
                       weekdays: Set(recurrenceWeekdays), endDate: recurrenceEndDate)
    }

    /// The visit to add to this visit's series once it's completed, if the
    /// series needs one (see RecurrenceRule.continuationDate), ready to insert.
    /// `visits` can be any visits; only this series' are considered.
    func continuation(among visits: [ScheduledVisit], calendar: Calendar = .current) -> ScheduledVisit? {
        guard isRecurring else { return nil }
        let series = visits
            .filter { $0.seriesID == seriesID && $0.id != id }
            .map { RecurrenceRule.SeriesVisit(date: $0.scheduledDate, isScheduled: $0.status == .scheduled) }
        guard let date = recurrenceRule.continuationDate(afterCompleting: scheduledDate, series: series,
                                                         calendar: calendar) else { return nil }
        return makeContinuation(on: date)
    }

    /// A visit continuing this series on `date`, with everything a visit in the
    /// series carries. (Visits added on completion used to lose their reason
    /// and expected services.)
    func makeContinuation(on date: Date) -> ScheduledVisit {
        let next = ScheduledVisit(operatorID: operatorID, clientID: clientID, clientName: clientName,
                                  clientAddress: clientAddress, scheduledDate: date)
        next.estimatedMinutes = estimatedMinutes
        next.notes = notes
        next.visitReason = visitReason
        next.expectedServiceIDs = expectedServiceIDs
        next.isRecurring = isRecurring
        next.recurrenceType = recurrenceType
        next.recurrenceInterval = recurrenceInterval
        next.recurrenceWeekdays = recurrenceWeekdays
        next.recurrenceEndDate = recurrenceEndDate
        next.seriesID = seriesID
        next.isAfterHours = isAfterHours
        next.afterHoursMultiplier = afterHoursMultiplier
        return next
    }
}

enum VisitStatus: String, CaseIterable {
    case scheduled = "Scheduled"
    case completed = "Completed"
    case cancelled = "Cancelled"
    case skipped   = "Skipped"

    var systemImage: String {
        switch self {
        case .scheduled: return "calendar.circle"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .skipped:   return "arrow.right.circle.fill"
        }
    }

    var chipColor: Color {
        switch self {
        case .scheduled: return .blue
        case .completed: return .green
        case .cancelled: return .red
        case .skipped:   return .orange
        }
    }
}

nonisolated enum RecurrenceType: String, CaseIterable {
    case daily    = "Daily"
    case weekly   = "Weekly"
    case biweekly = "Every 2 Weeks"
    case monthly  = "Monthly"
}
