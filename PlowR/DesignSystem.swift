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

// MARK: - Evergreen & Copper (the 1.7 design)

// Chosen by Joe on 2026-10-10 from mockups of four schemes: forest green for
// the brand, copper for the one action that matters on each screen, warm
// neutrals, and a deep forest green (not black) in dark mode. These are the
// tokens screens move to one at a time; until a screen does, it keeps its
// current colors, so adding them changes nothing on screen.
nonisolated extension PlowRColor {
    /// A color with a light and a dark appearance.
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) }
    }

    static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    // Surfaces, back to front.
    static let groundUIColor = adaptive(0xF5F2EC, 0x0D1813)
    static let surfaceUIColor = adaptive(0xFFFFFF, 0x15251D)
    static let raisedUIColor = adaptive(0xEAE5DB, 0x1E3328)
    static let lineUIColor = adaptive(0xDDD6CA, 0x284034)

    // Text.
    static let inkUIColor = adaptive(0x17201B, 0xEEF1EC)
    static let inkSecondaryUIColor = adaptive(0x5B635D, 0xA3AEA6)

    /// Forest green: the brand, navigation, the client avatar.
    static let brandUIColor = adaptive(0x1F4D3A, 0x9CCFB3)
    static let onBrandUIColor = adaptive(0xFFFFFF, 0x0D1813)

    /// Copper: the one main action on a screen (Complete Stop, Resume Route,
    /// Invoice). Brighter in dark mode, so it stays the brightest thing there.
    static let actionUIColor = adaptive(0xA85A22, 0xE0954F)
    static let onActionUIColor = adaptive(0xFFFFFF, 0x1C0E03)
    /// A copper-tinted background, and the text that goes on it.
    static let actionSoftUIColor = adaptive(0xF4E1D2, 0x3A2715)
    static let actionTextUIColor = adaptive(0x7E4318, 0xF0B27A)

    static let ground = Color(groundUIColor)
    static let surface = Color(surfaceUIColor)
    static let raised = Color(raisedUIColor)
    static let line = Color(lineUIColor)
    static let ink = Color(inkUIColor)
    static let inkSecondary = Color(inkSecondaryUIColor)
    static let brand = Color(brandUIColor)
    static let onBrand = Color(onBrandUIColor)
    static let action = Color(actionUIColor)
    static let onAction = Color(onActionUIColor)
    static let actionSoft = Color(actionSoftUIColor)
    static let actionText = Color(actionTextUIColor)

    /// What state a thing is in: one meaning per color, the same in every
    /// scheme and on every screen. A chip always says its word too, so color
    /// is never the only signal.
    nonisolated enum Status: CaseIterable {
        case done, scheduled, owed, overdue, lead, void

        /// For dots, bars and map pins.
        var fillUIColor: UIColor {
            switch self {
            case .done: adaptive(0x2F7D4F, 0x6CCB8E)
            case .scheduled: adaptive(0x2B6CB0, 0x7FB2EA)
            case .owed: adaptive(0xB7791F, 0xF2B94B)
            case .overdue: adaptive(0xC53030, 0xF28B8B)
            case .lead: adaptive(0x6B46C1, 0xB49AF0)
            case .void: adaptive(0x6B7280, 0x9CA3AF)
            }
        }

        /// A chip's background.
        var softUIColor: UIColor {
            switch self {
            case .done: adaptive(0xE3F2E8, 0x16301F)
            case .scheduled: adaptive(0xE1ECF8, 0x152B44)
            case .owed: adaptive(0xFBF0DB, 0x3A2C12)
            case .overdue: adaptive(0xFBE3E3, 0x3D1C1C)
            case .lead: adaptive(0xECE5F8, 0x2A2140)
            case .void: adaptive(0xEDEEF0, 0x262B33)
            }
        }

        /// A chip's text, and an amount shown in this state.
        var textUIColor: UIColor {
            switch self {
            case .done: adaptive(0x22603B, 0x8FDDA9)
            case .scheduled: adaptive(0x24578F, 0xA5CAF2)
            case .owed: adaptive(0x8A5A10, 0xF6CD7A)
            case .overdue: adaptive(0xA62626, 0xF6AAAA)
            case .lead: adaptive(0x5A3AA8, 0xC4B0F5)
            case .void: adaptive(0x4B5260, 0xC3C8D0)
            }
        }

        var fill: Color { Color(fillUIColor) }
        var soft: Color { Color(softUIColor) }
        var text: Color { Color(textUIColor) }
    }

    /// The kind of work: tags and map pins. White text on each.
    nonisolated enum Service: CaseIterable {
        case snow, lawn, landscaping

        var fillUIColor: UIColor {
            switch self {
            case .snow: rgb(0x2F6F98)
            case .lawn: rgb(0x3F7D23)
            case .landscaping: rgb(0x8A5A2B)
            }
        }

        var fill: Color { Color(fillUIColor) }
    }
}

