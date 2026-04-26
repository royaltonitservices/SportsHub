
//
//  HomeView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

// Sport enum is defined in Sport.swift

// MARK: - Activity Load State

private enum ActivityLoadState {
    case idle
    case loading
    case loaded([ActivityItem])
    case failed
}

struct HomeView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var selectedTab: Int
    @State private var selectedSport: Sport = .basketball
    @State private var showNotifications = false
    @State private var showMessages = false
    @State private var showSearchSheet = false
    @State private var searchText = ""

    // Activity feed state
    @State private var activityState: ActivityLoadState = .idle
    @State private var allActivityItems: [ActivityItem] = []

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Bar with Logo and Action Icons
                topBar

                // Search Bar
                searchBar

                // Greeting Section
                greetingSection

                // Sport Selector
                sportSelector

                // Highlights Carousel
                HighlightsCarouselView()
                    .frame(height: 120)
                    .padding(.vertical, Spacing.sm)

                // Main Content
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Activity Feed Placeholder
                        feedSection
                    }
                    .padding(Spacing.md)
                }
            }
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView()
        }
        .sheet(isPresented: $showSearchSheet) {
            AddFriendView(onRequestSent: {})
        }
        .sheet(isPresented: $showMessages) {
            MessagesListView()
        }
        .task {
            await loadActivityFeed()
        }
        .onChange(of: selectedSport) {
            // Re-filter cached data; no extra network call needed
            applyActivityFilter()
            // Keep AI Coach sport context in sync with home sport selector
            AICoachManager.shared.currentSport = selectedSport.rawValue
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.appTextSecondary)
                
                TextField(SearchScope.friendSearch.placeholder, text: $searchText)
                    .foregroundStyle(Color.appTextPrimary)
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.appSurface)
            .cornerRadius(12)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center) {
            // App Logo
            HStack(spacing: Spacing.xs) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(Color.appPrimary)

                Text("SportsHub")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)
            }

            Spacer()

            // Action Icons
            HStack(spacing: Spacing.md) {
                // Notifications Button
                Button(action: {
                    showNotifications = true
                }) {
                    Image(systemName: "bell.fill")
                        .font(.title3)
                        .foregroundStyle(Color.appTextPrimary)
                        .frame(width: 44, height: 44)
                }

                // Messages Button
                Button(action: {
                    showMessages = true
                }) {
                    Image(systemName: "message.fill")
                        .font(.title3)
                        .foregroundStyle(Color.appTextPrimary)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.appBackground)
    }

    // MARK: - Greeting Section

    private var greetingSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeBasedGreeting + ", \(athleteName)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)

                Text(personalizedSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
    
    private var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Welcome back"
        }
    }
    
    private var personalizedSubtitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5 && hour < 11 {
            return "Ready to train?"
        } else if hour >= 11 && hour < 14 {
            return "Time to compete?"
        } else if hour >= 14 && hour < 18 {
            return "Find a match?"
        } else if hour >= 18 && hour < 22 {
            return "How was your day?"
        } else {
            return "Ready for tomorrow?"
        }
    }

    private var athleteName: String {
        sessionManager.currentUser?.displayName ?? "Athlete"
    }

    // MARK: - Sport Selector

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
            .padding(.horizontal, Spacing.md)
        }
        .padding(.vertical, Spacing.sm)
        .background(Color.appBackground)
    }

    // MARK: - Feed Section

    private var feedSection: some View {
        VStack(spacing: Spacing.md) {
            // Quick Actions (static sport-aware shortcuts)
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.title3)
                        .foregroundStyle(Color.appPrimary)
                    Text("Quick Actions")
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    Spacer()
                }
                
                VStack(spacing: Spacing.sm) {
                    RecommendedActionCard(
                        icon: "figure.run",
                        title: "Quick \(selectedSport.rawValue) Session",
                        subtitle: "15 min skill drill",
                        color: .blue,
                        action: { selectedTab = 2 }
                    )
                    
                    RecommendedActionCard(
                        icon: "person.2.fill",
                        title: "Find Opponents",
                        subtitle: "Play ranked match",
                        color: .green,
                        action: { selectedTab = 1 }
                    )
                    
                    RecommendedActionCard(
                        icon: "brain.head.profile",
                        title: "Ask AI Coach",
                        subtitle: "Chat with your sport coach",
                        color: .purple,
                        action: {
                            withAnimation { AICoachManager.shared.isExpanded = true }
                        }
                    )
                }
            }
            .cardBackground()

            // Activity section — driven by real backend data
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Image(systemName: selectedSport.icon)
                        .font(.title3)
                        .foregroundStyle(Color.appPrimary)
                    Text("\(selectedSport.rawValue) Activity")
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    Spacer()
                }

                activityContent
            }
            .cardBackground()
        }
    }

    // MARK: - Activity Content (state-driven)

    @ViewBuilder
    private var activityContent: some View {
        switch activityState {
        case .idle:
            EmptyView()

        case .loading:
            HStack {
                Spacer()
                ProgressView()
                    .tint(Color.appPrimary)
                Spacer()
            }
            .padding(.vertical, Spacing.lg)

        case .loaded(let items) where items.isEmpty:
            VStack(spacing: Spacing.sm) {
                Image(systemName: "sportscourt")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.appTextSecondary.opacity(0.35))

                Text("No \(selectedSport.rawValue) activity yet")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appTextSecondary)

                Text("Play your first match to see results here")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)

        case .loaded(let items):
            VStack(spacing: 0) {
                ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { index, item in
                    ActivityRow(item: item)
                    if index < min(items.count, 5) - 1 {
                        Divider()
                            .background(Color.appTextSecondary.opacity(0.1))
                    }
                }
            }

        case .failed:
            VStack(spacing: Spacing.sm) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.appTextSecondary.opacity(0.45))

                Text("Activity unavailable")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appTextSecondary)

                Button("Try Again") {
                    Task { await loadActivityFeed() }
                }
                .font(.caption)
                .foregroundStyle(Color.appPrimary.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
        }
    }

    // MARK: - Activity Feed Load

    private func loadActivityFeed() async {
        guard sessionManager.backendAvailable else {
            // Banner already communicates server is offline — stay in idle (empty) to avoid alarming error state
            transition(to: .loaded([]), cameFromCache: true)
            return
        }
        transition(to: .loading)
        do {
            let items = try await APIClient.shared.getActivityFeed(limit: 50)
            allActivityItems = items
            applyActivityFilter()
        } catch {
            transition(to: .failed)
        }
    }

    private func applyActivityFilter() {
        let filtered = allActivityItems.filter {
            $0.sport.lowercased() == selectedSport.rawValue.lowercased()
        }
        transition(to: .loaded(filtered))
    }

    /// Sets `activityState` and validates the transition in DEBUG builds.
    ///
    /// Pass `cameFromCache: true` when seeding state directly from a local
    /// cache so the `.idle → .loaded` shortcut is treated as intentional.
    private func transition(to next: ActivityLoadState, cameFromCache: Bool = false) {
        let previous = activityState
        #if DEBUG
        if case .idle = previous, case .loaded = next, !cameFromCache {
            print(
                "⚠️ [CoherenceValidator] HomeView: skipped .loading state — " +
                "transitioned .idle → .loaded without an intermediate .loading. " +
                "If intentional (e.g. cache seed), call transition(to:cameFromCache: true)."
            )
        }
        #endif
        activityState = next
    }

    // MARK: - Search Action
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        showSearchSheet = true
    }
}

