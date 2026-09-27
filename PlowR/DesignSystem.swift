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

enum PlowRColor {

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
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.53, green: 0.70, blue: 1.00, alpha: 1)
            : navyUIColor
    }
    static let accent = Color(accentUIColor)
}
