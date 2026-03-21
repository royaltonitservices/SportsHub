//
//  SkillProgressionView.swift
//  SportsHub
//
//  Visual interface for skill progression tracking
//

import SwiftUI
import Charts

struct SkillProgressionView: View {
    let sport: Sport
    
    @StateObject private var engine = SkillProgressionEngine.shared
    @State private var selectedTimeframe: AnalysisTimeframe = .weekly
    @State private var showRecommendations = false
    
    private var profile: SkillProfile {
        engine.getProfile(for: sport)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Header
                headerSection
                
                // Skill Radar Chart
                skillRadarChart
                
                // Skill List with Trends
                skillListSection
                
                // AI Feedback
                if !engine.feedbackMessages.isEmpty {
                    feedbackSection
                }
                
                // Recommendations Button
                recommendationsButton
            }
            .padding(Spacing.md)
        }
        .background(Color.appBackground)
        .navigationTitle("Skill Progression")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showRecommendations) {
            RecommendationsSheet(sport: sport)
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundStyle(Color.appPrimary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skill Analysis")
                        .font(.headline)
                    Text("Track your improvement over time")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                }
                
                Spacer()
            }
            .padding(Spacing.md)
            .cardBackground()
        }
    }
    
    // MARK: - Radar Chart
    
    private var skillRadarChart: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Skill Balance")
                .font(.headline)
                .padding(.horizontal, Spacing.md)
            
            ZStack {
                // Radar chart background
                RadarChartShape(dataPoints: profile.skills.count)
                    .stroke(Color.appTextSecondary.opacity(0.2), lineWidth: 1)
                    .frame(height: 250)
                
                // Skill data overlay
                RadarChartDataShape(skills: profile.skills)
                    .fill(Color.appPrimary.opacity(0.3))
                    .frame(height: 250)
                
                RadarChartDataShape(skills: profile.skills)
                    .stroke(Color.appPrimary, lineWidth: 2)
                    .frame(height: 250)
                
                // Labels
                RadarChartLabels(skills: profile.skills)
            }
            .padding(Spacing.md)
            .cardBackground()
        }
    }
    
    // MARK: - Skill List
    
    private var skillListSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Skill Breakdown")
                    .font(.headline)
                
                Spacer()
                
                // Timeframe selector
                Picker("Timeframe", selection: $selectedTimeframe) {
                    Text("7d").tag(AnalysisTimeframe.weekly)
                    Text("30d").tag(AnalysisTimeframe.monthly)
                    Text("90d").tag(AnalysisTimeframe.seasonal)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            
            ForEach(profile.skills) { skill in
                SkillRow(skill: skill)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    // MARK: - Feedback Section
    
    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(Color.appPrimary)
                Text("AI Coach Feedback")
                    .font(.headline)
            }
            
            ForEach(engine.feedbackMessages) { feedback in
                FeedbackCard(message: feedback)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    // MARK: - Recommendations Button
    
    private var recommendationsButton: some View {
        Button(action: { showRecommendations = true }) {
            HStack {
                Image(systemName: "lightbulb.fill")
                Text("View Training Recommendations")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(Spacing.md)
            .background(Color.appPrimary)
            .cornerRadius(CornerRadius.md)
        }
    }
    
    enum AnalysisTimeframe: String {
        case weekly = "7d"
        case monthly = "30d"
        case seasonal = "90d"
    }
}

// MARK: - Skill Row

struct SkillRow: View {
    let skill: SkillScore
    
    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.category.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 4) {
                        Image(systemName: skill.trend.icon)
                            .font(.caption)
                        Text(skill.trend.displayName)
                            .font(.caption)
                    }
                    .foregroundStyle(trendColor(skill.trend))
                }
                
                Spacer()
                
                Text("\(Int(skill.score))")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(scoreColor(skill.score))
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.appTextSecondary.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(scoreColor(skill.score))
                        .frame(width: geometry.size.width * (skill.score / 100), height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, Spacing.sm)
    }
    
    private func trendColor(_ trend: SkillTrend) -> Color {
        switch trend {
        case .improving: return .green
        case .stable: return .orange
        case .declining: return .red
        }
    }
    
    private func scoreColor(_ score: Double) -> Color {
        if score >= 80 { return .green }
        else if score >= 60 { return Color(red: 0.4, green: 0.8, blue: 0.4) }
        else if score >= 40 { return .orange }
        else { return .red }
    }
}

