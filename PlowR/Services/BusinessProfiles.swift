import Foundation
import SwiftData

/// A business has one profile. Two devices can each make one before iCloud
/// brings the other's (a new phone set up before its first sync, Business
/// Profile saved on both): every screen then picked whichever came first in
/// an unsorted list, so devices could disagree, and invoices could take an
/// empty name and a 0% tax rate. `current` picks the same one everywhere;
/// `mergeDuplicates` folds the others into it.
enum BusinessProfiles {
    /// The business's profile: the same record on every device (lowest ID).
    static func current(_ profiles: [BusinessProfile], operatorID: String) -> BusinessProfile? {
        profiles.filter { $0.operatorID == operatorID }.min { $0.id.uuidString < $1.id.uuidString }
    }

    /// Folds a business's extra profiles into `current`: whatever the
    /// survivor lacks (a name, a logo, a tax rate, details) is taken from
    /// the others, then they're deleted. Returns how many were removed.
    @discardableResult
    static func mergeDuplicates(in context: ModelContext) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<BusinessProfile>()) else { return 0 }
        var removed = 0
        for operatorID in Set(all.map(\.operatorID)) {
            guard let keep = current(all, operatorID: operatorID) else { continue }
            for extra in all where extra.operatorID == operatorID && extra !== keep {
                fill(keep, from: extra)
                context.delete(extra)
                removed += 1
            }
        }
        if removed > 0 { try? context.save() }
        return removed
    }

    /// Fills `keep`'s empty fields from `other`; nothing `keep` has is lost.
    static func fill(_ keep: BusinessProfile, from other: BusinessProfile) {
        func text(_ path: ReferenceWritableKeyPath<BusinessProfile, String>) {
            if keep[keyPath: path].isEmpty { keep[keyPath: path] = other[keyPath: path] }
        }
        text(\.companyName); text(\.phone); text(\.email); text(\.tagline)
        text(\.licenseNumber); text(\.defaultDisclaimer); text(\.requestWelcome)
        if keep.logoData == nil { keep.logoData = other.logoData }
        if keep.defaultTaxRate == 0 { keep.defaultTaxRate = other.defaultTaxRate }
        if keep.accentColorHex == PlowRColor.navyHex { keep.accentColorHex = other.accentColorHex }
        for reason in other.customVisitReasons where !keep.customVisitReasons.contains(reason) {
            keep.customVisitReasons.append(reason)
        }
        if !keep.requestServicesChosen && other.requestServicesChosen {
            keep.requestServices = other.requestServices
            keep.requestServicesChosen = true
        }
    }
}
