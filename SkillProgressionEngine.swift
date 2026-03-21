//
//  SkillProgressionEngine.swift
//  SportsHub
//
//  Intelligence engine for analyzing skill progression and generating recommendations
//

import Foundation
import Combine

@MainActor
class SkillProgressionEngine: ObservableObject {
    static let shared = SkillProgressionEngine()
    
    @Published var profiles: [Sport: SkillProfile] = [:]
    @Published var recentEvents: [SkillEvent] = []
    @Published var recommendations: [AITrainingRecommendation] = []
    @Published var feedbackMessages: [SkillFeedbackMessage] = []
    
    private let storageKey = "skill_progression_profiles"
    private let eventsKey = "skill_progression_events"
    
    private init() {
        loadProfiles()
        loadEvents()
    }
    
    // MARK: - Data Management
    
    func getProfile(for sport: Sport) -> SkillProfile {
        if let existing = profiles[sport] {
            return existing
        } else {
            let newProfile = SkillProfile(sport: sport)
            profiles[sport] = newProfile
            saveProfiles()
            return newProfile
        }
    }
    
    func recordEvent(_ event: SkillEvent) {
        recentEvents.append(event)
        
        // Keep only last 100 events
        if recentEvents.count > 100 {
            recentEvents.removeFirst(recentEvents.count - 100)
        }
        
        saveEvents()
        
        // Update skill scores based on event
        updateSkillScore(from: event)
        
        // Analyze trends
        analyzeTrends(for: event.sport)
        
        // Generate recommendations
        generateRecommendations(for: event.sport)
    }
    
    // MARK: - Skill Score Updates
    
    private func updateSkillScore(from event: SkillEvent) {
        guard var profile = profiles[event.sport] else { return }
        
        // Calculate score change based on event type and performance
        let scoreChange = calculateScoreChange(event: event)
        
        // Get current skill score
        if let currentSkill = profile.skill(for: event.category) {
            let newScore = currentSkill.score + scoreChange
            profile.updateSkill(category: event.category, newScore: newScore)
        }
        
        profile.updateAnalysis()
        profiles[event.sport] = profile
        saveProfiles()
    }
    
    private func calculateScoreChange(event: SkillEvent) -> Double {
        switch event.eventType {
        case .drillCompletion:
            // Drill completion contributes +0.5 to +2.0 based on performance
            return (event.performance / 100.0) * 2.0
            
        case .challengeSuccess:
            // Challenge success contributes +1.0 to +3.0
            return 1.0 + (event.performance / 100.0) * 2.0
            
        case .challengeFailure:
            // Challenge failure contributes -0.5 to 0
            return -(1.0 - event.performance / 100.0) * 0.5
            
        case .matchWin:
            // Match win contributes +2.0 to +4.0
            return 2.0 + (event.performance / 100.0) * 2.0
            
        case .matchLoss:
            // Match loss contributes -1.0 to 0
            return -(1.0 - event.performance / 100.0)
            
        case .trainingSession:
            // Training session contributes +0.3 to +1.5
            return (event.performance / 100.0) * 1.5
            
        case .userSubmittedStats:
            // User stats contribute +0.5 to +2.5
            return 0.5 + (event.performance / 100.0) * 2.0
        }
    }
    
    // MARK: - Trend Analysis
    
    private func analyzeTrends(for sport: Sport) {
        guard var profile = profiles[sport] else { return }
        
        let recentSportEvents = recentEvents.filter { $0.sport == sport }
        
        // Analyze trends for each skill
        for (index, skill) in profile.skills.enumerated() {
            let skillEvents = recentSportEvents
                .filter { $0.category == skill.category }
                .suffix(10) // Last 10 events for this skill
            
            guard skillEvents.count >= 3 else {
                profile.skills[index].trend = .stable
                continue
            }
            
            let performances = skillEvents.map { $0.performance }
            let trend = calculateTrend(performances: performances)
            profile.skills[index].trend = trend
        }
        
        profile.updateAnalysis()
        profiles[sport] = profile
        saveProfiles()
        
        // Generate feedback messages based on trends
        generateFeedbackMessages(for: profile)
    }
    
    private func calculateTrend(performances: [Double]) -> SkillTrend {
        guard performances.count >= 3 else { return .stable }
        
        let recentAvg = performances.suffix(3).reduce(0, +) / 3.0
        let olderAvg = performances.prefix(performances.count - 3).reduce(0, +) / Double(performances.count - 3)
        
        let change = recentAvg - olderAvg
        
        if change > 5.0 {
            return .improving
        } else if change < -5.0 {
            return .declining
        } else {
            return .stable
        }
    }
    
