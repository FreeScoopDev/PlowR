import SwiftUI

/// The Dashboard's Get Started card (FirstRun.Checklist): the first things a
/// new business does in PlowR, each a tap away, ticked off as they happen.
/// Hidden once they're all done, or by its Hide button.
struct GetStartedCard: View {
    let checklist: FirstRun.Checklist
    let addClient: () -> Void
    let newRoute: () -> Void
    let hide: () -> Void
    @Binding var alertsUndecided: Bool
    /// Alerts were just allowed: schedule the ones waiting.
    var alertsAllowed: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space2) {
            HStack {
                Text("Get Started · \(checklist.doneCount) of \(alertsUndecided ? 5 : 4)")
                    .font(PlowRFont.label)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(PlowRColor.inkSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: hide) {
                    Text("Hide")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: PlowRLayout.minTapTarget, minHeight: PlowRLayout.minTapTarget)
                        .contentShape(Rectangle())
                }
            }
            PlowRCard {
                NavigationLink { BusinessProfileView() } label: {
                    row("Add your business details", detail: "Name, logo and contact details for your documents.",
                        symbol: "building.2", done: checklist.profileDone)
                }
                .buttonStyle(.plain)
                divider
                Button(action: addClient) {
                    row("Add your first client", detail: "Or import them from a spreadsheet, in Clients.",
                        symbol: PlowRSymbol.addClient.name, done: checklist.clientAdded)
                }
                .buttonStyle(.plain)
                divider
                Button(action: newRoute) {
                    row("Make a route", detail: "Your stops in order, ready to run with one tap.",
                        symbol: PlowRSymbol.route.name, done: checklist.routeMade)
                }
                .buttonStyle(.plain)
                divider
                NavigationLink { ProposalListView() } label: {
                    row("Send your first invoice", detail: "Record the work at a stop, then bill it in Documents.",
                        symbol: PlowRSymbol.document.name, done: checklist.invoiceSent)
                }
                .buttonStyle(.plain)
                if alertsUndecided {
                    divider
                    Button {
                        Task {
                            if await NotificationService.shared.requestAuthorization() { alertsAllowed() }
                            alertsUndecided = false
                        }
                    } label: {
                        row("Turn on alerts", detail: "The evening before bad weather is forecast, and when an invoice goes overdue.",
                            symbol: "bell.badge", done: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var divider: some View {
        Divider().overlay(PlowRColor.line).padding(.leading, PlowRLayout.space4 + 36 + PlowRLayout.space3)
    }

    private func row(_ title: String, detail: String, symbol: String, done: Bool) -> some View {
        HStack(spacing: PlowRLayout.space3) {
            IconBadge(systemImage: done ? PlowRSymbol.complete.name : symbol, status: done ? .done : nil, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(done ? PlowRColor.inkSecondary : PlowRColor.ink)
                    .strikethrough(done)
                if !done {
                    Text(detail).font(.caption).foregroundStyle(PlowRColor.inkSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PlowRColor.inkSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, PlowRLayout.space4)
        .padding(.vertical, PlowRLayout.space3)
        .frame(minHeight: PlowRLayout.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "")
    }
}
