import SwiftUI

/// The licence of the fonts PlowR ships (Barlow, SIL Open Font License 1.1),
/// which asks that its text go with the font. The bundled file stays exactly
/// as published; it's reflowed only for display (the file is hard-wrapped at
/// about 75 columns, which breaks into ragged lines on a phone).
struct FontLicenseView: View {
    /// The bundled licence text, or nil if it's missing from the app.
    static let text: String? = Bundle.main.url(forResource: "Barlow-OFL", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    /// Shown only if the file were missing: the notice the licence requires.
    static let fallback = """
        Copyright 2017 The Barlow Project Authors (https://github.com/jpt/barlow)

        Barlow is licensed under the SIL Open Font License, Version 1.1 (https://openfontlicense.org).
        """

    /// Single line breaks inside a paragraph become spaces; blank lines
    /// between paragraphs stay.
    nonisolated static func reflowed(_ text: String) -> String {
        text.components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            }
            .joined(separator: "\n\n")
    }

    var body: some View {
        ScrollView {
            Text(Self.reflowed(Self.text ?? Self.fallback))
                .font(.footnote)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Font Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
