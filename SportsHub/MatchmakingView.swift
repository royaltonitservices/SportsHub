//
//  MatchmakingView.swift
//  SportsHub
//
//  Enhanced Find Match Flow - Production Ready
//

import SwiftUI

struct MatchmakingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: SessionManager

    let sport: Sport

    @State private var matchType: MatchType = .ranked
    @State private var isSearching = false
    @State private var opponents: [OpponentResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var showChallengeSent = false
    @State private var challengedOpponentName = ""
    
    // Enhanced controls
    @State private var showManualRangeEditor = false
    @State private var manualRangeLower: Int = 50
    @State private var manualRangeUpper: Int = 50
    @State private var useManualRange = false
    @State private var eloRangeAdjustment: Int = 0 // Preset adjustments
    
    @State private var searchRadius: Double = 10.0 // miles
    @State private var showRadiusEditor = false
    
    @State private var availableNow: Bool = false
    @State private var isUpdatingAvailability = false
    
    // Friend search
    @State private var showFriendSearch = false
    @State private var friends: [FriendshipResponse] = []
    @State private var friendSearchQuery = ""
    @State private var isLoadingFriends = false
    
    // Trust warnings
    @State private var showTrustWarning = false
    @State private var selectedOpponentForWarning: OpponentResponse?
    
    // Tennis court selection
    @State private var showTennisCourtPicker = false
    @State private var selectedTennisCourt: TennisCourt?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Match Type Selector
                    matchTypeSelector
                    
                    // Tennis Court Selection (Tennis only)
                    if sport == .tennis {
                        tennisCourtSelector
                    }
                    
                    // Rating Range Controls
                    ratingRangeCard
                    
                    // Distance/Radius Control
                    radiusControlCard
                    
                    // Availability Control (Enhanced)
                    availabilityCard
                    
                    // Rating Info
                    ratingInfoCard

                    // Search Button
                    searchButton
                    
                    // Friend Invite CTA
                    friendInviteCTA

                    // Available Opponents or Fallback
                    if !isSearching {
                        availableOpponents
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("Find Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if showChallengeSent {
                    challengeSentOverlay
                }
            }
            .sheet(isPresented: $showFriendSearch) {
                friendSearchSheet
            }
            .sheet(isPresented: $showManualRangeEditor) {
                manualRangeEditorSheet
            }
            .sheet(isPresented: $showRadiusEditor) {
                radiusEditorSheet
            }
            .sheet(isPresented: $showTennisCourtPicker) {
                TennisCourtPickerView { court in
                    selectedTennisCourt = court
                }
                .environmentObject(sessionManager)
            }
            .alert("Trust Warning", isPresented: $showTrustWarning) {
                Button("Challenge Anyway", role: .destructive) {
                    if let opponent = selectedOpponentForWarning {
                        Task {
                            await challengeOpponent(opponent)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    selectedOpponentForWarning = nil
                }
            } message: {
                if let opponent = selectedOpponentForWarning {
                    Text(trustWarningMessage(for: opponent))
                }
            }
        }
        .task {
            await loadFriends()
        }
    }
    
    // MARK: - Match Type Selector
    
    private var matchTypeSelector: some View {
        HStack(spacing: Spacing.sm) {
            matchTypeButton(type: .ranked, label: "Ranked", icon: "trophy.fill")
            matchTypeButton(type: .unranked, label: "Unranked", icon: "gamecontroller.fill")
        }
    }

    private func matchTypeButton(type: MatchType, label: String, icon: String) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                matchType = type
            }
        }) {
            HStack {
                Image(systemName: icon)
                Text(label)
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(matchType == type ? .white : Color.appTextPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(matchType == type ? Color.appPrimary : Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        }
    }
    
    // MARK: - Rating Range Card (with manual control)
    
    private var ratingRangeCard: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(Color.appPrimary)
                    .font(.caption)
                Text("Skill Range")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
                
                if useManualRange {
                    Text("±\(manualRangeLower)-\(manualRangeUpper)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appPrimary)
                } else {
                    Text("±\(100 + eloRangeAdjustment)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appPrimary)
                }
            }
            
            // Preset buttons
            HStack(spacing: Spacing.sm) {
                rangeButton(label: "Narrow", adjustment: -50)
                rangeButton(label: "Standard", adjustment: 0)
                rangeButton(label: "Wide", adjustment: 50)
                rangeButton(label: "Very Wide", adjustment: 100)
            }
            
            // Manual range button
            Button(action: {
                showManualRangeEditor = true
            }) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                    Text("Custom Range")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(useManualRange ? .white : Color.appPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(useManualRange ? Color.appPrimary : Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private func rangeButton(label: String, adjustment: Int) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                eloRangeAdjustment = adjustment
                useManualRange = false
            }
        }) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle((eloRangeAdjustment == adjustment && !useManualRange) ? .white : Color.appTextPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background((eloRangeAdjustment == adjustment && !useManualRange) ? Color.appPrimary : Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        }
    }
    
    // MARK: - Radius Control Card
    
    private var radiusControlCard: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "location.circle.fill")
                    .foregroundStyle(Color.appPrimary)
                    .font(.caption)
                Text("Search Radius")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
                Text("\(Int(searchRadius)) mi")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appPrimary)
            }
            
            HStack(spacing: Spacing.sm) {
                radiusButton(label: "5 mi", radius: 5)
                radiusButton(label: "10 mi", radius: 10)
                radiusButton(label: "25 mi", radius: 25)
                radiusButton(label: "50 mi", radius: 50)
            }
            
            Button(action: {
                showRadiusEditor = true
            }) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                    Text("Custom Radius")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(Color.appPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private func radiusButton(label: String, radius: Double) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                searchRadius = radius
            }
        }) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(searchRadius == radius ? .white : Color.appTextPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(searchRadius == radius ? Color.appPrimary : Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        }
    }
    
    // MARK: - Availability Card (Enhanced)
    
    private var availabilityCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Circle()
                    .fill(availableNow ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Available Now")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    Text(availableNow ? "Visible to nearby players" : "Not visible to others")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                
                Spacer()
                
                if isUpdatingAvailability {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Toggle("", isOn: $availableNow)
                        .labelsHidden()
                        .onChange(of: availableNow) { _, newValue in
                            Task {
                                await updateAvailability(newValue)
                            }
                        }
                }
            }
            
            if availableNow {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.blue)
                    Text("Players within \(Int(searchRadius)) miles can see you're ready to play")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    // MARK: - Tennis Court Selector
    
    private var tennisCourtSelector: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "tennis.racket")
                    .foregroundStyle(Color.appPrimary)
                    .font(.caption)
                Text("Tennis Court Location")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
            }
            
            if let court = selectedTennisCourt {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(court.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.appTextPrimary)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Color.appPrimary)
                                Text("\(court.city), \(court.state)")
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextSecondary)
                                
                                if let distance = court.distanceMiles {
                                    Text("•")
                                        .foregroundStyle(Color.appTextSecondary.opacity(0.5))
                                    Text("\(String(format: "%.1f", distance)) mi")
                                        .font(.caption)
                                        .foregroundStyle(Color.appTextSecondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Button {
                            showTennisCourtPicker = true
                        } label: {
                            Text("Change")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.appPrimary)
                        }
                    }
                    
                    if court.requiresMembership || court.requiresReservation || court.hourlyRate != nil {
                        HStack(alignment: .top, spacing: Spacing.xs) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.orange)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                if court.requiresMembership {
                                    Text("• Membership required")
                                        .font(.caption2)
                                        .foregroundStyle(Color.appTextSecondary)
                                }
                                if court.requiresReservation {
                                    Text("• Reservation required")
                                        .font(.caption2)
                                        .foregroundStyle(Color.appTextSecondary)
                                }
                                if let rate = court.hourlyRate {
                                    Text("• \(court.currency ?? "USD") \(String(format: "%.2f", rate))/hour")
                                        .font(.caption2)
                                        .foregroundStyle(Color.appTextSecondary)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.sm)
                .background(Color.appSurface)
                .cornerRadius(CornerRadius.sm)
            } else {
                Button {
                    showTennisCourtPicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Select Tennis Court")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appPrimary)
                    .padding(.vertical, Spacing.sm)
                    .padding(.horizontal, Spacing.sm)
                    .background(Color.appSurface)
                    .cornerRadius(CornerRadius.sm)
                }
            }
            
            Text("Tennis matches must be played at real tennis courts. Court may require reservation, membership, or hourly rental.")
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, 4)
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    // MARK: - Rating Info Card
    
    private var ratingInfoCard: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.appPrimary)
                Text(matchType == .ranked ? "Ranked Match" : "Unranked Match")
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                if matchType == .ranked {
                    Text("• Your rating will change based on match result")
                    Text("• Matched with players near your skill level")
                    Text("• Builds your competitive ranking")
                } else {
                    Text("• Play for fun without rating changes")
                    Text("• Practice new strategies")
                    Text("• No impact on leaderboard position")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.appTextSecondary)
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    // MARK: - Search Button
    
    private var searchButton: some View {
        Button(action: {
            Task {
                await findOpponents()
            }
        }) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                }

                Text(isLoading ? "Searching..." : "Find Opponent")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)
            .background(Color.appPrimary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        }
        .disabled(isLoading)
    }
    
    // MARK: - Friend Invite CTA
    
    private var friendInviteCTA: some View {
        Button(action: {
            showFriendSearch = true
        }) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "person.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color.appPrimary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Challenge a Friend")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    Text("Invite someone you know to play")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            .padding(Spacing.md)
            .cardBackground()
        }
    }

    // MARK: - Available Opponents
    
    private var availableOpponents: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(Color.appPrimary)
                Text("Available Opponents")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
            }

            if let errorMessage = errorMessage {
                errorStateView(errorMessage)
            } else if opponents.isEmpty {
                if hasSearched {
                    emptyStateFallback
                } else {
                    Text("Tap 'Find Opponent' to search for players")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(Spacing.md)
                }
            } else {
                ForEach(Array(opponents.enumerated()), id: \.element.userId) { index, opponent in
                    opponentCard(opponent: opponent)
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(Double(index) * 0.05), value: opponents.count)
                }
            }
        }
    }
    
    private func errorStateView(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.orange)
            
            Text("Connection Issue")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
            
            Text(mapErrorToUserFriendly(message))
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                Task {
                    await findOpponents()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(Color.appPrimary)
                .cornerRadius(CornerRadius.md)
            }
        }
        .padding(Spacing.xl)
        .cardBackground()
    }
    
    // MARK: - Empty State Fallback
    
    private var emptyStateFallback: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.md) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.appTextSecondary.opacity(0.4))
                
                Text("No balanced match right now")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appTextPrimary)
                
                Text("Try these options to find a game")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Spacing.lg)
            
            VStack(spacing: Spacing.sm) {
                fallbackButton(
                    icon: "arrow.up.left.and.arrow.down.right",
                    title: "Widen Skill Range",
                    subtitle: "Search for more players"
                ) {
                    if useManualRange {
                        manualRangeLower = min(150, manualRangeLower + 50)
                        manualRangeUpper = min(150, manualRangeUpper + 50)
                    } else {
                        eloRangeAdjustment = min(200, eloRangeAdjustment + 50)
                    }
                    Task {
                        await findOpponents()
                    }
                }
                
                fallbackButton(
                    icon: "location.circle",
                    title: "Expand Search Radius",
                    subtitle: "Include players farther away"
                ) {
                    searchRadius = min(100, searchRadius * 2)
                    Task {
                        await findOpponents()
                    }
                }
                
                if matchType == .ranked {
                    fallbackButton(
                        icon: "gamecontroller.fill",
                        title: "Switch to Unranked",
                        subtitle: "More players available"
                    ) {
                        withAnimation {
                            matchType = .unranked
                        }
                        Task {
                            await findOpponents()
                        }
                    }
                }
                
                fallbackButton(
                    icon: "person.badge.plus",
                    title: "Invite a Friend",
                    subtitle: "Challenge someone you know"
                ) {
                    showFriendSearch = true
                }
                
                fallbackButton(
                    icon: "figure.run",
                    title: "Train While Waiting",
                    subtitle: "Practice drills and skills"
                ) {
                    dismiss()
                }
            }
        }
        .padding(Spacing.lg)
        .cardBackground()
    }
    
    private func fallbackButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.appPrimary)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            .padding(Spacing.md)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        }
    }
    
    // MARK: - Opponent Card
    
    private func opponentCard(opponent: OpponentResponse) -> some View {
        HStack(spacing: Spacing.md) {
            AvatarView(name: opponent.fullName, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Spacing.xs) {
                    Text(opponent.fullName)
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    if opponent.availableNow == true {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                }

                Text("@\(opponent.username)")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                
                HStack(spacing: 4) {
                    Text("\(opponent.wins)W - \(opponent.losses)L")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    Text("•")
                        .foregroundStyle(Color.appTextSecondary)
                    Text(opponent.rankTier)
                        .font(.caption)
                        .foregroundStyle(Color.appPrimary)
                    
                    if let lastActive = opponent.lastActive {
                        Text("•")
                            .foregroundStyle(Color.appTextSecondary)
                        Text(formatLastActive(lastActive))
                            .font(.caption)
                            .foregroundStyle(lastActiveColor(lastActive))
                    }
                }
                
                HStack(spacing: 4) {
                    if let trustTier = opponent.trustTier {
                        trustTierBadge(tier: trustTier)
                    }
                    
                    if let completionRate = opponent.completionRate, opponent.matchesCompleted ?? 0 > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: trustIcon(completionRate))
                                .font(.caption2)
                            Text(String(format: "%.0f%%", completionRate))
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(trustColor(completionRate))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(trustColor(completionRate).opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(opponent.rating)")
                    .font(.headline)
                    .foregroundStyle(Color.appPrimary)

                Text("Rating")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                
                if let quality = opponent.matchQuality {
                    matchQualityBadge(quality)
                }
            }

            Button(action: {
                if opponent.trustTier == "caution" || (opponent.disputeRate ?? 0) > 20 {
                    selectedOpponentForWarning = opponent
                    showTrustWarning = true
                } else {
                    Task {
                        await challengeOpponent(opponent)
                    }
                }
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.appPrimary)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    // MARK: - Sheets
    
    private var challengeSentOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: Spacing.lg) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.green)
                
                VStack(spacing: Spacing.xs) {
                    Text("Challenge Sent!")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    
                    Text("Waiting for \(challengedOpponentName) to accept")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(Spacing.xl)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
            .shadow(radius: 20)
            .padding(Spacing.xl)
        }
        .transition(.opacity.combined(with: .scale))
    }
    
    private var manualRangeEditorSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.md) {
                    Text("Custom Skill Range")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Set your preferred rating range")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                }
                .padding(.top, Spacing.lg)
                
                VStack(spacing: Spacing.lg) {
                    VStack(spacing: Spacing.sm) {
                        HStack {
                            Text("Lower Range")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Text("-\(manualRangeLower)")
                                .font(.headline)
                                .foregroundStyle(Color.appPrimary)
                        }
                        
                        Slider(value: Binding(
                            get: { Double(manualRangeLower) },
                            set: { manualRangeLower = Int($0) }
                        ), in: 0...200, step: 10)
                        .tint(Color.appPrimary)
                    }
                    
                    VStack(spacing: Spacing.sm) {
                        HStack {
                            Text("Upper Range")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Text("+\(manualRangeUpper)")
                                .font(.headline)
                                .foregroundStyle(Color.appPrimary)
                        }
                        
                        Slider(value: Binding(
                            get: { Double(manualRangeUpper) },
                            set: { manualRangeUpper = Int($0) }
                        ), in: 0...200, step: 10)
                        .tint(Color.appPrimary)
                    }
                }
                .padding(Spacing.lg)
                .cardBackground()
                
                Button(action: {
                    useManualRange = true
                    showManualRangeEditor = false
                }) {
                    Text("Apply Range")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.md)
                        .background(Color.appPrimary)
                        .cornerRadius(CornerRadius.md)
                }
                
                Spacer()
            }
            .padding(Spacing.lg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showManualRangeEditor = false
                    }
                }
            }
        }
    }
    
    private var radiusEditorSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.md) {
                    Text("Search Radius")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("How far are you willing to travel?")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                }
                .padding(.top, Spacing.lg)
                
                VStack(spacing: Spacing.sm) {
                    Text("\(Int(searchRadius)) miles")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(Color.appPrimary)
                    
                    Slider(value: $searchRadius, in: 1...100, step: 1)
                        .tint(Color.appPrimary)
                        .padding(.horizontal, Spacing.lg)
                }
                .padding(Spacing.lg)
                .cardBackground()
                
                Button(action: {
                    showRadiusEditor = false
                }) {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.md)
                        .background(Color.appPrimary)
                        .cornerRadius(CornerRadius.md)
                }
                
                Spacer()
            }
            .padding(Spacing.lg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showRadiusEditor = false
                    }
                }
            }
        }
    }
    
    private var friendSearchSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.appTextSecondary)
                    
                    TextField("Search friends...", text: $friendSearchQuery)
                        .textInputAutocapitalization(.never)
                }
                .padding(Spacing.md)
                .background(Color.appSurface)
                .cornerRadius(CornerRadius.md)
                .padding(Spacing.md)
                
                if isLoadingFriends {
                    ProgressView("Loading friends...")
                        .padding(Spacing.xl)
                } else if friends.isEmpty {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.appTextSecondary.opacity(0.4))
                        
                        Text("No Friends Yet")
                            .font(.headline)
                            .foregroundStyle(Color.appTextPrimary)
                        
                        Text("Add friends to challenge them directly")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Spacing.xl)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.sm) {
                            ForEach(filteredFriends) { friend in
                                friendRow(friend)
                            }
                        }
                        .padding(Spacing.md)
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Challenge Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showFriendSearch = false
                    }
                }
            }
        }
    }
    
    private var filteredFriends: [FriendshipResponse] {
        // For now, return all friends
        // Future: integrate with search when user details are available
        return friends
    }
    
    private func friendRow(_ friendship: FriendshipResponse) -> some View {
        Button(action: {
            Task {
                await challengeFriend(friendship)
            }
        }) {
            HStack(spacing: Spacing.md) {
                // Get friend's user ID (the ID that isn't current user)
                let friendUserId = friendship.userAId == sessionManager.currentUser?.id.uuidString ? friendship.userBId : friendship.userAId
                
                AvatarView(name: "Friend", size: 44)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Friend")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    Text("ID: \(friendUserId.prefix(8))...")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.appPrimary)
            }
            .padding(Spacing.md)
            .cardBackground()
        }
    }
    
    // MARK: - Helper Functions
    
    private func mapErrorToUserFriendly(_ error: String) -> String {
        let errorLower = error.lowercased()
        
        if errorLower.contains("internal server error") || errorLower.contains("500") {
            return "We're having trouble connecting to our servers right now. Please try again in a moment."
        } else if errorLower.contains("network") || errorLower.contains("connection") {
            return "Check your internet connection and try again."
        } else if errorLower.contains("timeout") {
            return "The request took too long. Please try again."
        } else if errorLower.contains("unauthorized") || errorLower.contains("401") {
            return "Your session expired. Please log in again."
        } else if errorLower.contains("not found") || errorLower.contains("404") {
            return "We couldn't find what you're looking for. Try adjusting your search."
        } else {
            return "Something went wrong. Please try again."
        }
    }
    
    private func findOpponents() async {
        isLoading = true
        errorMessage = nil
        hasSearched = true
        
        do {
            let matchTypeString = matchType == .ranked ? "ranked" : "unranked"
            
            // Build query parameters
            var queryParams: [String: Any] = [
                "sport": sport.apiValue,
                "match_type": matchTypeString,
                "radius_miles": searchRadius
            ]
            
            // Add range parameters
            if useManualRange {
                queryParams["elo_range_lower"] = manualRangeLower
                queryParams["elo_range_upper"] = manualRangeUpper
            } else {
                let rangeValue = 100 + eloRangeAdjustment
                queryParams["elo_range"] = rangeValue
            }
            
            opponents = try await APIClient.shared.findOpponents(
                sport: sport.apiValue,
                matchType: matchTypeString
            )
        } catch {
            errorMessage = "We couldn't find opponents right now. Check your connection and try again."
            opponents = []
        }
        
        isLoading = false
    }
    
    private func updateAvailability(_ available: Bool) async {
        isUpdatingAvailability = true
        
        do {
            try await APIClient.shared.updateAvailability(
                sport: sport.apiValue,
                available: available
            )
        } catch {
            // Silently fail and revert
            await MainActor.run {
                availableNow = !available
            }
        }
        
        isUpdatingAvailability = false
    }
    
    private func loadFriends() async {
        isLoadingFriends = true
        
        do {
            friends = try await APIClient.shared.getFriends()
        } catch {
            friends = []
        }
        
        isLoadingFriends = false
    }
    
    private func challengeFriend(_ friendship: FriendshipResponse) async {
        // Determine which user ID is the friend (not current user)
        guard let currentUserId = sessionManager.currentUser?.id.uuidString else { return }
        let friendUserId = friendship.userAId == currentUserId ? friendship.userBId : friendship.userAId
        
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        
        do {
            let matchTypeString = matchType == .ranked ? "ranked" : "unranked"
            let request = CreateChallengeRequest(
                opponentId: friendUserId,
                sport: sport.apiValue,
                matchType: matchTypeString,
                friendsOnly: true
            )
            _ = try await APIClient.shared.createChallenge(request: request)
            
            generator.notificationOccurred(.success)
            
            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    challengedOpponentName = "your friend"
                    showFriendSearch = false
                    showChallengeSent = true
                }
            }
            
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        } catch {
            generator.notificationOccurred(.error)
            errorMessage = "Failed to challenge friend"
        }
    }
    
    private func challengeOpponent(_ opponent: OpponentResponse) async {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        
        do {
            let matchTypeString = matchType == .ranked ? "ranked" : "unranked"
            let request = CreateChallengeRequest(
                opponentId: opponent.userId,
                sport: sport.apiValue,
                matchType: matchTypeString,
                friendsOnly: false
            )
            _ = try await APIClient.shared.createChallenge(request: request)
            
            generator.notificationOccurred(.success)
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                challengedOpponentName = opponent.fullName
                showChallengeSent = true
            }
            
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        } catch {
            generator.notificationOccurred(.error)
            errorMessage = "We couldn't send your challenge. Please try again."
        }
    }
    
    private func matchQualityBadge(_ quality: String) -> some View {
        let (color, icon) = matchQualityStyle(quality)
        
        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
            Text(quality)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
    
    private func matchQualityStyle(_ quality: String) -> (Color, String) {
        switch quality.lowercased() {
        case "balanced":
            return (Color.green, "equal.circle.fill")
        case "competitive":
            return (Color.orange, "chart.bar.fill")
        case "stretch":
            return (Color.purple, "arrow.up.right.circle.fill")
        default:
            return (Color.gray, "circle.fill")
        }
    }
    
    private func formatLastActive(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: timestamp) else {
            return "Recently"
        }
        
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            return "1w+ ago"
        }
    }
    
    private func lastActiveColor(_ timestamp: String) -> Color {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: timestamp) else {
            return Color.gray
        }
        
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 3600 {
            return Color.green
        } else if interval < 86400 {
            return Color.yellow
        } else {
            return Color.gray
        }
    }
    
    private func trustIcon(_ completionRate: Double) -> String {
        if completionRate >= 90 {
            return "checkmark.seal.fill"
        } else if completionRate >= 70 {
            return "checkmark.circle.fill"
        } else {
            return "exclamationmark.circle.fill"
        }
    }
    
    private func trustColor(_ completionRate: Double) -> Color {
        if completionRate >= 90 {
            return Color.green
        } else if completionRate >= 70 {
            return Color.orange
        } else {
            return Color.red
        }
    }
    
    private func trustTierBadge(tier: String) -> some View {
        let (icon, label, color) = trustTierInfo(tier)
        
        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
    
    private func trustTierInfo(_ tier: String) -> (String, String, Color) {
        switch tier.lowercased() {
        case "trusted":
            return ("checkmark.seal.fill", "Verified", Color.green)
        case "standard":
            return ("", "", Color.clear)
        case "caution":
            return ("exclamationmark.triangle.fill", "Caution", Color.orange)
        case "restricted":
            return ("xmark.shield.fill", "Restricted", Color.red)
        default:
            return ("", "", Color.clear)
        }
    }
    
    private func trustWarningMessage(for opponent: OpponentResponse) -> String {
        if let disputeRate = opponent.disputeRate, disputeRate > 30 {
            return "\(opponent.fullName) has a high dispute rate (\(String(format: "%.0f%%", disputeRate))). Consider challenging someone else or be prepared to submit evidence if needed."
        } else if let disputeRate = opponent.disputeRate, disputeRate > 20 {
            return "\(opponent.fullName) has an elevated dispute rate (\(String(format: "%.0f%%", disputeRate))). Match results may require additional verification."
        } else if opponent.trustTier == "caution" {
            return "\(opponent.fullName) is flagged for elevated match requirements. You may need to submit evidence for this match."
        } else {
            return "This player has elevated match requirements. Proceed with caution."
        }
    }
}

// Local enum for UI state
enum MatchType {
    case ranked
    case unranked
}

#Preview {
    MatchmakingView(sport: .basketball)
        .environmentObject(SessionManager.shared)
}
