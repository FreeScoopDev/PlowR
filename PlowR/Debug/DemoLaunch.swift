#if DEBUG
import Foundation
import SwiftData

/// A sample business for screenshots and checking screens by eye, from the
/// command line with no taps: launched with `-PlowRDemo YES`, PlowR signs in
/// as the dev user, skips the role screen and, the first time, fills the store
/// with clients, a route, today's visits and invoices in every state.
/// `-PlowRDemoTab 2` opens a tab (0 Home … 4 Schedule). Debug builds only.
///
///     xcrun simctl launch <device> Scoops.PlowR -PlowRDemo YES -PlowRDemoTab 1
enum DemoLaunch {
    static let operatorID = "dev-user"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: "PlowRDemo") }
    static var tab: Int? {
        UserDefaults.standard.object(forKey: "PlowRDemoTab") == nil ? nil : UserDefaults.standard.integer(forKey: "PlowRDemoTab")
    }

    @MainActor
    static func prepare(auth: AuthManager, context: ModelContext) {
        guard isOn else { return }
        UserDefaults.standard.set(UserRole.business, forKey: UserRole.key)
        if !auth.isSignedIn { auth.signIn(userID: operatorID, fullName: nil) }
        let mine = FetchDescriptor<Client>(predicate: #Predicate { $0.operatorID == "dev-user" })
        guard ((try? context.fetchCount(mine)) ?? 0) == 0 else { return }
        seed(in: context, now: .now)
    }

    @MainActor
    static func seed(in context: ModelContext, now: Date) {
        let calendar = Calendar.current
        let day: (Int) -> Date = { calendar.date(byAdding: .day, value: $0, to: now) ?? now }
        let at: (Int, Int) -> Date = { hour, minute in
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        }

        let profile = BusinessProfile(operatorID: operatorID)
        profile.companyName = "Green Mountain Grounds"
        profile.tagline = "Snow · Lawn · Landscaping"
        profile.defaultTaxRate = 6
        context.insert(profile)
        ServiceCatalog.addStandard(ServiceCatalog.standardCategories[0], operatorID: operatorID, existing: [], to: context)

        let people: [(String, String, String, Double, Double)] = [
            ("Linda Fortier", "603-543-2345", "231 Pleasant St, Claremont, NH 03743", 43.3782, -72.3435),
            ("Mike Gagnon", "603-543-6789", "55 Church St, Claremont, NH 03743", 43.3761, -72.3489),
            ("Ray Doucette", "603-542-8901", "7 Elm St, Claremont, NH 03743", 43.3756, -72.3462),
            ("Sandra Pierce", "603-542-5678", "88 Washington St, Claremont, NH 03743", 43.3742, -72.3478),
            ("Tom Belanger", "603-542-1234", "14 Maple St, Claremont, NH 03743", 43.3770, -72.3451),
            ("Pat Russo", "603-542-4410", "12 Broad St, Claremont, NH 03743", 43.3729, -72.3420)
        ]
        let clients = people.map { name, phone, address, lat, lon in
            let client = Client(name: name, phone: phone, address: address, operatorID: operatorID)
            client.latitude = lat
            client.longitude = lon
            client.customerSince = day(-200)
            context.insert(client)
            return client
        }

        let route = PlowRoute(name: "Monday North Side", operatorID: operatorID)
        context.insert(route)
        route.stops = clients.prefix(5).enumerated().map { RouteStop(order: $0.offset, client: $0.element) }

        for (client, time) in zip(clients.suffix(2), [(9, 0), (13, 30)]) {
            let visit = ScheduledVisit(operatorID: operatorID, clientID: client.id.uuidString, clientName: client.name,
                                       clientAddress: client.address, scheduledDate: at(time.0, time.1))
            visit.estimatedMinutes = 45
            context.insert(visit)
        }
        let coming = ScheduledVisit(operatorID: operatorID, clientID: clients[0].id.uuidString,
                                    clientName: clients[0].name, clientAddress: clients[0].address,
                                    scheduledDate: day(2))
        context.insert(coming)

        var number = 1
        func invoice(_ client: Client, _ amount: Double, created: Int) -> Proposal {
            let document = Proposal(operatorID: operatorID, client: client)
            document.invoiceNumber = String(format: "INV-%04d", number)
            number += 1
            document.createdAt = day(created)
            document.taxRate = 6
            let line = ProposalLineItem(serviceName: "Plow driveway", zoneLabel: "", quantity: 1, unitType: "flat",
                                        unitPrice: amount)
            context.insert(line)
            document.lineItems = [line]
            context.insert(document)
            return document
        }
        let overdue = invoice(clients[1], 240, created: -45)
        overdue.invoiceSentAt = day(-45)
        overdue.invoiceDueDate = day(-15)
        let owed = invoice(clients[2], 180, created: -6)
        owed.invoiceSentAt = day(-6)
        owed.invoiceDueDate = day(24)
        let paid = invoice(clients[3], 320, created: -20)
        paid.invoiceSentAt = day(-20)
        paid.invoiceDueDate = day(10)
        Payments.record(paid.total, method: "Check", receivedAt: day(-3), on: paid, in: context, now: now)
        _ = invoice(clients[4], 95, created: -1)       // a draft
        let quote = Proposal(operatorID: operatorID, client: clients[5])
        let quoteLine = ProposalLineItem(serviceName: "Seasonal plowing", zoneLabel: "", quantity: 1, unitType: "flat",
                                         unitPrice: 1_200)
        context.insert(quoteLine)
        quote.lineItems = [quoteLine]
        context.insert(quote)
        try? context.save()
    }
}
#endif
