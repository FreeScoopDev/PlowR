import SwiftUI
import MessageUI
import CoreLocation

private struct MessagePreset: Identifiable {
    let id = UUID()
    let label: String
    let text: String
}

private let messagePresets: [MessagePreset] = [
    MessagePreset(label: "Move Vehicles",
                  text: "If possible, please move any vehicles from the driveway before I arrive."),
    MessagePreset(label: "Running Late",
                  text: "I'm running a bit behind schedule — thank you so much for your patience."),
    MessagePreset(label: "Weather Delay",
                  text: "Weather conditions are slowing things down. I'm working safely and will be there shortly."),
    MessagePreset(label: "Refueling",
                  text: "I'm stopping to refuel on the way — just a brief delay ahead."),
    MessagePreset(label: "Road Conditions",
                  text: "Roads are slow right now — I'll be there as soon as conditions allow."),
    MessagePreset(label: "Door to Door",
                  text: "I'll make sure everything is tidy before I move on."),
    MessagePreset(label: "Gate / Access",
                  text: "Could you make sure the gate is unlocked when I arrive? Appreciate it."),
]

struct NotifyPromptView: View {
    let stop: RouteStop
    let locationManager: LocationManager
    let onAdvance: () -> Void
    var promptTitle: String = "Notify Next Client?"

    @Environment(\.dismiss) private var dismiss
    @State private var estimatedMinutes: Int?
    @State private var showingMessageComposer = false
    @State private var customNote: String = ""
    @State private var selectedPresetIDs: Set<UUID> = []
    @AppStorage("notifyIncludeLocation") private var includeLocation: Bool = false

    // MARK: - Computed

    var etaText: String {
        guard let minutes = estimatedMinutes else { return "a few minutes" }
        return "about \(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    private var baseMessage: String {
        let firstName = stop.clientName.components(separatedBy: " ").first ?? stop.clientName
        return "Hi \(firstName), I'm on my way and \(etaText) out."
    }

    private var selectedPresets: [MessagePreset] {
        messagePresets.filter { selectedPresetIDs.contains($0.id) }
    }

    var fullMessage: String {
        var parts: [String] = [baseMessage]
        for preset in selectedPresets { parts.append(preset.text) }
        let note = customNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { parts.append(note) }
        var message = parts.joined(separator: " ")
        if includeLocation, let coord = locationManager.currentLocation?.coordinate {
            message += "\n\nLocation: https://maps.apple.com/?ll=\(coord.latitude),\(coord.longitude)"
        }
        return message
    }

    private var previewMessage: String {
        var parts: [String] = [baseMessage]
        for preset in selectedPresets { parts.append(preset.text) }
        let note = customNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { parts.append(note) }
        var message = parts.joined(separator: " ")
        if includeLocation && locationManager.currentLocation != nil {
            message += "\n\n📍 [Your location link will appear here]"
        }
        return message
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    clientHeader
                    etaRow
                    presetsSection
                    customNoteField
                    if locationManager.currentLocation != nil { locationToggle }
                    messagePreview
                }
                .padding(.horizontal)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .safeAreaInset(edge: .bottom) { actionButtons }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            estimatedMinutes = await locationManager.calculateETA(to: stop)
        }
        .sheet(isPresented: $showingMessageComposer) {
            MessageComposer(recipients: [stop.clientPhone], body: fullMessage) { outcome in
                // Cancelled or failed: back to this prompt, where Skip moves on
                // without a text. It used to move on as if the text had gone.
                guard outcome == .sent else {
                    showingMessageComposer = false
                    return
                }
                onAdvance()
                dismiss()
            }
        }
    }

    // MARK: - Sub-views

    private var clientHeader: some View {
        VStack(spacing: 6) {
            Text(promptTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(stop.clientName)
                .font(.largeTitle)
                .fontWeight(.bold)
            if !stop.clientAddress.isEmpty {
                Text(stop.clientAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .multilineTextAlignment(.center)
    }

    private var etaRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.fill").foregroundStyle(.blue)
            if estimatedMinutes == nil {
                ProgressView().scaleEffect(0.8)
                Text("Calculating ETA…").foregroundStyle(.secondary)
            } else {
                Text(etaText + " away").font(.headline)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Add-Ons")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(messagePresets) { preset in
                        let isOn = selectedPresetIDs.contains(preset.id)
                        Button {
                            if isOn { selectedPresetIDs.remove(preset.id) }
                            else    { selectedPresetIDs.insert(preset.id) }
                        } label: {
                            Text(preset.label)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isOn ? Color.blue : Color(.systemGray5))
                                .foregroundStyle(isOn ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var customNoteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom Note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Add a personal note (optional)…", text: $customNote, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...4)
                .padding(14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var locationToggle: some View {
        Toggle(isOn: $includeLocation) {
            Label("Include my location link", systemImage: "location.fill")
                .font(.subheadline)
        }
        .tint(.blue)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var messagePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Message Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(previewMessage)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                if MFMessageComposeViewController.canSendText() {
                    showingMessageComposer = true
                } else {
                    onAdvance()
                    dismiss()
                }
            } label: {
                Label("Send Message", systemImage: "message.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button {
                onAdvance()
                dismiss()
            } label: {
                Text("Skip")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }
}
