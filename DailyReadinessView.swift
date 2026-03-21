//
//  DailyReadinessView.swift
//  SportsHub
//
//  Daily Readiness Coaching - Premium AI Feature
//  Integrates wearable data with adaptive training recommendations
//

import SwiftUI

struct DailyReadinessView: View {
    let sport: Sport
    
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var storeManager = StoreManager.shared
    @State private var recoveryStatus: RecoveryStatus?
    @State private var trainingRecommendation: TrainingRecommendation?
    @State private var isLoading = true
    @State private var showWearableSetup = false
    @State private var showDrillLibrary = false
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Header
                readinessHeader
                
                if isLoading {
                    ProgressView("Loading readiness data...")
                        .padding(Spacing.xl)
                } else if let error = errorMessage {
                    errorView(error)
                } else if let recovery = recoveryStatus {
                    // Main readiness card
                    readinessScoreCard(recovery)
                    
                    // Training recommendation
                    if let recommendation = trainingRecommendation {
                        trainingRecommendationCard(recommendation)
                    }
                    
                    // Biometric breakdown
                    biometricDetailsCard(recovery)
                    
                    // Recommended drills
                    if let recommendation = trainingRecommendation {
                        recommendedDrillsSection(recommendation)
                    }
                } else {
                    noDataView
                }
            }
            .padding(Spacing.lg)
        }
        .navigationTitle("Daily Readiness")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showWearableSetup) {
            SmartwatchSyncView()
        }
        .sheet(isPresented: $showDrillLibrary) {
            DrillLibraryView(sport: sport)
        }
        .task {
            await loadReadinessData()
        }
    }
    
    // MARK: - Header
    
    private var readinessHeader: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "heart.text.square.fill")
                    .font(.title2)
                    .foregroundColor(.appPrimary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Readiness Coach")
                        .font(.headline)
                    Text("Powered by your wearable data")
                        .font(.caption)
                        .foregroundColor(.appSecondary)
                }
                
                Spacer()
                
                if storeManager.isPremium {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                }
            }
            .padding(Spacing.md)
            .cardBackground()
        }
    }
    
    // MARK: - Readiness Score Card
    
    private func readinessScoreCard(_ recovery: RecoveryStatus) -> some View {
        VStack(spacing: Spacing.md) {
            Text("Today's Readiness")
                .font(.title3)
                .fontWeight(.semibold)
            
            // Large circular readiness score
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                    .frame(width: 180, height: 180)
                
                Circle()
                    .trim(from: 0, to: CGFloat(recovery.readinessScore ?? 50) / 100)
                    .stroke(readinessColor(recovery.readinessScore ?? 50), style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: recovery.readinessScore)
                
                VStack(spacing: 4) {
                    Text("\(Int(recovery.readinessScore ?? 0))")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(readinessColor(recovery.readinessScore ?? 50))
                    
                    Text(readinessLabel(recovery.readinessScore ?? 50))
                        .font(.caption)
                        .foregroundColor(.appSecondary)
                }
            }
            .padding(.vertical, Spacing.md)
            
            // Fatigue level badge
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(fatigueColor(recovery.fatigueLevel))
                Text("Fatigue: \(recovery.fatigueLevel.capitalized)")
                    .fontWeight(.medium)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(fatigueColor(recovery.fatigueLevel).opacity(0.15))
            .cornerRadius(CornerRadius.sm)
            
            Divider()
                .padding(.vertical, Spacing.sm)
            
            // Last updated
            Text("Last updated: \(formatTimestamp(recovery.lastUpdated))")
                .font(.caption)
                .foregroundColor(.appSecondary)
        }
        .padding(Spacing.lg)
        .cardBackground()
    }
    
    // MARK: - Training Recommendation Card
    
    private func trainingRecommendationCard(_ recommendation: TrainingRecommendation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: recommendation.icon)
                    .font(.title2)
                    .foregroundColor(recommendation.color)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.title)
                        .font(.headline)
                    Text(recommendation.intensity)
                        .font(.subheadline)
                        .foregroundColor(.appSecondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Duration recommendation
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.appPrimary)
                Text("Suggested Duration")
                    .font(.subheadline)
                Spacer()
                Text(recommendation.suggestedDuration)
                    .font(.headline)
                    .foregroundColor(.appPrimary)
            }
            
            // Volume recommendation
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.appPrimary)
                Text("Training Volume")
                    .font(.subheadline)
                Spacer()
                Text(recommendation.volumeLevel)
                    .font(.headline)
                    .foregroundColor(.appSecondary)
            }
            
            Divider()
            
            // AI reasoning
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.appPrimary)
                    Text("AI Recommendation")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Text(recommendation.reasoning)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .background(Color.appPrimary.opacity(0.1))
            .cornerRadius(CornerRadius.md)
        }
        .padding(Spacing.lg)
        .cardBackground()
    }
    
    // MARK: - Biometric Details
    
    private func biometricDetailsCard(_ recovery: RecoveryStatus) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Biometric Breakdown")
                .font(.headline)
            
            if let sleepQuality = recovery.sleepQuality {
                biometricRow(
                    icon: "bed.double.fill",
                    label: "Sleep Quality",
                    value: "\(Int(sleepQuality))/100",
                    color: sleepQuality > 70 ? .green : sleepQuality > 40 ? .orange : .red
                )
            }
            
            biometricRow(
                icon: "heart.fill",
                label: "HRV Status",
                value: recovery.hrvStatus.capitalized,
                color: hrvStatusColor(recovery.hrvStatus)
            )
            
            if let recoveryScore = recovery.recoveryScore {
                biometricRow(
                    icon: "arrow.clockwise.circle.fill",
                    label: "Recovery Score",
                    value: "\(Int(recoveryScore))/100",
                    color: recoveryScore > 70 ? .green : recoveryScore > 40 ? .orange : .red
                )
            }
            
            Divider()
            
            Button(action: { showWearableSetup = true }) {
                HStack {
                    Image(systemName: "applewatch")
                    Text("Sync Wearable Data")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundColor(.appPrimary)
            }
        }
        .padding(Spacing.lg)
        .cardBackground()
    }
    
    private func biometricRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(label)
                .font(.subheadline)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
    
    // MARK: - Recommended Drills
    
    private func recommendedDrillsSection(_ recommendation: TrainingRecommendation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Recommended Activities")
                    .font(.headline)
                Spacer()
                Button(action: { showDrillLibrary = true }) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.appPrimary)
                }
            }
            
            ForEach(recommendation.recommendedDrills, id: \.self) { drill in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.appPrimary)
                    Text(drill)
                        .font(.body)
                    Spacer()
                }
                .padding(.vertical, Spacing.xs)
            }
            
            if recommendation.avoidActivities.count > 0 {
                Divider()
                    .padding(.vertical, Spacing.sm)
                
                Text("Avoid Today")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                
                ForEach(recommendation.avoidActivities, id: \.self) { activity in
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(activity)
                            .font(.body)
                            .foregroundColor(.appSecondary)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }
        }
        .padding(Spacing.lg)
        .cardBackground()
    }
    
    // MARK: - Error & No Data Views
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Unable to Load Data")
                .font(.headline)
            
            Text(message)
                .font(.body)
                .foregroundColor(.appSecondary)
                .multilineTextAlignment(.center)
            
            Button(action: { Task { await loadReadinessData() } }) {
                Text("Try Again")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(Spacing.md)
                    .background(Color.appPrimary)
                    .cornerRadius(CornerRadius.md)
            }
        }
        .padding(Spacing.xl)
    }
    
    private var noDataView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "applewatch.slash")
                .font(.system(size: 60))
                .foregroundColor(.appSecondary)
            
            Text("No Wearable Data")
                .font(.headline)
            
            Text("Connect your Apple Watch or other wearable to get personalized daily readiness recommendations.")
                .font(.body)
                .foregroundColor(.appSecondary)
                .multilineTextAlignment(.center)
            
            Button(action: { showWearableSetup = true }) {
                HStack {
                    Image(systemName: "applewatch")
                    Text("Connect Wearable")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(Spacing.md)
                .background(Color.appPrimary)
                .cornerRadius(CornerRadius.md)
            }
            
            Divider()
                .padding(.vertical, Spacing.lg)
            
            Text("Using Manual Input")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text("Without wearable data, recommendations are based on your training history and goals.")
                .font(.caption)
                .foregroundColor(.appSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
    }
    
    // MARK: - Helper Functions
    
    private func readinessColor(_ score: Double) -> Color {
        if score >= 80 { return .green }
        else if score >= 60 { return Color(red: 0.4, green: 0.8, blue: 0.4) }
        else if score >= 40 { return .orange }
        else { return .red }
    }
    
    private func readinessLabel(_ score: Double) -> String {
        if score >= 80 { return "Excellent" }
        else if score >= 60 { return "Good" }
        else if score >= 40 { return "Fair" }
        else { return "Poor" }
    }
    
    private func fatigueColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "low": return .green
        case "medium": return .orange
        case "high", "very_high": return .red
        default: return .gray
        }
    }
    
    private func hrvStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "optimal": return .green
        case "normal": return Color(red: 0.4, green: 0.8, blue: 0.4)
        case "low": return .orange
        case "very_low": return .red
        default: return .gray
        }
    }
    
    private func formatTimestamp(_ timestamp: String?) -> String {
        guard let timestamp = timestamp else { return "Unknown" }
        
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: timestamp) else { return "Unknown" }
        
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        
        return timeFormatter.string(from: date)
    }
    
    // MARK: - Data Loading
    
    private func loadReadinessData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Check premium access
            guard storeManager.isPremium else {
                errorMessage = "Daily Readiness is a Premium feature. Upgrade to access AI-powered training recommendations."
                isLoading = false
                return
            }
            
            // Fetch recovery status from API
            let apiClient = APIClient.shared
            recoveryStatus = try await apiClient.getRecoveryStatus()
            
            // Generate training recommendation based on recovery status
            if let recovery = recoveryStatus {
                trainingRecommendation = generateRecommendation(from: recovery)
            }
            
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func generateRecommendation(from recovery: RecoveryStatus) -> TrainingRecommendation {
        let readiness = recovery.readinessScore ?? 50
        
        // Match-ready (80-100)
        if readiness >= 80 {
            return TrainingRecommendation(
                title: "Match-Ready",
                intensity: "High Intensity Training",
                icon: "flame.fill",
                color: .green,
                suggestedDuration: "45-60 min",
                volumeLevel: "High",
                reasoning: "Excellent recovery! Your body is ready for intense training or competition. HRV is optimal and sleep quality is high. This is the perfect day to push your limits.",
                recommendedDrills: [
                    "Full-intensity scrimmage",
                    "Competition simulation",
                    "High-intensity interval training",
                    "Sport-specific skill work"
                ],
                avoidActivities: []
            )
        }
        // Good recovery (60-79)
        else if readiness >= 60 {
            return TrainingRecommendation(
                title: "Good to Train",
                intensity: "Moderate to High Intensity",
                icon: "figure.run",
                color: Color(red: 0.4, green: 0.8, blue: 0.4),
                suggestedDuration: "35-45 min",
                volumeLevel: "Moderate-High",
                reasoning: "Good recovery status. You can handle moderate to high intensity work. Focus on technical skills and game situations while monitoring fatigue.",
                recommendedDrills: [
                    "Moderate-intensity drills",
                    "Technical skill work",
                    "Tactical training",
                    "Short scrimmages"
                ],
                avoidActivities: [
                    "Max-effort sprints",
                    "Heavy strength training"
                ]
            )
        }
        // Fair recovery (40-59)
        else if readiness >= 40 {
            return TrainingRecommendation(
                title: "Light Training",
                intensity: "Low to Moderate Intensity",
                icon: "figure.walk",
                color: .orange,
                suggestedDuration: "20-30 min",
                volumeLevel: "Low-Moderate",
                reasoning: "Fair recovery. Your body needs active recovery. Focus on technique, mobility, and light cardio. Keep intensity low to promote recovery.",
                recommendedDrills: [
                    "Form shooting (basketball)",
                    "Light technical work",
                    "Mobility and flexibility",
                    "Light cardio"
                ],
                avoidActivities: [
                    "Full-contact drills",
                    "High-intensity intervals",
                    "Heavy strength work",
                    "Competitive scrimmages"
                ]
            )
        }
        // Poor recovery (0-39)
        else {
            return TrainingRecommendation(
                title: "Recovery Day",
                intensity: "Rest or Very Light Activity",
                icon: "bed.double.fill",
                color: .red,
                suggestedDuration: "15-20 min (optional)",
                volumeLevel: "Very Low",
                reasoning: "Poor recovery signals detected. Your body needs rest. Low HRV and/or poor sleep indicate accumulated fatigue. Prioritize sleep, nutrition, and hydration today.",
                recommendedDrills: [
                    "Light stretching",
                    "Meditation or breathing exercises",
                    "Easy walk",
                    "Foam rolling"
                ],
                avoidActivities: [
                    "Any intense training",
                    "Scrimmages",
                    "Strength training",
                    "High-volume practice"
                ]
            )
        }
    }
}

// MARK: - Supporting Models

struct TrainingRecommendation {
    let title: String
    let intensity: String
    let icon: String
    let color: Color
    let suggestedDuration: String
    let volumeLevel: String
    let reasoning: String
    let recommendedDrills: [String]
    let avoidActivities: [String]
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DailyReadinessView(sport: .basketball)
            .environmentObject(SessionManager.shared)
    }
}
