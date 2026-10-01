import UIKit

/// Writes a document top to bottom across letter pages: the business's
/// header, text that runs on to the next page (breaking between words), and
/// rows of photos. The contract and the proof-of-service report use it, in
/// the business's colour and ink (PDFGenerator).
final class PDFPageWriter {
    static let pageSize = CGSize(width: 612, height: 792)
    let margin: CGFloat = 54
    var width: CGFloat { Self.pageSize.width - margin * 2 }
    var bottom: CGFloat { Self.pageSize.height - margin }

    let accent: UIColor
    private let context: UIGraphicsPDFRendererContext
    /// Where the next thing is drawn.
    var y: CGFloat

    init(context: UIGraphicsPDFRendererContext, profile: BusinessProfile?) {
        self.context = context
        accent = PDFGenerator.accent(for: profile)
        context.beginPage()
        y = margin
    }

    /// A PDF written by `body`.
    static func document(profile: BusinessProfile?, _ body: (PDFPageWriter) -> Void) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize)).pdfData { context in
            body(PDFPageWriter(context: context, profile: profile))
        }
    }

    func newPage() {
        context.beginPage()
        y = margin
    }

    /// A new page unless `space` is left on this one: keeps a heading with
    /// what follows it, or a block together.
    func keep(_ space: CGFloat) {
        if y + space > bottom, y > margin { newPage() }
    }

    func height(_ text: String, _ attributes: [NSAttributedString.Key: Any], width: CGFloat? = nil) -> CGFloat {
        (text as NSString).boundingRect(with: CGSize(width: width ?? self.width, height: .greatestFiniteMagnitude),
                                        options: .usesLineFragmentOrigin, attributes: attributes,
                                        context: nil).height.rounded(.up)
    }

    /// Draws `text`, paragraph by paragraph, breaking a paragraph between
    /// words where the page ends: nothing is cut off.
    func text(_ text: String, _ font: UIFont, _ color: UIColor = PDFGenerator.ink, gap: CGFloat = 4) {
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

    /// A section heading in the business's colour.
    func heading(_ title: String) {
        keep(40)
        text(title.uppercased(), .systemFont(ofSize: 9, weight: .semibold), accent, gap: 3)
    }

    /// The document's title, and the business: its name, contact, licence,
    /// and logo at the right.
    func header(title: String, subtitle: String, profile: BusinessProfile?) {
        if let data = profile?.logoData, let logo = UIImage(data: data) {
            let scale = min(48 / logo.size.height, 96 / logo.size.width)
            let size = CGSize(width: logo.size.width * scale, height: logo.size.height * scale)
            logo.draw(in: CGRect(x: Self.pageSize.width - margin - size.width, y: margin, width: size.width, height: size.height))
        }
        text(title, .systemFont(ofSize: 20, weight: .bold), accent, gap: 2)
        if !subtitle.isEmpty { text(subtitle, .systemFont(ofSize: 14, weight: .semibold), gap: 10) }
        text(Self.businessName(profile), .systemFont(ofSize: 12, weight: .semibold), gap: 2)
        let contact = [profile?.phone ?? "", profile?.email ?? "", profile?.licenseNumber ?? ""].filter { !$0.isEmpty }
        if !contact.isEmpty { text(contact.joined(separator: " · "), .systemFont(ofSize: 10), PDFGenerator.inkMid, gap: 14) }
    }

    static func businessName(_ profile: BusinessProfile?) -> String {
        profile?.companyName.isEmpty == false ? profile?.companyName ?? "" : "Service Provider"
    }

    /// Photos in a row (up to four), each scaled to fit `height` and
    /// shrunk before drawing so the file stays small, with a caption under
    /// each.
    func photos(_ items: [(image: UIImage, caption: String)], height: CGFloat = 110) {
        guard !items.isEmpty else { return }
        let captionFont = UIFont.systemFont(ofSize: 8)
        let gap: CGFloat = 8
        for row in stride(from: 0, to: items.count, by: 4).map({ Array(items[$0..<min($0 + 4, items.count)]) }) {
            let slot = (width - gap * 3) / 4
            // Each fitted to its slot; the row as tall as its tallest, and
            // each caption right under its own photo.
            let sizes = row.map { item -> CGSize in
                let size = item.image.size
                guard size.width > 0, size.height > 0 else { return .zero }
                let scale = min(slot / size.width, height / size.height)
                return CGSize(width: size.width * scale, height: size.height * scale)
            }
            let rowHeight = sizes.map(\.height).max() ?? 0
            keep(rowHeight + 28)
            for (index, item) in row.enumerated() where sizes[index] != .zero {
                let rect = CGRect(x: margin + CGFloat(index) * (slot + gap), y: y,
                                  width: sizes[index].width, height: sizes[index].height)
                Self.shrunk(item.image, to: sizes[index]).draw(in: rect)
                (item.caption as NSString).draw(with: CGRect(x: rect.minX, y: rect.maxY + 2, width: slot, height: 22),
                                                options: .usesLineFragmentOrigin,
                                                attributes: [.font: captionFont, .foregroundColor: PDFGenerator.inkMid],
                                                context: nil)
            }
            y += rowHeight + 28
        }
    }

    /// `image` at twice the drawn size, re-encoded as JPEG: a phone photo
    /// drawn as is would put megabytes of pixels in the PDF.
    private static func shrunk(_ image: UIImage, to size: CGSize) -> UIImage {
        let pixels = CGSize(width: size.width * 2, height: size.height * 2)
        // Scale 1: the default is the screen's (3x), which made each photo
        // nine times the pixels meant.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: pixels, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixels))
        }
        return small.jpegData(compressionQuality: 0.7).flatMap(UIImage.init(data:)) ?? small
    }
}
