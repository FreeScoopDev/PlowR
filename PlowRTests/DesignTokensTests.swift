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

    private func components(_ color: UIColor, dark: Bool) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        let converted = resolved(color, dark: dark).getRed(&r, green: &g, blue: &b, alpha: &alpha)
        #expect(converted && alpha == 1, "every token is an opaque RGB color")
        return (r, g, b)
    }

    /// WCAG relative luminance contrast, 1 to 21.
    private func contrast(_ a: UIColor, _ b: UIColor, dark: Bool) -> Double {
        func luminance(_ c: UIColor) -> Double {
            let (r, g, b) = components(c, dark: dark)
            func lin(_ v: CGFloat) -> Double {
                let v = Double(v)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    typealias C = PlowRColor
    private let surfaces: [(String, UIColor)] = [
        ("ground", C.groundUIColor), ("surface", C.surfaceUIColor), ("raised", C.raisedUIColor)
    ]
    private var texts: [(String, UIColor)] {
        [("ink", C.inkUIColor), ("secondary", C.inkSecondaryUIColor), ("brand", C.brandUIColor),
         ("action text", C.actionTextUIColor)]
            + C.Status.allCases.map { ("\($0) text", $0.textUIColor) }
    }

    // Every text token on every surface, light and dark.
    @Test(arguments: [false, true])
    func textIsReadableOnEverySurface(dark: Bool) {
        for (text, color) in texts {
            for (surface, background) in surfaces {
                #expect(contrast(color, background, dark: dark) >= 4.5, "\(text) on \(surface), dark \(dark)")
            }
        }
    }

    // Text drawn on a colored fill.
    @Test(arguments: [false, true])
    func textOnFillsIsReadable(dark: Bool) {
        let pairs: [(String, UIColor, UIColor)] = [
            ("on-brand on brand", C.onBrandUIColor, C.brandUIColor),
            ("on-action on action", C.onActionUIColor, C.actionUIColor),
            ("action text on action soft", C.actionTextUIColor, C.actionSoftUIColor)
        ] + C.Status.allCases.map { ("\($0) chip", $0.textUIColor, $0.softUIColor) }
        for (name, text, background) in pairs {
            #expect(contrast(text, background, dark: dark) >= 4.5, "\(name), dark \(dark)")
        }
    }

    // Dark mode is really dark: every adaptive token changes with the
    // appearance (a broken provider would test the light pair twice).
    @Test func everyAdaptiveTokenHasADarkVersion() {
        let adaptive: [UIColor] = [C.groundUIColor, C.surfaceUIColor, C.raisedUIColor, C.lineUIColor, C.inkUIColor,
                                   C.inkSecondaryUIColor, C.brandUIColor, C.onBrandUIColor, C.actionUIColor,
                                   C.onActionUIColor, C.actionSoftUIColor, C.actionTextUIColor]
            + C.Status.allCases.flatMap { [$0.fillUIColor, $0.softUIColor, $0.textUIColor] }
        for color in adaptive {
            let light = components(color, dark: false), dark = components(color, dark: true)
            #expect(light != dark)
        }
    }

    @Test func serviceTagsCarryWhiteText() {
        for service in C.Service.allCases {
            #expect(contrast(.white, service.fillUIColor, dark: false) >= 4.5, "\(service)")
        }
    }

    // Each status means one thing: no two share a fill.
    @Test(arguments: [false, true])
    func statusesLookDifferent(dark: Bool) {
        let fills = C.Status.allCases.map { resolved($0.fillUIColor, dark: dark) }
        #expect(Set(fills.map { $0.description }).count == fills.count)
    }

    @Test func everyIconExists() {
        for symbol in PlowRSymbol.allCases {
            #expect(UIImage(systemName: symbol.name) != nil, "\(symbol)")
        }
    }

    /// Each role as it should be: text style, Barlow face, size.
    private let roles: [(String, Font, Font.TextStyle, PlowRFont.Weight, CGFloat)] = [
        ("screenTitle", PlowRFont.screenTitle, .largeTitle, .bold, 32),
        ("title", PlowRFont.title, .title2, .bold, 22),
        ("stopName", PlowRFont.stopName, .title, .extraBold, 26),
        ("bigNumber", PlowRFont.bigNumber, .largeTitle, .extraBold, 40),
        ("number", PlowRFont.number, .headline, .semibold, 17),
        ("button", PlowRFont.button, .headline, .bold, 17),
        ("label", PlowRFont.label, .footnote, .semibold, 13)
    ]

    // Every role, whichever path this build takes: without Barlow, the system
    // font at its text style and weight (so it scales with text size); with
    // it, the named face at its size, scaling with its style.
    @Test func everyRoleIsItsStyleAndWeight() {
        let systemWeight: [PlowRFont.Weight: Font.Weight] = [.medium: .medium, .semibold: .semibold,
                                                             .bold: .bold, .extraBold: .heavy]
        for (name, font, style, weight, size) in roles {
            if PlowRFont.isBarlowAvailable {
                #expect(font == .custom(weight.rawValue, size: size, relativeTo: style), "\(name)")
            } else {
                #expect(font == .system(style, weight: systemWeight[weight] ?? .regular), "\(name)")
                #expect(font != .system(size: size), "\(name) must scale")
            }
        }
        for weight in PlowRFont.Weight.allCases {
            #expect(weight.system == systemWeight[weight])
        }
    }

    // With Barlow, a role is the named face at its size, scaling with its style.
    @Test func withBarlowARoleScalesWithItsTextStyle() {
        let font = PlowRFont.barlow(.bold, size: 32, relativeTo: .largeTitle, available: true)
        #expect(font == .custom("Barlow-Bold", size: 32, relativeTo: .largeTitle))
        #expect(font != .custom("Barlow-Bold", size: 32))
        #expect(font != .custom("Barlow-Bold", size: 32, relativeTo: .footnote))
    }
}
