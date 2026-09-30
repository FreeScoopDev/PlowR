//
//  DesignSystem.swift
//  PlowR
//
//  Shared design tokens. Compiled into the app AND the widget extension
//  (a membership exception in project.pbxproj, like RouteActivityAttributes),
//  so the widget and Live Activity can use the same values instead of copies.
//
//  Add a token here the moment a value is needed in a second place. A value
//  hand-copied into two files is a drift waiting to happen: the brand navy was
//  in four places before this file existed.
//

import SwiftUI
import UIKit

// `nonisolated` because the app target defaults everything to @MainActor but
// SwiftData's generated model code (BusinessProfile's default accentColorHex)
// reads these off the main actor. Without it, that is a warning under strict
// concurrency and an error in Swift 6 mode. It also gives the file the same
// isolation in the widget, which has no default actor.
nonisolated enum PlowRColor {

    /// Brand navy, light appearance, as the hex string stored in
    /// `BusinessProfile.accentColorHex`. Must describe the same colour as
    /// `navyUIColor`; `DesignSystemTests` checks that.
    static let navyHex = "1E3A8A"

    /// Brand navy, fixed (no dark variant). For surfaces that don't follow the
    /// system appearance: PDFs, and the default client avatar fill.
    static let navyUIColor = UIColor(red: 0.118, green: 0.227, blue: 0.541, alpha: 1)
    static let navy = Color(navyUIColor)

    /// The app's tint: navy in light mode, a brighter blue in dark mode so it
    /// stays readable on dark backgrounds.
    static let accentUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? accentDarkUIColor : navyUIColor
    }
    static let accent = Color(accentUIColor)

    /// The accent's dark-mode colour: a brighter blue, readable on dark backgrounds.
    static let accentDarkUIColor = UIColor(red: 0.53, green: 0.70, blue: 1.00, alpha: 1)
}

/// Shared sizes, so the same kind of element is drawn the same way on every
/// screen. Screens had grown their own values (tiles at radius 12 or 14 with
/// gaps of 10, 12 or 24); these are the few the app uses. Corners are
/// `.continuous` wherever they're used.
nonisolated enum PlowRLayout {
    /// Small insets inside a card: thumbnails, notes.
    static let cornerSmall: CGFloat = 8
    /// Tiles and stat cards.
    static let cornerMedium: CGFloat = 12
    /// Cards and panels.
    static let cornerLarge: CGFloat = 14
    /// Between tiles in a row or grid.
    static let tileSpacing: CGFloat = 8
}
