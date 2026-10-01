import SwiftUI
import SwiftData
import PhotosUI

struct ClientPhotoGalleryView: View {
    let client: Client
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
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
            .filter { filterBefore == nil || $0.isBefore == filterBefore }
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
            CameraCapture { image, metadata in
                if let data = image.jpegData(compressionQuality: 0.85) {
                    pendingImageData = data
                    pendingCapture = PhotoCapture.fromCamera(image, metadata: metadata)
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
                if let data = try? await item.loadTransferable(type: Data.self) {
                    pendingImageData = data
                    pendingCapture = PhotoCapture.fromLibrary(data)
                    showingPhotoTypePrompt = true
                }
                selectedPickerItem = nil
            }
        }
    }

    // MARK: - Add Menu

    private var addPhotoMenu: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                }
            }
            Button {
                showingLibraryPicker = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "plus")
        }
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
                    .fill(Color(.systemGray5))
                    .frame(height: 110)
            }
            Label(photo.isBefore ? "Before" : "After",
                  systemImage: photo.isBefore ? "clock" : "checkmark")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(photo.isBefore ? Color.orange.opacity(0.85) : Color.green.opacity(0.85))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(4)
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
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    showingLibraryPicker = true
                } label: {
                    Label("Library", systemImage: "photo.on.rectangle")
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

// MARK: - Camera Capture

private struct CameraCapture: UIViewControllerRepresentable {
    let onCapture: (UIImage, [String: Any]?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image, info[.mediaMetadata] as? [String: Any])
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Photo Detail View

private struct PhotoDetailView: View {
    let photo: StopPhoto
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var showingShareSheet = false

    private var image: UIImage? { UIImage(data: photo.imageData) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let img = image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = max(1.0, min(lastScale * value, 5.0))
                                    }
                                    .onEnded { _ in lastScale = scale }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring()) {
                                    if scale > 1.05 { scale = 1.0; lastScale = 1.0 }
                                    else { scale = 2.0; lastScale = 2.0 }
                                }
                            }
                            .padding()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Type", value: photo.isBefore ? "Before Service" : "After Service")
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
            .navigationTitle(photo.isBefore ? "Before Photo" : "After Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingShareSheet = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(image == nil)
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        modelContext.delete(photo)
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
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
