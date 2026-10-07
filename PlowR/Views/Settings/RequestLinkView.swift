import MessageUI
import SwiftData
import SwiftUI

/// Settings › Request Link (also on the Pipeline): the business's Request
/// Service link (RequestLink, RequestLinkSettings). Anyone who opens it can
/// ask for service from any phone or computer, without the app: the request
/// comes as a text from their own phone, ending in Add to PlowR. Here the
/// business chooses what the form offers, and copies, shares or texts the
/// link, or shows it as a QR code.
struct RequestLinkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.openURL) private var openURL
    @Query private var profiles: [BusinessProfile]
    @Query private var catalog: [ServiceItem]

    /// The QR code screen, with the link as it was when opened.
    @State private var qr: QRCodeShown?

    struct QRCodeShown: Identifiable {
        let link: URL
        let name: String
        var id: String { link.absoluteString }
    }
    @State private var composing = false
    @State private var copied = false
    /// The welcome line as typed, cut to the link's limit as it's typed.
    @State private var welcome = ""

    private var profile: BusinessProfile? {
        profiles.first { $0.operatorID == authManager.userID }
    }

    private var link: URL? {
        RequestLinkSettings.link(for: profile, catalog: catalog, operatorID: authManager.userID)
    }

    var body: some View {
        Form {
            if let profile, let link {
                linkSection(link, profile: profile)
                servicesSection(profile)
                welcomeSection(profile)
            } else {
                missingSection
            }
        }
        .navigationTitle("Request Link")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { welcome = profile?.requestWelcome ?? "" }
        // Changed on another device while open: the field follows.
        .onChange(of: profile?.requestWelcome) { _, synced in
            if let synced, synced != welcome { welcome = synced }
        }
        // The clipboard holds the link as it was: Copied says so only until it changes.
        .onChange(of: link) { copied = false }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(4))
            copied = false
        }
        .fullScreenCover(item: $qr) { shown in
            // The link as it was when opened: a change synced meanwhile can't
            // leave a blank screen with no way out.
            RequestLinkQRView(link: shown.link, businessName: shown.name)
        }
        .sheet(isPresented: $composing) {
            if let link, let profile {
                MessageComposer(recipients: [],
                                body: RequestLinkSettings.invitation(businessName: profile.companyName, link: link)) { _ in
                    composing = false
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Sections

    private var missingSection: some View {
        Section {
            let missing = RequestLinkSettings.missing(profile).map(\.title)
            Text("Your link needs \(missing.joined(separator: " and ")). Add \(missing.count == 1 ? "it" : "them") in Business Profile.")
            NavigationLink("Business Profile") { BusinessProfileView() }
        } footer: {
            Text("A link anyone can open to ask you for service, from any phone or computer, without the app.")
        }
    }

    private func linkSection(_ link: URL, profile: BusinessProfile) -> some View {
        Section {
            Text(link.absoluteString)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.url = link
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            ShareLink(item: link, message: Text(RequestLinkSettings.invitationLead(businessName: profile.companyName))) {
                Label("Share Link", systemImage: "square.and.arrow.up")
            }
            Button {
                qr = QRCodeShown(link: link, name: profile.companyName)
            } label: {
                Label("Show or Save QR Code", systemImage: "qrcode")
            }
            if MFMessageComposeViewController.canSendText() {
                Button {
                    composing = true
                } label: {
                    Label("Text to a Client", systemImage: "message")
                }
            }
            Button {
                openURL(link)
            } label: {
                Label("See What Clients See", systemImage: "safari")
            }
        } header: {
            Text("Your Link")
        } footer: {
            Text("Put it in a text, on social media or your website, or print the QR code on a flyer or your truck. Whoever opens it fills in a short form, and the request comes to \(profile.phone) as a text from their own phone\(RequestLink.validEmail(profile.email).isEmpty ? "" : " (or, from a computer, an email to \(RequestLink.validEmail(profile.email)))"), ending in Add to PlowR: tap that to add them as a lead. Nothing goes through a server, and no app is needed to send a request.")
        }
    }

    private func servicesSection(_ profile: BusinessProfile) -> some View {
        let offerable = RequestLinkSettings.offerable(catalog, operatorID: authManager.userID)
        let chosen = RequestLinkSettings.services(for: profile, catalog: catalog, operatorID: authManager.userID)
        let full = chosen.count >= RequestLink.Limit.services
        let fromCatalog = RequestLinkSettings.hasCatalog(catalog, operatorID: authManager.userID)
        return Section {
            ForEach(offerable, id: \.self) { service in
                let isOn = chosen.contains(service)
                Button {
                    toggle(service, in: chosen, offerable: offerable, profile: profile)
                } label: {
                    HStack {
                        Text(service).foregroundStyle(.primary)
                        Spacer()
                        if isOn {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                        }
                    }
                }
                .disabled(!isOn && full)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        } header: {
            Text("Services on the Form")
        } footer: {
            Text((fromCatalog ? "Up to \(RequestLink.Limit.services), from your Service Catalog." : "Tick what you do. Add services to your Service Catalog to offer your own.")
                 + (chosen.isEmpty ? " With none ticked, the form asks only for their details and notes."
                                   : " The form also offers Something else.")
                 + " Changes go into your link from now on; a link you've already given out keeps what it had.")
        }
    }

    private func welcomeSection(_ profile: BusinessProfile) -> some View {
        Section {
            TextField("Welcome line (optional)", text: $welcome, axis: .vertical)
                .lineLimit(1...3)
                .onChange(of: welcome) { _, typed in
                    let cut = String(typed.prefix(RequestLink.Limit.welcome))
                    if cut != typed { welcome = cut }
                    if profile.requestWelcome != cut { profile.requestWelcome = cut }
                }
        } footer: {
            Text("Shown at the top of the form, like \u{201C}Tell us about your property and we'll text you a quote.\u{201D} \(RequestLink.Limit.welcome - welcome.count) characters left.")
        }
    }

    /// The form's services with `service` turned on or off, in catalog order.
    private func toggle(_ service: String, in chosen: [String], offerable: [String], profile: BusinessProfile) {
        profile.requestServices = RequestLinkSettings.toggled(service, chosen: chosen, offerable: offerable)
        profile.requestServicesChosen = true
        copied = false
        try? modelContext.save()
    }
}

/// The Request Service link as a QR code, big enough to scan from the
/// screen, with Save for a flyer or a decal. Always has Done, even if the
/// link is gone.
struct RequestLinkQRView: View {
    let link: URL?
    let businessName: String
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var made = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Text(businessName).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                Text("Scan to request service").foregroundStyle(.secondary)
                if let image {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320)
                        .accessibilityLabel("QR code for your request link")
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Request link QR code",
                                                                                 image: Image(uiImage: image))) {
                        Label("Save QR Code", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Save Image puts it in Photos, for a flyer, a sign or your truck. The bigger it's printed, the farther away it scans.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else if made {
                    Text(link == nil ? "Your link isn't available right now."
                         : "This link is too long for a QR code. Shorten your business name or welcome line, or offer fewer services.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: link) {
            image = link.flatMap { QRCode.image(for: $0.absoluteString, size: 1_024, border: true) }
            made = true
        }
    }
}
