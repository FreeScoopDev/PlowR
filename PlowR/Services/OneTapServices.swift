import Foundation
import SwiftData

/// The route screen's main button, when it records the stop's services too.
///
/// Complete used to record the visit and its time but no services: those
/// came only from Record Services (Add Expected, then Save), so a crew that
/// just tapped Complete ended the day with records saying "No services" and
/// nothing for Bill Unbilled Work to bill. When the stop is expected to need
/// services and none are recorded yet, the button now names them ("Done:
/// Mow, Trim") and completing with it records exactly those (Joe's call,
/// 2026-11-10). Services are still never ticked silently: the button says
/// what it records, and Complete Without Services completes as before.
///
/// The decision is here, as plain values, so it can be tested without a
/// screen. Recording happens inside the store's completion
/// (`ActiveRouteStore.completeCurrentStop(expecting:recordingServices:)`),
/// so a cancelled text, a stop changed by iCloud and Undo are handled where
/// the visit is.
nonisolated enum OneTapServices {

    /// What the current stop's copper button is.
    enum MainButton: Equatable {
        /// The last stop, nothing to record by it.
        case completeRoute
        /// No one to text next.
        case completeStop
        case completeAndText
        /// "Done: " and the names. Completing with it records `serviceIDs`
        /// (and only those: they are the ones named).
        case done(serviceIDs: [String], names: [String])

        /// The services completing with this button records.
        var recordedServiceIDs: [String] {
            if case .done(let ids, _) = self { return ids }
            return []
        }

        /// Whether the quieter Complete Without Services shows beside it.
        var offersCompletingWithout: Bool { !recordedServiceIDs.isEmpty }
    }

    /// The stop's expected services that are in the business's active
    /// catalog (`ServiceLog.activeServices`), in the catalog's order. Record
    /// Services' Add Expected offers the same ones.
    static func expectedInCatalog(_ expected: [String],
                                  active: [StopRecording.Service]) -> [StopRecording.Service] {
        let wanted = Set(expected)
        return active.filter { wanted.contains($0.id) }
    }

    /// The services the button names: none for a stop without a client (a
    /// custom stop, or its client is gone), or when something is already
    /// recorded for it this run (`ServiceLog.hasNothingRecorded`).
    static func servicesToName(expected: [String], active: [StopRecording.Service], hasClient: Bool,
                               nothingRecorded: Bool) -> [StopRecording.Service] {
        guard hasClient, nothingRecorded else { return [] }
        return expectedInCatalog(expected, active: active)
    }

    /// The button for the current stop. With services to name it's "Done:",
    /// on any stop; otherwise exactly as before.
    static func mainButton(naming services: [StopRecording.Service], isLastStop: Bool,
                           skipsText: Bool) -> MainButton {
        if !services.isEmpty { return .done(serviceIDs: services.map(\.id), names: services.map(\.name)) }
        if isLastStop { return .completeRoute }
        return skipsText ? .completeStop : .completeAndText
    }

    /// The route screen's button for `stop`, the store's current stop, as
    /// it is now: `client` is the stop's (nil for a custom stop, or one
    /// whose client is gone), `catalog` every service item. The screen and
    /// the tests both ask this. With a `memo`, the database is read only
    /// when something the answer depends on has changed since it was last
    /// worked out (`MainButtonMemo.Key`); the screen redraws on every GPS
    /// fix, and `dataVersion` counts the database's saves and synced changes.
    @MainActor
    static func mainButton(for stop: RouteStop, client: Client?, catalog: [ServiceItem], operatorID: String,
                           store: ActiveRouteStore, skipsText: Bool, in context: ModelContext,
                           memo: MainButtonMemo? = nil, dataVersion: Int = 0) -> MainButton {
        let active = ServiceLog.activeServices(catalog, operatorID: operatorID)
        let expected = StopServices.expected(for: stop, client: client)
        let isLastStop = store.isLastStop
        let compute = {
            var nothingRecorded = false
            if let client, let run = store.runID, let startedAt = store.stopStartedAt {
                nothingRecorded = ServiceLog.hasNothingRecorded(for: stop, of: client, run: run,
                                                                startedAt: startedAt, in: context)
            }
            let services = servicesToName(expected: expected, active: active, hasClient: client != nil,
                                          nothingRecorded: nothingRecorded)
            return mainButton(naming: services, isLastStop: isLastStop, skipsText: skipsText)
        }
        guard let memo else { return compute() }
        let key = MainButtonMemo.Key(stopID: stop.id, clientID: client?.id, runID: store.runID,
                                     stopStartedAt: store.stopStartedAt, recorded: stop.completedServiceIDs,
                                     expected: expected, catalog: active.map { "\($0.id)|\($0.name)" },
                                     isLastStop: isLastStop, skipsText: skipsText, dataVersion: dataVersion)
        return memo.button(for: key, compute: compute)
    }

    /// The ordinary button's words (never "Done:").
    static func ordinaryTitle(isLastStop: Bool, skipsText: Bool) -> String {
        if isLastStop { return "Complete Route" }
        return skipsText ? "Complete Stop" : "Complete · Text Next Client"
    }

    /// The "Done:" label's forms, longest first: every name, then fewer
    /// names and "+N more", down to the first name and "+N more". The
    /// screen shows the first that fits on one line. The last form is the
    /// one shown when none fits, made smaller to fit: with two or more
    /// services it's the count ("Done: 3 services"), so shrinking or
    /// cutting it short can never hide that more is recorded; with one,
    /// it's that one's name.
    static func doneTitles(_ names: [String]) -> [String] {
        guard !names.isEmpty else { return [] }
        var titles = ["Done: " + names.joined(separator: ", ")]
        for shown in stride(from: names.count - 1, through: 1, by: -1) {
            titles.append("Done: " + names.prefix(shown).joined(separator: ", ") + " +\(names.count - shown) more")
        }
        if names.count > 1 { titles.append("Done: \(names.count) services") }
        return titles
    }

    /// What the text sheet offered after leaving a stop says, above its
    /// buttons, about what Send or Skip does to the stop left
    /// (`NotifyAdvance.Completion.exitOffer`). `names`: the services the
    /// card's button names for that stop ("Done:"), every one; empty when
    /// it's the ordinary Complete. The sheet's header names the next
    /// client, so this names the one left. Cancel leaves the stop as it was,
    /// where Complete Without Services is.
    static func exitOfferNotice(clientName: String, names: [String]) -> String {
        guard !names.isEmpty else {
            // True whether nothing is expected or something is recorded
            // already: the visit is still logged, only no service is added.
            return "Send Message or Complete Without Text completes the stop for \(clientName) and adds no services."
                + " Tap Cancel to stay on that stop."
        }
        return "Send Message or Complete Without Text completes the stop for \(clientName) and records \(englishList(names))."
            + " To complete it without \(names.count == 1 ? "that service" : "them"),"
            + " tap Cancel and choose on the stop."
    }

    /// After Send or Skip on the exit offer recorded less than its sheet
    /// named (`NotifyAdvance.Completion.runNotingUnrecorded`): which weren't,
    /// and where to add them. nil when nothing is missing.
    static func notRecordedNote(clientName: String, names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let one = names.count == 1
        return "\(englishList(names)) \(one ? "wasn't" : "weren't") recorded for \(clientName)."
            + " If \(one ? "it was" : "they were") done, add \(one ? "it" : "them")"
            + " from the Route Recap when you finish the route."
    }

    /// The app's copy is in English only: lists read "Mow, Trim, and Edge"
    /// whatever the device's region, never half in another language.
    static let copyLocale = Locale(identifier: "en_US")

    /// `names` as an English list.
    static func englishList(_ names: [String]) -> String {
        names.formatted(.list(type: .and).locale(copyLocale))
    }

    /// What VoiceOver reads for the "Done:" button: every name, whatever the
    /// label could fit.
    static func doneAccessibilityLabel(_ names: [String]) -> String {
        "Done: complete and record " + englishList(names)
    }
}

/// The route screen's last button and what it was worked out from, so a
/// redraw with nothing changed doesn't read the database again. Not
/// observed: it only saves work, and changes nothing the screen shows.
@MainActor
final class MainButtonMemo {
    /// Everything the button depends on. The record and any invoice live in
    /// the database: `dataVersion` changes with every save and synced change.
    struct Key: Hashable {
        var stopID: UUID
        var clientID: UUID?
        var runID: UUID?
        var stopStartedAt: Date?
        var recorded: [String]
        var expected: [String]
        var catalog: [String]
        var isLastStop: Bool
        var skipsText: Bool
        var dataVersion: Int
    }

    private var last: (key: Key, button: OneTapServices.MainButton)?
    /// How many times the button was worked out (for tests).
    private(set) var computed = 0

    func button(for key: Key, compute: () -> OneTapServices.MainButton) -> OneTapServices.MainButton {
        if let last, last.key == key { return last.button }
        let button = compute()
        computed += 1
        last = (key, button)
        return button
    }
}
