import CoreImage.CIFilterBuiltins
import UIKit

/// A QR code for some text: an invoice's payment link (PDFGenerator), a
/// business's Request Service link (RequestLinkView).
enum QRCode {
    private static let context = CIContext()

    /// Square, `size` points wide, black on white. The generator leaves a
    /// 1-module margin; `border` widens it to the 4 modules scanners expect
    /// all round, so it scans from a screen, a printout or a truck. Nil if
    /// the text is too long to encode (about 2,300 bytes).
    static func image(for text: String, size: CGFloat, border: Bool = false) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let pad: CGFloat = border ? 3 : 0
        let padded = output.transformed(by: CGAffineTransform(translationX: pad, y: pad))
            .composited(over: CIImage(color: .white)
                .cropped(to: CGRect(x: 0, y: 0, width: output.extent.width + pad * 2, height: output.extent.height + pad * 2)))
        let scale = size / padded.extent.width
        let scaled = padded.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
