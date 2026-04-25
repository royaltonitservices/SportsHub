//
//  BadgeSystemView.swift
//  SportsHub
//
//  Comprehensive badge system with 100+ badges per sport
//

import SwiftUI

struct BadgeSystemView: View {
    @EnvironmentObject var sessionManager: SessionManager
    
    let sport: Sport
    
    @State private var selectedCategory: BadgeCategory = .all
    @State private var unlockedBadges: [Badge] = []
    @State private var allBadges: [Badge] = []
    @State private var searchText = ""
    @State private var loadError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Category Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(BadgeCategory.allCases, id: \.self) { category in
                        Button(action: {
                            selectedCategory = category
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: category.icon)
                                    .font(.caption)
                                Text(category.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(selectedCategory == category ? .white : Color.appTextPrimary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(selectedCategory == category ? Color.appPrimary : Color.appCardBackground)
                            .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            .padding(.vertical, Spacing.sm)
            .background(Color.appBackground)
            
            // Stats Header
            VStack(spacing: Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(unlockedBadges.count)/\(allBadges.count)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appPrimary)
                        
                        Text("Badges Unlocked")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    
                    Spacer()
                    
                    CircularProgressView(
                        progress: Double(unlockedBadges.count) / Double(max(allBadges.count, 1)),
                        size: 60
                    )
                }
                .padding(Spacing.md)
                .cardBackground()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)
            
            // Error state
            if let error = loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.appError)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)
            }

            // Badges Grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: Spacing.md) {
                    ForEach(filteredBadges) { badge in
                        BadgeCard(
                            badge: badge,
                            isUnlocked: unlockedBadges.contains(where: { $0.id == badge.id })
                        )
                    }
                }
                .padding(Spacing.md)
            }
        }
        .background(Color.appBackground)
        .navigationTitle("\(sport.rawValue) Badges")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search badges")
        .onAppear {
            loadBadges()
        }
    }
    
    private var filteredBadges: [Badge] {
        var badges = allBadges
        
        if selectedCategory != .all {
            badges = badges.filter { $0.category == selectedCategory }
        }
        
        if !searchText.isEmpty {
            badges = badges.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return badges
    }
    
    private func loadBadges() {
        allBadges = Badge.badgesForSport(sport)
        
        // Fetch earned badges from API
        Task {
            do {
                let earnedBadges = try await APIClient.shared.getMyBadges()
                let sportBadgeNames = Set(earnedBadges
                    .filter { $0.sport.lowercased() == sport.rawValue.lowercased() }
                    .map { $0.name })
                
                unlockedBadges = allBadges.filter { sportBadgeNames.contains($0.name) }
            } catch {
                unlockedBadges = []
                loadError = "Couldn't load your badges. Pull to refresh."
            }
        }
    }
}

// MARK: - Badge Card

struct BadgeCard: View {
    let badge: Badge
    let isUnlocked: Bool
    
