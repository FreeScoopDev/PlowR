import SwiftUI
import SwiftData

struct PaymentMethodsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allMethods: [PaymentMethod]
    @State private var showingAdd = false

    private var myMethods: [PaymentMethod] {
        allMethods
            .filter { $0.operatorID == authManager.userID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            if myMethods.isEmpty {
                ContentUnavailableView(
                    "No Payment Methods",
                    systemImage: "creditcard",
                    description: Text("Add the ways clients can pay you. These appear on invoices.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(myMethods) { method in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(method.label)
                                .font(.subheadline.weight(.medium))
                            Text(method.displayValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { method.isActive },
                            set: { method.isActive = $0 }
                        ))
                        .labelsHidden()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(method)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove { indices, destination in
                    var reordered = myMethods
                    reordered.move(fromOffsets: indices, toOffset: destination)
                    for (i, m) in reordered.enumerated() { m.sortOrder = i }
                }
            }
        }
        .navigationTitle("Payment Methods")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddPaymentMethodSheet(nextSortOrder: myMethods.count) { method in
                method.operatorID = authManager.userID
                modelContext.insert(method)
            }
        }
    }
}

// MARK: - Add Sheet

private enum MethodPreset: String, CaseIterable {
    case venmo    = "Venmo"
    case paypal   = "PayPal"
    case square   = "Square"
    case cashapp  = "Cash App"
    case zelle    = "Zelle"
    case check    = "Check"
    case cash     = "Cash"
    case custom   = "Custom"

    var methodType: String {
        switch self {
        case .check:  return "check"
        case .cash:   return "cash"
        case .zelle:  return "text"
        default:      return "link"
        }
    }

    /// Pre-filled base URL — user only needs to append their handle
    var urlPrefix: String {
        switch self {
        case .venmo:   return "venmo.com/u/"
        case .paypal:  return "paypal.me/"
        case .square:  return "square.link/"
        case .cashapp: return "cash.app/$"
        default:       return ""
        }
    }

    /// Placeholder shown in the text field for the variable portion
    var valuePlaceholder: String {
        switch self {
        case .venmo:   return "yourhandle"
        case .paypal:  return "yourname"
        case .square:  return "your-link-id"
        case .cashapp: return "yourhandle"
        case .zelle:   return "email or phone number"
        case .check:   return "Your Business Name LLC"
        case .cash, .custom: return ""
        }
    }

    var requiresValue: Bool {
        switch self { case .cash: return false; default: return true }
    }

    var keyboardType: UIKeyboardType {
        switch self {
        case .venmo, .paypal, .square, .cashapp, .custom: return .URL
        case .zelle: return .emailAddress
        default: return .default
        }
    }

    var systemImage: String {
        switch self {
        case .venmo:   return "v.circle.fill"
        case .paypal:  return "p.circle.fill"
        case .square:  return "squareshape.fill"
        case .cashapp: return "dollarsign.circle.fill"
        case .zelle:   return "z.circle.fill"
        case .check:   return "checkmark.rectangle.fill"
        case .cash:    return "banknote.fill"
        case .custom:  return "creditcard.fill"
        }
    }
}

private struct AddPaymentMethodSheet: View {
    let nextSortOrder: Int
    let onSave: (PaymentMethod) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var preset: MethodPreset = .venmo
    @State private var label = "Venmo"
    @State private var value = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Payment Type", selection: $preset) {
                        ForEach(MethodPreset.allCases, id: \.self) { p in
                            Label(p.rawValue, systemImage: p.systemImage).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: preset) { _, p in
                        label = p.rawValue
                        value = p.urlPrefix
                    }
                }

                Section("Details") {
                    TextField("Label", text: $label)
                    if preset.requiresValue {
                        TextField(preset.valuePlaceholder, text: $value)
                            .keyboardType(preset.keyboardType)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .onAppear { if value.isEmpty { value = preset.urlPrefix } }
                    }
                }

                if preset == .check {
                    Section {
                        EmptyView()
                    } footer: {
                        Text("The name clients should write on the check.")
                    }
                } else if preset.methodType == "link" {
                    Section {
                        EmptyView()
                    } footer: {
                        Text("Paste the payment link from your provider. Appears as a tappable link and QR code on invoices.")
                    }
                }
            }
            .navigationTitle("Add Payment Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let method = PaymentMethod(
                            operatorID: "",
                            label: label.isEmpty ? preset.rawValue : label,
                            value: value,
                            methodType: preset.methodType,
                            sortOrder: nextSortOrder
                        )
                        onSave(method)
                        dismiss()
                    }
                    .disabled(label.isEmpty || (preset.requiresValue && value.isEmpty))
                }
            }
        }
    }
}

// MARK: - Display helper

extension PaymentMethod {
    var displayValue: String {
        if isCash { return "Cash accepted" }
        if isCheck { return "Check payable to: \(value)" }
        return value.isEmpty ? label : value
    }
}