    // MARK: - Recommendations
    
    func generateRecommendations(for sport: Sport) {
        guard let profile = profiles[sport] else { return }
        
        var newRecommendations: [AITrainingRecommendation] = []
        
        // 1. Target declining skills with high priority
        let decliningSkills = profile.skills.filter { $0.trend == .declining }
        for skill in decliningSkills {
            let recommendation = AITrainingRecommendation(
                targetSkill: skill.category,
                reason: "Your \(skill.category.displayName.lowercased()) performance has been declining recently.",
                suggestedDrills: getDrillsForSkill(skill.category, sport: sport),
                priority: .high,
                estimatedImpact: "Focused training can reverse this decline within 1-2 weeks"
            )
            newRecommendations.append(recommendation)
        }
        
        // 2. Target stagnating skills with medium priority
        let stagnatingSkills = profile.skills.filter { $0.trend == .stable && $0.score < 60 }
        for skill in stagnatingSkills {
            let recommendation = AITrainingRecommendation(
                targetSkill: skill.category,
                reason: "Your \(skill.category.displayName.lowercased()) has plateaued. Let's break through this ceiling.",
                suggestedDrills: getDrillsForSkill(skill.category, sport: sport),
                priority: .medium,
                estimatedImpact: "Progressive training can boost this skill by 10-15 points"
            )
            newRecommendations.append(recommendation)
        }
        
        // 3. Balance rapidly improving skills
        let rapidlyImproving = profile.skills.filter { $0.trend == .improving && $0.score > 70 }
        if rapidlyImproving.count > 0, let weakest = profile.weakestSkill {
            let recommendation = AITrainingRecommendation(
                targetSkill: weakest,
                reason: "Your strong skills are improving well. Now focus on \(weakest.displayName.lowercased()) to become a more balanced athlete.",
                suggestedDrills: getDrillsForSkill(weakest, sport: sport),
                priority: .medium,
                estimatedImpact: "Balanced skill development leads to better overall performance"
            )
            newRecommendations.append(recommendation)
        }
        
        // 4. Critical priority for very weak skills
        let criticalSkills = profile.skills.filter { $0.score < 30 }
        for skill in criticalSkills {
            let recommendation = AITrainingRecommendation(
                targetSkill: skill.category,
                reason: "Your \(skill.category.displayName.lowercased()) needs urgent attention. This weakness may be holding you back.",
                suggestedDrills: getDrillsForSkill(skill.category, sport: sport),
                priority: .critical,
                estimatedImpact: "Immediate focus can show dramatic improvement quickly"
            )
            newRecommendations.append(recommendation)
        }
        
        // Sort by priority
        recommendations = newRecommendations.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    private func getDrillsForSkill(_ category: SkillCategory, sport: Sport) -> [String] {
        // Return sport and skill-specific drill suggestions
        switch category {
        // Basketball
        case .shooting:
            return ["Form Shooting", "Spot-Up Shooting", "Off-the-Dribble", "Free Throws"]
        case .ballHandling:
            return ["Stationary Dribbling", "Figure 8s", "Cone Weave", "Full Court Dribbling"]
        case .finishing:
            return ["Layup Series", "Floaters", "Contact Finishes", "Reverse Layups"]
        case .passing:
            return ["Chest Pass Drill", "Bounce Pass Drill", "Outlet Passing", "No-Look Passes"]
        case .defense:
            return ["Defensive Slides", "Close-Outs", "Help Defense", "One-on-One Defense"]
        case .conditioning:
            return ["Suicides", "Full Court Sprints", "17s", "Interval Training"]
            
        // Soccer
        case .dribbling:
            return ["Cone Weaving", "Speed Dribbling", "1v1 Moves", "Ball Mastery"]
        case .soccerPassing:
            return ["Short Passing", "Long Passing", "Through Balls", "Wall Passes"]
        case .soccerShooting:
            return ["Finishing Drill", "Long Shots", "Volleys", "Headers"]
        case .firstTouch:
            return ["Control Drills", "Chest Control", "Thigh Control", "Touch & Turn"]
        case .positioning:
            return ["Small-Sided Games", "Tactical Drills", "Shadow Play", "Positioning Games"]
        case .soccerConditioning:
            return ["Shuttle Runs", "Interval Sprints", "Fartlek Training", "Recovery Runs"]
            
        // Tennis
        case .serve:
            return ["Serve Technique", "Power Serves", "Placement Serves", "Second Serve"]
        case .forehand:
            return ["Forehand Baseline", "Topspin Forehand", "Forehand Approach", "Inside-Out Forehand"]
        case .backhand:
            return ["Backhand Baseline", "Slice Backhand", "Topspin Backhand", "Two-Handed Backhand"]
        case .footwork:
            return ["Ladder Drills", "Court Movement", "Split Step", "Recovery Steps"]
        case .netPlay:
            return ["Volley Drills", "Overhead Smash", "Approach Shots", "Net Positioning"]
        case .endurance:
            return ["Court Sprints", "Endurance Sets", "Interval Training", "Match Simulation"]
            
        // Football
        case .agility:
            return ["Cone Drills", "Ladder Drills", "Change of Direction", "Quick Feet"]
        case .catching:
            return ["Hand Eye Coordination", "Over-the-Shoulder", "One-Handed Catches", "Route Catches"]
        case .throwing:
            return ["Throwing Mechanics", "Accuracy Throws", "Deep Balls", "Quick Release"]
        case .routeRunning:
            return ["Route Tree", "Break Points", "Cuts", "Release Techniques"]
        case .blocking:
            return ["Hand Placement", "Footwork", "Drive Blocking", "Pass Protection"]
        case .footballConditioning:
            return ["40-Yard Sprints", "Position Drills", "Interval Training", "Game Speed Reps"]
        }
    }
    
    // MARK: - Feedback Messages
    
    private func generateFeedbackMessages(for profile: SkillProfile) {
        var messages: [SkillFeedbackMessage] = []
        
        // Positive feedback for improving skills
        let improving = profile.skills.filter { $0.trend == .improving }
        if let skill = improving.randomElement() {
            let message = SkillFeedbackMessage(
                message: "Great progress! Your \(skill.category.displayName.lowercased()) has improved significantly over the past two weeks.",
                category: skill.category,
                isPositive: true
            )
            messages.append(message)
        }
        
        // Constructive feedback for declining skills
        let declining = profile.skills.filter { $0.trend == .declining }
        if let skill = declining.first {
            let message = SkillFeedbackMessage(
                message: "Your \(skill.category.displayName.lowercased()) drills have been inconsistent. Let's focus on that skill today.",
                category: skill.category,
                isPositive: false
            )
            messages.append(message)
        }
        
        // Overall performance feedback
        let avgScore = profile.skills.map { $0.score }.reduce(0, +) / Double(profile.skills.count)
        if avgScore > 70 {
            let message = SkillFeedbackMessage(
                message: "You've been performing well across all skills, which suggests your overall game awareness is improving.",
                category: nil,
                isPositive: true
            )
            messages.append(message)
        }
        
        feedbackMessages = messages
    }
    
    // MARK: - Persistence
    
    private struct ProfileEntry: Codable {
        let sportName: String
        let profile: SkillProfile
    }
    
    private func saveProfiles() {
        let entries = profiles.map { ProfileEntry(sportName: $0.key.rawValue, profile: $0.value) }
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let entries = try? JSONDecoder().decode([ProfileEntry].self, from: data) {
            var loadedProfiles: [Sport: SkillProfile] = [:]
            for entry in entries {
                if let sport = Sport(rawValue: entry.sportName) {
                    loadedProfiles[sport] = entry.profile
                }
            }
            profiles = loadedProfiles
        }
    }
    
    private func saveEvents() {
        if let encoded = try? JSONEncoder().encode(recentEvents) {
            UserDefaults.standard.set(encoded, forKey: eventsKey)
        }
    }
    
    private func loadEvents() {
        if let data = UserDefaults.standard.data(forKey: eventsKey),
           let decoded = try? JSONDecoder().decode([SkillEvent].self, from: data) {
            recentEvents = decoded
        }
    }
    
    // MARK: - Public API
    
    func simulateEvent(sport: Sport, category: SkillCategory, performance: Double) {
        guard let userId = UUID().uuidString as String? else { return }
        let event = SkillEvent(
            userId: userId,
            sport: sport,
            category: category,
            eventType: .drillCompletion,
            performance: performance
        )
        recordEvent(event)
    }
}
