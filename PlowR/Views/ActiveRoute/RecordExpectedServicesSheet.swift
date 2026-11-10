import SwiftUI

/// The route recap's confirmation for Record Expected Services: every stop it
/// would record for, by client, with the services, before anything is
/// recorded (RecapServices). Cancel changes nothing.
struct RecordExpectedServicesSheet: View {
    let planned: [RecapServices.Planned]
    /// Records them (RecapServiceRecorder); the sheet then closes.
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(planned) { stop in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.clientName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PlowRColor.ink)
                            Text(RecapServices.servicesText(stop))
                                .font(.subheadline)
                                .foregroundStyle(PlowRColor.inkSecondary)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    SectionNote(verbatim: RecapServices.confirmNote)
                }
                .listRowBackground(PlowRColor.surface)

                Section {
                    Button {
                        onConfirm()
                        dismiss()
                    } label: {
                        Label(RecapServices.confirmTitle(count: planned.count), systemImage: "checklist")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plowRAction)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                .listRowBackground(PlowRColor.surface)
            }
            .plowRGrouped()
            .navigationTitle("Record Expected Services")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
