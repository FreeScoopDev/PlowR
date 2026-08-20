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
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                filterMenu
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            photoDetailView(photo)
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

    @ViewBuilder
    private func photoDetailView(_ photo: StopPhoto) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image = UIImage(data: photo.imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    Button("Done") { selectedPhoto = nil }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        modelContext.delete(photo)
                        selectedPhoto = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
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
