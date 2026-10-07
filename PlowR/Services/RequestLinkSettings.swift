import Foundation

/// The business's own Request Service link (RequestLink), from its Business
/// Profile and Service Catalog: what the link carries and what's missing to
/// make one. The screen is RequestLinkView.
enum RequestLinkSettings {
    /// What a business with nothing in its Service Catalog can choose from.
    /// None is offered until chosen: a business offers only what it does.
    static let fallbackServices = ["Snow Removal", "Lawn Care", "Landscaping"]

    /// The services a business can offer on its form: its active catalog
    /// services, in catalog order, each name once; or, with an empty
    /// catalog, the fallback list.
    static func offerable(_ catalog: [ServiceItem], operatorID: String) -> [String] {
        let names = catalogNames(catalog, operatorID: operatorID)
        return names.isEmpty ? fallbackServices : names
    }

    /// The business's active catalog services, in catalog order, each name
    /// once: empty means it has no catalog yet (the one test of that).
    static func catalogNames(_ catalog: [ServiceItem], operatorID: String) -> [String] {
        var seen = Set<String>()
        return catalog.filter { $0.operatorID == operatorID && $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func hasCatalog(_ catalog: [ServiceItem], operatorID: String) -> Bool {
        !catalogNames(catalog, operatorID: operatorID).isEmpty
    }

    /// What the form offers: of what can be offered now, the business's
    /// choice once made (a service since renamed, removed or turned off
    /// drops out, so the form never offers what the screen doesn't show);
    /// before any choice, the catalog's services, or none from the fallback
    /// list. As many as a link holds.
    static func services(for profile: BusinessProfile?, catalog: [ServiceItem], operatorID: String) -> [String] {
        let offerable = offerable(catalog, operatorID: operatorID)
        if let profile, profile.requestServicesChosen {
            let chosen = Set(profile.requestServices.map { $0.lowercased() })
            return Array(offerable.filter { chosen.contains($0.lowercased()) }.prefix(RequestLink.Limit.services))
        }
        return hasCatalog(catalog, operatorID: operatorID) ? Array(offerable.prefix(RequestLink.Limit.services)) : []
    }

    /// The choice after turning `service` on or off, in catalog order, capped.
    static func toggled(_ service: String, chosen: [String], offerable: [String]) -> [String] {
        var set = Set(chosen.map { $0.lowercased() })
        if set.contains(service.lowercased()) { set.remove(service.lowercased()) } else { set.insert(service.lowercased()) }
        return Array(offerable.filter { set.contains($0.lowercased()) }.prefix(RequestLink.Limit.services))
    }

    /// What a link needs that the Business Profile doesn't have yet.
    enum Missing: Equatable {
        case name, phone

        var title: String {
            switch self {
            case .name: "your business name"
            case .phone: "a phone number prospects can text"
            }
        }
    }

    static func missing(_ profile: BusinessProfile?) -> [Missing] {
        let name = RequestLink.clean(profile?.companyName ?? "", limit: RequestLink.Limit.name)
        let phone = RequestLink.clean(profile?.phone ?? "", limit: RequestLink.Limit.phone)
        return (RequestLink.hasLetterOrDigit(name) ? [] : [.name]) + (RequestLink.phoneDigits(phone) == nil ? [.phone] : [])
    }

    /// The business's link, or nil until the profile has a name and a phone.
    static func link(for profile: BusinessProfile?, catalog: [ServiceItem], operatorID: String) -> URL? {
        guard let profile, missing(profile).isEmpty else { return nil }
        return RequestLink.url(for: RequestLink.Business(
            name: profile.companyName, phone: profile.phone, email: profile.email,
            services: services(for: profile, catalog: catalog, operatorID: operatorID),
            welcome: profile.requestWelcome))
    }

    /// The text that goes with the link when it's sent to someone.
    static func invitation(businessName: String, link: URL) -> String {
        "\(invitationLead(businessName: businessName)) \(link.absoluteString)"
    }

    /// The same without the link, for a share that sends the link itself.
    static func invitationLead(businessName: String) -> String {
        "You can request service from \(businessName) here:"
    }
}