// MARK: - Type

/// Text roles. Headings, numbers and buttons are Barlow (Joe, 2026-10-10:
/// tall, clear, made for reading at a glance); body text stays the system
/// font. Every role scales with the user's text size (`relativeTo`), and
/// falls back to the system font, same weight, when Barlow isn't bundled.
nonisolated enum PlowRFont {
    enum Weight: String, CaseIterable {
        case medium = "Barlow-Medium", semibold = "Barlow-SemiBold", bold = "Barlow-Bold", extraBold = "Barlow-ExtraBold"

        var system: Font.Weight {
            switch self {
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .extraBold: .heavy
            }
        }
    }

    /// Whether every Barlow face is in the app (registered in Info.plist): a
    /// missing face would draw as the regular system font, not fall back at
    /// its weight.
    static let isBarlowAvailable = Weight.allCases.allSatisfy { UIFont(name: $0.rawValue, size: 12) != nil }

    /// Barlow at `size`, scaling with `style`; the system font if Barlow is
    /// missing (`available` is a parameter so both paths are tested).
    static func barlow(_ weight: Weight, size: CGFloat, relativeTo style: Font.TextStyle,
                       available: Bool = isBarlowAvailable) -> Font {
        available
            ? .custom(weight.rawValue, size: size, relativeTo: style)
            : .system(style, weight: weight.system)
    }

    /// A screen's own title.
    static let screenTitle = barlow(.bold, size: 32, relativeTo: .largeTitle)
    /// A card or section title: a client's or a route's name.
    static let title = barlow(.bold, size: 22, relativeTo: .title2)
    /// The current stop's name on the route screen.
    static let stopName = barlow(.extraBold, size: 26, relativeTo: .title)
    /// A big figure at a glance: minutes to the next stop, a total owed.
    static let bigNumber = barlow(.extraBold, size: 40, relativeTo: .largeTitle)
    /// A figure in a row or tile: an amount, a count, a time.
    static let number = barlow(.semibold, size: 17, relativeTo: .headline)
    /// A button's label.
    static let button = barlow(.bold, size: 17, relativeTo: .headline)
    /// A small uppercase label over a section ("NEXT UP"); never smaller than footnote.
    static let label = barlow(.semibold, size: 13, relativeTo: .footnote)
}

// MARK: - Spacing and touch

nonisolated extension PlowRLayout {
    /// The spacing scale: every gap and inset is one of these.
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space6: CGFloat = 24

    /// Apple's minimum tap target.
    static let minTapTarget: CGFloat = 44
    /// Secondary buttons beside a glove-height one (Navigate, Record Services).
    static let secondaryTapTarget: CGFloat = 48
    /// The main buttons on the route screen: big enough for gloves.
    static let gloveTapTarget: CGFloat = 56
}

// MARK: - Icons

/// One SF Symbol per idea, so the same thing looks the same everywhere (the
/// audit found four symbols for "route" and six for "invoice"). Filled in tab
/// bars, tiles and primary buttons; screens take `.fill` off for list rows.
/// No snow symbol here: this file is shared by every screen and the widget,
/// and snow-only icons live with snow-only features (ServiceIcon).
/// `scripts/check_symbols.py` checks each name exists on iOS 26.0.
nonisolated enum PlowRSymbol: String, CaseIterable {
    case home = "house.fill"
    case client = "person.2.fill"
    case addClient = "person.badge.plus"
    case route = "point.topleft.down.to.point.bottomright.curvepath"
    case document = "doc.text.fill"
    case proposal = "doc.richtext.fill"
    case contract = "signature"
    case payment = "dollarsign.circle.fill"
    case schedule = "calendar"
    case weather = "cloud.sun.fill"
    case navigate = "arrow.triangle.turn.up.right.circle.fill"
    case call = "phone.fill"
    case text = "message.fill"
    case email = "envelope.fill"
    case complete = "checkmark.circle.fill"
    case settings = "gearshape.fill"
    case pro = "star.circle.fill"
    case warning = "exclamationmark.triangle.fill"

    /// The name, for `Image(systemName:)` and `Label(_:systemImage:)`.
    var name: String { rawValue }
}
