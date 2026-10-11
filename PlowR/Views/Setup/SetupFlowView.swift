import CoreLocation
import PhotosUI
import SwiftData
import SwiftUI
import UserNotifications

/// First-run setup for a new business (FirstRun): the business, what it
/// does, its sales tax, alerts and location (each asked with why), then
/// what's free and what PlowR Pro adds. Every step can be skipped; Finish or
/// Skip on the last step saves what was given and opens the app.
struct SetupFlowView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable { case business, services, tax, alerts, pro }

    @State private var step: Step = .business
    @State private var answers = FirstRun.Answers()
    @State private var logoItem: PhotosPickerItem?
    @State private var logoImage: Image?
    @State private var permissions = SetupPermissions()
    @State private var showingPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, PlowRLayout.space4)
            ScrollView {
                VStack(alignment: .leading, spacing: PlowRLayout.space4) {
                    switch step {
                    case .business: businessStep
                    case .services: servicesStep
                    case .tax: taxStep
                    case .alerts: alertsStep
                    case .pro: proStep
                    }
                }
                .padding(PlowRLayout.space4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            buttons
                .padding(PlowRLayout.space4)
        }
        .background(PlowRColor.ground.ignoresSafeArea())
        .tint(PlowRColor.brand)
        .sheet(isPresented: $showingPaywall, onDismiss: finish) { ProPaywallView() }
        .onChange(of: logoItem) { _, item in
            Task {
                if let original = try? await item?.loadTransferable(type: Data.self),
                   let data = await Task.detached(operation: { PhotoCapture.removingLocation(from: original) }).value {
                    answers.logoData = data
                    if let uiImage = UIImage(data: data) { logoImage = Image(uiImage: uiImage) }
                }
            }
        }
        .task { await permissions.refresh() }
    }

    // MARK: - Steps

    private var businessStep: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space4) {
            heading("Welcome to PlowR",
                    "A few quick questions to set up your business. Skip anything; it's all in Settings later.")
            field("Business name") {
                TextField("e.g. Green Mountain Grounds", text: $answers.companyName)
                    .textContentType(.organizationName)
                    .submitLabel(.done)
            }
            PhotosPicker(selection: $logoItem, matching: .images) {
                HStack(spacing: PlowRLayout.space3) {
                    Group {
                        if let logoImage {
                            logoImage.resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(.title2)
                                .foregroundStyle(PlowRColor.brand)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .background(PlowRColor.raised)
                    .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(logoImage == nil ? "Add your logo" : "Change logo")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(PlowRColor.ink)
                        Text("It goes on your proposals and invoices.")
                            .font(.caption)
                            .foregroundStyle(PlowRColor.inkSecondary)
                    }
                }
                .frame(minHeight: PlowRLayout.minTapTarget)
            }
            .buttonStyle(.plain)
        }
    }

    private var servicesStep: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space4) {
            heading("What do you do?",
                    "Pick any. PlowR adds the usual services and prices for each; change them in Settings → Service Catalog.")
            ForEach(ServiceCatalog.standardCategories) { category in
                let on = answers.categories.contains(category.key)
                Button {
                    if on { answers.categories.remove(category.key) } else { answers.categories.insert(category.key) }
                } label: {
                    HStack(spacing: PlowRLayout.space3) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(on ? PlowRColor.brand : PlowRColor.inkSecondary)
                        Text(category.label)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(PlowRColor.ink)
                        Spacer()
                    }
                    .padding(PlowRLayout.space4)
                    .frame(minHeight: PlowRLayout.gloveTapTarget)
                    .background(PlowRColor.surface,
                                in: RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous)
                        .strokeBorder(on ? PlowRColor.brand : PlowRColor.line, lineWidth: on ? 2 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var taxStep: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space4) {
            heading("Sales tax",
                    "The rate PlowR puts on new invoices and proposals. Leave it at 0 if you don't charge tax; you can change it on any document, and mark a client tax exempt.")
            field("Default tax rate (%)") {
                TextField("0", text: $answers.taxRate)
                    .keyboardType(.decimalPad)
            }
            if Proposal.readTaxRate(answers.taxRate) == nil {
                Text("Enter a rate from 0 to 100.")
                    .font(.caption)
                    .foregroundStyle(PlowRColor.Status.overdue.text)
            }
            Text("Not sure what to charge? Many states tax snow removal or landscaping; check with your accountant.")
                .font(.footnote)
                .foregroundStyle(PlowRColor.inkSecondary)
        }
    }

    private var alertsStep: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space4) {
            heading("Stay a step ahead", "Two things PlowR can do for you. You can change either in the Settings app.")
            permissionRow(symbol: "bell.badge.fill", title: "Alerts",
                          detail: "A heads-up the evening before snow or a storm, and a reminder when an invoice goes overdue.",
                          state: permissions.notifications) {
                Task { await permissions.askForNotifications() }
            }
            permissionRow(symbol: "location.fill", title: "Your location",
                          detail: "Today's weather on Home, and arrival times to your stops when you run a route.",
                          state: permissions.location) {
                permissions.askForLocation()
            }
        }
    }

    private var proStep: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space4) {
            heading("Free to start", "PlowR is free for up to \(Access.freeClientLimit) clients and one route, for as long as you like.")
            PlowRCard {
                VStack(alignment: .leading, spacing: PlowRLayout.space3) {
                    Label("PlowR Pro", systemImage: PlowRSymbol.pro.name)
                        .font(PlowRFont.title)
                        .foregroundStyle(PlowRColor.brand)
                    ForEach(Self.proFeatures, id: \.self) { feature in
                        Label {
                            Text(feature).foregroundStyle(PlowRColor.ink)
                        } icon: {
                            Image(systemName: PlowRSymbol.complete.name).foregroundStyle(PlowRColor.brand)
                        }
                        .font(.subheadline)
                    }
                    // Apple's paywall says whether this Apple Account still has
                    // the free month: not everyone does.
                    Text("New subscribers get their first month free. Cancel any time in the App Store; nothing you've made is ever deleted.")
                        .font(.footnote)
                        .foregroundStyle(PlowRColor.inkSecondary)
                }
                .padding(PlowRLayout.space4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// What Pro adds (Access): never the price, which Apple's paywall shows.
    static let proFeatures = [
        "Unlimited clients and routes",
        "Service Reports for every visit",
        "Storm tools: text clients, mark below trigger",
        "Import clients from a spreadsheet",
        "A request link for new customers",
        "Documents without \u{201C}Made with PlowR\u{201D}"
    ]

    // MARK: - Pieces

    private var progress: some View {
        HStack(spacing: PlowRLayout.space1) {
            ForEach(Step.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? PlowRColor.brand : PlowRColor.line)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, PlowRLayout.space4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    private var buttons: some View {
        VStack(spacing: PlowRLayout.space2) {
            if step == .pro {
                Button { showingPaywall = true } label: { Text("Try Pro Free for a Month") }
                    .buttonStyle(.plowRAction)
                Button("Not Now") { finish() }
                    .font(.body.weight(.semibold))
                    .frame(minHeight: PlowRLayout.minTapTarget)
            } else {
                Button { advance() } label: { Text("Continue") }
                    .buttonStyle(.plowRAction)
                    .disabled(step == .tax && Proposal.readTaxRate(answers.taxRate) == nil)
                Button("Skip") { skip() }
                    .font(.body.weight(.semibold))
                    .frame(minHeight: PlowRLayout.minTapTarget)
            }
        }
    }

    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space2) {
            Text(title)
                .font(PlowRFont.screenTitle)
                .foregroundStyle(PlowRColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.body)
                .foregroundStyle(PlowRColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space1) {
            Text(label)
                .font(PlowRFont.label)
                .textCase(.uppercase)
                .foregroundStyle(PlowRColor.inkSecondary)
            content()
                .font(.title3)
                .padding(PlowRLayout.space3)
                .frame(minHeight: PlowRLayout.gloveTapTarget)
                .background(PlowRColor.surface,
                            in: RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous)
                    .strokeBorder(PlowRColor.line))
        }
    }

    private func permissionRow(symbol: String, title: String, detail: String,
                               state: SetupPermissions.State, ask: @escaping () -> Void) -> some View {
        PlowRCard {
            HStack(alignment: .top, spacing: PlowRLayout.space3) {
                IconBadge(systemImage: symbol, size: 40)
                VStack(alignment: .leading, spacing: PlowRLayout.space2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(PlowRColor.ink)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(PlowRColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    switch state {
                    case .undecided:
                        Button("Turn On", action: ask).plowRProminent()
                    case .allowed:
                        StatusChip("On", systemImage: PlowRSymbol.complete.name, status: .done)
                    case .declined:
                        StatusChip("Off: change it in the Settings app", status: .neutral)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(PlowRLayout.space4)
        }
    }

    // MARK: - Moving on

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return finish() }
        withAnimation { step = next }
    }

    /// A step skipped leaves its part as it was.
    private func skip() {
        switch step {
        case .business: answers.companyName = ""; answers.logoData = nil
        case .services: answers.categories = []
        case .tax: answers.taxRate = ""
        case .alerts, .pro: break
        }
        advance()
    }

    private func finish() {
        FirstRun.save(answers, operatorID: authManager.userID, in: modelContext)
        UserDefaults.standard.set(true, forKey: FirstRun.completedKey(authManager.userID))
        onFinish()
    }
}

/// Notifications and location, asked from setup with a reason beside each.
/// Location is While Using here: the route screen asks for Always when a
/// route needs it, and says why there (RouteGPS).
@MainActor @Observable
final class SetupPermissions: NSObject, CLLocationManagerDelegate {
    enum State { case undecided, allowed, declined }

    var notifications: State = .undecided
    var location: State = .undecided
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        location = Self.state(manager.authorizationStatus)
    }

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = Self.state(settings.authorizationStatus)
        location = Self.state(manager.authorizationStatus)
    }

    func askForNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        await refresh()
    }

    func askForLocation() {
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.location = Self.state(status) }
    }

    nonisolated static func state(_ status: UNAuthorizationStatus) -> State {
        switch status {
        case .notDetermined: .undecided
        case .denied: .declined
        default: .allowed
        }
    }

    nonisolated static func state(_ status: CLAuthorizationStatus) -> State {
        switch status {
        case .notDetermined: .undecided
        case .denied, .restricted: .declined
        default: .allowed
        }
    }
}
