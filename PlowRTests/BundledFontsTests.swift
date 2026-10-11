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
    // Every face the type roles use (PlowRFont.Weight), so a face added there
    // without its file fails here instead of quietly falling back.
    @Test(arguments: PlowRFont.Weight.allCases)
    func everyFaceIsRegistered(weight: PlowRFont.Weight) {
        #expect(UIFont(name: weight.rawValue, size: 17) != nil, "\(weight.rawValue) isn't in UIAppFonts or the bundle")
    }

    @Test func theTypeRolesUseBarlow() {
        #expect(PlowRFont.isBarlowAvailable)
    }

    @Test func theLicenceShipsWithTheFont() throws {
        let text = try #require(FontLicenseView.text)
        #expect(text.contains("SIL Open Font License"))
        #expect(text.contains("The Barlow Project Authors"))
    }

    // The licence file is hard-wrapped; on screen its paragraphs flow.
    @Test func theLicenceIsReflowedForTheScreen() {
        #expect(FontLicenseView.reflowed("a\nb\n\nc") == "a b\n\nc")
        #expect(FontLicenseView.reflowed(FontLicenseView.fallback).contains("Copyright 2017 The Barlow Project Authors"))
    }
}
