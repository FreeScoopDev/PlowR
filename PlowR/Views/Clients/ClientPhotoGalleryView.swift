import SwiftUI
import SwiftData
import PhotosUI

struct ClientPhotoGalleryView: View {
    @Environment(\.access) private var access
    @State private var gate: ProGate?
    let client: Client
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(UndoCenter.self) private var undoCenter
    @Query private var allPhotos: [StopPhoto]

    @State private var selectedPhoto: StopPhoto?
    @State private var filterBefore: Bool? = nil

    // Import state
    @State private var selectedPickerItem: PhotosPickerItem? = nil
    @State private var showingCamera = false
    @State private var showingLibraryPicker = false
    @State private var pendingImageData: Data? = nil
    /// When the pending photo was taken (PhotoCapture), if known.
    @State private var pendingCapture: CapturedPhoto?
    @State private var showingPhotoTypePrompt = false

    private var clientPhotos: [StopPhoto] {
        allPhotos
            .filter { $0.clientID == client.id.uuidString }
            // A delete held back for its Undo (UndoCenter) is already gone here.
            .filter { !undoCenter.isPendingDeletion($0) }
            // Before and After are work photos; a below-trigger check's is neither.
            .filter { filterBefore == nil || (!$0.isCheckPhoto && $0.isBefore == filterBefore) }
            .sorted { $0.displayTime > $1.displayTime }
    }

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 3)]

    var body: some View {
        Group {
            if clientPhotos.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(clientPhotos) { photo in
                            photoCell(photo)
                                .onTapGesture { selectedPhoto = photo }
                        }
                    }
                }
            }
        }
        .navigationTitle("Photos (\(clientPhotos.count))")
        .proGateSheet($gate)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                addPhotoMenu
            }
            ToolbarItem(placement: .topBarLeading) {
                filterMenu
            }
        }
        .photosPicker(isPresented: $showingLibraryPicker, selection: $selectedPickerItem, matching: .images)
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo)
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { image, metadata in
                if let photo = PhotoCapture.saving(camera: image, metadata: metadata) {
                    pendingImageData = photo.data
                    pendingCapture = photo.capture
                    showingPhotoTypePrompt = true
                }
            }
        }
        .confirmationDialog("Label this photo", isPresented: $showingPhotoTypePrompt, titleVisibility: .visible) {
            Button("Before Service") { savePhoto(isBefore: true) }
            Button("After Service")  { savePhoto(isBefore: false) }
            Button("Cancel", role: .cancel) { pendingImageData = nil }
        } message: {
            Text("Is this a before or after photo?")
        }
        .onChange(of: selectedPickerItem) { _, newItem in
            Task {
                guard let item = newItem else { return }
                // Without its location; the time is read from the original.
                if let data = try? await item.loadTransferable(type: Data.self),
                   let photo = await PhotoCapture.saving(library: data) {
                    pendingImageData = photo.data
                    pendingCapture = photo.capture
                    showingPhotoTypePrompt = true
                }
                selectedPickerItem = nil
            }
        }
    }

    // MARK: - Add Menu

    private var addPhotoMenu: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button {
                    $gate.unless(ProGate.edit(access)) { showingCamera = true }
                } label: {
                    Label("Take Photo", systemImage: PlowRSymbol.takePhoto.name)
                }
            }
            Button {
                $gate.unless(ProGate.edit(access)) { showingLibraryPicker = true }
            } label: {
                Label("Choose from Library", systemImage: PlowRSymbol.choosePhoto.name)
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add Photo")
    }

    // MARK: - Photo Cell

    private func photoCell(_ photo: StopPhoto) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let image = UIImage(data: photo.imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 110, maxWidth: .infinity, minHeight: 110, maxHeight: 160)
                    .clipped()
            } else {
                Rectangle()
                    .fill(PlowRColor.raised)
                    .frame(height: 110)
            }
            PhotoTag(photo: photo)
        }
        .clipped()
        .contentShape(Rectangle())
    }

    // MARK: - Filter Menu

    private var filterMenu: some View {
        Menu {
            Button {
                filterBefore = nil
            } label: {
                Label("All Photos", systemImage: filterBefore == nil ? "checkmark" : "photo.on.rectangle")
            }
            Button {
                filterBefore = true
            } label: {
                Label("Before Only", systemImage: filterBefore == true ? "checkmark" : "clock")
            }
            Button {
                filterBefore = false
            } label: {
                Label("After Only", systemImage: filterBefore == false ? "checkmark" : "checkmark.circle")
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter Photos")
        .accessibilityValue(filterBefore == nil ? "All Photos" : (filterBefore == true ? "Before Only" : "After Only"))
    }

    // MARK: - Empty State

    // The system's empty state, as the other empty screens use.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Photos Yet", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Add photos from your library or camera, or take them during a route stop.")
        } actions: {
            HStack(spacing: 12) {
                if CameraPicker.isAvailable {
                    Button {
                        $gate.unless(ProGate.edit(access)) { showingCamera = true }
                    } label: {
                        Label("Take Photo", systemImage: PlowRSymbol.takePhoto.name)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    $gate.unless(ProGate.edit(access)) { showingLibraryPicker = true }
                } label: {
                    Label("Library", systemImage: PlowRSymbol.choosePhoto.name)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Save

    private func savePhoto(isBefore: Bool) {
        guard let data = pendingImageData else { return }
        let photo = StopPhoto(
            operatorID: authManager.userID,
            clientID: client.id.uuidString,
            routeID: "",
            isBefore: isBefore,
            imageData: data
        )
        photo.capturedAt = pendingCapture?.capturedAt
        photo.captureSourceRaw = pendingCapture?.source?.rawValue ?? ""
        modelContext.insert(photo)
        pendingImageData = nil
        pendingCapture = nil
    }
}

// MARK: - Photo Detail View

private struct PhotoDetailView: View {
    let photo: StopPhoto
    @Environment(UndoCenter.self) private var undoCenter
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false

    private var image: UIImage? { UIImage(data: photo.imageData) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let img = image {
                        ZoomableImage(image: img, label: "Photo")
                            .padding()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Type", value: photo.isCheckPhoto ? "Below Trigger"
                                       : photo.isBefore ? "Before Service" : "After Service")
                        // When it was taken, or the file's date, or when it was added: said which.
                        LabeledContent(photo.displayTimeLabel) {
                            Text(photo.displayTime, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                        }
                        if !photo.caption.isEmpty {
                            LabeledContent("Caption", value: photo.caption)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("\(photo.kindLabel) Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingShareSheet = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share Photo")
                    .disabled(image == nil)
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        // Held back for the window, with Undo (UndoCenter).
                        undoCenter.delete(photo)
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete Photo")
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let img = image { PhotoShareSheet(image: img) }
            }
        }
    }
}

private struct PhotoShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
