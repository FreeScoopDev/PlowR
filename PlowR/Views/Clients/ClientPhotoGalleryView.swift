import SwiftUI
import SwiftData

struct ClientPhotoGalleryView: View {
    let client: Client
    @Environment(\.modelContext) private var modelContext
    @Query private var allPhotos: [StopPhoto]

    @State private var selectedPhoto: StopPhoto?
    @State private var filterBefore: Bool? = nil // nil = all, true = before, false = after

    private var clientPhotos: [StopPhoto] {
        allPhotos
            .filter { $0.clientID == client.id.uuidString }
            .filter { filterBefore == nil || $0.isBefore == filterBefore }
            .sorted { $0.takenAt > $1.takenAt }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 3)
    ]

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
                filterMenu
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo)
        }
    }

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
            Label(photo.isBefore ? "Before" : "After", systemImage: photo.isBefore ? "clock" : "checkmark")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(photo.isBefore ? Color.orange.opacity(0.85) : Color.green.opacity(0.85))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(4)
        }
        .clipped()
        .contentShape(Rectangle())
    }


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

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No Photos Yet")
                .font(.headline)
            Text("Photos taken during route stops will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
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
                        LabeledContent("Date") {
                            Text(photo.takenAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
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
                    Button {
                        showingShareSheet = true
                    } label: {
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
                if let img = image {
                    PhotoShareSheet(image: img)
                }
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
