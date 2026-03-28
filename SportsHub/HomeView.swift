//
//  HomeView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

enum Sport: String, CaseIterable {
    case basketball = "Basketball"
    case football = "Football"
    case soccer = "Soccer"
    case tennis = "Tennis"

    var icon: String {
        switch self {
        case .basketball: return "basketball.fill"
        case .football: return "football.fill"
        case .soccer: return "soccerball"
        case .tennis: return "tennisball.fill"
        }
    }
    
    // Lowercase value for API calls (matches backend enum)
    var apiValue: String {
        return self.rawValue.lowercased()
    }
}

struct HomeView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedSport: Sport = .basketball
    @State private var showNotifications = false
    @State private var showMessages = false
    @State private var searchText = ""

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
        .sheet(isPresented: $showMessages) {
            MessagesListView()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.appTextSecondary)
                
                TextField("Search athletes, matches, content...", text: $searchText)
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
            // Recommended Actions
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(Color.appPrimary)
                    Text("Recommended for You")
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    Spacer()
                }
                
                // Quick action cards
                VStack(spacing: Spacing.sm) {
                    RecommendedActionCard(
                        icon: "figure.run",
                        title: "Quick \(selectedSport.rawValue) Session",
                        subtitle: "15 min skill drill",
                        color: .blue,
                        action: { /* Navigate to train */ }
                    )
                    
                    RecommendedActionCard(
                        icon: "person.2.fill",
                        title: "Find Opponents",
                        subtitle: "Play ranked match",
                        color: .green,
                        action: { /* Navigate to play */ }
                    )
                    
                    RecommendedActionCard(
                        icon: "brain.head.profile",
                        title: "Ask AI Coach",
                        subtitle: "Get personalized tips",
                        color: .purple,
                        action: { /* Open AI coach */ }
                    )
                }
            }
            .cardBackground()
            
            // Activity placeholder with better prompt
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

                VStack(spacing: Spacing.sm) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.appTextSecondary.opacity(0.4))

                    Text("Start your journey")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appTextPrimary)

                    Text("Complete your first match to see your progress here")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.lg)
            }
            .cardBackground()
        }
    }
    
    // MARK: - Search Action
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        // TODO: Navigate to search results or filter feed
        print("Searching for: \(searchText)")
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
    HomeView()
        .environmentObject(SessionManager.shared)
}
