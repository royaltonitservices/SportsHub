//
//  TrainView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

struct TrainView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var storeManager = StoreManager.shared
    @State private var selectedSport: Sport = .basketball
    @State private var showLogSession = false
    @State private var showDrillLibrary = false
    @State private var showCreateChallenge = false
    @State private var showReadiness = false
    @State private var showAICoach = false
    @State private var recentSessions: [TrainingSessionPreview] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Sport Selector
                    sportSelector
                    
                    // Daily Readiness Card (Premium)
                    if storeManager.isPremium {
                        dailyReadinessCard
                    }
                    
                    // AI Coach Chat (Premium)
                    if storeManager.isPremium {
                        aiCoachChatCard
                    }
                    
                    // Quick Actions
                    quickActions

                    // Recent Sessions
                    if !recentSessions.isEmpty {
                        recentSessionsSection
                    }
                    
                    // Challenges Section
                    challengesSection

                    // Training Programs
                    VStack(spacing: Spacing.md) {
                        HStack {
                            Image(systemName: "figure.run")
                                .foregroundStyle(Color.appPrimary)
                            Text("Training Programs")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.appTextPrimary)
                            Spacer()
                        }

                        VStack(spacing: Spacing.md) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 64))
                                .foregroundStyle(Color.appTextSecondary.opacity(0.3))

                            Text("No programs available")
                                .font(.headline)
                                .foregroundStyle(Color.appTextSecondary)

                            Text("Personalized \(selectedSport.rawValue.lowercased()) training programs coming soon")
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextSecondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                        .cardBackground()
                    }

                    // Skill Progression (Premium AI Feature)
                    NavigationLink {
                        SkillProgressionView(sport: selectedSport)
                    } label: {
                        VStack(spacing: Spacing.md) {
                            HStack {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .foregroundStyle(Color.appPrimary)
                                Text("Skill Progression")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.appTextPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.appSecondary)
                            }
                            
                            HStack(spacing: Spacing.md) {
                                VStack {
                                    Image(systemName: "brain.head.profile")
                                        .font(.title2)
                                        .foregroundStyle(Color.appPrimary)
                                    Text("AI Analysis")
                                        .font(.caption)
                                        .foregroundStyle(Color.appSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                
                                VStack {
                                    Image(systemName: "target")
                                        .font(.title2)
                                        .foregroundStyle(Color.appSecondary)
                                    Text("Smart Training")
                                        .font(.caption)
                                        .foregroundStyle(Color.appSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                
                                VStack {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.title2)
                                        .foregroundStyle(.green)
                                    Text("Track Growth")
                                        .font(.caption)
                                        .foregroundStyle(Color.appSecondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(Spacing.md)
                        .cardBackground()
                    }
                    .buttonStyle(.plain)
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showLogSession) {
                TrainingSessionView(sport: selectedSport)
            }
            .sheet(isPresented: $showDrillLibrary) {
                DrillLibraryView(sport: selectedSport)
            }
            .sheet(isPresented: $showCreateChallenge) {
                ChallengeCreationView(sport: selectedSport)
            }
            .sheet(isPresented: $showReadiness) {
                DailyReadinessView(sport: selectedSport)
            }
            .sheet(isPresented: $showAICoach) {
                NavigationStack {
                    AICoachChatView(sport: selectedSport)
                }
            }
        }
    }
    
    // MARK: - Daily Readiness Card
    
    private var dailyReadinessCard: some View {
        Button(action: { showReadiness = true }) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Image(systemName: "heart.text.square.fill")
                        .font(.title2)
                        .foregroundStyle(Color.appPrimary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Daily Readiness")
                                .font(.headline)
                                .foregroundStyle(Color.appTextPrimary)
                            
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                        
                        Text("AI-powered training recommendations")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.appSecondary)
                }
                
                Divider()
                
                HStack(spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today's Score")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondary)
                        Text("--")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appPrimary)
                    }
                    
                    Divider()
                        .frame(height: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recommendation")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondary)
                        Text("Tap to view")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appTextPrimary)
                    }
                }
            }
            .padding(Spacing.md)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Quick Actions
    
    private var quickActions: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Color.appPrimary)
                Text("Quick Actions")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
            }
            
            HStack(spacing: Spacing.md) {
                Button(action: {
                    showLogSession = true
                }) {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundStyle(Color.appPrimary)
                        
                        Text("Log Session")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appTextPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .cardBackground()
                }
                
                Button(action: {
                    showDrillLibrary = true
                }) {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.title)
                            .foregroundStyle(Color.appSecondary)
                        
                        Text("Drills")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appTextPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .cardBackground()
                }
                
                Button(action: {
                    // TODO: Find training partner
                }) {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "person.2.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                        
                        Text("Find Partner")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appTextPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .cardBackground()
                }
            }
        }
    }
    
    // MARK: - Recent Sessions
    
    private var recentSessionsSection: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(Color.appPrimary)
                Text("Recent Sessions")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
            }
            
            VStack(spacing: Spacing.sm) {
                ForEach(recentSessions.prefix(5)) { session in
                    TrainingSessionCard(session: session)
                }
            }
        }
    }

    // MARK: - Challenges Section
    
    private var challengesSection: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: "flag.fill")
                    .foregroundStyle(Color.appSecondary)
                Text("Challenges")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
            }
            
            Button(action: {
                showCreateChallenge = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.appPrimary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create a Challenge")
                            .font(.headline)
                            .foregroundStyle(Color.appTextPrimary)
                        
                        Text("Challenge yourself or friends to improve")
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

    // MARK: - AI Coach Chat Card

    private var aiCoachChatCard: some View {
        Button(action: {
            showAICoach = true
        }) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.appAccent, Color.appPrimary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Text("AI Coach Chat")
                            .font(.headline)
                            .foregroundStyle(Color.appTextPrimary)

                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.appSecondary)
                }

                Text("Chat with your personal \(selectedSport.rawValue) coach. Get real-time advice, motivation, and training guidance.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.leading)

                HStack(spacing: Spacing.md) {
                    Label("Personalized", systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(Color.appPrimary)

                    Label("Real-time", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(Color.appAccent)

                    Label("24/7 Available", systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color.appAccent.opacity(0.05),
                        Color.appPrimary.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(
                        LinearGradient(
                            colors: [Color.appAccent.opacity(0.3), Color.appPrimary.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Supporting Types

struct TrainingSessionPreview: Identifiable {
    let id = UUID()
    let drillName: String
    let sport: Sport
    let duration: Int
    let metricType: String
    let metricValue: String
    let date: Date
    let effortLevel: String
}

struct TrainingSessionCard: View {
    let session: TrainingSessionPreview
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.drillName)
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)
                
                HStack(spacing: Spacing.xs) {
                    Image(systemName: session.sport.icon)
                        .font(.caption)
                        .foregroundStyle(Color.appPrimary)
                    
                    Text(session.sport.rawValue)
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    
                    Text("•")
                        .foregroundStyle(Color.appTextSecondary)
                    
                    Text("\(session.duration) min")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(session.metricValue)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appPrimary)
                
                Text(session.metricType)
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
}

#Preview {
    TrainView()
        .environmentObject(SessionManager.shared)
}
