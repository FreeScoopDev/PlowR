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

    // The app's tint is the brand forest green in both appearances (1.7).
    // Pinned by value, so a change to the tint of the whole app shows up here
    // instead of passing silently.
    @Test func accentIsTheBrandGreen() {
        let light = PlowRColor.accentUIColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = PlowRColor.accentUIColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        func rgb(_ color: UIColor) -> [CGFloat] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            #expect(color.getRed(&r, green: &g, blue: &b, alpha: &a))
            return [r, g, b]
        }
        for (actual, want) in zip(rgb(light), [0x1F, 0x4D, 0x3A].map { CGFloat($0) / 255 }) {
            #expect(abs(actual - want) <= 0.001)
        }
        for (actual, want) in zip(rgb(dark), [0x9C, 0xCF, 0xB3].map { CGFloat($0) / 255 }) {
            #expect(abs(actual - want) <= 0.001)
        }
    }
}
