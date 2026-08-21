import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(AuthManager.self) private var authManager

    @Query private var allProfiles: [BusinessProfile]
    @Query private var allClients: [Client]
    @Query(sort: \ScheduledVisit.scheduledDate) private var allVisits: [ScheduledVisit]
    @Query(sort: \PlowRoute.createdAt, order: .reverse) private var allRoutes: [PlowRoute]
    @Query private var allProposals: [Proposal]

    @State private var showingSettings = false
    @State private var showingAddClient = false
    @State private var showingCreateRoute = false
    @State private var showingAddVisit = false

    // MARK: - Derived Data

    private var profile: BusinessProfile? {
        allProfiles.first { $0.operatorID == authManager.userID }
    }

    private var myClients: [Client] {
        allClients.filter { $0.operatorID == authManager.userID }
    }

    private var myProposals: [Proposal] {
        allProposals.filter { $0.operatorID == authManager.userID }
    }

    private var todayVisits: [ScheduledVisit] {
        allVisits.filter {
            $0.operatorID == authManager.userID &&
            $0.status == .scheduled &&
            Calendar.current.isDateInToday($0.scheduledDate)
        }
    }

    private var upcomingVisits: [ScheduledVisit] {
        let tomorrow = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
        let weekEnd  = tomorrow.addingTimeInterval(86400 * 7)
        return allVisits.filter {
            $0.operatorID == authManager.userID &&
            $0.status == .scheduled &&
            $0.scheduledDate >= tomorrow &&
            $0.scheduledDate < weekEnd
        }.prefix(5).map { $0 }
    }

    private var recentRoutes: [PlowRoute] {
        allRoutes.filter { $0.operatorID == authManager.userID }.prefix(3).map { $0 }
    }

    private var outstandingBalance: Double {
        myProposals.filter { $0.isInvoice && $0.invoicePaidAt == nil }.reduce(0) { $0 + $1.total }
    }

    private var overdueCount: Int { myProposals.filter { $0.invoiceStatus == .overdue }.count }
    private var draftCount:   Int { myProposals.filter { $0.invoiceStatus == .draft   }.count }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profileCard
                    todayCard
                    financeRow
                    routesCard
                    if !upcomingVisits.isEmpty { upcomingCard }
                    quickActionsGrid
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showingAddClient)  { AddClientView() }
        .sheet(isPresented: $showingCreateRoute) { CreateRouteView() }
        .sheet(isPresented: $showingAddVisit)   { AddVisitView() }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        HStack(spacing: 14) {
            logoMark.frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile?.companyName.dashNilIfEmpty ?? "My Business")
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Group {
                    if let tagline = profile?.tagline.dashNilIfEmpty {
                        Text(tagline)
                    } else {
                        Text("\(myClients.count) client\(myClients.count == 1 ? "" : "s")")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var logoMark: some View {
        if let data = profile?.logoData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.gradient)
                .overlay {
                    Text((profile?.companyName ?? "").dashInitials)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
        }
    }

    // MARK: - Today

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Today", icon: "calendar",
                          badge: todayVisits.isEmpty ? nil : "\(todayVisits.count)",
                          badgeColor: .blue)

            DashCard {
                if todayVisits.isEmpty {
                    emptyRow("No visits scheduled today", icon: "calendar.badge.plus")
                } else {
                    ForEach(Array(todayVisits.prefix(5).enumerated()), id: \.element.id) { i, visit in
                        if i > 0 { Divider().padding(.leading, 44) }
                        visitRow(visit)
                    }
                    if todayVisits.count > 5 {
                        Divider()
                        Text("+ \(todayVisits.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func visitRow(_ visit: ScheduledVisit) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.circle.fill")
                .font(.title3)
                .foregroundStyle(visit.status.chipColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(visit.clientName).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(visit.scheduledDate, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if visit.estimatedMinutes > 0 {
                Text("\(visit.estimatedMinutes)m").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Finances

    private var financeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Finances", icon: "dollarsign.circle",
                          badge: overdueCount > 0 ? "\(overdueCount) overdue" : nil,
                          badgeColor: .red)
            HStack(spacing: 10) {
                financeTile(
                    value: outstandingBalance.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                    label: "Outstanding",
                    color: outstandingBalance > 0 ? .orange : .secondary
                )
                financeTile(value: "\(overdueCount)", label: "Overdue",
                            color: overdueCount > 0 ? .red : .secondary)
                financeTile(value: "\(draftCount)", label: "Drafts",
                            color: draftCount > 0 ? .blue : .secondary)
            }
        }
    }

    private func financeTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Routes

    private var routesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Routes", icon: "map")

            DashCard {
                if recentRoutes.isEmpty {
                    emptyRow("No routes yet", icon: "map.badge.plus")
                } else {
                    ForEach(Array(recentRoutes.enumerated()), id: \.element.id) { i, route in
                        if i > 0 { Divider().padding(.leading, 44) }
                        NavigationLink { RouteDetailView(route: route) } label: {
                            routeRow(route)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func routeRow(_ route: PlowRoute) -> some View {
        let total = route.sortedStops.count
        let done  = route.sortedStops.filter { $0.actualMinutes > 0 }.count
        let isActive = done > 0 && done < total
        let isDone   = total > 0 && done == total

        return HStack(spacing: 12) {
            Image(systemName: isActive ? "map.fill"
                             : (isDone ? "checkmark.circle.fill" : "map"))
                .font(.title3)
                .foregroundStyle(isActive ? .orange : (isDone ? .green : .secondary))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(route.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Text(total == 0  ? "No stops"
                     : isDone    ? "Completed"
                     : done == 0 ? "\(total) stop\(total == 1 ? "" : "s")"
                                 : "\(done)/\(total) complete")
                    .font(.caption)
                    .foregroundStyle(isActive ? .orange : .secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Upcoming

    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Coming Up", icon: "calendar.badge.clock")
            DashCard {
                ForEach(Array(upcomingVisits.enumerated()), id: \.element.id) { i, visit in
                    if i > 0 { Divider().padding(.leading, 56) }
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            Text(visit.scheduledDate, format: .dateTime.weekday(.abbreviated))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(visit.scheduledDate, format: .dateTime.day())
                                .font(.title3.weight(.bold))
                        }
                        .frame(width: 36)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(visit.clientName).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(visit.scheduledDate, style: .time)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if visit.isAfterHours {
                            Image(systemName: "moon.fill").font(.caption2).foregroundStyle(.indigo)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Quick Actions", icon: "bolt.fill")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                quickAction("New Client",      icon: "person.badge.plus",   color: .blue)   { showingAddClient = true }
                quickAction("New Route",       icon: "map.badge.plus",      color: .green)  { showingCreateRoute = true }
                quickAction("Schedule Visit",  icon: "calendar.badge.plus", color: .orange) { showingAddVisit = true }
                quickAction("Settings",        icon: "gearshape.fill",      color: .gray)   { showingSettings = true }
            }
        }
    }

    private func quickAction(_ title: String, icon: String, color: Color,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 22, alignment: .center)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared Helpers

    private func sectionHeader(_ title: String, icon: String,
                                badge: String? = nil, badgeColor: Color = .orange) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(badgeColor.opacity(0.15))
                    .foregroundStyle(badgeColor)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    private func emptyRow(_ message: String, icon: String) -> some View {
        Label(message, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
    }
}

// MARK: - Card Container

private struct DashCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - String Helpers (file-private)

private extension String {
    var dashNilIfEmpty: String? { isEmpty ? nil : self }
    var dashInitials: String {
        split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
            .dashNilIfEmpty ?? "P"
    }
}
