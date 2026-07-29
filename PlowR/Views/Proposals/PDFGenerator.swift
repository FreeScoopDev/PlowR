import UIKit
import CoreLocation
import CoreImage
import CoreImage.CIFilterBuiltins

struct PDFGenerator {

    // MARK: - Palette
    private static let ink       = UIColor(white: 0.06, alpha: 1)
    private static let inkDark   = UIColor(white: 0.20, alpha: 1)
    private static let inkMid    = UIColor(white: 0.48, alpha: 1)
    private static let inkLight  = UIColor(white: 0.66, alpha: 1)
    private static let ruleLight = UIColor(white: 0.84, alpha: 1)
    private static let ruleMid   = UIColor(white: 0.52, alpha: 1)

    // Deep navy — matches BusinessProfile default 1E3A8A
    private static let defaultAccent = UIColor(red: 0.118, green: 0.227, blue: 0.541, alpha: 1)

    // MARK: - Fonts
    // GillSans family for all headings/labels — clean, readable, strong character.
    // Verdana for body — highest x-height of any common font, excellent for older readers.

    private static func displayFont(_ size: CGFloat) -> UIFont {
        UIFont(name: "GillSans-Bold", size: size)
            ?? .systemFont(ofSize: size, weight: .bold)
    }
    private static func headingFont(_ size: CGFloat) -> UIFont {
        UIFont(name: "GillSans", size: size)
            ?? .systemFont(ofSize: size, weight: .regular)
    }
    private static func labelFont(_ size: CGFloat) -> UIFont {
        UIFont(name: "GillSans-SemiBold", size: size)
            ?? UIFont(name: "GillSans-Bold", size: size)
            ?? .systemFont(ofSize: size, weight: .semibold)
    }
    private static func bodyFont(_ size: CGFloat) -> UIFont {
        UIFont(name: "Verdana", size: size)
            ?? .systemFont(ofSize: size)
    }
    private static func bodyBoldFont(_ size: CGFloat) -> UIFont {
        UIFont(name: "Verdana-Bold", size: size)
            ?? .systemFont(ofSize: size, weight: .semibold)
    }
    private static func italicFont(_ size: CGFloat) -> UIFont {
        UIFont(name: "GillSans-Italic", size: size)
            ?? .italicSystemFont(ofSize: size)
    }

    // MARK: - Public Entry Point

