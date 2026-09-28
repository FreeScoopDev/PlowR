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
    var externalCalendarID: String = ""  // EKEvent identifier for Calendar.app sync

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

    /// When the series' next visit after `date` is, or nil if it doesn't repeat
    /// or has ended.
    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isRecurring else { return nil }
        return recurrenceRule.next(after: date, calendar: calendar)
    }

    /// The series' next visit after this one, with everything a visit in the
    /// series carries, ready to insert; nil if it doesn't repeat or has ended.
    /// (Visits added on completion used to lose their reason and expected services.)
    func makeNextOccurrence(calendar: Calendar = .current) -> ScheduledVisit? {
        guard let date = nextOccurrence(after: scheduledDate, calendar: calendar) else { return nil }
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