// MARK: - Feedback Card

struct FeedbackCard: View {
    let message: SkillFeedbackMessage
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: message.isPositive ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundStyle(message.isPositive ? .green : .orange)
            
            Text(message.message)
                .font(.body)
                .foregroundStyle(Color.appTextPrimary)
            
            Spacer()
        }
        .padding(Spacing.md)
        .background(message.isPositive ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        .cornerRadius(CornerRadius.md)
    }
}

// MARK: - Radar Chart Shapes

struct RadarChartShape: Shape {
    let dataPoints: Int
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * 0.8
        
        for i in 0..<dataPoints {
            let angle = (Double(i) / Double(dataPoints)) * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )
            
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        
        return path
    }
}

struct RadarChartDataShape: Shape {
    let skills: [SkillScore]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2 * 0.8
        
        for (index, skill) in skills.enumerated() {
            let angle = (Double(index) / Double(skills.count)) * 2 * .pi - .pi / 2
            let radius = maxRadius * CGFloat(skill.score / 100)
            let point = CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )
            
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        
        return path
    }
}

struct RadarChartLabels: View {
    let skills: [SkillScore]
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(skills.enumerated()), id: \.element.id) { item in
                RadarLabel(
                    skill: item.element,
                    index: item.offset,
                    totalCount: skills.count,
                    geometry: geometry
                )
            }
        }
    }
}

struct RadarLabel: View {
    let skill: SkillScore
    let index: Int
    let totalCount: Int
    let geometry: GeometryProxy
    
    private var position: CGPoint {
        let angle = (Double(index) / Double(totalCount)) * 2 * .pi - .pi / 2
        let minDimension = min(geometry.size.width, geometry.size.height)
        let radius = minDimension / 2 * 0.95
        let centerX = geometry.size.width / 2
        let centerY = geometry.size.height / 2
        
        let x = centerX + radius * CGFloat(cos(angle))
        let y = centerY + radius * CGFloat(sin(angle))
        
        return CGPoint(x: x, y: y)
    }
    
    var body: some View {
        Text(skill.category.displayName)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(Color.appTextPrimary)
            .position(position)
    }
}

// MARK: - Recommendations Sheet

struct RecommendationsSheet: View {
    let sport: Sport
    @StateObject private var engine = SkillProgressionEngine.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    if engine.recommendations.isEmpty {
                        emptyState
                    } else {
                        ForEach(engine.recommendations) { recommendation in
                            RecommendationCard(recommendation: recommendation)
                        }
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("AI Recommendations")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text("Great Work!")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Your skills are well-balanced. Keep training consistently to maintain your progress.")
                .font(.body)
                .foregroundStyle(Color.appSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
    }
}

struct RecommendationCard: View {
    let recommendation: AITrainingRecommendation
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.targetSkill.displayName)
                        .font(.headline)
                    Text(recommendation.priority.displayName)
                        .font(.caption)
                        .foregroundStyle(priorityColor(recommendation.priority))
                }
                
                Spacer()
                
                Image(systemName: "target")
                    .font(.title2)
                    .foregroundStyle(priorityColor(recommendation.priority))
            }
            
            Divider()
            
            // Reason
            Text(recommendation.reason)
                .font(.body)
                .foregroundStyle(Color.appTextPrimary)
            
            // Suggested Drills
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Suggested Drills:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                ForEach(recommendation.suggestedDrills, id: \.self) { drill in
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(Color.appPrimary)
                        Text(drill)
                            .font(.subheadline)
                        Spacer()
                    }
                }
            }
            
            // Estimated Impact
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(Color.appSecondary)
                Text(recommendation.estimatedImpact)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondary)
            }
            .padding(.top, Spacing.sm)
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private func priorityColor(_ priority: AITrainingRecommendation.RecommendationPriority) -> Color {
        switch priority {
        case .low: return .gray
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
}

#Preview {
    NavigationStack {
        SkillProgressionView(sport: .basketball)
    }
}
