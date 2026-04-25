//
//  HotMapsView.swift
//  SportsHub
//
//  Hot Maps — real user location via CoreLocation + available players from matchmaking API
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - HotMapsView

struct HotMapsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var locationManager = LocationManager()
    @State private var selectedSport: Sport = .basketball
    @State private var nearbyPlayers: [OpponentResponse] = []
    @State private var isLoadingPlayers = false
    @State private var loadError: String?
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Interactive map centered on real location
                Map(position: $cameraPosition) {
                    UserAnnotation()
                }
                .ignoresSafeArea(edges: .top)

                // Bottom panel
                VStack(spacing: 0) {
                    // Sport selector
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            ForEach(Sport.allCases, id: \.self) { sport in
                                Button {
                                    selectedSport = sport
                                    Task { await loadNearbyPlayers() }
                                } label: {
                                    HStack {
                                        Image(systemName: sport.icon)
                                        Text(sport.rawValue.capitalized)
                                            .fontWeight(.medium)
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, Spacing.sm)
                                    .background(selectedSport == sport ? Color.appPrimary : Color.appSurface)
                                    .foregroundStyle(selectedSport == sport ? .white : Color.appTextPrimary)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                    .padding(.vertical, Spacing.sm)
                    .background(Color.appSurface.opacity(0.97))

                    Divider()

                    // Players panel
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text("Available Players Nearby")
                                .font(.headline)
                                .foregroundStyle(Color.appTextPrimary)
                            Spacer()
                            if isLoadingPlayers {
                                ProgressView()
                            } else {
                                Text("\(nearbyPlayers.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appPrimary)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.sm)

                        if let error = loadError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.appError)
                                .padding(.horizontal, Spacing.md)
                        } else if nearbyPlayers.isEmpty && !isLoadingPlayers {
                            Text("No available \(selectedSport.rawValue.capitalized) players right now")
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextSecondary)
                                .padding(.horizontal, Spacing.md)
                                .padding(.bottom, Spacing.sm)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Spacing.sm) {
                                    ForEach(nearbyPlayers.prefix(10), id: \.userId) { player in
                                        nearbyPlayerCard(player)
                                    }
                                }
                                .padding(.horizontal, Spacing.md)
                            }
                        }
                    }
                    .padding(.bottom, Spacing.md)
                    .background(Color.appSurface.opacity(0.97))
                }
            }
            .navigationTitle("Hot Maps")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: locationManager.location) { _, newLocation in
                guard let location = newLocation else { return }
                cameraPosition = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
            .task {
                locationManager.requestLocation()
                await loadNearbyPlayers()
            }
        }
    }

    private func nearbyPlayerCard(_ player: OpponentResponse) -> some View {
        VStack(spacing: Spacing.sm) {
            AvatarView(name: player.fullName, size: 48)

            VStack(spacing: 4) {
                Text(player.username)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appTextPrimary)
                    .lineLimit(1)

                Text("Rating: \(player.rating)")
                    .font(.caption2)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
        .frame(width: 80)
        .padding(Spacing.sm)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
    }

    private func loadNearbyPlayers() async {
        isLoadingPlayers = true
        loadError = nil
        defer { isLoadingPlayers = false }

        do {
            nearbyPlayers = try await APIClient.shared.findOpponents(sport: selectedSport.rawValue, matchType: "casual")
        } catch {
            loadError = "Couldn't load players. Pull to refresh."
        }
    }
}

#Preview {
    HotMapsView()
        .environmentObject(SessionManager.shared)
}
