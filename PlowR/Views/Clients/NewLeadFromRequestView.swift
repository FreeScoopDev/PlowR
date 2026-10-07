import SwiftData
import SwiftUI

/// Add to PlowR: a request from the business's Request Service link,
/// opened from the text it came in. Shown filled in, to check and change;
/// nothing is saved until Save Lead, since the link came from someone else.
/// If the phone number is already a client's, that's said first (and again
/// at Save, if their client arrived from iCloud meanwhile), with their page
/// a tap away. Saved, the screen closes: the lead is in the Pipeline, and
/// its pin is looked up in the background (ImportPins).
struct NewLeadFromRequestView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    /// Closes the window it's in (LeadRequestWindow).
    let onClose: () -> Void

    @State private var request: RequestLink.Request
    @State private var existing: Client?
    /// Save Lead was tapped knowing the number is already a client's.
    @State private var savingAnyway = false
    @State private var isSaved = false
    /// A client with this number arrived from iCloud after the screen opened.
    @State private var lateMatch: Client?

    init(request: RequestLink.Request, onClose: @escaping () -> Void) {
        _request = State(initialValue: request)
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            form
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onClose)
                    }
                }
        }
        .onAppear { checkExisting() }
        .confirmationDialog("\(lateMatch?.name ?? "A client") already has this phone number",
                            isPresented: Binding(get: { lateMatch != nil }, set: { if !$0 { lateMatch = nil } }),
                            titleVisibility: .visible) {
            Button("Save as a New Lead Anyway") {
                savingAnyway = true
                save()
            }
            Button("Don't Save", role: .cancel) {}
        } message: {
            Text("They were added on another device after this opened. Open their page from the top of this screen to check.")
        }
    }

    private var form: some View {
        Form {
            if let existing {
                Section {
                    Label("\(existing.name) already has this phone number.", systemImage: "person.crop.circle.badge.checkmark")
                    NavigationLink("Open \(existing.name)") { EditClientView(client: existing) }
                } footer: {
                    Text("A returning client, or someone who asked before. Save Lead adds a new lead anyway.")
                }
            }
            Section("Contact") {
                TextField("Name", text: $request.name).textContentType(.name)
                TextField("Phone", text: $request.phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
                TextField("Email (optional)", text: $request.email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                TextField("Address", text: $request.address, axis: .vertical).textContentType(.fullStreetAddress)
            }
            if !request.service.isEmpty || request.when != nil {
                Section("Asked For") {
                    if !request.service.isEmpty { LabeledContent("Service", value: request.service) }
                    if let when = request.when { LabeledContent("How often", value: when.title) }
                }
            }
            Section("Their Notes") {
                TextField("Notes", text: $request.notes, axis: .vertical).lineLimit(2...8)
            }
            Section {
                Button("Save Lead") { save() }
                    .disabled(cleaned == nil || isSaved)
            } footer: {
                Text(problem ?? "Saved as a lead in your Pipeline, tagged with today's date, and put on the map from the address. Check the details first: the request came in a text, and anyone could have sent it.")
                    .foregroundStyle(problem == nil ? Color.secondary : Color.orange)
            }
        }
        .navigationTitle("New Lead")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The request as it would be saved: cut and cleaned as the link's own
    /// fields are; nil without a name and a phone number to call.
    private var cleaned: RequestLink.Request? { RequestLink.cleaned(request) }

    /// What stops a save, or what would be lost, said under the button.
    private var problem: String? {
        if !RequestLink.hasLetterOrDigit(request.name) { return "Add their name." }
        if RequestLink.phoneDigits(RequestLink.clean(request.phone, limit: RequestLink.Limit.phone)) == nil {
            return "Add a phone number to reach them: digits, spaces, dashes and + ( ) only."
        }
        if !request.email.trimmingCharacters(in: .whitespaces).isEmpty, RequestLink.validEmail(request.email).isEmpty {
            return "That email doesn't look right, so it won't be saved. Fix it, or clear it."
        }
        return nil
    }

    /// On opening: a client with this number is said first, and Save Lead
    /// then adds the lead anyway, as the screen says.
    private func checkExisting() {
        existing = LeadIntake.existingClient(for: request, operatorID: authManager.userID, in: modelContext)
        savingAnyway = existing != nil
    }

    private func save() {
        guard !isSaved, let cleaned else { return }
        // A client with this number may have arrived from iCloud since the
        // screen opened (the same link opened on another device): said
        // first, and the next Save Lead adds the lead anyway.
        if !savingAnyway, let match = LeadIntake.existingClient(for: cleaned, operatorID: authManager.userID,
                                                                in: modelContext) {
            existing = match
            lateMatch = match
            return
        }
        isSaved = true
        LeadIntake.save(cleaned, operatorID: authManager.userID, in: modelContext)
        let context = modelContext, operatorID = authManager.userID
        Task { await ImportPins.shared.startAfterImport(in: context, operatorID: operatorID) }
        onClose()
    }
}
