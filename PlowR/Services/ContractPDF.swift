import Foundation
import UIKit

/// A contract as a page to share with the client: who it's between, the
/// period and places, the services it covers, the price and its payments,
/// the visits it books, the notes, and lines to sign. Signing is by hand
/// (Mark Signed): e-signatures would need a server.
enum ContractPDF {
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 54

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

    /// The page: the business's colour (or black and white), logo and ink,
    /// as its proposals and invoices are (PDFGenerator). Long terms run on
    /// to further pages, and the signature lines stay together.
    static func generate(_ contract: Contract, client: Client?, profile: BusinessProfile?,
                         catalog: [ServiceItem]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let width = pageSize.width - margin * 2
        let bottom = pageSize.height - margin
        let accent = PDFGenerator.accent(for: profile)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y = margin
            func height(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
                (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                options: .usesLineFragmentOrigin, attributes: attributes,
                                                context: nil).height.rounded(.up)
            }
            func newPage() {
                ctx.beginPage()
                y = margin
            }
            /// Draws `text`, paragraph by paragraph, breaking a paragraph
            /// between words where the page ends.
            func draw(_ text: String, _ font: UIFont, _ color: UIColor = PDFGenerator.ink, gap: CGFloat = 4) {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                for paragraph in text.components(separatedBy: "\n") {
                    var words = paragraph.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
                    repeat {
                        // The most words that fit what's left of the page.
                        var low = 0, high = words.count
                        while low < high {
                            let mid = (low + high + 1) / 2
                            if y + height(words[..<mid].joined(separator: " "), attributes) <= bottom { low = mid } else { high = mid - 1 }
                        }
                        if low == 0, y > margin {
                            newPage()
                            continue
                        }
                        let take = max(1, low)
                        let piece = words[..<take].joined(separator: " ")
                        let pieceHeight = height(piece.isEmpty ? " " : piece, attributes)
                        (piece as NSString).draw(with: CGRect(x: margin, y: y, width: width, height: pieceHeight),
                                                 options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
                        y += pieceHeight
                        words.removeFirst(min(take, words.count))
                        if !words.isEmpty { newPage() }
                    } while !words.isEmpty
                    y += gap
                }
            }
            let business = profile?.companyName.isEmpty == false ? profile?.companyName ?? "" : "Service Provider"
            if let data = profile?.logoData, let logo = UIImage(data: data) {
                let scale = min(48 / logo.size.height, 96 / logo.size.width)
                let size = CGSize(width: logo.size.width * scale, height: logo.size.height * scale)
                logo.draw(in: CGRect(x: pageSize.width - margin - size.width, y: margin, width: size.width, height: size.height))
            }
            draw("SERVICE CONTRACT", .systemFont(ofSize: 20, weight: .bold), accent, gap: 2)
            draw(contract.name, .systemFont(ofSize: 14, weight: .semibold), gap: 10)
            draw(business, .systemFont(ofSize: 12, weight: .semibold), gap: 2)
            let contact = [profile?.phone ?? "", profile?.email ?? "", profile?.licenseNumber ?? ""].filter { !$0.isEmpty }
            if !contact.isEmpty { draw(contact.joined(separator: " · "), .systemFont(ofSize: 10), PDFGenerator.inkMid, gap: 14) }
            for section in sections(of: contract, client: client, catalog: catalog) {
                if y + 40 > bottom { newPage() }                                    // a heading with its first line
                draw(section.heading.uppercased(), .systemFont(ofSize: 9, weight: .semibold), accent, gap: 3)
                for line in section.lines { draw(line, .systemFont(ofSize: 11), gap: 2) }
                y += 10
            }
            // The signatures together, on one page.
            if y + 190 > bottom { newPage() } else { y += 24 }
            draw("Agreed by", .systemFont(ofSize: 9, weight: .semibold), accent, gap: 30)
            for party in [contract.clientName.isEmpty ? (client?.name ?? "Client") : contract.clientName, business] {
                draw("______________________________          Date ____________", .systemFont(ofSize: 11), gap: 2)
                draw(party, .systemFont(ofSize: 10), PDFGenerator.inkMid, gap: 26)
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