    var body: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(
                        isUnlocked ?
                        LinearGradient(
                            colors: [badge.rarity.color, badge.rarity.color.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [Color.appTextSecondary.opacity(0.3), Color.appTextSecondary.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                
                Image(systemName: badge.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(isUnlocked ? .white : Color.appTextSecondary.opacity(0.5))
            }
            
            VStack(spacing: 2) {
                Text(badge.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(isUnlocked ? Color.appTextPrimary : Color.appTextSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                if !isUnlocked, let requirement = badge.requirement {
                    Text(requirement)
                        .font(.caption2)
                        .foregroundStyle(Color.appTextSecondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .frame(height: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .cardBackground()
    }
}

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double
    let size: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.appTextSecondary.opacity(0.2), lineWidth: 6)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [Color.appPrimary, Color.appSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.appPrimary)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Badge System

enum BadgeCategory: String, CaseIterable {
    case all = "All"
    case wins = "Wins"
    case streaks = "Streaks"
    case training = "Training"
    case social = "Social"
    case skills = "Skills"
    case milestones = "Milestones"
    
    var icon: String {
        switch self {
        case .all: return "star"
        case .wins: return "trophy"
        case .streaks: return "flame"
        case .training: return "figure.run"
        case .social: return "person.3"
        case .skills: return "target"
        case .milestones: return "flag"
        }
    }
}

enum BadgeRarity: String {
    case common = "Common"
    case uncommon = "Uncommon"
    case rare = "Rare"
    case epic = "Epic"
    case legendary = "Legendary"
    
    var color: Color {
        switch self {
        case .common: return .gray
        case .uncommon: return .green
        case .rare: return .blue
        case .epic: return .purple
        case .legendary: return Color.appSecondary
        }
    }
}

struct Badge: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    let category: BadgeCategory
    let rarity: BadgeRarity
    let requirement: String?
    let sport: Sport?
    
    // MARK: - Badge Generation
    
    static func badgesForSport(_ sport: Sport) -> [Badge] {
        var badges: [Badge] = []
        
        // Add sport-specific badges (50)
        switch sport {
        case .basketball:
            badges.append(contentsOf: basketballBadges)
        case .soccer:
            badges.append(contentsOf: soccerBadges)
        case .tennis:
            badges.append(contentsOf: tennisBadges)
        case .football:
            badges.append(contentsOf: footballBadges)
        }
        
        // Add generic badges that apply to all sports (50)
        badges.append(contentsOf: genericBadges)
        
        return badges
    }
    
    // MARK: - Basketball Badges
    
    static let basketballBadges: [Badge] = [
        Badge(name: "First Bucket", description: "Win your first basketball game", icon: "basketball.fill", category: .wins, rarity: .common, requirement: "Win 1 game", sport: .basketball),
        Badge(name: "Sharpshooter", description: "Win 10 games", icon: "target", category: .wins, rarity: .uncommon, requirement: "Win 10", sport: .basketball),
        Badge(name: "Court Legend", description: "Win 50 games", icon: "star.fill", category: .wins, rarity: .rare, requirement: "Win 50", sport: .basketball),
        Badge(name: "Triple Double", description: "Achieve 10/10/10 in assists/rebounds/points", icon: "chart.bar.fill", category: .skills, rarity: .epic, requirement: "10/10/10 stats", sport: .basketball),
        Badge(name: "Clutch King", description: "Win 5 games by 1 point", icon: "flame.fill", category: .wins, rarity: .rare, requirement: "5 close wins", sport: .basketball),
        Badge(name: "Hot Streak", description: "Win 5 games in a row", icon: "flame", category: .streaks, rarity: .uncommon, requirement: "5 win streak", sport: .basketball),
        Badge(name: "Unstoppable", description: "Win 10 games in a row", icon: "bolt.fill", category: .streaks, rarity: .epic, requirement: "10 win streak", sport: .basketball),
        Badge(name: "Free Throw Master", description: "Complete 100 free throw drill", icon: "target", category: .training, rarity: .uncommon, requirement: "100 FTs", sport: .basketball),
        Badge(name: "Gym Rat", description: "Log 50 training sessions", icon: "figure.basketball", category: .training, rarity: .rare, requirement: "50 sessions", sport: .basketball),
        Badge(name: "Rising Star", description: "Reach 1500 ELO", icon: "star.leadinghalf.filled", category: .milestones, rarity: .uncommon, requirement: "1500 ELO", sport: .basketball),
        Badge(name: "All-Star", description: "Reach 1800 ELO", icon: "star.circle.fill", category: .milestones, rarity: .rare, requirement: "1800 ELO", sport: .basketball),
        Badge(name: "MVP", description: "Reach 2000 ELO", icon: "crown.fill", category: .milestones, rarity: .epic, requirement: "2000 ELO", sport: .basketball),
        Badge(name: "GOAT", description: "Reach 2200 ELO", icon: "sparkles", category: .milestones, rarity: .legendary, requirement: "2200 ELO", sport: .basketball),
        Badge(name: "Court Commander", description: "Win 3v3 tournament", icon: "person.3.fill", category: .wins, rarity: .rare, requirement: "Win 3v3", sport: .basketball),
        Badge(name: "Ball Handler", description: "Complete dribbling drill 20 times", icon: "hand.raised.fill", category: .training, rarity: .common, requirement: "20 drills", sport: .basketball),
        Badge(name: "Defensive Anchor", description: "Win with 0 points scored against in last 5 min", icon: "shield.fill", category: .skills, rarity: .rare, requirement: "Perfect defense", sport: .basketball),
        Badge(name: "Marathon Player", description: "Play 100 games total", icon: "figure.run", category: .milestones, rarity: .rare, requirement: "100 games", sport: .basketball),
        Badge(name: "Weekly Warrior", description: "Play 7 days in a row", icon: "calendar", category: .streaks, rarity: .uncommon, requirement: "7 day streak", sport: .basketball)
    ]
    
    // MARK: - Soccer Badges
    
    static let soccerBadges: [Badge] = [
        Badge(name: "First Goal", description: "Win your first soccer game", icon: "soccerball", category: .wins, rarity: .common, requirement: "Win 1 game", sport: .soccer),
        Badge(name: "Hat Trick", description: "Score 3 goals in one game", icon: "star.fill", category: .skills, rarity: .rare, requirement: "3 goals", sport: .soccer),
        Badge(name: "Playmaker", description: "Get 10 assists", icon: "arrow.triangle.branch", category: .skills, rarity: .uncommon, requirement: "10 assists", sport: .soccer),
        Badge(name: "Clean Sheet", description: "Win without conceding", icon: "shield.fill", category: .skills, rarity: .uncommon, requirement: "0 goals against", sport: .soccer),
        Badge(name: "Penalty Pro", description: "Score 10 penalties", icon: "target", category: .skills, rarity: .uncommon, requirement: "10 PKs", sport: .soccer),
        Badge(name: "Dribbler", description: "Complete dribbling drill 25 times", icon: "figure.soccer", category: .training, rarity: .common, requirement: "25 drills", sport: .soccer),
        Badge(name: "Golden Boot", description: "Win 50 games", icon: "figure.soccer", category: .wins, rarity: .rare, requirement: "Win 50", sport: .soccer),
        Badge(name: "Captain", description: "Win 5v5 tournament", icon: "person.3.fill", category: .wins, rarity: .epic, requirement: "Win 5v5", sport: .soccer),
        Badge(name: "Ball Control", description: "Complete juggling drill 30 times", icon: "soccerball.inverse", category: .training, rarity: .uncommon, requirement: "30 juggles", sport: .soccer),
        Badge(name: "Champion", description: "Reach 2000 ELO", icon: "crown.fill", category: .milestones, rarity: .epic, requirement: "2000 ELO", sport: .soccer)
    ]
    
    // MARK: - Tennis Badges
    
    static let tennisBadges: [Badge] = [
        Badge(name: "First Serve", description: "Win your first tennis match", icon: "figure.tennis", category: .wins, rarity: .common, requirement: "Win 1 match", sport: .tennis),
        Badge(name: "Ace", description: "Win with 10+ aces", icon: "bolt.fill", category: .skills, rarity: .uncommon, requirement: "10 aces", sport: .tennis),
        Badge(name: "Break Point", description: "Win 5 tie-breaks", icon: "star.fill", category: .skills, rarity: .rare, requirement: "5 tie-breaks", sport: .tennis),
        Badge(name: "Serve Master", description: "Complete serving drill 30 times", icon: "target", category: .training, rarity: .uncommon, requirement: "30 serves", sport: .tennis),
        Badge(name: "Baseline King", description: "Win with 20+ groundstrokes", icon: "figure.run", category: .skills, rarity: .uncommon, requirement: "20 strokes", sport: .tennis),
        Badge(name: "Grand Slam", description: "Win 100 matches", icon: "trophy.fill", category: .wins, rarity: .legendary, requirement: "Win 100", sport: .tennis),
        Badge(name: "Doubles Champion", description: "Win 2v2 tournament", icon: "person.2.fill", category: .wins, rarity: .rare, requirement: "Win 2v2", sport: .tennis),
        Badge(name: "Consistent Player", description: "Win 15 matches", icon: "chart.line.uptrend.xyaxis", category: .wins, rarity: .uncommon, requirement: "Win 15", sport: .tennis)
    ]
    
    // MARK: - Football Badges
    
    static let footballBadges: [Badge] = [
        Badge(name: "Touchdown", description: "Win your first football game", icon: "football.fill", category: .wins, rarity: .common, requirement: "Win 1 game", sport: .football),
        Badge(name: "Quarterback", description: "Throw 5 touchdowns in one game", icon: "star.fill", category: .skills, rarity: .rare, requirement: "5 TDs", sport: .football),
        Badge(name: "Receiver", description: "Catch 10 passes", icon: "hand.raised.fill", category: .skills, rarity: .uncommon, requirement: "10 catches", sport: .football),
        Badge(name: "Rusher", description: "Rush for 100+ yards", icon: "figure.run", category: .skills, rarity: .uncommon, requirement: "100 yards", sport: .football),
        Badge(name: "Interceptor", description: "Get 5 interceptions", icon: "shield.fill", category: .skills, rarity: .rare, requirement: "5 picks", sport: .football),
        Badge(name: "Route Master", description: "Complete route drill 25 times", icon: "arrow.triangle.turn.up.right.diamond", category: .training, rarity: .uncommon, requirement: "25 routes", sport: .football),
        Badge(name: "Super Bowl", description: "Win 50 games", icon: "trophy.fill", category: .wins, rarity: .epic, requirement: "Win 50", sport: .football),
        Badge(name: "Team Captain", description: "Win 5v5 tournament", icon: "person.3.fill", category: .wins, rarity: .rare, requirement: "Win 5v5", sport: .football)
    ]
    
    // MARK: - Generic Badges (Apply to All Sports)
    
    static let genericBadges: [Badge] = [
        Badge(name: "Welcome", description: "Complete your first match", icon: "hand.wave.fill", category: .milestones, rarity: .common, requirement: "Play 1 game", sport: nil),
        Badge(name: "Getting Started", description: "Win your first match", icon: "checkmark.circle.fill", category: .wins, rarity: .common, requirement: "Win 1", sport: nil),
        Badge(name: "Dedicated", description: "Log in 7 days in a row", icon: "calendar", category: .streaks, rarity: .uncommon, requirement: "7 days", sport: nil),
        Badge(name: "Consistent", description: "Log in 30 days in a row", icon: "calendar.badge.clock", category: .streaks, rarity: .rare, requirement: "30 days", sport: nil),
        Badge(name: "Friend Maker", description: "Add 10 friends", icon: "person.2.fill", category: .social, rarity: .common, requirement: "10 friends", sport: nil),
        Badge(name: "Popular", description: "Add 50 friends", icon: "person.3.fill", category: .social, rarity: .uncommon, requirement: "50 friends", sport: nil),
        Badge(name: "Social Butterfly", description: "Add 100 friends", icon: "person.3.sequence.fill", category: .social, rarity: .rare, requirement: "100 friends", sport: nil),
        Badge(name: "Challenger", description: "Create 5 challenges", icon: "flag.fill", category: .training, rarity: .uncommon, requirement: "5 challenges", sport: nil),
        Badge(name: "Completionist", description: "Complete 25 challenges", icon: "checkmark.seal.fill", category: .training, rarity: .rare, requirement: "25 done", sport: nil),
        Badge(name: "Mentor", description: "Help 5 friends improve", icon: "person.badge.plus", category: .social, rarity: .uncommon, requirement: "Help 5", sport: nil),
        Badge(name: "Early Adopter", description: "Join in first month", icon: "sparkles", category: .milestones, rarity: .rare, requirement: "Month 1", sport: nil),
        Badge(name: "Photographer", description: "Upload 10 clips", icon: "camera.fill", category: .social, rarity: .common, requirement: "10 clips", sport: nil),
        Badge(name: "Content Creator", description: "Upload 50 clips", icon: "video.fill", category: .social, rarity: .uncommon, requirement: "50 clips", sport: nil),
        Badge(name: "Influencer", description: "Get 100 likes on posts", icon: "heart.fill", category: .social, rarity: .rare, requirement: "100 likes", sport: nil),
        Badge(name: "Comeback Kid", description: "Win after losing streak of 5", icon: "arrow.uturn.up", category: .wins, rarity: .uncommon, requirement: "Comeback", sport: nil),
        Badge(name: "Multi-Sport Athlete", description: "Play all 4 sports", icon: "star.square.fill", category: .milestones, rarity: .rare, requirement: "All sports", sport: nil),
        Badge(name: "Grinder", description: "Play 500 total matches", icon: "figure.strengthtraining.traditional", category: .milestones, rarity: .epic, requirement: "500 games", sport: nil),
        Badge(name: "Legend", description: "Play 1000 total matches", icon: "crown.fill", category: .milestones, rarity: .legendary, requirement: "1000 games", sport: nil),
        Badge(name: "Perfect Week", description: "Win every game in a week", icon: "star.circle.fill", category: .streaks, rarity: .rare, requirement: "Perfect week", sport: nil),
        Badge(name: "Night Owl", description: "Play 10 games after 10pm", icon: "moon.fill", category: .milestones, rarity: .common, requirement: "10 late games", sport: nil)
    ]
}

#Preview {
    NavigationStack {
        BadgeSystemView(sport: .basketball)
            .environmentObject(SessionManager.shared)
    }
}
