import PhotosUI
import SwiftUI

/// At a stop on a route: less snow fell here than the contract's trigger.
/// Saves a check (TriggerCheck) with a note and photos, then moves on to the
/// next stop without crediting a visit or billing one.
struct BelowTriggerSheet: View {
    let clientName: String
    let triggerLabel: String
    /// Saves the check with this note and these photos, and moves on.
    let save: (String, [CapturedPhoto]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var photos: [CapturedPhoto] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Client", value: clientName)
                    LabeledContent("Contract trigger", value: triggerLabel)
                } footer: {
                    Text("Less fell here than the trigger. PlowR keeps this check (the time, and the GPS arrival if it caught one) for the Service Report, and moves on to the next stop. No visit is credited or billed.")
                }
                Section("Note") {
                    TextField("How much fell, say", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    if !photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(photos) { photo in
                                    Image(uiImage: photo.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerSmall,
                                                                    style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                photos.removeAll { $0.id == photo.id }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .black.opacity(0.6))
                                            }
                                            .accessibilityLabel("Remove photo")
                                            .padding(2)
                                        }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Button { showingCamera = true } label: { Label("Camera", systemImage: "camera") }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 5, matching: .images) {
                        Label("Library", systemImage: "photo")
                    }
                } header: {
                    Text("Photos")
                } footer: {
                    Text("A photo of what's on the ground shows the trigger wasn't reached.")
                }
            }
            .navigationTitle("Below Trigger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Move On") {
                        save(note, photos)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPickerView { image, metadata in
                    photos.append(PhotoCapture.fromCamera(image, metadata: metadata))
                }
            }
            .onChange(of: pickerItems) { _, items in
                for item in items {
                    item.loadTransferable(type: Data.self) { result in
                        if case .success(let data) = result, let data, let photo = PhotoCapture.fromLibrary(data) {
                            DispatchQueue.main.async { photos.append(photo) }
                        }
                    }
                }
                pickerItems = []
            }
            .interactiveDismissDisabled(!note.isEmpty || !photos.isEmpty)
        }
    }
}
