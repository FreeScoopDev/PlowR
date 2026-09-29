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

    // A new profile saved without touching the colour keeps the app's navy.
    @Test func aNewProfileStartsNavy() {
        #expect(BusinessProfileView.defaultAccent.hexString == PlowRColor.navyHex)
        #expect(BusinessProfile(operatorID: "op").accentColorHex == PlowRColor.navyHex)
    }

    // A colour picked outside sRGB still gives six hex digits, clamped.
    @Test func aWideGamutColourIsClamped() {
        let p3Red = Color(.displayP3, red: 1, green: 0, blue: 0)
        #expect(p3Red.hexString == "FF0000")
        #expect(Color(hex: p3Red.hexString) != nil)
    }
}
