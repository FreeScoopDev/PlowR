import SwiftUI

struct ClientHomeView: View {
    @AppStorage("userRole") private var userRole = ""
    @State private var showingFindService = false
    @State private var workOrderStore = ClientWorkOrderStore()
    @State private var resendingOrder: ClientWorkOrder?
    @State private var showingResendSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Hero
                    VStack(spacing: 10) {
                        Image(systemName: "snowflake")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        Text("Welcome to PlowR")
                            .font(.title.bold())
                        Text("Find local service operators and send a property-specific request in minutes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 48)

                    Button {
                        showingFindService = true
                    } label: {
                        Label("Find Services Near Me", systemImage: "location.magnifyingglass")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 32)

                    // Past Requests
                    if !workOrderStore.orders.isEmpty {
                        pastRequestsSection
                    }

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("PlowR")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            userRole = ""
                        } label: {
                            Label("Switch to Operator Mode", systemImage: "arrow.left.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingFindService) {
            FindServiceFlow()
                .environment(workOrderStore)
        }
        .sheet(isPresented: $showingResendSheet) {
            if let order = resendingOrder {
                WorkOrderShareSheet(message: order.messageText)
            }
        }
    }

    private var pastRequestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Past Requests")
                    .font(.headline)
                Spacer()
                if workOrderStore.orders.count > 3 {
                    NavigationLink("See All") {
                        allRequestsView
                    }
                    .font(.subheadline)
                }
            }
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                ForEach(workOrderStore.orders.prefix(3)) { order in
                    workOrderRow(order)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var allRequestsView: some View {
        List {
            ForEach(workOrderStore.orders) { order in
                workOrderRow(order)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            workOrderStore.delete(order)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle("All Requests")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func workOrderRow(_ order: ClientWorkOrder) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(order.businessName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(order.category)
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    Text(order.submittedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !order.propertyAddress.isEmpty {
                    Text(order.propertyAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                resendingOrder = order
                showingResendSheet = true
            } label: {
                Label("Resend", systemImage: "arrow.uturn.right")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }
}
