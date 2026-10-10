import Foundation
import UIKit

/// A contract as a page to share with the client: who it's between, the
/// period and places, the services it covers, the price and its payments,
/// the visits it books, the notes, and lines to sign. Signing is by hand
/// (Mark Signed): e-signatures would need a server.
enum ContractPDF {

    /// The page's text, top to bottom: each a heading and its lines.
    struct Section: Equatable {
        var heading: String
        var lines: [String]
    }

    /// What the page says (also what tests read).
    static func sections(of contract: Contract, client: Client?, catalog: [ServiceItem],
                         calendar: Calendar = .current) -> [Section] {
        let format = Date.FormatStyle.dateTime.month(.wide).day().year()
        var sections: [Section] = []
        let clientName = client?.name ?? contract.clientName
        var who = [clientName]
        if let client {
            who += [client.address, client.phone, client.email].filter { !$0.isEmpty }
        }
        sections.append(Section(heading: "Client", lines: who))
        sections.append(Section(heading: "Period", lines: [
            "\(contract.startDate.formatted(format)) to \(contract.endDate.formatted(format))"]))
        if let client {
            let places = contract.placeIDs.compactMap { Place.of(client, propertyID: $0) }
                .map { $0.isMain ? $0.address : "\($0.label): \($0.address)" }
            if !places.isEmpty { sections.append(Section(heading: places.count == 1 ? "Property" : "Properties", lines: places)) }
        }
        let services = catalog.filter { contract.serviceIDs.contains($0.id.uuidString) }
            .sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
        sections.append(Section(heading: "Services Covered", lines: services.isEmpty ? ["As agreed"] : services))
        var price = [Contracts.priceSummary(of: contract)]
        let schedule = ContractInstallments.schedule(of: contract, calendar: calendar)
        if schedule.count > 1 || Contracts.pricing(of: contract) == .monthly {
            price += schedule.map {
                "\($0.date.formatted(.dateTime.month(.abbreviated).day().year())): \($0.amount.formatted(.currency(code: "USD")))"
            }
        }
        if Contracts.pricing(of: contract) != .perVisit {
            price.append("Services not listed above are billed separately.")
        }
        sections.append(Section(heading: "Price", lines: price))
        if ContractSchedule.hasSchedule(contract) {
            sections.append(Section(heading: "Visits", lines: [ContractSchedule.summary(of: contract, calendar: calendar)]))
        }
        if contract.triggerInches > 0 {
            sections.append(Section(heading: "Trigger", lines: ["Service starts at \(contract.triggerInches.formatted()) in of snow or more."]))
        }
        if !contract.notes.isEmpty {
            sections.append(Section(heading: "Terms", lines: [contract.notes]))
        }
        return sections
    }

    /// The page, in the business's colour, logo and ink (PDFPageWriter):
    /// long terms run on to further pages, and the signature lines stay
    /// together.
    /// `madeWithPlowR` is `Access.showsMadeWithPlowR`: PlowR's line at the end.
    static func generate(_ contract: Contract, client: Client?, profile: BusinessProfile?,
                         catalog: [ServiceItem], madeWithPlowR: Bool) -> Data {
        PDFPageWriter.document(profile: profile) { page in
            page.header(title: "SERVICE CONTRACT", subtitle: contract.name, profile: profile)
            for section in sections(of: contract, client: client, catalog: catalog) {
                page.heading(section.heading)
                for line in section.lines { page.text(line, .systemFont(ofSize: 11), gap: 2) }
                page.y += 10
            }
            // The signatures together, on one page.
            if page.y + 190 > page.bottom { page.newPage() } else { page.y += 24 }
            page.text("Agreed by", .systemFont(ofSize: 9, weight: .semibold), page.accent, gap: 30)
            let business = PDFPageWriter.businessName(profile)
            for party in [contract.clientName.isEmpty ? (client?.name ?? "Client") : contract.clientName, business] {
                page.text("______________________________          Date ____________", .systemFont(ofSize: 11), gap: 2)
                page.text(party, .systemFont(ofSize: 10), PDFGenerator.inkMid, gap: 26)
            }
            if madeWithPlowR {
                page.text(PDFGenerator.plowRLine, .systemFont(ofSize: 8), PDFGenerator.inkLight)
            }
        }
    }

    /// The shared file's name: the client's and the contract's, kept short.
    static func fileName(_ contract: Contract) -> String {
        let raw = [contract.clientName, contract.name].filter { !$0.isEmpty }.joined(separator: " - ")
        let safe = raw.map { "/\\:?*\"<>|".contains($0) ? "-" : $0 }
        return "Contract - \(String(safe.prefix(80))).pdf"
    }
}
