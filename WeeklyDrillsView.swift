// Weekly Drills View
// Premium feature: AI-generated personalized weekly drills

import SwiftUI

struct WeeklyDrillsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var storeManager = StoreManager.shared
    let sport: Sport
    
    @State private var weeklyPlan: WeeklyDrillsPlan?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPremiumSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if !storeManager.isPremium {
                    // Premium Gate
                    premiumLockedView
                } else if isLoading {
                    // Loading State
                    loadingView
                } else if let error = errorMessage {
                    // Error State
                    errorView(error)
                } else if let plan = weeklyPlan {
                    // Weekly Drills Content
                    weeklyDrillsContent(plan)
                } else {
                    // Empty State
                    emptyStateView
                }
            }
            .padding(Spacing.md)
        }
        .background(Color.appBackground)
        .navigationTitle("Weekly Drills")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if storeManager.isPremium && weeklyPlan != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        refreshDrills()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Color.appPrimary)
                    }
                    .disabled(isLoading)
                }
            }
        }
        .sheet(isPresented: $showPremiumSheet) {
            PremiumSubscriptionView()
        }
        .task {
            if storeManager.isPremium {
                await loadWeeklyDrills()
            }
        }
    }
    
    // MARK: - Premium Locked View
    
    private var premiumLockedView: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: Spacing.md) {
                Text("Premium Feature")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)
                
                Text("Get fresh, AI-generated drills every week tailored to your skill level, weak points, and goals.")
                    .font(.body)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }
            
            VStack(alignment: .leading, spacing: Spacing.sm) {
                premiumFeature(icon: "calendar.badge.clock", text: "New drills every Monday", color: .cyan)
                premiumFeature(icon: "target", text: "Personalized to your weak points", color: .orange)
                premiumFeature(icon: "brain.head.profile", text: "AI-tailored progression", color: .purple)
                premiumFeature(icon: "chart.line.uptrend.xyaxis", text: "Based on your recent activity", color: .green)
            }
            .padding(Spacing.md)
            .background(Color.appSurface)
            .cornerRadius(CornerRadius.large)
            
            Button(action: {
                showPremiumSheet = true
            }) {
                HStack {
                    Image(systemName: "star.fill")
                    Text("Unlock Premium")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.large)
            }
            
            Spacer()
        }
    }
    
    private func premiumFeature(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 28)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.appTextPrimary)
            
            Spacer()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            ProgressView()
                .tint(Color.appPrimary)
            Text("Generating your personalized drills...")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
            Spacer()
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.appError)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            
            Button("Try Again") {
                Task {
                    await loadWeeklyDrills()
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.appPrimary)
            
            Spacer()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "figure.run")
                .font(.system(size: 48))
                .foregroundStyle(Color.appTextSecondary)
            
            Text("No drills yet")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
            
            Text("Tap refresh to generate your personalized weekly drills")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            
            Button(action: {
                Task {
                    await loadWeeklyDrills()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Generate Drills")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(Color.appPrimary)
                .cornerRadius(CornerRadius.medium)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Weekly Drills Content
    
    private func weeklyDrillsContent(_ plan: WeeklyDrillsPlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header Card
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This Week's Focus")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                        
                        Text(plan.weeklyFocus)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appTextPrimary)
                    }
                    
                    Spacer()
                }
                
                Divider()
                
                // Personalization Context
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Tailored for you")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appTextSecondary)
                    
                    HStack(spacing: Spacing.xs) {
                        contextBadge(text: plan.personalizationContext.skillLevel.capitalized)
                        
                        if let readiness = plan.personalizationContext.readinessScore {
                            contextBadge(text: "Readiness: \(Int(readiness * 100))%")
                        }
                    }
                    
                    if !plan.personalizationContext.weakPoints.isEmpty {
                        Text("Focusing on: \(plan.personalizationContext.weakPoints.prefix(3).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(Spacing.md)
            .background(
                LinearGradient(
                    colors: [
                        Color.purple.opacity(0.05),
                        Color.blue.opacity(0.05)
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
                            colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            
            // Drills List
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("\(plan.drills.count) Drills")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)
                
                ForEach(Array(plan.drills.enumerated()), id: \.offset) { index, drill in
                    PersonalizedDrillCard(drill: drill, index: index + 1)
                }
            }
            
            // Week Info
            HStack {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                
                Text("Week of \(formatDate(plan.weekStartDate))")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                
                Spacer()
                
                Text("Generated \(formatRelativeDate(plan.generatedAt))")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            .padding(.top, Spacing.md)
        }
    }
    
    private func contextBadge(text: String) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(Color.appPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.appPrimary.opacity(0.1))
            .cornerRadius(6)
    }
    
    // MARK: - Data Loading
    
    private func loadWeeklyDrills() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let plan = try await APIClient.shared.getWeeklyDrills(sport: sport.rawValue.lowercased())
            await MainActor.run {
                weeklyPlan = plan
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load weekly drills: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func refreshDrills() {
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                let plan = try await APIClient.shared.generateWeeklyDrills(sport: sport.rawValue.lowercased())
                await MainActor.run {
                    weeklyPlan = plan
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate new drills: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ dateString: String) -> String {
        // Simple date formatter
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return displayFormatter.string(from: date)
        }
        return dateString
    }
    
    private func formatRelativeDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let now = Date()
            let components = Calendar.current.dateComponents([.day, .hour], from: date, to: now)
            
            if let days = components.day, days > 0 {
                return "\(days)d ago"
            } else if let hours = components.hour, hours > 0 {
                return "\(hours)h ago"
            } else {
                return "just now"
            }
        }
        return dateString
    }
}

