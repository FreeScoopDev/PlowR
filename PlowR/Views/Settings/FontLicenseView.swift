import SwiftUI

/// The licence of the fonts PlowR ships (Barlow, SIL Open Font License 1.1),
/// which asks that its text go with the font.
struct FontLicenseView: View {
    /// The bundled licence text, or nil if it's missing from the app.
    static let text: String? = Bundle.main.url(forResource: "Barlow-OFL", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    var body: some View {
        ScrollView {
            Text(Self.text ?? "Barlow is licensed under the SIL Open Font License, Version 1.1.")
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Font Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
