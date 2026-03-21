//
//  HotMapsView.swift
//  SportsHub
//
//  Hot Maps - Location-based player activity visualization
//

import SwiftUI
import MapKit

struct HotMapsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedSport: Sport = .basketball
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var nearbyPlayers: [NearbyPlayer] = []
    @State private var isLoadingLocation = false
    @State private var locationError: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Map View
                Map(position: .constant(.region(region))) {
                    ForEach(nearbyPlayers) { player in
                        Annotation("", coordinate: player.coordinate) {
                            playerAnnotation(player: player)
                        }
                    }
                }
                .ignoresSafeArea()
                
                // Overlay UI
                VStack {
                    // Sport Selector
                    sportSelectorCard
                        .padding(Spacing.md)
                    
                    Spacer()
                    
                    // Player List Card
                    if !nearbyPlayers.isEmpty {
                        nearbyPlayersCard
                            .padding(Spacing.md)
                    }
                }
                
                // Location Error Banner
                if let error = locationError {
                    VStack {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                                .font(.caption)
                            Spacer()
                            Button("Dismiss") {
                                locationError = nil
                            }
                            .font(.caption)
                        }
                        .padding(Spacing.sm)
                        .background(Color.appError)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                        .padding(Spacing.md)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Hot Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        loadNearbyPlayers()
                    }) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(Color.appPrimary)
                    }
                }
            }
            .task {
                loadNearbyPlayers()
            }
        }
    }
    
    private var sportSelectorCard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Sport.allCases, id: \.self) { sport in
                    Button(action: {
                        selectedSport = sport
                        loadNearbyPlayers()
                    }) {
                        HStack {
                            Image(systemName: sport.icon)
                            Text(sport.rawValue)
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
            .padding(.horizontal, Spacing.xs)
        }
        .padding(Spacing.sm)
        .background(Color.appSurface.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
    
    private var nearbyPlayersCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Nearby Players")
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
                Text("\(nearbyPlayers.count)")
                    .font(.subheadline)
                    .foregroundStyle(Color.appPrimary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(nearbyPlayers) { player in
                        nearbyPlayerCard(player: player)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.appSurface.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
    
    private func nearbyPlayerCard(player: NearbyPlayer) -> some View {
        VStack(spacing: Spacing.sm) {
            AvatarView(name: player.name, size: 48)
            
            VStack(spacing: 4) {
                Text(player.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appTextPrimary)
                
                Text(String(format: "%.1f km", player.distance))
                    .font(.caption2)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
        .frame(width: 80)
        .padding(Spacing.sm)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
    }
    
    private func playerAnnotation(player: NearbyPlayer) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.appPrimary)
                    .frame(width: 32, height: 32)
                
                Image(systemName: selectedSport.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            
            // Pin tail
            Path { path in
                path.move(to: CGPoint(x: 16, y: 32))
                path.addLine(to: CGPoint(x: 16, y: 40))
            }
            .stroke(Color.appPrimary, lineWidth: 2)
        }
    }
    
    private func loadNearbyPlayers() {
        isLoadingLocation = true
        locationError = nil
        
        // TODO: Request location permissions and fetch user's current location
        // TODO: Call backend API to get nearby players
        
        // Mock data for demonstration
        nearbyPlayers = [
            NearbyPlayer(
                id: "1",
                name: "Alex Rivera",
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                distance: 0.5,
                rating: 1540
            ),
            NearbyPlayer(
                id: "2",
                name: "Morgan Chen",
                coordinate: CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4094),
                distance: 1.2,
                rating: 1485
            ),
            NearbyPlayer(
                id: "3",
                name: "Taylor Kim",
                coordinate: CLLocationCoordinate2D(latitude: 37.7649, longitude: -122.4294),
                distance: 1.8,
                rating: 1520
            )
        ]
        
        isLoadingLocation = false
    }
}

// MARK: - Nearby Player Model
struct NearbyPlayer: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let distance: Double // in km
    let rating: Int
}

#Preview {
    HotMapsView()
        .environmentObject(SessionManager.shared)
}