    /// forceIsInvoice bypasses proposal.isInvoice to avoid SwiftData quirks on non-context objects.
    static func generate(
        proposal: Proposal,
        zones: [PropertyZone] = [],
        profile: BusinessProfile?,
        paymentMethods: [PaymentMethod] = [],
        forceIsInvoice: Bool? = nil
    ) -> Data {
        let pageW:   CGFloat = 612
        let pageH:   CGFloat = 792
        let margin:  CGFloat = 54
        let contentW = pageW - margin * 2

        let isInvoice = forceIsInvoice ?? proposal.isInvoice
        let colorPDFs = profile?.colorPDFs ?? true
        let accent: UIColor = colorPDFs
            ? (accentUIColor(from: profile?.accentColorHex) ?? defaultAccent)
            : UIColor(white: 0.08, alpha: 1)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = margin

            y = drawHeader(profile: profile, isInvoice: isInvoice,
                           invoiceNumber: proposal.invoiceNumber, createdAt: proposal.createdAt,
                           contentW: contentW, margin: margin, y: y, accent: accent)
            y += 18
            drawHRule(x: margin, y: y, width: contentW, weight: 0.75, color: ruleLight)
            y += 22

            y = drawClientBlock(proposal: proposal, isInvoice: isInvoice,
                                zones: zones, contentW: contentW, margin: margin,
                                y: y, accent: accent, colorPDFs: colorPDFs)
            y += 22
            drawHRule(x: margin, y: y, width: contentW, weight: 0.75, color: ruleLight)
            y += 24

            y = drawServiceTable(proposal: proposal, contentW: contentW,
                                 margin: margin, y: y, accent: accent)
            y += 16

            y = drawTotals(proposal: proposal, isInvoice: isInvoice,
                           contentW: contentW, margin: margin, y: y, accent: accent)

            if !proposal.notes.isEmpty {
                y += 26
                y = drawNotes(proposal: proposal, contentW: contentW, margin: margin, y: y)
            }

            if !proposal.disclaimer.isEmpty {
                y += 18
                drawDisclaimer(proposal: proposal, contentW: contentW, margin: margin, y: y)
                let lines = max(1, (proposal.disclaimer.count / 88) + 1)
                y += CGFloat(lines) * 12 + 14
            }

            let activeMethods = paymentMethods.filter { $0.isActive }
            if isInvoice && !activeMethods.isEmpty {
                y += 22
                drawPaymentSection(methods: activeMethods, contentW: contentW,
                                   margin: margin, y: y, accent: accent)
            }

            drawFooter(profile: profile, pageW: pageW, pageH: pageH,
                       margin: margin, contentW: contentW)
        }
    }

    // MARK: - Header

    @discardableResult
    private static func drawHeader(
        profile: BusinessProfile?, isInvoice: Bool,
        invoiceNumber: String, createdAt: Date,
        contentW: CGFloat, margin: CGFloat, y: CGFloat, accent: UIColor
    ) -> CGFloat {
        let rightW:  CGFloat = 180
        let leftW    = contentW - rightW - 14
        let dateFmt  = DateFormatter(); dateFmt.dateStyle = .short

        // Right — large document title
        let docTitle = isInvoice ? "INVOICE" : "PROPOSAL"
        drawText(docTitle, x: margin + leftW + 14, y: y - 4, width: rightW,
                 font: displayFont(36), color: accent, kern: 1.5, alignment: .right, singleLine: true)

        var metaY = y + 40
        if isInvoice && !invoiceNumber.isEmpty {
            labeled("Invoice\u{00A0}#", value: invoiceNumber)
                .draw(in: CGRect(x: margin + leftW + 14, y: metaY, width: rightW, height: 20))
            metaY += 15
        }
        labeled("Date:", value: dateFmt.string(from: createdAt))
            .draw(in: CGRect(x: margin + leftW + 14, y: metaY, width: rightW, height: 20))
        metaY += 15

        // Left — company block
        var leftY = y
        var logoOffset: CGFloat = 0
        if let logoData = profile?.logoData, let logo = UIImage(data: logoData) {
            let logoH: CGFloat = 48
            let scale = min(logoH / logo.size.height, 72 / logo.size.width)
            let lW = logo.size.width * scale, lH = logo.size.height * scale
            logo.draw(in: CGRect(x: margin, y: leftY, width: lW, height: lH))
            logoOffset = lW + 12
        }
        let name = profile?.companyName.isEmpty == false ? profile!.companyName : "Service Provider"
        drawText(name, x: margin + logoOffset, y: leftY, width: leftW - logoOffset,
                 font: headingFont(15), color: ink, singleLine: true)
        leftY += 20
        if let tagline = profile?.tagline, !tagline.isEmpty {
            drawText(tagline, x: margin + logoOffset, y: leftY, width: leftW - logoOffset,
                     font: bodyFont(10), color: inkMid, singleLine: true)
            leftY += 14
        }
        let contacts = [profile?.phone, profile?.email].compactMap { $0 }.filter { !$0.isEmpty }
        if !contacts.isEmpty {
            drawText(contacts.joined(separator: "   ·   "), x: margin + logoOffset, y: leftY,
                     width: leftW - logoOffset, font: bodyFont(9.5), color: inkLight, singleLine: true)
            leftY += 13
        }
        if let lic = profile?.licenseNumber, !lic.isEmpty {
            drawText("License: \(lic)", x: margin + logoOffset, y: leftY,
                     width: leftW - logoOffset, font: bodyFont(9.5), color: inkLight)
            leftY += 13
        }

        return max(leftY, metaY)
    }

    /// Gill Sans bold label + Verdana value, right-aligned.
    private static func labeled(_ label: String, value: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle(); para.alignment = .right
        let str = NSMutableAttributedString(string: "\(label) ", attributes: [
            .font: labelFont(9), .foregroundColor: inkMid, .paragraphStyle: para
        ])
        str.append(NSAttributedString(string: value, attributes: [
            .font: bodyFont(9), .foregroundColor: inkDark, .paragraphStyle: para
        ]))
        return str
    }

    // MARK: - Client Block + Minimap

    @discardableResult
    private static func drawClientBlock(
        proposal: Proposal, isInvoice: Bool,
        zones: [PropertyZone], contentW: CGFloat, margin: CGFloat, y: CGFloat,
        accent: UIColor, colorPDFs: Bool
    ) -> CGFloat {
        let validZones = zones.filter { $0.coordinates.count >= 3 }
        let hasMap     = !validZones.isEmpty
        // Minimap needs extra ring for compass labels outside circle
        let mapD:      CGFloat = 120
        let compassRing: CGFloat = 20   // extra space outside circle for ticks + labels
        let totalMapW  = mapD + compassRing * 2
        let leftW      = hasMap ? contentW - totalMapW - 16 : contentW

        var leftY = y

        drawText("BILLED TO", x: margin, y: leftY, width: leftW,
                 font: labelFont(8), color: accent, kern: 1.8)
        leftY += 15
        drawText(proposal.clientName, x: margin, y: leftY, width: leftW,
                 font: headingFont(14), color: ink)
        leftY += 19
        if !proposal.clientAddress.isEmpty {
            drawText(proposal.clientAddress, x: margin, y: leftY, width: leftW - 8,
                     font: bodyFont(11), color: inkDark)
            leftY += 15
        }
        if !proposal.clientPhone.isEmpty {
            drawText(proposal.clientPhone, x: margin, y: leftY, width: leftW - 8,
                     font: bodyFont(11), color: inkDark)
            leftY += 15
        }

        if isInvoice, let due = proposal.invoiceDueDate {
            leftY += 8
            let fmt = DateFormatter(); fmt.dateStyle = .long
            drawText("DUE DATE", x: margin, y: leftY, width: leftW,
                     font: labelFont(8), color: accent, kern: 1.8)
            leftY += 14
            drawText(fmt.string(from: due), x: margin, y: leftY, width: leftW,
                     font: bodyBoldFont(11), color: ink)
            leftY += 15
        } else if !isInvoice, let validUntil = proposal.validUntil {
            leftY += 8
            let fmt = DateFormatter(); fmt.dateStyle = .long
            drawText("VALID UNTIL", x: margin, y: leftY, width: leftW,
                     font: labelFont(8), color: accent, kern: 1.8)
            leftY += 14
            drawText(fmt.string(from: validUntil), x: margin, y: leftY, width: leftW,
                     font: bodyBoldFont(11), color: ink)
            leftY += 15
        }

        if hasMap {
            // Center the minimap (including compass ring) in the right column
            let mapAreaX = margin + leftW + 16
            let center = CGPoint(
                x: mapAreaX + compassRing + mapD / 2,
                y: y + compassRing + mapD / 2 + 4
            )
            drawMinimap(zones: validZones, center: center,
                        radius: mapD / 2, accent: accent, colorPDFs: colorPDFs)
        }

        let mapBottom = hasMap ? y + mapD + compassRing * 2 + 8 : y
        return max(leftY, mapBottom)
    }

    // MARK: - Minimap

    private static func drawMinimap(
        zones: [PropertyZone], center: CGPoint, radius: CGFloat,
        accent: UIColor, colorPDFs: Bool
    ) {
        let allCoords = zones.flatMap { $0.coordinates }
        guard !allCoords.isEmpty else { return }

        let rawMinLat = allCoords.map(\.latitude).min()!
        let rawMaxLat = allCoords.map(\.latitude).max()!
        let rawMinLon = allCoords.map(\.longitude).min()!
        let rawMaxLon = allCoords.map(\.longitude).max()!
        let latSpan   = rawMaxLat - rawMinLat
        let lonSpan   = rawMaxLon - rawMinLon
        guard latSpan > 0, lonSpan > 0 else { return }

        let cosLat  = CGFloat(cos((rawMinLat + rawMaxLat) / 2 * .pi / 180))
        let adjLon  = CGFloat(lonSpan) * cosLat
        let fitSize = radius * 2 * 0.78
        let scale   = min(fitSize / adjLon, fitSize / CGFloat(latSpan))
        let drawW   = adjLon * scale
        let drawH   = CGFloat(latSpan) * scale
        let originX = center.x - drawW / 2
        let originY = center.y - drawH / 2

        func toPoint(_ c: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(
                x: originX + CGFloat(c.longitude - rawMinLon) * cosLat * scale,
                y: originY + CGFloat(1.0 - (c.latitude - rawMinLat) / latSpan) * drawH
            )
        }

        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let circleRect = CGRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2)

        // Interior (clipped to circle)
        ctx.saveGState()
        UIBezierPath(ovalIn: circleRect).addClip()

        UIColor(white: 0.955, alpha: 1).setFill()
        UIBezierPath(ovalIn: circleRect).fill()

        let zoneAlphas: [CGFloat] = [0.82, 0.42, 0.62, 0.28, 0.72]
        for (i, zone) in zones.enumerated() {
            guard zone.coordinates.count >= 3 else { continue }
            let pts  = zone.coordinates.map { toPoint($0) }
            let path = UIBezierPath()
            path.move(to: pts[0]); pts.dropFirst().forEach { path.addLine(to: $0) }; path.close()
            let a = zoneAlphas[i % zoneAlphas.count]
            let fillColor: UIColor = colorPDFs
                ? accent.withAlphaComponent(a)
                : UIColor(white: 0.55 - a * 0.2, alpha: 1)
            fillColor.setFill()
            accent.withAlphaComponent(min(1, a + 0.12)).setStroke()
            path.lineWidth = 0.75; path.fill(); path.stroke()
        }

        // Zone labels inside circle
        for (i, zone) in zones.enumerated() {
            guard zone.coordinates.count >= 3 else { continue }
            let pts = zone.coordinates.map { toPoint($0) }
            let cx  = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
            let cy  = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
            guard circleRect.contains(CGPoint(x: cx, y: cy)) else { continue }
            let a   = zoneAlphas[i % zoneAlphas.count]
            let fg: UIColor = a > 0.55 ? .white : UIColor(white: 0.1, alpha: 1)
            let attr = NSAttributedString(string: zone.label, attributes: [
                .font: UIFont(name: "GillSans-Bold", size: 6.5) ?? .systemFont(ofSize: 6.5, weight: .bold),
                .foregroundColor: fg
            ])
            let sz = attr.size()
            attr.draw(at: CGPoint(x: cx - sz.width / 2, y: cy - sz.height / 2))
        }

        ctx.restoreGState()

        // Circle border
        accent.withAlphaComponent(0.5).setStroke()
        UIBezierPath(ovalIn: circleRect.insetBy(dx: 0.5, dy: 0.5)).lineWidth = 1.2
        UIBezierPath(ovalIn: circleRect.insetBy(dx: 0.5, dy: 0.5)).stroke()

        // Degree hash marks on the ring outside the circle
        drawCompassRing(center: center, radius: radius, accent: accent)
    }

    private static func drawCompassRing(center: CGPoint, radius: CGFloat, accent: UIColor) {
        // 12 tick marks at 30° intervals — major at cardinal (every 90°), minor otherwise
        for i in 0..<12 {
            let angleDeg = Double(i) * 30.0
            let angleRad = CGFloat(angleDeg - 90) * .pi / 180  // -90° rotates 0° to top (N)
            let isMajor  = i % 3 == 0   // 0°, 90°, 180°, 270°
            let tickInner = radius + 3
            let tickOuter = radius + (isMajor ? 10 : 6)
            let cosA = cos(angleRad), sinA = sin(angleRad)

            inkLight.withAlphaComponent(isMajor ? 0.7 : 0.45).setStroke()
            let tick = UIBezierPath()
            tick.move(to: CGPoint(x: center.x + tickInner * cosA, y: center.y + tickInner * sinA))
            tick.addLine(to: CGPoint(x: center.x + tickOuter * cosA, y: center.y + tickOuter * sinA))
            tick.lineWidth = isMajor ? 1.2 : 0.75
            tick.stroke()
        }

        // N arrow — small filled triangle just above the tick at N
        let arrowTip  = CGPoint(x: center.x, y: center.y - radius - 3)
        let arrowBase = center.y - radius + 5
        let aw: CGFloat = 5
        accent.setFill()
        let arrow = UIBezierPath()
        arrow.move(to: arrowTip)
        arrow.addLine(to: CGPoint(x: center.x - aw, y: arrowBase))
        arrow.addLine(to: CGPoint(x: center.x + aw, y: arrowBase))
        arrow.close(); arrow.fill()

        // Cardinal labels outside the tick ring
        let labelOffset: CGFloat = radius + 18
        let cardinals: [(String, CGFloat, Bool)] = [
            ("N", -.pi / 2, true),
            ("S",  .pi / 2, false),
            ("E",  0,       false),
            ("W",  .pi,     false),
        ]
        for (label, angle, isNorth) in cardinals {
            let lx = center.x + labelOffset * cos(angle)
            let ly = center.y + labelOffset * sin(angle)
            let font: UIFont = isNorth
                ? (UIFont(name: "GillSans-Bold", size: 10)   ?? .systemFont(ofSize: 10, weight: .bold))
                : (UIFont(name: "GillSans-SemiBold", size: 8) ?? .systemFont(ofSize: 8))
            let color: UIColor = isNorth ? accent : inkMid
            let attr = NSAttributedString(string: label,
                                          attributes: [.font: font, .foregroundColor: color])
            let sz = attr.size()
            attr.draw(at: CGPoint(x: lx - sz.width / 2, y: ly - sz.height / 2))
        }
    }

    // MARK: - Service Table

    @discardableResult
    private static func drawServiceTable(
        proposal: Proposal, contentW: CGFloat, margin: CGFloat,
        y: CGFloat, accent: UIColor
    ) -> CGFloat {
        var curY = y
        let c1 = contentW * 0.44
        let c2 = contentW * 0.22
        let c3 = contentW * 0.14
        let c4 = contentW - c1 - c2 - c3

        // Section label
        drawText("DESCRIPTION OF SERVICES", x: margin, y: curY, width: contentW,
                 font: labelFont(8.5), color: accent, kern: 2)
        curY += 16

        // Column headers
        let hFont = labelFont(8)
        drawText("DESCRIPTION", x: margin,               y: curY, width: c1, font: hFont, color: inkMid, kern: 0.5)
        drawText("ZONE",        x: margin + c1,           y: curY, width: c2, font: hFont, color: inkMid, kern: 0.5)
        drawText("QTY",         x: margin + c1 + c2,      y: curY, width: c3, font: hFont, color: inkMid, kern: 0.5, alignment: .right)
        drawText("AMOUNT",      x: margin + c1 + c2 + c3, y: curY, width: c4 - 4, font: hFont, color: inkMid, kern: 0.5, alignment: .right)
        curY += 12

        // Accent underline
        accent.withAlphaComponent(0.65).setStroke()
        let rl = UIBezierPath()
        rl.move(to: CGPoint(x: margin, y: curY))
        rl.addLine(to: CGPoint(x: margin + contentW, y: curY))
        rl.lineWidth = 1.2; rl.stroke()
        curY += 9

        let nameFont = bodyBoldFont(11)
        let dataFont = bodyFont(11)
        let noteFont = italicFont(9)
        let items    = proposal.sortedLineItems
        for item in items {
            let hasNotes = !item.itemNotes.isEmpty
            let rowH: CGFloat = hasNotes ? 34 : 26
            let rY   = curY + 7
            drawServiceIcon(name: iconForService(item.serviceName),
                            rect: CGRect(x: margin, y: rY, width: 11, height: 11),
                            color: accent.withAlphaComponent(0.45))
            drawText(item.serviceName, x: margin + 15, y: rY, width: c1 - 15, font: nameFont, color: ink)
            if hasNotes {
                drawText(item.itemNotes, x: margin + 15, y: rY + 14, width: c1 - 15,
                         font: noteFont, color: inkMid)
            }
            drawText(item.zoneLabel, x: margin + c1, y: rY, width: c2, font: dataFont, color: inkDark)
            let qtyStr = item.unitType == "flat" ? "—" : "\(Int(item.quantity)) ft²"
            drawText(qtyStr, x: margin + c1 + c2, y: rY, width: c3,
                     font: dataFont, color: inkMid, alignment: .right)
            drawText(String(format: "$%.2f", item.lineTotal),
                     x: margin + c1 + c2 + c3, y: rY, width: c4 - 4,
                     font: nameFont, color: ink, alignment: .right)
            curY += rowH
            drawHRule(x: margin, y: curY, width: contentW, weight: 0.5, color: ruleLight)
        }
        return curY
    }

    // MARK: - Totals

    @discardableResult
    private static func drawTotals(
        proposal: Proposal, isInvoice: Bool,
        contentW: CGFloat, margin: CGFloat, y: CGFloat, accent: UIColor
    ) -> CGFloat {
        var curY = y + 10
        let lX = margin + contentW * 0.54
        let lW = contentW * 0.29
        let vW = contentW * 0.17
        let vX = margin + contentW - vW

        if proposal.discountAmount > 0 || proposal.taxRate > 0 {
            subtotalRow("Sub-Total", value: proposal.subtotal, lX: lX, lW: lW, vX: vX, vW: vW, y: curY)
            curY += 17
        }
        if proposal.discountAmount > 0 {
            subtotalRow("Discount", value: proposal.discountAmount, lX: lX, lW: lW, vX: vX, vW: vW, y: curY, negate: true)
            curY += 17
        }
        if proposal.taxRate > 0 {
            subtotalRow(String(format: "Tax (%.1f%%)", proposal.taxRate),
                        value: proposal.taxAmount, lX: lX, lW: lW, vX: vX, vW: vW, y: curY)
            curY += 17
        }

        curY += 6
        drawHRule(x: lX, y: curY, width: lW + vW, weight: 0.75, color: ruleMid)
        curY += 12

        let totalLabel = isInvoice ? "TOTAL DUE" : "TOTAL"
        drawText(totalLabel, x: lX, y: curY, width: lW,
                 font: labelFont(10), color: accent, kern: 1.5, alignment: .right)
        drawText(String(format: "$%.2f", proposal.total), x: vX, y: curY, width: vW,
                 font: bodyBoldFont(14), color: ink, alignment: .right)
        return curY + 24
    }

    private static func subtotalRow(
        _ label: String, value: Double,
        lX: CGFloat, lW: CGFloat, vX: CGFloat, vW: CGFloat,
        y: CGFloat, negate: Bool = false
    ) {
        drawText(label, x: lX, y: y, width: lW, font: bodyFont(11), color: inkMid, alignment: .right)
        let valStr = negate
            ? String(format: "−$%.2f", abs(value))
            : String(format: "$%.2f", value)
        drawText(valStr, x: vX, y: y, width: vW, font: bodyFont(11), color: inkDark, alignment: .right)
    }

    // MARK: - Notes

    @discardableResult
    private static func drawNotes(
        proposal: Proposal, contentW: CGFloat, margin: CGFloat, y: CGFloat
    ) -> CGFloat {
        drawText("NOTES", x: margin, y: y, width: contentW,
                 font: labelFont(7.5), color: inkLight, kern: 1.5)
        let textY = y + 15
        drawText(proposal.notes, x: margin, y: textY, width: contentW,
                 font: bodyFont(10.5), color: inkDark)
        let lines = max(1, (proposal.notes.count / 85) + 1)
        return textY + CGFloat(lines) * 14
    }

    // MARK: - Disclaimer

    private static func drawDisclaimer(
        proposal: Proposal, contentW: CGFloat, margin: CGFloat, y: CGFloat
    ) {
        drawHRule(x: margin, y: y, width: contentW, weight: 0.5, color: ruleLight)
        drawText(proposal.disclaimer, x: margin, y: y + 10, width: contentW,
                 font: italicFont(9), color: inkLight)
    }

    // MARK: - Payment Section

    private static func drawPaymentSection(
        methods: [PaymentMethod], contentW: CGFloat, margin: CGFloat,
        y: CGFloat, accent: UIColor
    ) {
        drawHRule(x: margin, y: y, width: contentW, weight: 0.75, color: ruleLight)
        var curY = y + 14
        drawText("PAYMENT OPTIONS", x: margin, y: curY, width: contentW,
                 font: labelFont(8), color: accent, kern: 2)
        curY += 15

        let qrSize: CGFloat = 72
        let firstURL = methods.first { $0.isURLBased && !$0.value.isEmpty }
        let listW = firstURL != nil ? contentW - qrSize - 20 : contentW

        for method in methods {
            let (text, color) = paymentLine(method)
            drawText(text, x: margin, y: curY, width: listW, font: bodyFont(10.5), color: color)
            curY += 17
        }

        if let urlMethod = firstURL, let qrImg = makeQRCode(from: urlMethod.value, size: qrSize) {
            qrImg.draw(in: CGRect(x: margin + listW + 20, y: y + 28, width: qrSize, height: qrSize))
            drawText("Scan to pay", x: margin + listW + 20, y: y + 28 + qrSize + 3, width: qrSize,
                     font: italicFont(7), color: inkLight, alignment: .center)
        }
    }

    private static func paymentLine(_ method: PaymentMethod) -> (String, UIColor) {
        if method.isCash  { return ("Cash accepted", inkMid) }
        if method.isCheck { return ("Make check payable to: \(method.value)", inkDark) }
        let text = method.value.isEmpty ? method.label : "\(method.label): \(method.value)"
        return (text, method.isURLBased ? UIColor.systemBlue : inkDark)
    }

    // MARK: - Footer

    private static func drawFooter(
        profile: BusinessProfile?, pageW: CGFloat, pageH: CGFloat,
        margin: CGFloat, contentW: CGFloat
    ) {
        let footerY = pageH - margin - 14
        drawHRule(x: margin, y: footerY - 10, width: contentW, weight: 0.5, color: ruleLight)
        let biz = profile?.companyName.isEmpty == false ? "\(profile!.companyName)  ·  " : ""
        drawText("\(biz)Prepared with PlowR", x: margin, y: footerY, width: contentW,
                 font: bodyFont(8), color: inkLight, alignment: .center)
    }

    // MARK: - Color Helpers

    private static func accentUIColor(from hex: String?) -> UIColor? {
        guard let hex, hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return UIColor(
            red:   CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >>  8) & 0xFF) / 255,
            blue:  CGFloat( value        & 0xFF) / 255,
            alpha: 1
        )
    }

    // MARK: - Service Icons

    private static func iconForService(_ name: String) -> String {
        let l = name.lowercased()
        if l.contains("snow") || l.contains("plow")                          { return "snowflake" }
        if l.contains("ice") || l.contains("salt")                           { return "thermometer.snowflake" }
        if l.contains("lawn") || l.contains("mow")                           { return "leaf.fill" }
        if l.contains("tree") || l.contains("landscap") ||
           l.contains("mulch") || l.contains("plant")                        { return "tree.fill" }
        if l.contains("walk") || l.contains("shovel") || l.contains("path")  { return "figure.walk" }
        if l.contains("driv") || l.contains("clean") || l.contains("wash")   { return "sparkles" }
        if l.contains("edge") || l.contains("trim")                          { return "scissors" }
        if l.contains("haul") || l.contains("debris") || l.contains("remov") { return "trash.fill" }
        if l.contains("fert") || l.contains("seed")                          { return "drop.fill" }
        return "wrench.and.screwdriver.fill"
    }

    private static func drawServiceIcon(name: String, rect: CGRect, color: UIColor) {
        let cfg = UIImage.SymbolConfiguration(pointSize: rect.width, weight: .medium)
        guard let img = UIImage(systemName: name, withConfiguration: cfg)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        img.draw(in: rect)
    }

    // MARK: - QR Code

    private static func makeQRCode(from string: String, size: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - Primitives

    private static func drawHRule(x: CGFloat, y: CGFloat, width: CGFloat, weight: CGFloat, color: UIColor) {
        color.setStroke()
        let p = UIBezierPath()
        p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + width, y: y))
        p.lineWidth = weight; p.stroke()
    }

    private static func drawText(
        _ text: String, x: CGFloat, y: CGFloat, width: CGFloat,
        font: UIFont, color: UIColor,
        kern: CGFloat = 0, alignment: NSTextAlignment = .left,
        singleLine: Bool = false
    ) {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        if singleLine { para.lineBreakMode = .byTruncatingTail }
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: para
        ]
        if kern != 0 { attrs[.kern] = kern }
        let height: CGFloat = singleLine ? ceil(font.lineHeight) + 4 : 300
        NSAttributedString(string: text, attributes: attrs)
            .draw(in: CGRect(x: x, y: y, width: width, height: height))
    }
}
