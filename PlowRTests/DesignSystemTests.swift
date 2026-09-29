//
//  DesignSystemTests.swift
//  PlowRTests
//

import Testing
import UIKit
@testable import PlowR

struct DesignSystemTests {

    // The brand navy exists twice in DesignSystem.swift: as a hex string
    // (what BusinessProfile stores and the PDF reads) and as RGB components
    // (what the app tints with). Editing one without the other would make the
    // PDF and the app disagree, silently. Within half a step of 255, so a
    // one-step change to either fails (a whole step let one direction pass).
    @Test func navyHexAndRGBAreTheSameColour() throws {
        let hex = try #require(UInt32(PlowRColor.navyHex, radix: 16))
        let expected = [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
        ]
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(PlowRColor.navyUIColor.getRed(&r, green: &g, blue: &b, alpha: &a))
        for (actual, want) in zip([r, g, b], expected) {
            #expect(abs(actual - want) < 0.5 / 255)
        }
    }

    // Light-mode accent is the brand navy; dark mode is the brighter blue it
    // shipped with (0.53, 0.70, 1.00). Pinned by value, so a change to the
    // dark tint of the whole app shows up here instead of passing silently.
    @Test func accentIsNavyInLightAndBrightBlueInDark() {
        let light = PlowRColor.accentUIColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = PlowRColor.accentUIColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(light == PlowRColor.navyUIColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(dark.getRed(&r, green: &g, blue: &b, alpha: &a))
        for (actual, want) in zip([r, g, b], [0.53, 0.70, 1.00] as [CGFloat]) {
            #expect(abs(actual - want) <= 0.001)
        }
    }
}
