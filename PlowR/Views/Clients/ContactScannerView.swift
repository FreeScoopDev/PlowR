import SwiftUI
import SwiftData
import Vision
import CoreLocation

// MARK: - Scanner View

struct ContactScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var capturedImage: UIImage? = nil
    @State private var showingCamera = false
    @State private var isProcessing = false
    @State private var result: ScannedContact? = nil
    @State private var isSaving = false

    // Editable review fields
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Group {
                if isProcessing {
                    processingView
                } else if result != nil {
                    reviewForm
                } else {
                    // Empty placeholder — camera sheet is shown on appear
                    Color(.systemGroupedBackground).ignoresSafeArea()
                }
            }
            .navigationTitle(result != nil ? "Review Contact" : "Scan Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if result != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Retake") { retake() }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera, onDismiss: handleCameraDismiss) {
            ContactCameraCapture { image in
                capturedImage = image
            }
        }
        .onAppear { showingCamera = true }
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.4)
            Text("Reading contact info…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Review Form

    private var reviewForm: some View {
        Form {
            // Thumbnail
            if let img = capturedImage {
                Section {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            Section("Contact Info") {
                TextField("Full Name", text: $name).textContentType(.name)
                TextField("Phone Number", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                TextField("Email (optional)", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }

            Section("Service Address") {
                TextField("Street Address", text: $address, axis: .vertical)
                    .textContentType(.fullStreetAddress)
                    .lineLimit(2...3)
            }

            if !notes.isEmpty {
                Section {
                    TextField("Notes…", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Other Detected Text")
                } footer: {
                    Text("Text that didn't match a contact field — saved as client notes.")
                        .font(.caption)
                }
            }

            Section {
                Button {
                    saveClient()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                        } else {
                            Label("Save Client", systemImage: "person.badge.plus")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || isSaving)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
        }
    }

    // MARK: - Actions

    private func handleCameraDismiss() {
        guard let image = capturedImage else {
            // User cancelled the camera
            dismiss()
            return
        }
        processImage(image)
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        Task {
            let lines = await ContactTextParser.recognizeText(in: image)
            let parsed = ContactTextParser.parse(lines: lines)
            await MainActor.run {
                name    = parsed.name
                phone   = parsed.phone
                email   = parsed.email
                address = parsed.address
                notes   = parsed.notes
                result  = parsed
                isProcessing = false
            }
        }
    }

    private func retake() {
        capturedImage = nil
        result = nil
        name = ""; phone = ""; email = ""; address = ""; notes = ""
        showingCamera = true
    }

    private func saveClient() {
        isSaving = true
        let client = Client(name: name, phone: phone, address: address,
                            operatorID: authManager.userID)
        client.email = email
        client.notes = notes

        guard !address.isEmpty else {
            modelContext.insert(client)
            isSaving = false
            dismiss()
            return
        }

        Task {
            let geocoder = CLGeocoder()
            if let placemark = try? await geocoder.geocodeAddressString(address).first,
               let location = placemark.location {
                client.latitude  = location.coordinate.latitude
                client.longitude = location.coordinate.longitude
            }
            modelContext.insert(client)
            await MainActor.run { isSaving = false; dismiss() }
        }
    }
}

// MARK: - Camera Capture (internal to this flow)

private struct ContactCameraCapture: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ContactCameraCapture
        init(_ parent: ContactCameraCapture) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onCapture(img) }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Text Parser

typealias ScannedContact = ContactTextParser.ParsedContact

enum ContactTextParser {

    struct ParsedContact {
        var name: String    = ""
        var phone: String   = ""
        var email: String   = ""
        var address: String = ""
        var notes: String   = ""
    }

    // MARK: Vision OCR

    static func recognizeText(in image: UIImage) async -> [String] {
        // Normalize orientation so Vision sees a correctly-rotated image
        let normalized = image.normalized()
        guard let cgImage = normalized.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }
    }

    // MARK: Field Extraction

    static func parse(lines raw: [String]) -> ParsedContact {
        var lines = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                       .filter { !$0.isEmpty }
        var result = ParsedContact()

        // 1. Email — unambiguous via @
        lines = lines.filter { line in
            if result.email.isEmpty, let e = extractEmail(from: line) {
                result.email = e; return false
            }
            return true
        }

        // 2. Phone — digit-heavy pattern
        lines = lines.filter { line in
            if result.phone.isEmpty, let p = extractPhone(from: line) {
                result.phone = p; return false
            }
            return true
        }

        // 3. Address — street line + optional city/state/zip on next line
        if let si = lines.firstIndex(where: { isStreetLine($0) }) {
            var parts = [lines[si]]
            if si + 1 < lines.count && isCityStateZip(lines[si + 1]) {
                parts.append(lines[si + 1])
                lines.remove(at: si + 1)
            }
            lines.remove(at: si)
            result.address = parts.joined(separator: ", ")
        }

        // 4. Name — first remaining line that reads like a person/company name
        if let ni = lines.firstIndex(where: { looksLikeName($0) }) {
            result.name = lines[ni]
            lines.remove(at: ni)
        }

        // 5. Anything left → notes (company titles, website, misc text)
        result.notes = lines.joined(separator: "\n")

        return result
    }

    // MARK: Heuristics

    private static func extractEmail(from text: String) -> String? {
        let pattern = "[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}"
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[r]).lowercased()
    }

    private static func extractPhone(from text: String) -> String? {
        let patterns = [
            "\\(\\d{3}\\)\\s?\\d{3}[\\-.\\s]\\d{4}",        // (555) 867-5309
            "\\d{3}[\\-.\\s]\\d{3}[\\-.\\s]\\d{4}",          // 555-867-5309
            "\\+1[\\-.\\s]?\\d{3}[\\-.\\s]?\\d{3}[\\-.\\s]?\\d{4}" // +1 555 867 5309
        ]
        for pattern in patterns {
            if let r = text.range(of: pattern, options: .regularExpression) {
                return String(text[r])
            }
        }
        return nil
    }

    private static func isStreetLine(_ text: String) -> Bool {
        guard text.first?.isNumber == true else { return false }
        let keywords = ["St\\b","Ave\\b","Blvd\\b","Dr\\b","Rd\\b","Ln\\b","Ct\\b",
                        "Way\\b","Pl\\b","Place\\b","Street\\b","Avenue\\b",
                        "Boulevard\\b","Drive\\b","Road\\b","Lane\\b","Court\\b",
                        "Circle\\b","Terrace\\b","Hwy\\b","Highway\\b"]
        return keywords.contains { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    private static func isCityStateZip(_ text: String) -> Bool {
        // "Springfield, IL 62701"  or  "Springfield IL 62701"
        let pattern = "^[A-Za-z][A-Za-z\\s]{1,30},?\\s+[A-Z]{2}\\s+\\d{5}"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func looksLikeName(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        return words.count >= 1
            && words.count <= 5
            && text.count >= 2
            && text.count <= 60
            && !text.contains { $0.isNumber }
            && !text.contains("@")
            && !text.contains("www.")
            && !text.contains("http")
            && !text.contains("/")
    }
}

// MARK: - UIImage Orientation Normalization

private extension UIImage {
    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
