import SwiftUI
import SwiftData
import PhotosUI
import UIKit

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        guard h.count == 6, let value = UInt32(h, radix: 16) else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

struct BusinessProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var profiles: [BusinessProfile]

    @State private var companyName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var tagline = ""
    @State private var licenseNumber = ""
    @State private var defaultDisclaimer = ""
    @State private var accentColor: Color = .blue
    @State private var colorPDFs = true
    @State private var logoItem: PhotosPickerItem?
    @State private var logoImage: Image?
    @State private var logoData: Data?

    private var profile: BusinessProfile? {
        profiles.first { $0.operatorID == authManager.userID }
    }

    var body: some View {
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
            } header: {
                Text("PDF Appearance")
            } footer: {
                Text("Turn off for black-and-white print-ready documents.")
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
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
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
        colorPDFs = p.colorPDFs
        accentColor = Color(hex: p.accentColorHex) ?? .blue
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
        p.colorPDFs = colorPDFs
        p.accentColorHex = accentColor.hexString
        if let data = logoData { p.logoData = data }
    }
}
