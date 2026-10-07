import Foundation
import SwiftData

/// A request from the Request Service link (RequestLink), turned into a
/// lead: what Add to PlowR does once the business taps Save on the New
/// Lead screen (NewLeadFromRequestView). Nothing is saved before that: the
/// link came from a stranger's text. Its pin is looked up as an import's
/// are (ImportPins, which finds leads by their tag): once, retried while
/// the map can't be reached, and marked if the map doesn't know it.
@MainActor
enum LeadIntake {
    /// How every request's tag begins ("Requested Oct 7").
    static let tagPrefix = "Requested "

    /// One of PlowR's request tags ("Requested Oct 7", "Requested 7 Oct",
    /// "Requested 10月7日": the date is written in the phone's own way), not
    /// a tag of the user's own that begins the same way ("Requested quote",
    /// "Requested 2 quotes"): what follows the prefix must read back as a
    /// date in `locale` (or in US English, for a phone whose language changed).
    static func isRequestTag(_ tag: String, locale: Locale = .current) -> Bool {
        guard tag.hasPrefix(tagPrefix) else { return false }
        let rest = String(tag.dropFirst(tagPrefix.count))
        return [locale, Locale(identifier: "en_US")].contains { locale in
            let style = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(locale)
            return (try? Date(rest, strategy: style.parseStrategy)) != nil
        }
    }

    static func tag(for date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(locale)
        style.timeZone = timeZone
        return tagPrefix + date.formatted(style)
    }

    /// The client already in PlowR with the request's phone number, if any:
    /// a returning customer, or someone who asked before.
    static func existingClient(for request: RequestLink.Request, operatorID: String,
                               in context: ModelContext) -> Client? {
        guard let key = ClientImport.phoneKey(request.phone) else { return nil }
        let clients = (try? context.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.operatorID == operatorID }))) ?? []
        return clients.first { ClientImport.phoneKey($0.phone) == key }
    }

    /// The client's notes from a request: when and how it came, what was
    /// asked for, and what the person wrote.
    static func notes(for request: RequestLink.Request, date: Date, locale: Locale = .current,
                      timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day().year().locale(locale)
        style.timeZone = timeZone
        var lines = ["Requested service through your request link on \(date.formatted(style))."]
        if !request.service.isEmpty { lines.append("Service: \(request.service)") }
        if let when = request.when { lines.append("How often: \(when.title)") }
        if !request.notes.isEmpty { lines.append(""); lines.append(request.notes) }
        return lines.joined(separator: "\n")
    }

    /// Saves `request`, as the business left it on the New Lead screen, as a
    /// new lead (no customerSince: the Pipeline lists them as a lead).
    @discardableResult
    static func save(_ request: RequestLink.Request, operatorID: String, in context: ModelContext,
                     now: Date = .now, locale: Locale = .current, timeZone: TimeZone = .current) -> Client {
        let client = Client(name: request.name, phone: request.phone, address: request.address, operatorID: operatorID)
        client.email = request.email
        client.notes = notes(for: request, date: now, locale: locale, timeZone: timeZone)
        client.tags = [tag(for: now, locale: locale, timeZone: timeZone)]
        client.createdAt = now
        context.insert(client)
        try? context.save()
        return client
    }
}
