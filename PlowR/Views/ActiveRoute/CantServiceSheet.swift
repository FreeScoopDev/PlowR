import SwiftUI

/// Can't Service, at the current stop: picks the reason and takes a note.
/// It only collects them: `save` hands them to the route screen, which skips
/// the stop through ActiveRouteStore. Cancel changes nothing.
struct CantServiceSheet: View {
    let clientName: String
    /// Skips the stop with this reason (CantService.reason) and moves on.
    let save: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var preset = CantService.presets[0]
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Stop", value: clientName)
                } footer: {
                    SectionNote("PlowR moves on to the next stop. No visit, time or services are recorded, and nothing is billed. The reason stays on the route's page and in the recap until the route's next run.")
                }
                .listRowBackground(PlowRColor.surface)
                Section(title: "Reason") {
                    Picker("Reason", selection: $preset) {
                        ForEach(CantService.presets, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .listRowBackground(PlowRColor.surface)
                Section(title: "Note") {
                    TextField(preset == CantService.other ? "What happened" : "Optional", text: $note,
                              axis: .vertical)
                        .lineLimit(2...5)
                }
                .listRowBackground(PlowRColor.surface)
            }
            .plowRGrouped()
            .navigationTitle("Can't Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Move On") {
                        save(CantService.reason(preset: preset, note: note))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .interactiveDismissDisabled(!note.isEmpty)
        }
    }
}
