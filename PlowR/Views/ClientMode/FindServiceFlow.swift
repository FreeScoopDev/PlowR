import SwiftUI
import MapKit
import CoreLocation

// MARK: - Shared Client Mode Types

struct BusinessResult: Hashable, Identifiable {
    let id = UUID()
    let name: String
    let phone: String
    let address: String
    let latitude: Double
    let longitude: Double
    var website: URL? = nil

    static func from(_ item: MKMapItem) -> BusinessResult {
        let addrParts = [
            item.placemark.subThoroughfare,
            item.placemark.thoroughfare,
            item.placemark.locality,
            item.placemark.administrativeArea,
        ].compactMap { $0 }
        return BusinessResult(
            name: item.name ?? "Business",
            phone: item.phoneNumber ?? "",
            address: addrParts.joined(separator: " "),
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude,
            website: item.url
        )
    }
}

struct ClientZoneDraft: Hashable, Identifiable {
    let id = UUID()
    var label: String
    var areaSquareFeet: Double
    var rateType: String
    var elevationGrade: Double
    var coordinatesData: Data

    var coordinates: [CLLocationCoordinate2D] {
        ((try? JSONDecoder().decode([[Double]].self, from: coordinatesData)) ?? [])
            .compactMap { pair in
                guard pair.count == 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
            }
    }

    init(label: String, areaSquareFeet: Double, rateType: String, elevationGrade: Double, coordinates: [CLLocationCoordinate2D]) {
        self.label = label
        self.areaSquareFeet = areaSquareFeet
        self.rateType = rateType
        self.elevationGrade = elevationGrade
        let pairs = coordinates.map { [$0.latitude, $0.longitude] }
        self.coordinatesData = (try? JSONEncoder().encode(pairs)) ?? Data()
    }
}

// MARK: - Navigation Destinations

enum ServiceFlowDestination: Hashable {
    case businessSearch(category: String)
    case propertyScan(business: BusinessResult, category: String)
    case workOrder(zones: [ClientZoneDraft], business: BusinessResult, category: String, propertyAddress: String)
}

// MARK: - FindServiceFlow

struct FindServiceFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [ServiceFlowDestination] = []

    private let serviceCategories: [(name: String, icon: String)] = [
        ("Snow Removal", "snowflake"),
        ("Ice Management", "thermometer.snowflake"),
        ("Lawn Care", "leaf.fill"),
        ("Landscaping", "tree.fill"),
        ("Driveway Cleaning", "sparkles"),
        ("Walkway Service", "figure.walk"),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            categoryGrid
                .navigationDestination(for: ServiceFlowDestination.self) { destination in
                    switch destination {
                    case .businessSearch(let category):
                        BusinessSearchView(category: category) { business in
                            path.append(.propertyScan(business: business, category: category))
                        }
                    case .propertyScan(let business, let category):
                        ClientPropertyScanView(business: business, category: category) { zones, address in
                            path.append(.workOrder(zones: zones, business: business, category: category, propertyAddress: address))
                        }
                    case .workOrder(let zones, let business, let category, let address):
                        WorkOrderRequestView(zones: zones, business: business, category: category, propertyAddress: address)
                    }
                }
        }
    }

    private var categoryGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("What service are you looking for?")
                    .font(.title2.bold())
                    .padding(.horizontal)
                    .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(serviceCategories, id: \.name) { cat in
                        Button {
                            path.append(.businessSearch(category: cat.name))
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 32))
                                    .foregroundStyle(.blue)
                                Text(cat.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("Find a Service")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
