import SwiftUI
import Testing
import UIKit
@testable import PlowR

/// The 1.7 design across the app: one accent, one meaning per status colour.
@MainActor
struct DesignFoundationTests {
    private func hex(_ color: UIColor, dark: Bool) -> UInt32 {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32((r * 255).rounded()) << 16 | UInt32((g * 255).rounded()) << 8 | UInt32((b * 255).rounded())
    }

    /// `Color.accentColor` (the asset) and `PlowRColor.accent` (the tint) are
    /// the same green: screens that use either look the same. The asset was
    /// empty, so those screens fell back to system blue.
    @Test(arguments: [false, true])
    func theAccentColourAssetIsTheBrand(dark: Bool) throws {
        let asset = try #require(UIColor(named: "AccentColor", in: Bundle(for: AuthManager.self), compatibleWith: nil))
        #expect(hex(asset, dark: dark) == hex(PlowRColor.brandUIColor, dark: dark))
        #expect(hex(PlowRColor.accentUIColor, dark: dark) == hex(PlowRColor.brandUIColor, dark: dark))
    }

    /// Money owed amber, late red, paid green, a quote blue, a draft plain,
    /// void grey: the same on every screen.
    @Test func invoiceStatusesHaveOneColourEach() {
        #expect(InvoiceStatus.sent.chipStatus == .owed)
        #expect(InvoiceStatus.overdue.chipStatus == .overdue)
        #expect(InvoiceStatus.paid.chipStatus == .done)
        #expect(InvoiceStatus.proposal.chipStatus == .scheduled)
        #expect(InvoiceStatus.draft.chipStatus == .neutral)
        #expect(InvoiceStatus.void.chipStatus == .void)
    }

    /// A cancelled visit is void, not red: red is for money that's late.
    @Test func visitStatusesHaveOneColourEach() {
        #expect(VisitStatus.scheduled.chipStatus == .scheduled)
        #expect(VisitStatus.completed.chipStatus == .done)
        #expect(VisitStatus.cancelled.chipStatus == .void)
        #expect(VisitStatus.skipped.chipStatus == .owed)
    }

    @Test func contractStatusesHaveOneColourEach() {
        #expect(Contracts.Status.active.chipStatus == .done)
        #expect(Contracts.Status.upcoming.chipStatus == .done)
        #expect(Contracts.Status.draft.chipStatus == .neutral)
        #expect(Contracts.Status.ended.chipStatus == .void)
        #expect(Contracts.Status.cancelled.chipStatus == .void)
    }

    /// Every status colour is its own: no two statuses can be told apart
    /// only by their word.
    @Test(arguments: [false, true])
    func everyStatusFillIsDistinct(dark: Bool) {
        let fills = PlowRColor.Status.allCases.map { hex($0.fillUIColor, dark: dark) }
        #expect(Set(fills).count == fills.count)
    }
}
