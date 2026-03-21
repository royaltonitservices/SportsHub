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
                Text("Hello, \(athleteName)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)

                Text("Ready to compete?")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
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
            // Sport-specific content header
            HStack {
                Image(systemName: selectedSport.icon)
                    .font(.title2)
                    .foregroundStyle(Color.appPrimary)

                Text("\(selectedSport.rawValue) Feed")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)

                Spacer()
            }

            // Empty state for now
            VStack(spacing: Spacing.md) {
                Image(systemName: selectedSport.icon)
                    .font(.system(size: 64))
                    .foregroundStyle(Color.appTextSecondary.opacity(0.3))

                Text("No \(selectedSport.rawValue.lowercased()) activity yet")
                    .font(.headline)
                    .foregroundStyle(Color.appTextSecondary)

                Text("Start competing, training, or connect with other athletes")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
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
