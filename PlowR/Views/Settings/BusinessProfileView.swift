import SwiftUI
import SwiftData
import PhotosUI
import UIKit

extension Color {
    nonisolated init?(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        guard h.count == 6, let value = UInt32(h, radix: 16) else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }

    /// "1E3A8A". Rounded: truncating lost a step on some values, so the
    /// profile's colour could darken a little on every save. Clamped: a
    /// colour picked outside sRGB (Display P3) has components beyond 0...1,
    /// which made hex no colour could be read back from.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ c: CGFloat) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

struct BusinessProfileView: View {
    /// The accent the form shows for a profile's stored hex: that colour, or
    /// the app's navy (BusinessProfile's default) for no profile yet or hex
    /// that can't be read. It was system blue, so a new profile's first save
    /// wrote blue over the navy default.
    static func accent(for hex: String?) -> Color {
        hex.flatMap { Color(hex: $0) } ?? PlowRColor.navy
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Query private var profiles: [BusinessProfile]

    @State private var companyName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var tagline = ""
    @State private var licenseNumber = ""
    @State private var defaultDisclaimer = ""
    @State private var defaultTaxRate = ""
    @State private var accentColor: Color = Self.accent(for: nil)
    @State private var colorPDFs = true
    @State private var compactHeader = false
    @State private var logoItem: PhotosPickerItem?
    @State private var logoImage: Image?
    @State private var logoData: Data?

    private var profile: BusinessProfile? {
        profiles.first { $0.operatorID == authManager.userID }
    }

    // PlowR Pro: read only, this editor shows why instead (EditsNeedPro).
    var body: some View { editor.editsNeedPro() }

    @ViewBuilder private var editor: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        if let logoImage {
                            logoImage
                                .resizable()
                                .scaledToFill()
                                .frame(width: 90, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemGray5))
                                .frame(width: 90, height: 90)
                                .overlay {
                                    Image(systemName: "building.2")
                                        .font(.title)
                                        .foregroundStyle(.secondary)
                                }
                        }
                        PhotosPicker(selection: $logoItem, matching: .images) {
                            Text(logoImage == nil ? "Add Logo" : "Change Logo")
                                .font(.caption)
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("Business Info") {
                TextField("Company Name", text: $companyName)
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                TextField("Tagline (optional)", text: $tagline)
            }

            Section("Optional") {
                TextField("License / Certification Number", text: $licenseNumber)
            }

            Section {
                Toggle("Color proposals & invoices", isOn: $colorPDFs)
                if colorPDFs {
                    ColorPicker("Accent color", selection: $accentColor, supportsOpacity: false)
                }
                Toggle("Compact header", isOn: $compactHeader)
            } header: {
                Text("PDF Appearance")
            } footer: {
                Text("Compact header uses a smaller document title — useful when a wide logo fills the header.")
            }

            Section {
                LabeledContent("Sales Tax Rate") {
                    HStack(spacing: 2) {
                        TextField("0", text: $defaultTaxRate)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Tax")
            } footer: {
                Text("Put on every new invoice and proposal, and you can change it on any one. Leave it at 0 if you don't charge sales tax. Whether your services are taxed, and at what rate, depends on your state: check with your state or an accountant.")
            }

            Section("Default Proposal Disclaimer") {
                TextEditor(text: $defaultDisclaimer)
                    .frame(minHeight: 80)
            }
        }
        .navigationTitle("Business Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(companyName.isEmpty)
            }
        }
        .onAppear { loadProfile() }
        .onChange(of: logoItem) { _, newItem in
            Task {
                if let original = try? await newItem?.loadTransferable(type: Data.self),
                   let data = await Task.detached(operation: { PhotoCapture.removingLocation(from: original) }).value {
                    logoData = data
                    if let uiImage = UIImage(data: data) {
                        logoImage = Image(uiImage: uiImage)
                    }
                }
            }
        }
    }

    private func loadProfile() {
        guard let p = profile else { return }
        companyName = p.companyName
        phone = p.phone
        email = p.email
        tagline = p.tagline
        licenseNumber = p.licenseNumber
        defaultDisclaimer = p.defaultDisclaimer
        defaultTaxRate = p.defaultTaxRate > 0 ? Proposal.percentText(p.defaultTaxRate) : ""
        colorPDFs = p.colorPDFs
        compactHeader = p.compactHeader
        accentColor = Self.accent(for: p.accentColorHex)
        if let data = p.logoData, let uiImage = UIImage(data: data) {
            logoImage = Image(uiImage: uiImage)
            logoData = data
        }
    }

    private func save() {
        let p = profile ?? {
            let new = BusinessProfile(operatorID: authManager.userID)
            modelContext.insert(new)
            return new
        }()
        p.companyName = companyName
        p.phone = phone
        p.email = email
        p.tagline = tagline
        p.licenseNumber = licenseNumber
        p.defaultDisclaimer = defaultDisclaimer
        p.defaultTaxRate = Proposal.taxRate(typed: defaultTaxRate)
        p.colorPDFs = colorPDFs
        p.compactHeader = compactHeader
        p.accentColorHex = accentColor.hexString
        if let data = logoData { p.logoData = data }
        dismiss()
    }
}
