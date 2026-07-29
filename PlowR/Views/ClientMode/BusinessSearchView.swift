import SwiftUI
import MapKit
import CoreLocation

struct BusinessSearchView: View {
    let category: String
    let onSelect: (BusinessResult) -> Void

    @State private var locationQuery = ""
    @State private var locationCompleter = AddressCompleter()
    @State private var businesses: [BusinessResult] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchError: String? = nil

    private var searchQuery: String {
        let map: [String: String] = [
            "Snow Removal": "snow plowing snow removal",
            "Ice Management": "deicing ice melt service",
            "Lawn Care": "lawn care lawn mowing",
            "Landscaping": "landscaping",
            "Driveway Cleaning": "pressure washing driveway",
            "Walkway Service": "property maintenance walkway",
        ]
        return map[category] ?? category
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if !locationCompleter.completions.isEmpty {
                locationSuggestions
            }
            Divider()
            resultContent
        }
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.circle")
                .foregroundStyle(.secondary)
            TextField("Town, city, or ZIP code", text: $locationQuery)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: locationQuery) { _, q in locationCompleter.search(q) }
                .onSubmit { Task { await search() } }
            if isSearching {
                ProgressView().scaleEffect(0.8)
            } else {
                Button("Search") { Task { await search() } }
                    .disabled(locationQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var locationSuggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(locationCompleter.completions, id: \.self) { completion in
                Button {
                    Task {
                        let result = await locationCompleter.resolve(completion)
                        locationQuery = [completion.title, completion.subtitle]
                            .filter { !$0.isEmpty }.joined(separator: ", ")
                        locationCompleter.clear()
                        await search(coordinate: result.coordinate)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(completion.title)
                                .foregroundStyle(.primary)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .tint(.primary)
                Divider()
            }
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var resultContent: some View {
        if let error = searchError {
            ContentUnavailableView(error, systemImage: "exclamationmark.circle")
        } else if hasSearched && businesses.isEmpty {
            ContentUnavailableView(
                "No Results Found",
                systemImage: "magnifyingglass",
                description: Text("Try a nearby location or different category.")
            )
        } else {
            List {
                if !businesses.isEmpty {
                    Section("\(businesses.count) results near \(locationQuery)") {
                        ForEach(businesses) { business in
                            Button {
                                onSelect(business)
                            } label: {
                                BusinessRow(business: business)
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func search(coordinate: CLLocationCoordinate2D? = nil) async {
        let query = locationQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isSearching = true
        searchError = nil
        businesses = []

        do {
            let center: CLLocationCoordinate2D
            if let coord = coordinate {
                center = coord
            } else {
                center = try await geocodeLocation(query)
            }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = searchQuery
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 50000,
                longitudinalMeters: 50000
            )
            let response = try await MKLocalSearch(request: request).start()
            await MainActor.run {
                businesses = response.mapItems.filter { $0.name != nil }.map { BusinessResult.from($0) }
                hasSearched = true
                isSearching = false
            }
        } catch {
            await MainActor.run {
                searchError = "Could not find results near '\(query)'. Try a different location."
                hasSearched = true
                isSearching = false
            }
        }
    }

    private func geocodeLocation(_ query: String) async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            CLGeocoder().geocodeAddressString(query) { placemarks, error in
                if let coord = placemarks?.first?.location?.coordinate {
                    continuation.resume(returning: coord)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "PlowR.Geocoding", code: 0))
                }
            }
        }
    }
}

struct BusinessRow: View {
    let business: BusinessResult
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(business.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !business.address.isEmpty {
                    Text(business.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !business.phone.isEmpty {
                    Text(business.phone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 6) {
                if !business.phone.isEmpty,
                   let url = URL(string: "tel:\(business.phone.filter { $0.isNumber })") {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.borderless)
                }
                if let url = business.website {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "safari")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
