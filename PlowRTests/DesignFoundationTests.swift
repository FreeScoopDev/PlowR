import Foundation
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

    /// A quote is blue wherever it shows (a proposal, the Pipeline), a lead
    /// purple: the client page drew a quote purple and Home drew it blue.
    @Test func pipelineStagesMatchTheirDocuments() {
        #expect(Pipeline.Stage.quoted.chipStatus == InvoiceStatus.proposal.chipStatus)
        #expect(Pipeline.Stage.lead.chipStatus == .lead)
        #expect(Pipeline.Stage.lost.chipStatus == .void)
    }

    /// The two greys differ only in lightness, so they must differ enough
    /// to tell a draft's bar from a void one's (at least 2:1).
    @Test(arguments: [false, true])
    func neutralAndVoidAreTwoGreys(dark: Bool) {
        func luminance(_ hex: UInt32) -> Double {
            func channel(_ shift: UInt32) -> Double {
                let c = Double((hex >> shift) & 0xFF) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        }
        let a = luminance(hex(PlowRColor.Status.neutral.fillUIColor, dark: dark))
        let b = luminance(hex(PlowRColor.Status.void.fillUIColor, dark: dark))
        #expect((max(a, b) + 0.05) / (min(a, b) + 0.05) >= 2)
    }
}
