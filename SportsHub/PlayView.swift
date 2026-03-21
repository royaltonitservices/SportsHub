//
//  PlayView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

struct PlayView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedSport: Sport = .basketball
    @State private var showMatchmaking = false
    @State private var showTeamLobby = false
    @State private var showLeaderboard = false
    @State private var sportProfile: SportProfileResponse?
    @State private var activeChallenges: [ChallengeResponse] = []
    @State private var isLoadingProfile = true
    @State private var isLoadingChallenges = true
    @State private var showResultSubmission = false
    @State private var selectedChallenge: ChallengeResponse?
    @State private var showDisputeDetail = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Sport Selector
                    sportSelector

                    // Placement Progress (if unrated)
                    if let profile = sportProfile, profile.isProvisional {
                        placementProgressCard
                    }

                    // Your Rating Card
                    yourRatingCard

                    // Quick Actions Row
                    quickActionsRow

                    // Active Challenges
                    VStack(spacing: Spacing.md) {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(Color.appPrimary)
                            Text(activeChallenges.isEmpty ? "Get Started" : "Active Matches")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.appTextPrimary)
                            Spacer()
                        }

                        if isLoadingChallenges {
                            ProgressView()
                                .padding(Spacing.xl)
                        } else if activeChallenges.isEmpty {
                            // Action-oriented empty state
                            noChallengesActionCard
                        } else {
                            ForEach(activeChallenges, id: \.id) { challenge in
                                challengeCard(challenge: challenge)
                            }
                        }
                    }

                    // Leaderboard Preview
                    VStack(spacing: Spacing.md) {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .foregroundStyle(Color.appPrimary)
                            Text("Leaderboard")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.appTextPrimary)
                            Spacer()
                            Button(action: { showLeaderboard = true }) {
                                Text("View All")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appPrimary)
                            }
                        }

                        VStack(spacing: Spacing.md) {
                            Image(systemName: "medal.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(Color.appTextSecondary.opacity(0.3))

                            Text("No rankings yet")
                                .font(.headline)
                                .foregroundStyle(Color.appTextSecondary)

                            Text("Start competing to appear on the leaderboard")
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextSecondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                        .cardBackground()
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("Play")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showMatchmaking) {
                MatchmakingView(sport: selectedSport)
                    .environmentObject(sessionManager)
            }
            .sheet(isPresented: $showTeamLobby) {
                TeamLobbyView(sport: selectedSport)
            }
            .sheet(isPresented: $showLeaderboard) {
                LeaderboardView(sport: selectedSport)
                    .environmentObject(sessionManager)
            }
            .sheet(isPresented: $showResultSubmission) {
                if let challenge = selectedChallenge {
                    ResultSubmissionView(challenge: challenge) {
                        await loadActiveChallenges()
                    }
                }
            }
            .sheet(isPresented: $showDisputeDetail) {
                if let challenge = selectedChallenge {
                    DisputeDetailView(challenge: challenge) {
                        await loadActiveChallenges()
                    }
                    .environmentObject(sessionManager)
                }
            }
            .task(id: selectedSport) {
                await loadSportProfile()
                await loadActiveChallenges()
            }
        }
    }
    
    private func loadSportProfile() async {
        isLoadingProfile = true
        
        do {
            sportProfile = try await APIClient.shared.getSportProfile(sport: selectedSport.rawValue)
        } catch {
            // Profile doesn't exist, create it
            do {
                sportProfile = try await APIClient.shared.createSportProfile(sport: selectedSport.rawValue)
            } catch {
                print("Failed to create sport profile: \(error)")
            }
        }
        
        isLoadingProfile = false
    }
    
    private func loadActiveChallenges() async {
        isLoadingChallenges = true
        
        do {
            activeChallenges = try await APIClient.shared.getPendingChallenges()
            // Filter to current sport
            activeChallenges = activeChallenges.filter { $0.sport.lowercased() == selectedSport.rawValue.lowercased() }
        } catch {
            print("Failed to load challenges: \(error)")
            activeChallenges = []
        }
        
        isLoadingChallenges = false
    }

    private var yourRatingCard: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Your Rating")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)

                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    if isLoadingProfile {
                        ProgressView()
                    } else {
                        Text("\(sportProfile?.rating ?? 1500)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appTextPrimary)
                    }

                    if let rankTier = sportProfile?.rankTier {
                        Text(rankTier)
                            .font(.subheadline)
                            .foregroundStyle(Color.appPrimary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.appPrimary.opacity(0.2)))
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text("Win Rate")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)

                if let profile = sportProfile {
                    Text(String(format: "%.1f%%", profile.winRate))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appTextPrimary)
                } else {
                    Text("0%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appTextPrimary)
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    private var findMatchButton: some View {
        Button(action: { showMatchmaking = true }) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.title3)

                Text("Find Match")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(Spacing.md)
            .background(Color.appPrimary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
    }
    
    private var teamPlayButton: some View {
        Button(action: { showTeamLobby = true }) {
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.title3)

                Text("Team Play")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(Spacing.md)
            .background(Color.appSecondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
    }

    private var sportSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Sport.allCases, id: \.self) { sport in
                    SportPillButton(
                        sport: sport,
                        isSelected: selectedSport == sport,
                        action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedSport = sport
                            }
                        }
                    )
                }
            }
        }
    }
    
    private var placementProgressCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "flag.checkered")
                    .font(.title2)
                    .foregroundStyle(Color.appPrimary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Placement Matches")
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    if let profile = sportProfile {
                        Text("\(profile.provisionalGames) of 5 complete")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
                
                Spacer()
            }
            
            ProgressView(value: Double(sportProfile?.provisionalGames ?? 0), total: 5.0)
                .tint(Color.appPrimary)
            
            Text("Complete 5 matches to unlock your official rating and appear on leaderboards")
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .strokeBorder(Color.appPrimary.opacity(0.3), lineWidth: 2)
        )
    }
    
    private var quickActionsRow: some View {
        HStack(spacing: Spacing.md) {
            // Find Match - Primary action
            Button(action: { showMatchmaking = true }) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find Match")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("1v1 Ranked")
                            .font(.caption2)
                            .opacity(0.8)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.appPrimary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            
            // Team Play - Secondary action
            Button(action: { showTeamLobby = true }) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "person.3.fill")
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Team Play")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Coming Soon")
                            .font(.caption2)
                            .opacity(0.8)
                    }
                }
                .foregroundStyle(Color.appPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.appPrimary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .strokeBorder(Color.appPrimary.opacity(0.3), lineWidth: 1.5)
                )
            }
        }
    }
    
    private var noChallengesActionCard: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.appPrimary.opacity(0.3))
                
                Text("Ready to compete?")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)
                
                Text("Start your first match or challenge a friend to begin tracking your progress")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Spacing.md)
            
            // Action buttons
            VStack(spacing: Spacing.sm) {
                Button(action: { showMatchmaking = true }) {
                    HStack {
                        Image(systemName: "person.2.fill")
                        Text("Find Match")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(.white)
                    .padding(Spacing.md)
                    .background(Color.appPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }
                
                Button(action: { showLeaderboard = true }) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                        Text("Browse Leaderboard")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(Color.appPrimary)
                    .padding(Spacing.md)
                    .background(Color.appPrimary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .strokeBorder(Color.appPrimary.opacity(0.3), lineWidth: 1.5)
                    )
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private func challengeCard(challenge: ChallengeResponse) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header with status
            HStack {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: statusIcon(for: challenge.status))
                        .font(.caption)
                        .foregroundStyle(statusColor(for: challenge.status))
                    Text(statusText(for: challenge.status))
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                }
                
                Spacer()
                
                HStack(spacing: Spacing.xs) {
                    Image(systemName: challenge.matchType == "ranked" ? "trophy.fill" : "gamecontroller.fill")
                        .font(.caption)
                    Text(challenge.matchType.capitalized)
                        .font(.caption)
                }
                .foregroundStyle(Color.appPrimary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.appPrimary.opacity(0.2)))
            }
            
            Divider()
            
            // Opponent info
            HStack(spacing: Spacing.md) {
                AvatarView(name: "Opponent", size: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opponent")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appTextPrimary)
                    Text(challenge.sport.capitalized)
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    
                    // Submission status badge
                    getSubmissionStatusBadge(for: challenge)
                }
                
                Spacer()
                
                // Action button
                if challenge.status == "pending" {
                    VStack(spacing: Spacing.xs) {
                        Button("Accept") {
                            Task {
                                await acceptChallenge(challenge)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appPrimary)

                        Button("Decline") {
                            Task {
                                await declineChallenge(challenge)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.appTextSecondary)
                        .font(.caption)
                    }
                } else if challenge.status == "accepted" {
                    VStack(spacing: 4) {
                        Button {
                            selectedChallenge = challenge
                            showResultSubmission = true
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Report Score")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.green)

                        Text("Match accepted")
                            .font(.caption2)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                } else if challenge.status == "disputed" {
                    // Phase 3: Show view details for disputed matches
                    Button {
                        selectedChallenge = challenge
                        showDisputeDetail = true
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("View Details")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.red)
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .strokeBorder(statusColor(for: challenge.status).opacity(0.3), lineWidth: 2)
        )
    }
    
    private func statusIcon(for status: String) -> String {
        switch status {
        case "pending": return "clock.fill"
        case "accepted": return "sportscourt.fill"
        case "completed": return "checkmark.circle.fill"
        case "disputed": return "exclamationmark.triangle.fill"
        default: return "questionmark.circle.fill"
        }
    }
    
    private func statusColor(for status: String) -> Color {
        switch status {
        case "pending": return Color.orange
        case "accepted": return Color.green
        case "completed": return Color.blue
        case "disputed": return Color.red
        default: return Color.gray
        }
    }
    
    private func statusText(for status: String) -> String {
        switch status {
        case "pending": return "Awaiting Response"
        case "accepted": return "Match Ready"
        case "completed": return "Completed"
        case "disputed": return "Under Review"
        default: return "Challenge"
        }
    }
    
    @ViewBuilder
    private func getSubmissionStatusBadge(for challenge: ChallengeResponse) -> some View {
        if challenge.status == "accepted" {
            let currentUserId = sessionManager.currentUser?.id.uuidString ?? ""
        let isChallenger = challenge.challengerId == currentUserId
        let userSubmitted = isChallenger ? challenge.challengerSubmittedScore != nil : challenge.opponentSubmittedScore != nil
        let opponentSubmitted = isChallenger ? challenge.opponentSubmittedScore != nil : challenge.challengerSubmittedScore != nil
        
        if userSubmitted && opponentSubmitted {
            // Both submitted - check if they match
            let scoresMatch = challenge.challengerSubmittedScore == challenge.opponentSubmittedScore
            if scoresMatch {
                HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("Confirmed")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            } else {
                HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("Disputed")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.15))
                    .clipShape(Capsule())
            }
        } else if userSubmitted {
            HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                    Text("Waiting for Opponent")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
        }
        }
    }
    
    private func declineChallenge(_ challenge: ChallengeResponse) async {
        do {
            // TODO: Add decline endpoint to API
            await loadActiveChallenges()
        } catch {
            print("Failed to decline challenge: \(error)")
        }
    }
    
    private func acceptChallenge(_ challenge: ChallengeResponse) async {
        do {
            _ = try await APIClient.shared.acceptChallenge(challengeId: challenge.id)
            await loadActiveChallenges()
        } catch {
            print("Failed to accept challenge: \(error)")
        }
    }
}

#Preview {
    PlayView()
        .environmentObject(SessionManager.shared)
}
