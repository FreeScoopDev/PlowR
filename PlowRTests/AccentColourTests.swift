//
//  AccentColourTests.swift
//  PlowRTests
//

import SwiftUI
import Testing
@testable import PlowR

/// The business profile's accent colour is stored as hex and read back on
/// every visit to the profile: the two must agree, or each save shifts it.
struct AccentColourTests {
    // Every channel value survives hex -> Color -> hex.
    @Test func hexSurvivesARoundTrip() {
        for value in 0...255 {
            let hex = String(format: "%02X%02X%02X", value, 255 - value, (value * 7) % 256)
            #expect(Color(hex: hex)?.hexString == hex, "\(hex)")
        }
        #expect(Color(hex: PlowRColor.navyHex)?.hexString == PlowRColor.navyHex)
    }

    // The form's colour for no profile yet, or hex it can't read (as the
    // wide-gamut bug stored), is the app's navy: a new profile saved without
    // touching it keeps BusinessProfile's default. A readable hex is kept.
    @Test func theFormStartsNavy() {
        #expect(BusinessProfileView.accent(for: nil).hexString == PlowRColor.navyHex)
        #expect(BusinessProfileView.accent(for: "117FFFFFFC6FFFFFFDA").hexString == PlowRColor.navyHex)
        #expect(BusinessProfileView.accent(for: "05FA23").hexString == "05FA23")
        #expect(BusinessProfile(operatorID: "op").accentColorHex == PlowRColor.navyHex)
    }

    // A colour picked outside sRGB still gives six hex digits, clamped.
    @Test func aWideGamutColourIsClamped() {
        let p3Red = Color(.displayP3, red: 1, green: 0, blue: 0)
        #expect(p3Red.hexString == "FF0000")
        #expect(Color(hex: p3Red.hexString) != nil)
    }
}