// MARK: - Personalized Drill Card

struct PersonalizedDrillCard: View {
    let drill: PersonalizedDrill
    let index: Int
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack(alignment: .top, spacing: Spacing.sm) {
                // Drill Number Badge
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Text("\(index)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appPrimary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(drill.name)
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    HStack(spacing: Spacing.xs) {
                        difficultyBadge(drill.difficulty)
                        
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text("\(drill.durationMinutes) min")
                                .font(.caption)
                        }
                        .foregroundStyle(Color.appTextSecondary)
                        
                        Text("•")
                            .foregroundStyle(Color.appTextSecondary.opacity(0.5))
                        
                        Text(drill.category)
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.appPrimary)
                }
            }
            
            // Why This Drill
            HStack(alignment: .top, spacing: Spacing.xs) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                
                Text(drill.whyThisDrill)
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Color.orange.opacity(0.05))
            .cornerRadius(CornerRadius.sm)
            
            if isExpanded {
                Divider()
                
                // Description
                Text(drill.description)
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextPrimary)
                
                // Key Points
                if !drill.keyPoints.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Key Points")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appTextSecondary)
                        
                        ForEach(drill.keyPoints, id: \.self) { point in
                            HStack(alignment: .top, spacing: Spacing.xs) {
                                Text("•")
                                    .foregroundStyle(Color.appPrimary)
                                Text(point)
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextPrimary)
                            }
                        }
                    }
                }
                
                // Equipment
                if !drill.equipment.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                        
                        Text("Equipment:")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                        
                        Text(drill.equipment.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Color.appTextPrimary)
                    }
                }
                
                // Progression Tips
                if !drill.progressionTips.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.caption)
                            Text("Progression Tips")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Color.appPrimary)
                        
                        ForEach(drill.progressionTips, id: \.self) { tip in
                            HStack(alignment: .top, spacing: Spacing.xs) {
                                Text("→")
                                    .foregroundStyle(Color.appPrimary)
                                Text(tip)
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextPrimary)
                            }
                        }
                    }
                    .padding(Spacing.sm)
                    .background(Color.appPrimary.opacity(0.05))
                    .cornerRadius(CornerRadius.sm)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.appSurface)
        .cornerRadius(CornerRadius.large)
    }
    
    private func difficultyBadge(_ difficulty: String) -> some View {
        let color: Color = {
            switch difficulty.lowercased() {
            case "beginner": return .green
            case "intermediate": return .orange
            case "advanced": return .red
            default: return .gray
            }
        }()
        
        return Text(difficulty.capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }
}

#Preview {
    NavigationStack {
        WeeklyDrillsView(sport: .basketball)
            .environmentObject(SessionManager.shared)
    }
}
