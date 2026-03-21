//
//  AICoachLevelView.swift
//  SportsHub
//
//  AI Coach multi-level progression system
//

import SwiftUI

struct AICoachLevelView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var storeManager = StoreManager.shared
    
    @State private var currentLevel: AICoachLevel = .basic
    @State private var trustScore: Int = 25
    @State private var insightsReceived: Int = 42
    @State private var insightsActedOn: Int = 28
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Current Level Card
                VStack(spacing: Spacing.md) {
                    HStack {
                        Image(systemName: currentLevel.icon)
                            .font(.system(size: 48))
                            .foregroundStyle(currentLevel.color)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentLevel.rawValue)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.appTextPrimary)
                            
                            Text("AI Coach Level \(currentLevel.levelNumber)")
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Trust Score Progress
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text("Trust Score")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Text("\(trustScore)/100")
                                .font(.subheadline)
                                .foregroundStyle(Color.appPrimary)
                        }
                        
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.appTextSecondary.opacity(0.2))
                                    .frame(height: 8)
                                
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        LinearGradient(
                                            colors: [currentLevel.color, currentLevel.color.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geometry.size.width * CGFloat(trustScore) / 100, height: 8)
                            }
                        }
                        .frame(height: 8)
                        
                        if let nextLevel = currentLevel.nextLevel {
                            Text("Unlock \(nextLevel.rawValue) at \(nextLevel.requiredTrustScore) trust")
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary)
                        } else {
                            Text("Maximum level achieved!")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(Spacing.md)
                .cardBackground()
                
                // Current Capabilities
                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader(icon: "sparkles", title: "Current Capabilities")
                    
                    VStack(spacing: Spacing.sm) {
                        ForEach(currentLevel.capabilities, id: \.self) { capability in
                            CapabilityRow(capability: capability, isUnlocked: true)
                        }
                    }
                }
                .padding(Spacing.md)
                .cardBackground()
                
                // Stats
                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader(icon: "chart.bar.fill", title: "Your Progress")
                    
                    HStack(spacing: Spacing.md) {
                        AIStatCard(
                            title: "Insights",
                            value: "\(insightsReceived)",
                            subtitle: "Received",
                            icon: "lightbulb.fill",
                            color: Color.appPrimary
                        )
                        
                        AIStatCard(
                            title: "Acted On",
                            value: "\(insightsActedOn)",
                            subtitle: String(format: "%.0f%% rate", Double(insightsActedOn) / Double(insightsReceived) * 100),
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                    }
                }
                .padding(Spacing.md)
                .cardBackground()
                
                // How to Increase Trust
                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader(icon: "arrow.up.circle.fill", title: "Increase Trust Score")
                    
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        TrustActionRow(
                            title: "Follow recommendations",
                            points: "+5 points",
                            icon: "checkmark.circle",
                            color: .green
                        )
                        
                        TrustActionRow(
                            title: "Complete suggested drills",
                            points: "+3 points",
                            icon: "figure.run",
                            color: Color.appPrimary
                        )
                        
                        TrustActionRow(
                            title: "Win matches after prep",
                            points: "+8 points",
                            icon: "trophy",
                            color: Color.appSecondary
                        )
                        
                        TrustActionRow(
                            title: "Submit proof of training",
                            points: "+2 points",
                            icon: "camera",
                            color: .blue
                        )
                    }
                }
                .padding(Spacing.md)
                .cardBackground()
                
                // All Levels Preview
                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader(icon: "star.fill", title: "All AI Coach Levels")
                    
                    VStack(spacing: Spacing.md) {
                        ForEach(AICoachLevel.allCases, id: \.self) { level in
                            LevelCard(
                                level: level,
                                isUnlocked: level.levelNumber <= currentLevel.levelNumber,
                                isCurrent: level == currentLevel
                            )
                        }
                    }
                }
                .padding(Spacing.md)
                .cardBackground()
            }
            .padding(Spacing.md)
        }
        .background(Color.appBackground)
        .navigationTitle("AI Coach Progression")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Supporting Views

