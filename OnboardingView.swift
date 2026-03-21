//
//  OnboardingView.swift
//  SportsHub
//
//  Interactive onboarding tutorial for new users
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "sportscourt.fill",
            title: "Welcome to SportsHub",
            description: "Your ultimate platform for competitive sports, training, and community",
            color: .appPrimary
        ),
        OnboardingPage(
            icon: "person.2.fill",
            title: "Find Opponents",
            description: "Match with players at your skill level using our ELO ranking system",
            color: .appAccent
        ),
        OnboardingPage(
            icon: "chart.line.uptrend.xyaxis",
            title: "Track Progress",
            description: "Monitor your performance with detailed stats, graphs, and analytics",
            color: .green
        ),
        OnboardingPage(
            icon: "figure.run",
            title: "Train Like a Pro",
            description: "Access AI-powered training plans, workout builders, and coaching",
            color: .orange
        ),
        OnboardingPage(
            icon: "trophy.fill",
            title: "Join Tournaments",
            description: "Compete in leagues, climb leaderboards, and earn badges",
            color: .yellow
        )
    ]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    pages[currentPage].color.opacity(0.3),
                    Color.appBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: Spacing.xl) {
                // Skip button
                HStack {
                    Spacer()
                    Button {
                        completeOnboarding()
                    } label: {
                        Text("Skip")
                            .foregroundColor(Color.appSecondary)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                
                Spacer()
                
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 500)
                
                // Page indicators
                HStack(spacing: Spacing.sm) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? pages[currentPage].color : Color.appSecondary)
                            .frame(width: currentPage == index ? 12 : 8, height: currentPage == index ? 12 : 8)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.vertical, Spacing.lg)
                
                // Action buttons
                HStack(spacing: Spacing.md) {
                    if currentPage > 0 {
                        Button {
                            withAnimation {
                                currentPage -= 1
                            }
                        } label: {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .foregroundColor(.appPrimary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.appPrimary.opacity(0.1))
                            .cornerRadius(CornerRadius.md)
                        }
                    }
                    
                    Button {
                        if currentPage < pages.count - 1 {
                            withAnimation {
                                currentPage += 1
                            }
                        } else {
                            completeOnboarding()
                        }
                    } label: {
                        HStack {
                            Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                            if currentPage < pages.count - 1 {
                                Image(systemName: "chevron.right")
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(pages[currentPage].color)
                        .cornerRadius(CornerRadius.md)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
        }
    }
    
    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: Spacing.xl) {
            // Icon
            ZStack {
                Circle()
                    .fill(page.color.opacity(0.2))
                    .frame(width: 180, height: 180)
                
                Circle()
                    .fill(page.color.opacity(0.3))
                    .frame(width: 140, height: 140)
                
                Image(systemName: page.icon)
                    .font(.system(size: 64))
                    .foregroundColor(page.color)
            }
            .padding(.bottom, Spacing.lg)
            
            // Title
            Text(page.title)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.appTextPrimary)
                .multilineTextAlignment(.center)
            
            // Description
            Text(page.description)
                .font(.body)
                .foregroundColor(Color.appSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
        }
        .padding(Spacing.lg)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(SessionManager.shared)
}
