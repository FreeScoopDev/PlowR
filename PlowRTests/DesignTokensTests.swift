//
//  DesignTokensTests.swift
//  PlowRTests
//

import SwiftUI
import Testing
import UIKit
@testable import PlowR

/// The 1.7 design tokens (Evergreen & Copper): every text color is readable
/// on the background it's meant for, in light and dark mode, by the WCAG
/// contrast rule (4.5:1 for text). The point of the scheme is reading it
/// early in the morning and late at night.
@MainActor
struct DesignTokensTests {
    private func resolved(_ color: UIColor, dark: Bool) -> UIColor {
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
    }

    /// WCAG relative luminance contrast, 1 to 21.
    private func contrast(_ a: UIColor, _ b: UIColor, dark: Bool) -> Double {
        func luminance(_ c: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
            resolved(c, dark: dark).getRed(&r, green: &g, blue: &b, alpha: &al)
            func lin(_ v: CGFloat) -> Double {
                let v = Double(v)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    @Test(arguments: [false, true])
    func textIsReadableOnItsBackground(dark: Bool) {
        typealias C = PlowRColor
        let pairs: [(String, UIColor, UIColor)] = [
            ("ink on ground", C.inkUIColor, C.groundUIColor),
            ("ink on surface", C.inkUIColor, C.surfaceUIColor),
            ("ink on raised", C.inkUIColor, C.raisedUIColor),
            ("secondary on ground", C.inkSecondaryUIColor, C.groundUIColor),
            ("secondary on surface", C.inkSecondaryUIColor, C.surfaceUIColor),
            ("brand on ground", C.brandUIColor, C.groundUIColor),
            ("on-brand on brand", C.onBrandUIColor, C.brandUIColor),
            ("on-action on action", C.onActionUIColor, C.actionUIColor),
            ("action text on action soft", C.actionTextUIColor, C.actionSoftUIColor)
        ]
        for (name, text, background) in pairs {
            #expect(contrast(text, background, dark: dark) >= 4.5, "\(name), dark \(dark)")
        }
    }

    @Test(arguments: [false, true])
    func statusChipsAndAmountsAreReadable(dark: Bool) {
        for status in PlowRColor.Status.allCases {
            #expect(contrast(status.textUIColor, status.softUIColor, dark: dark) >= 4.5, "\(status) chip, dark \(dark)")
            #expect(contrast(status.textUIColor, PlowRColor.surfaceUIColor, dark: dark) >= 4.5,
                    "\(status) amount on a card, dark \(dark)")
        }
    }

    @Test func serviceTagsCarryWhiteText() {
        for service in PlowRColor.Service.allCases {
            #expect(contrast(.white, service.fillUIColor, dark: false) >= 4.5, "\(service)")
        }
    }

    // Each status means one thing: no two share a fill.
    @Test(arguments: [false, true])
    func statusesLookDifferent(dark: Bool) {
        let fills = PlowRColor.Status.allCases.map { resolved($0.fillUIColor, dark: dark) }
        #expect(Set(fills.map { $0.description }).count == fills.count)
    }

    @Test func everyIconExists() {
        for name in PlowRSymbol.all {
            #expect(UIImage(systemName: name) != nil, "\(name)")
        }
    }

    // Until the Barlow files are bundled, every role is the system font, so
    // nothing breaks; the roles are still there for screens to use.
    @Test func typeRolesWorkWithOrWithoutBarlow() {
        let roles: [Font] = [PlowRFont.screenTitle, PlowRFont.title, PlowRFont.stopName, PlowRFont.bigNumber,
                             PlowRFont.number, PlowRFont.button, PlowRFont.label]
        #expect(roles.count == 7)
        #expect(PlowRFont.isBarlowAvailable == (UIFont(name: "Barlow-Bold", size: 12) != nil))
    }
}