struct CapabilityRow: View {
    let capability: String
    let isUnlocked: Bool
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: isUnlocked ? "checkmark.circle.fill" : "lock.circle.fill")
                .foregroundStyle(isUnlocked ? .green : Color.appTextSecondary)
            
            Text(capability)
                .font(.subheadline)
                .foregroundStyle(isUnlocked ? Color.appTextPrimary : Color.appTextSecondary)
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct AIStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.appTextPrimary)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.md)
        .background(Color.appCardBackground)
        .cornerRadius(12)
    }
}

struct TrustActionRow: View {
    let title: String
    let points: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextPrimary)
            }
            
            Spacer()
            
            Text(points)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .padding(.vertical, Spacing.xs)
    }
}

struct LevelCard: View {
    let level: AICoachLevel
    let isUnlocked: Bool
    let isCurrent: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: level.icon)
                        .font(.title3)
                        .foregroundStyle(isUnlocked ? level.color : Color.appTextSecondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.rawValue)
                            .font(.headline)
                            .foregroundStyle(isUnlocked ? Color.appTextPrimary : Color.appTextSecondary)
                        
                        Text("Level \(level.levelNumber)")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
                
                Spacer()
                
                if isCurrent {
                    Text("Current")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background(level.color)
                        .cornerRadius(8)
                } else if !isUnlocked {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        Text("\(level.requiredTrustScore)")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                }
            }
            
            Text(level.description)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .lineLimit(2)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isUnlocked ? Color.appCardBackground : Color.appCardBackground.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? level.color : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - AI Coach Level System

enum AICoachLevel: String, CaseIterable {
    case basic = "Basic Coach"
    case insightful = "Insightful Coach"
    case strategic = "Strategic Coach"
    case elite = "Elite Coach"
    case legendary = "Legendary Coach"
    
    var levelNumber: Int {
        switch self {
        case .basic: return 1
        case .insightful: return 2
        case .strategic: return 3
        case .elite: return 4
        case .legendary: return 5
        }
    }
    
    var requiredTrustScore: Int {
        switch self {
        case .basic: return 0
        case .insightful: return 25
        case .strategic: return 50
        case .elite: return 75
        case .legendary: return 95
        }
    }
    
    var icon: String {
        switch self {
        case .basic: return "brain"
        case .insightful: return "brain.head.profile"
        case .strategic: return "brain.filled.head.profile"
        case .elite: return "sparkles"
        case .legendary: return "crown.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .basic: return .gray
        case .insightful: return .blue
        case .strategic: return .purple
        case .elite: return Color.appSecondary
        case .legendary: return Color.appPrimary
        }
    }
    
    var description: String {
        switch self {
        case .basic:
            return "General training tips and basic insights based on your activity"
        case .insightful:
            return "Personalized analysis of your performance patterns and trends"
        case .strategic:
            return "Advanced game planning and opponent-specific strategies"
        case .elite:
            return "Deep psychological insights and mental game optimization"
        case .legendary:
            return "Pro-level coaching with predictive analytics and cutting-edge techniques"
        }
    }
    
    var capabilities: [String] {
        switch self {
        case .basic:
            return [
                "Daily training tips",
                "Basic performance feedback",
                "Simple drill suggestions"
            ]
        case .insightful:
            return [
                "All Basic capabilities",
                "Performance trend analysis",
                "Personalized drill recommendations",
                "Win rate insights"
            ]
        case .strategic:
            return [
                "All Insightful capabilities",
                "Game planning assistance",
                "Opponent analysis",
                "Strategy recommendations"
            ]
        case .elite:
            return [
                "All Strategic capabilities",
                "Mental game coaching",
                "Pressure situation training",
                "Advanced biomechanics feedback"
            ]
        case .legendary:
            return [
                "All Elite capabilities",
                "Predictive match outcomes",
                "Pro technique analysis",
                "Career progression planning",
                "Tournament preparation"
            ]
        }
    }
    
    var nextLevel: AICoachLevel? {
        let allLevels = AICoachLevel.allCases
        guard let currentIndex = allLevels.firstIndex(of: self),
              currentIndex + 1 < allLevels.count else {
            return nil
        }
        return allLevels[currentIndex + 1]
    }
}

#Preview {
    NavigationStack {
        AICoachLevelView()
            .environmentObject(SessionManager.shared)
    }
}
