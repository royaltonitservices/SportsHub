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
    @State private var showPremiumUpgrade = false
    @State private var showFindPartner = false
    @State private var showWeaknessSurvey = false
    @State private var recentSessions: [TrainingSessionPreview] = []
    @State private var savedWorkouts: [SavedWorkout] = []
    @State private var showQuickDrillSession = false
    @State private var quickDrillName = ""
    @State private var quickDrillDuration: Int = 0
    @State private var selectedSessionDetail: TrainingSessionPreview? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Sport Selector
                    sportSelector
                    
                    // Weekly AI Drills (Premium)
                    if storeManager.isPremium {
                        weeklyDrillsCard
                    }
                    
                    // Daily Readiness Card (Premium)
                    if storeManager.isPremium {
                        dailyReadinessCard
                    }
                    
                    // AI Coach Chat (Visible to all, Premium-gated on tap)
                    aiCoachChatCard

                    // Weakness / Focus Area Survey
                    weaknessSurveyCard

                    // Quick Actions
                    quickActions
                    
                    // Recommended Drills (new)
                    recommendedDrillsSection

                    // Recent Sessions
                    if !recentSessions.isEmpty {
                        recentSessionsSection
                    }

                    // Saved Workouts (built via Workout Builder)
                    if !savedWorkouts.isEmpty {
                        savedWorkoutsSection
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
                    .capabilityGated(.trainingPrograms)

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
                                    Image(systemName: "chart.xyaxis.line")
                                        .font(.title2)
                                        .foregroundStyle(Color.appPrimary)
                                    Text("Skill Tracking")
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
            .sheet(isPresented: $showLogSession, onDismiss: {
                Task { await loadRecentSessions() }
            }) {
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
            .sheet(isPresented: $showWeaknessSurvey) {
                WeaknessSurveyView(sport: selectedSport)
            }
            .sheet(isPresented: $showFindPartner) {
                MatchmakingView(sport: selectedSport)
            }
            .sheet(isPresented: $showPremiumUpgrade) {
                PremiumSubscriptionView()
            }
            .sheet(isPresented: $showQuickDrillSession) {
                TrainingSessionView(sport: selectedSport, prefilledDrillName: quickDrillName, prefilledDuration: quickDrillDuration > 0 ? quickDrillDuration : nil)
            }
            .task(id: selectedSport) {
                // Keep AI Coach sport context in sync with train sport selector
                AICoachManager.shared.currentSport = selectedSport.rawValue
                await loadRecentSessions()
                loadSavedWorkouts()
            }
        }
    }
    
    private func loadRecentSessions() async {
        // Try backend first
        do {
            let sessions = try await APIClient.shared.getTrainingHistory(sport: selectedSport)
            // Flatten multi-drill sessions into individual preview entries
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            recentSessions = sessions.flatMap { session in
                let date = formatter.date(from: session.createdAt) ?? Date()
                return session.drills.map { drill in
                    TrainingSessionPreview(
                        drillName: drill.drillName,
                        sport: selectedSport,
                        duration: drill.duration,
                        metricType: drill.metricType ?? "",
                        metricValue: drill.metricValue ?? "",
                        date: date,
                        effortLevel: drill.effort ?? ""
                    )
                }
            }
            return
        } catch {
            print("Training history backend unavailable, using local cache: \(error)")
        }
        // Fallback: load from UserDefaults cache
        let key = "recent_sessions_\(selectedSport.rawValue)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let savedSessions = try? JSONDecoder().decode([SavedSessionData].self, from: data) else {
            recentSessions = []
            return
        }
        recentSessions = savedSessions.map { saved in
            TrainingSessionPreview(
                drillName: saved.drillName,
                sport: selectedSport,
                duration: saved.duration,
                metricType: saved.metricType,
                metricValue: saved.metricValue,
                date: saved.date,
                effortLevel: saved.effortLevel
            )
        }
    }
    
    private func loadSavedWorkouts() {
        guard let data = UserDefaults.standard.data(forKey: "saved_workouts_v2"),
              let decoded = try? JSONDecoder().decode([SavedWorkout].self, from: data) else {
            savedWorkouts = []
            return
        }
        savedWorkouts = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Weekly Drills Card
    
    private var weeklyDrillsCard: some View {
        NavigationLink {
            WeeklyDrillsView(sport: selectedSport)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.2), .purple.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "calendar.badge.clock")
                            .font(.title3)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("AI Weekly Drills")
                                .font(.headline)
                                .foregroundStyle(Color.appTextPrimary)
                            
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.cyan)
                        }
                        
                        Text("Curated drill recommendations for your sport")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.appSecondary)
                }
                
                Divider()
                
                HStack(spacing: Spacing.md) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "target")
                            .font(.caption)
                            .foregroundStyle(Color.orange)
                        Text("Sport-specific drills")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    
                    Text("•")
                        .foregroundStyle(Color.appTextSecondary.opacity(0.5))
                    
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(Color.green)
                        Text("Skill progression")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
            }
            .padding(Spacing.md)
            .background(
                LinearGradient(
                    colors: [
                        Color.cyan.opacity(0.05),
                        Color.purple.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .stroke(
                        LinearGradient(
                            colors: [.cyan.opacity(0.3), .purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
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
    
    // MARK: - Weakness Survey Card

    private var weaknessSurveyCard: some View {
        Button(action: { showWeaknessSurvey = true }) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.appAccent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "target")
                        .font(.title3)
                        .foregroundStyle(Color.appAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text("Set Focus Areas")
                            .font(.headline)
                            .foregroundStyle(Color.appTextPrimary)
                        if SportWeaknesses.hasCompleted(for: selectedSport) {
                            let count = SportWeaknesses.load(for: selectedSport).count
                            Text("\(count) selected")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.appPrimary.opacity(0.15))
                                .foregroundStyle(Color.appPrimary)
                                .cornerRadius(4)
                        }
                    }

                    Text(SportWeaknesses.hasCompleted(for: selectedSport)
                         ? "Tap to update your \(selectedSport.rawValue) weak points"
                         : "Tell your coach what to target — sport-specific, personalized")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                    showFindPartner = true
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
                    Button {
                        selectedSessionDetail = session
                    } label: {
                        TrainingSessionCard(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $selectedSessionDetail) { session in
            TrainingSessionDetailSheet(session: session)
        }
    }

    // MARK: - Saved Workouts Section

    private var savedWorkoutsSection: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(Color.appPrimary)
                Text("Saved Workouts")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
                Text("Stored on this device")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }

            VStack(spacing: Spacing.sm) {
                ForEach(savedWorkouts.prefix(5)) { workout in
                    Button(action: {
                        quickDrillName = workout.name
                        quickDrillDuration = workout.drills.reduce(0) { $0 + $1.durationMinutes }
                        showQuickDrillSession = true
                    }) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: workout.sport.icon)
                                .font(.title2)
                                .foregroundStyle(Color.appPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.appPrimary.opacity(0.15))
                                .cornerRadius(CornerRadius.sm)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.appTextPrimary)
                                Text("\(workout.drills.count) drill\(workout.drills.count == 1 ? "" : "s") · \(workout.sport.rawValue.capitalized)")
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextSecondary)
                            }

                            Spacer()

                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.appPrimary)
                        }
                        .padding(Spacing.md)
                        .background(Color.appSurface)
                        .cornerRadius(CornerRadius.md)
                    }
                    .buttonStyle(.plain)
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
            if storeManager.isPremium {
                showAICoach = true
            } else {
                showPremiumUpgrade = true
            }
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
                        
                        // Premium badge for free users
                        if !storeManager.isPremium {
                            Text("PREMIUM")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    LinearGradient(
                                        colors: [Color.purple, Color.blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                        }
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

struct SavedSessionData: Codable {
    let drillName: String
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

// MARK: - Session Detail Sheet

struct TrainingSessionDetailSheet: View {
    let session: TrainingSessionPreview
    @Environment(\.dismiss) private var dismiss

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: session.date)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Drill") {
                    LabeledContent("Name", value: session.drillName)
                    LabeledContent("Sport", value: session.sport.rawValue.capitalized)
                }
                Section("Performance") {
                    LabeledContent("Duration", value: "\(session.duration) min")
                    LabeledContent(session.metricType, value: session.metricValue)
                    LabeledContent("Effort", value: session.effortLevel.capitalized)
                }
                Section("Logged") {
                    LabeledContent("Date", value: formattedDate)
                }
            }
            .navigationTitle("Session Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Recommended Drills Extension

extension TrainView {
    // MARK: - Recommended Drills Section
    
    var recommendedDrillsSection: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(Color.appPrimary)
                Text("Quick Start Drills")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
            }
            
            VStack(spacing: Spacing.sm) {
                ForEach(recommendedDrills, id: \.title) { drill in
                    QuickDrillCard(drill: drill, sport: selectedSport, onTap: {
                        quickDrillName = drill.title
                        quickDrillDuration = 0
                        showQuickDrillSession = true
                    })
                }
            }
        }
    }
    
    private var recommendedDrills: [QuickDrill] {
        switch selectedSport {
        case .basketball:
            return [
                QuickDrill(title: "Form Shooting", duration: "10 min", icon: "figure.basketball", description: "Perfect your shot mechanics"),
                QuickDrill(title: "Ball Handling", duration: "15 min", icon: "hands.sparkles", description: "Dribbling fundamentals"),
                QuickDrill(title: "Free Throws", duration: "10 min", icon: "target", description: "Build consistency")
            ]
        case .tennis:
            return [
                QuickDrill(title: "Serve Practice", duration: "15 min", icon: "figure.tennis", description: "Build power and accuracy"),
                QuickDrill(title: "Groundstrokes", duration: "20 min", icon: "arrow.left.and.right", description: "Forehand and backhand"),
                QuickDrill(title: "Footwork", duration: "10 min", icon: "figure.run", description: "Court movement drills")
            ]
        case .soccer:
            return [
                QuickDrill(title: "Dribbling", duration: "15 min", icon: "figure.soccer", description: "Touch and control"),
                QuickDrill(title: "Passing", duration: "15 min", icon: "arrow.triangle.swap", description: "Accuracy drills"),
                QuickDrill(title: "Shooting", duration: "20 min", icon: "target", description: "Finishing practice")
            ]
        case .football:
            return [
                QuickDrill(title: "Route Running", duration: "15 min", icon: "figure.american.football", description: "Precision cuts"),
                QuickDrill(title: "Catching", duration: "15 min", icon: "hands.clap", description: "Hand-eye coordination"),
                QuickDrill(title: "Agility", duration: "10 min", icon: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", description: "Quick feet drills")
            ]
        }
    }
}

struct QuickDrill {
    let title: String
    let duration: String
    let icon: String
    let description: String
}

struct QuickDrillCard: View {
    let drill: QuickDrill
    let sport: Sport
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                Image(systemName: drill.icon)
                    .font(.title2)
                    .foregroundStyle(Color.appPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.appPrimary.opacity(0.15))
                    .cornerRadius(CornerRadius.sm)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(drill.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    Text(drill.description)
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(drill.duration)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appPrimary)
                    
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.appPrimary)
                }
            }
            .padding(Spacing.md)
            .background(Color.appSurface)
            .cornerRadius(CornerRadius.md)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TrainView()
        .environmentObject(SessionManager.shared)
}
