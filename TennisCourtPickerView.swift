import SwiftUI
import CoreLocation
import Combine

struct TennisCourtPickerView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var locationManager = LocationManager()
    @State private var courts: [TennisCourt] = []
    @State private var selectedCourt: TennisCourt?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchRadius: Double = 10.0

    let onCourtSelected: (TennisCourt) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Controls
                VStack(spacing: Spacing.md) {
                    // Radius Control
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text("Search Radius")
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextSecondary)
                            Spacer()
                            Text("\(Int(searchRadius)) miles")
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextPrimary)
                        }

                        Slider(value: $searchRadius, in: 1...50, step: 1)
                            .tint(Color.appPrimary)
                            .onChange(of: searchRadius) { _, _ in
                                fetchNearbyCourts()
                            }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)

                    // Search Button
                    Button {
                        fetchNearbyCourts()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh Courts")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.appTextPrimary)
                        .padding(.vertical, Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(Color.appSurface)
                        .cornerRadius(CornerRadius.medium)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .disabled(isLoading)
                }
                .padding(.bottom, Spacing.md)
                .background(Color.appBackground)

                Divider()

                // Court List
                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(Color.appPrimary)
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.appError)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.xl)
                        Button("Retry") {
                            fetchNearbyCourts()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.appPrimary)
                    }
                    Spacer()
                } else if courts.isEmpty {
                    Spacer()
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.appTextSecondary)
                        Text("No tennis courts found nearby")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary)
                        Text("Try increasing the search radius")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary.opacity(0.7))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.md) {
                            ForEach(courts) { court in
                                TennisCourtRow(
                                    court: court,
                                    isSelected: selectedCourt?.id == court.id
                                )
                                .onTapGesture {
                                    selectedCourt = court
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                    }
                }
            }
            .navigationTitle("Select Tennis Court")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.appTextSecondary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Select") {
                        if let court = selectedCourt {
                            onCourtSelected(court)
                            dismiss()
                        }
                    }
                    .foregroundStyle(Color.appPrimary)
                    .disabled(selectedCourt == nil)
                }
            }
        }
        .onAppear {
            locationManager.requestLocation()
            fetchNearbyCourts()
        }
    }

    private func fetchNearbyCourts() {
        guard let location = locationManager.location else {
            errorMessage = "Unable to determine your location. Please enable location services."
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetchedCourts = try await APIClient.shared.getNearbyTennisCourts(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    radiusMiles: searchRadius
                )

                await MainActor.run {
                    courts = fetchedCourts
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load tennis courts: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

struct TennisCourtRow: View {
    let court: TennisCourt
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(court.name)
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.appPrimary)
                        Text("\(court.city), \(court.state)")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary)

                        if let distance = court.distanceMiles {
                            Text("•")
                                .foregroundStyle(Color.appTextSecondary.opacity(0.5))
                            Text("\(String(format: "%.1f", distance)) mi")
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.appPrimary)
                }
            }

            // Court Details
            HStack(spacing: Spacing.md) {
                if let surface = court.surfaceType {
                    CourtFeatureBadge(icon: "circle.fill", text: surface.capitalized, color: .blue)
                }

                if court.indoor {
                    CourtFeatureBadge(icon: "building.2.fill", text: "Indoor", color: .green)
                } else if court.hasLights {
                    CourtFeatureBadge(icon: "lightbulb.fill", text: "Lights", color: .yellow)
                }

                if court.numCourts > 1 {
                    CourtFeatureBadge(icon: "rectangle.grid.2x2", text: "\(court.numCourts) courts", color: .purple)
                }
            }

            // Venue Access Warning
            if court.requiresMembership || court.requiresReservation || court.hourlyRate != nil {
                Divider()
                    .padding(.vertical, Spacing.xs)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            if court.requiresMembership {
                                Text("• Membership required")
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextSecondary)
                            }
                            if court.requiresReservation {
                                Text("• Reservation required")
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextSecondary)
                            }
                            if let rate = court.hourlyRate {
                                Text("• \(court.currency ?? "USD") \(String(format: "%.2f", rate))/hour")
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextSecondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(isSelected ? Color.appPrimary.opacity(0.1) : Color.appSurface)
        .cornerRadius(CornerRadius.large)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(isSelected ? Color.appPrimary : Color.clear, lineWidth: 2)
        )
    }
}

struct CourtFeatureBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(6)
    }
}

// Location Manager for getting user's current location
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}
