//
//  LeaderboardView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/9/26.
//

import SwiftUI

struct LeaderboardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: SessionManager
    let sport: Sport
    
    @State private var leaderboardData: [LeaderboardEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Sport Header
                    sportHeader

                    // Leaderboard Entries
                    VStack(spacing: Spacing.sm) {
                        if isLoading {
                            ProgressView()
                                .padding(Spacing.xl)
                        } else if let errorMessage = errorMessage {
                            VStack(spacing: Spacing.md) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundStyle(Color.appError)
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appTextSecondary)
                                    .multilineTextAlignment(.center)
                                Button("Retry") {
                                    Task {
                                        await loadLeaderboard()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(Spacing.xl)
                        } else if leaderboardData.isEmpty {
                            VStack(spacing: Spacing.md) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(Color.appTextSecondary.opacity(0.3))
                                
                                Text("No rankings yet")
                                    .font(.headline)
                                    .foregroundStyle(Color.appTextPrimary)
                                
                                Text("Play 5+ ranked matches to appear on the leaderboard")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appTextSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(Spacing.xl)
                        } else {
                            ForEach(leaderboardData, id: \.userId) { entry in
                                leaderboardRow(entry: entry)
                            }
                        }
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("\(sport.rawValue) Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadLeaderboard()
            }
        }
    }
    
    private func loadLeaderboard() async {
        isLoading = true
        errorMessage = nil
        
        do {
            leaderboardData = try await APIClient.shared.getLeaderboard(sport: sport.apiValue)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }

    private var sportHeader: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: sport.icon)
                .font(.system(size: 40))
                .foregroundStyle(Color.appPrimary)

            VStack(alignment: .leading, spacing: 4) {
                Text(sport.rawValue)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)

                Text("Top 100 Rankings")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
            }

            Spacer()
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    private func leaderboardRow(entry: LeaderboardEntry) -> some View {
        HStack(spacing: Spacing.md) {
            // Rank Badge
            ZStack {
                Circle()
                    .fill(rankColor(entry.rank))
                    .frame(width: 40, height: 40)

                Text("\(entry.rank)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }

            // Avatar
            AvatarView(name: entry.fullName, size: 40)

            // Player Info
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.fullName)
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)

                Text("@\(entry.username)")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                
                Text(entry.rankTier)
                    .font(.caption2)
                    .foregroundStyle(Color.appPrimary)
            }

            Spacer()

            // Stats
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(entry.rating)")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appPrimary)

                Text("\(entry.wins)W - \(entry.losses)L")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1:
            return Color(hex: "FFD700") // Gold
        case 2:
            return Color(hex: "C0C0C0") // Silver
        case 3:
            return Color(hex: "CD7F32") // Bronze
        default:
            return Color.appTextSecondary.opacity(0.3)
        }
    }

}

// Helper extension for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        let scanner = Scanner(string: hex)
        scanner.scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    LeaderboardView(sport: .basketball)
        .environmentObject(SessionManager.shared)
}