// MARK: - Activity Row Component

struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background(iconColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appTextPrimary)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(timeAgo)
                .font(.caption2)
                .foregroundStyle(Color.appTextSecondary.opacity(0.7))
        }
        .padding(.vertical, Spacing.sm)
    }

    private var icon: String {
        switch item.type {
        case "match_completed", "match_result":
            return item.winnerUsername == item.username ? "trophy.fill" : "gamecontroller.fill"
        case "challenge_received":  return "flag.fill"
        case "challenge_accepted":  return "checkmark.circle.fill"
        case "challenge_declined":  return "xmark.circle.fill"
        case "friend_request", "friend_accepted": return "person.fill"
        case "badge_earned":        return "rosette"
        default:                    return "bell.fill"
        }
    }

    private var iconColor: Color {
        switch item.type {
        case "match_completed", "match_result":
            return item.winnerUsername == item.username ? Color.appSuccess : Color.appTextSecondary
        case "challenge_received", "challenge_accepted": return Color.appPrimary
        case "challenge_declined":  return Color.appError
        case "friend_request", "friend_accepted": return .blue
        case "badge_earned":        return .yellow
        default:                    return Color.appPrimary
        }
    }

    private var title: String {
        let sport = item.sport.capitalized
        switch item.type {
        case "match_completed", "match_result":
            return item.winnerUsername == item.username
                ? "Won \(sport) Match"
                : "\(sport) Match Result"
        case "challenge_received":  return "New \(sport) Challenge"
        case "challenge_accepted":  return "\(sport) Challenge Accepted"
        case "challenge_declined":  return "\(sport) Challenge Declined"
        case "friend_request":      return "Friend Request"
        case "friend_accepted":     return "New Friend"
        case "badge_earned":        return "\(sport) Badge Earned"
        default:                    return "\(sport) Activity"
        }
    }

    private var detail: String {
        let opponent = item.opponentUsername.map { "@\($0)" } ?? "an opponent"
        switch item.type {
        case "match_completed", "match_result":
            var text = "vs \(opponent)"
            if let us = item.userScore, let them = item.opponentScore {
                text += " · \(us)–\(them)"
            }
            if let delta = item.ratingChange, delta != 0 {
                text += delta > 0 ? " · +\(delta) pts" : " · \(delta) pts"
            }
            return text
        case "challenge_received":  return "\(opponent) sent you a challenge"
        case "challenge_accepted":  return "\(opponent) accepted your challenge"
        case "challenge_declined":  return "\(opponent) declined your challenge"
        case "friend_request":      return "@\(item.username) sent you a friend request"
        case "friend_accepted":     return "@\(item.username) is now your friend"
        case "badge_earned":        return "You earned a new \(item.sport.capitalized) badge"
        default:                    return "@\(item.username) had activity"
        }
    }

    private var timeAgo: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: item.createdAt)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: item.createdAt)
        }
        guard let date else { return "Recently" }
        let seconds = Int(-date.timeIntervalSinceNow)
        switch seconds {
        case ..<60:     return "Just now"
        case 60..<3600: return "\(seconds / 60)m ago"
        case 3600..<86400: return "\(seconds / 3600)h ago"
        case 86400..<604800: return "\(seconds / 86400)d ago"
        default:        return "\(seconds / 604800)w ago"
        }
    }
}

// MARK: - Recommended Action Card Component

struct RecommendedActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.15))
                    .cornerRadius(CornerRadius.md)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
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
            .cornerRadius(CornerRadius.md)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sport Pill Button Component

struct SportPillButton: View {
    let sport: Sport
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: sport.icon)
                    .font(.callout)

                Text(sport.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? Color.appPrimary : Color.appSurface)
            )
            .foregroundStyle(isSelected ? .white : Color.appTextPrimary)
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : Color.appTextSecondary.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
    }
}

#Preview {
    HomeView(selectedTab: .constant(0))
        .environmentObject(SessionManager.shared)
}
