import SwiftUI
import MessageUI
import CoreLocation

struct NotifyPromptView: View {
    let stop: RouteStop
    let locationManager: LocationManager
    let onAdvance: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var estimatedMinutes: Int?
    @State private var showingMessageComposer = false

    var etaText: String {
        guard let minutes = estimatedMinutes else { return "a few minutes" }
        return "about \(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    var messageBody: String {
        let firstName = stop.clientName.components(separatedBy: " ").first ?? stop.clientName
        var message = "Hi \(firstName), I'm on my way and \(etaText) out."
        if let coord = locationManager.currentLocation?.coordinate {
            message += " Here's my location: https://maps.apple.com/?ll=\(coord.latitude),\(coord.longitude)"
        }
        return message
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Notify Next Client?")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Text(stop.clientName)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    if !stop.clientAddress.isEmpty {
                        Text(stop.clientAddress)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.blue)
                    if estimatedMinutes == nil {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Calculating...")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(etaText + " away")
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Message Preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    Text(messageBody)
                        .font(.subheadline)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
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
                            .padding()
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
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
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
            MessageComposer(recipients: [stop.clientPhone], body: messageBody) {
                onAdvance()
                dismiss()
            }
        }
    }
}
