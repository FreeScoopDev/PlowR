import SwiftUI

/// The services part of a Service Log form: the catalog's services to tick,
/// each with its price for the property; services recorded earlier that are
/// no longer in the catalog; and custom items. Record Services, Log Work and
/// a record's own page all edit a StopRecording's parts through this, so the
/// three can't drift apart.
struct ServiceLinesSections: View {
    /// The active catalog, in its order.
    let services: [StopRecording.Service]
    let zones: [InvoiceLines.Zone]
    let operatorID: String
    @Binding var selectedIDs: Set<String>
    @Binding var typedPrices: [String: String]
    @Binding var customItems: [StopRecording.CustomItem]
    @Binding var keptLines: [ServiceRecord.Line]
    /// On an invoice with services: nothing here can change.
    var locked = false
    var footer: String?

    var body: some View {
        Section {
            if services.isEmpty {
                // A business that went straight to a route had none, and had
                // to leave for Settings to get any.
                StandardServicesOffer(operatorID: operatorID)
            } else {
                ForEach(services, id: \.id) { service in
                    serviceRow(service)
                }
            }
        } header: {
            Text("Services Performed")
        } footer: {
            if let footer { Text(footer) }
        }

        if !keptLines.isEmpty {
            Section {
                ForEach(keptLines, id: \.serviceID) { line in
                    LabeledContent(line.name, value: "$" + StopRecording.money(line.price))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                keptLines.removeAll { $0.serviceID == line.serviceID }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text("Also Recorded")
            } footer: {
                Text("No longer in your active services, so kept as recorded.")
            }
            .disabled(locked)
        }

        Section("Custom Services") {
            ForEach($customItems) { $item in
                HStack(spacing: 8) {
                    TextField("Service name", text: $item.name)
                    Divider()
                    Text("$").foregroundStyle(.secondary)
                    TextField("0.00", text: $item.price)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        customItems.removeAll { $0.id == item.id }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                customItems.append(StopRecording.CustomItem(name: "", price: ""))
            } label: {
                Label("Add Custom Item", systemImage: "plus")
            }
        }
        .disabled(locked)
    }

    /// No measured area to price it by, and no price entered yet; not on a
    /// locked record, whose price is changed on its invoice.
    private func showsPriceNote(for service: StopRecording.Service) -> Bool {
        !locked && InvoiceLines.needsPrice(unitType: service.unitType, zones: zones)
            && InvoiceLines.price(typed: typedPrices[service.id], default: 0) <= 0
    }

    // For per-sqft services, the meaningful price is rate × total area.
    // People see and override the dollar total, not the per-sqft unit rate.
    private func defaultPrice(for service: StopRecording.Service) -> Double {
        InvoiceLines.propertyPrice(unitType: service.unitType, pricePerUnit: service.pricePerUnit, zones: zones)
    }

    private func serviceRow(_ service: StopRecording.Service) -> some View {
        let key = service.id
        let isOn = selectedIDs.contains(key)
        return VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { on in
                    UIImpactFeedbackGenerator(style: on ? .medium : .light).impactOccurred()
                    if on {
                        selectedIDs.insert(key)
                        if typedPrices[key] == nil {
                            typedPrices[key] = StopRecording.money(defaultPrice(for: service))
                        }
                    } else {
                        selectedIDs.remove(key)
                    }
                }
            )) {
                Text(service.name)
            }
            .disabled(locked)
            if isOn {
                HStack(spacing: 4) {
                    Text("Price: $").font(.caption).foregroundStyle(.secondary)
                    TextField("0.00", text: Binding(
                        get: { typedPrices[key] ?? StopRecording.money(defaultPrice(for: service)) },
                        set: { typedPrices[key] = $0 }
                    ))
                    .keyboardType(.decimalPad)
                    .font(.caption)
                    .frame(width: 72)
                    .disabled(locked)
                    if service.unitType == "perSqFt", case let area = InvoiceLines.totalArea(zones), area > 0 {
                        Text("(\(Int(area)) sqft)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 48)
                .padding(.bottom, showsPriceNote(for: service) ? 0 : 6)
                if showsPriceNote(for: service) {
                    Text("Priced by the square foot, and there's no measured area: enter the price.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.leading, 48)
                        .padding(.bottom, 6)
                }
            }
        }
    }
}
