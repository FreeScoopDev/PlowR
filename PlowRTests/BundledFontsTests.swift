//
//  BundledFontsTests.swift
//  PlowRTests
//

import Testing
import UIKit
@testable import PlowR

/// Barlow (Joe's pick for headings, numbers and buttons, 2026-10-10) is in
/// the app: every face registers, and its licence travels with it.
@MainActor
struct BundledFontsTests {
    @Test(arguments: ["Barlow-Medium", "Barlow-SemiBold", "Barlow-Bold", "Barlow-ExtraBold"])
    func everyFaceIsRegistered(face: String) {
        #expect(UIFont(name: face, size: 17) != nil, "\(face) isn't in UIAppFonts or the bundle")
    }

    @Test func theLicenceShipsWithTheFont() throws {
        let text = try #require(FontLicenseView.text)
        #expect(text.contains("SIL Open Font License"))
        #expect(text.contains("The Barlow Project Authors"))
    }
}
