// Premium Subscription Models
// Master Premium System - iOS Client

import Foundation

// MARK: - Subscription

struct Subscription: Codable, Identifiable {
    let id: String
    let userId: String
    let tier: SubscriptionTier
    let status: SubscriptionStatus
    let pricePerMonth: Double
    let startedAt: String
    let expiresAt: String?
    let cancelledAt: String?
    let platform: String?
    let features: SubscriptionFeatures
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case tier
        case status
        case pricePerMonth = "price_per_month"
        case startedAt = "started_at"
        case expiresAt = "expires_at"
        case cancelledAt = "cancelled_at"
        case platform
        case features
    }
}

enum SubscriptionTier: String, Codable {
    case free
    case premium
}

enum SubscriptionStatus: String, Codable {
    case active
    case cancelled
    case expired
    case trial
}

struct SubscriptionFeatures: Codable {
    let aiCoach: Bool
    let smartwatchSync: Bool
    let tournaments: Bool
    let advancedAnalytics: Bool
    let goalsSystem: Bool
    let performancePredictions: Bool
    
    enum CodingKeys: String, CodingKey {
        case aiCoach = "ai_coach"
        case smartwatchSync = "smartwatch_sync"
        case tournaments
        case advancedAnalytics = "advanced_analytics"
        case goalsSystem = "goals_system"
        case performancePredictions = "performance_predictions"
    }
}

// MARK: - Sport Goals

struct SportGoals: Codable, Identifiable {
    let id: String
    let userId: String
    let sport: String
    let skillFocus: [String]
    let physicalFocus: [String]
    let tacticalFocus: [String]
    let mentalFocus: [String]
    let customGoals: String?
    let improvementPriority: [String: Int]
    let createdAt: String
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sport
        case skillFocus = "skill_focus"
        case physicalFocus = "physical_focus"
        case tacticalFocus = "tactical_focus"
        case mentalFocus = "mental_focus"
        case customGoals = "custom_goals"
        case improvementPriority = "improvement_priority"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SkillOptions: Codable {
    let basketball: [String]
    let football: [String]
    let soccer: [String]
    let tennis: [String]
    let general: [String]
}

struct GoalsSurveyRequest: Codable {
    let sport: String
    let skillFocus: [String]
    let physicalFocus: [String]
    let tacticalFocus: [String]
    let mentalFocus: [String]
    let customGoals: String?
    let improvementPriority: [String: Int]
    
    enum CodingKeys: String, CodingKey {
        case sport
        case skillFocus = "skill_focus"
        case physicalFocus = "physical_focus"
        case tacticalFocus = "tactical_focus"
        case mentalFocus = "mental_focus"
        case customGoals = "custom_goals"
        case improvementPriority = "improvement_priority"
    }
}

// MARK: - Wearable Sync
// Canonical type definitions are in APIClient.swift
// BiometricDataRequest is unique to premium flows

struct BiometricDataRequest: Codable {
    let date: String
    let restingHeartRate: Int?
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let heartRateVariability: Int?
    let sleepDuration: Int?
    let deepSleep: Int?
    let remSleep: Int?
    let lightSleep: Int?
    let sleepQualityScore: Double?
    let steps: Int?
    let activeCalories: Int?
    let totalCalories: Int?
    let exerciseMinutes: Int?
    let recoveryScore: Double?
    let trainingStrain: Double?
    
    enum CodingKeys: String, CodingKey {
        case date
        case restingHeartRate = "resting_heart_rate"
        case avgHeartRate = "avg_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case heartRateVariability = "heart_rate_variability"
        case sleepDuration = "sleep_duration"
        case deepSleep = "deep_sleep"
        case remSleep = "rem_sleep"
        case lightSleep = "light_sleep"
        case sleepQualityScore = "sleep_quality_score"
        case steps
        case activeCalories = "active_calories"
        case totalCalories = "total_calories"
        case exerciseMinutes = "exercise_minutes"
        case recoveryScore = "recovery_score"
        case trainingStrain = "training_strain"
    }
}

// MARK: - Tournaments

struct Tournament: Codable, Identifiable {
    let id: String
    let creatorId: String
    let name: String
    let description: String?
    let sport: String
    let tournamentType: String
    let format: String
    let rankedType: String
    let maxParticipants: Int
    let teamSize: Int
    let minElo: Int?
    let maxElo: Int?
    let registrationOpens: String
    let registrationCloses: String
    let startsAt: String
    let endsAt: String?
    let status: String
    let currentRound: Int
    let participantCount: Int
    let isPublic: Bool
    let isSchool: Bool
    let isRegional: Bool
    let region: String?
    let schoolName: String?
    let prizes: [String: String]
    let createdAt: String
    /// Per-user registration status. Optional for backward compatibility with responses
    /// that predate the is_registered batch query addition.
    var isRegistered: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case creatorId = "creator_id"
        case name, description, sport
        case tournamentType = "tournament_type"
        case format
        case rankedType = "ranked_type"
        case maxParticipants = "max_participants"
        case teamSize = "team_size"
        case minElo = "min_elo"
        case maxElo = "max_elo"
        case registrationOpens = "registration_opens"
        case registrationCloses = "registration_closes"
        case startsAt = "start_date"
        case endsAt = "end_date"
        case status
        case currentRound = "current_round"
        case participantCount = "current_participants"
        case isPublic = "is_public"
        case isSchool = "is_school"
        case isRegional = "is_regional"
        case region
        case schoolName = "school_name"
        case prizes
        case createdAt = "created_at"
        case isRegistered = "is_registered"
    }
}

struct CreateTournamentRequest: Codable {
    let name: String
    let description: String?
    let sport: String
    let tournamentType: String
    let format: String
    let rankedType: String
    let maxParticipants: Int
    let teamSize: Int
    let minElo: Int?
    let maxElo: Int?
    let registrationOpens: String
    let registrationCloses: String
    let startsAt: String
    let isPublic: Bool
    let isSchool: Bool
    let isRegional: Bool
    let region: String?
    let schoolName: String?
    let prizes: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case name, description, sport
        case tournamentType = "tournament_type"
        case format
        case rankedType = "ranked_type"
        case maxParticipants = "max_participants"
        case teamSize = "team_size"
        case minElo = "min_elo"
        case maxElo = "max_elo"
        case registrationOpens = "registration_opens"
        case registrationCloses = "registration_closes"
        case startsAt = "starts_at"
        case isPublic = "is_public"
        case isSchool = "is_school"
        case isRegional = "is_regional"
        case region
        case schoolName = "school_name"
        case prizes
    }
}

struct TournamentParticipant: Codable, Identifiable {
    let id: String
    let tournamentId: String
    let userId: String?
    let teamId: String?
    let username: String?
    let teamName: String?
    let seed: Int?
    let placement: Int?
    let wins: Int
    let losses: Int
    let isEliminated: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case tournamentId = "tournament_id"
        case userId = "user_id"
        case teamId = "team_id"
        case username
        case teamName = "team_name"
        case seed, placement, wins, losses
        case isEliminated = "is_eliminated"
    }
}

struct TournamentMatch: Codable, Identifiable {
    let id: String
    let tournamentId: String
    let roundNumber: Int
    let matchNumber: Int
    let bracketPosition: String?
    let participant1Id: String?
    let participant2Id: String?
    let participant1Name: String?
    let participant2Name: String?
    let participant1Score: Int?
    let participant2Score: Int?
    let winnerId: String?
    let scheduledAt: String?
    let completedAt: String?
    let isComplete: Bool
    let isBye: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case tournamentId = "tournament_id"
        case roundNumber = "round_number"
        case matchNumber = "match_number"
        case bracketPosition = "bracket_position"
        case participant1Id = "participant1_id"
        case participant2Id = "participant2_id"
        case participant1Name = "participant1_name"
        case participant2Name = "participant2_name"
        case participant1Score = "participant1_score"
        case participant2Score = "participant2_score"
        case winnerId = "winner_id"
        case scheduledAt = "scheduled_at"
        case completedAt = "completed_at"
        case isComplete = "is_complete"
        case isBye = "is_bye"
    }
}

struct TournamentBracket: Codable {
    let tournamentId: String
    let format: String
    let currentRound: Int
    let totalRounds: Int
    let matches: [TournamentMatch]
    
    enum CodingKeys: String, CodingKey {
        case tournamentId = "tournament_id"
        case format
        case currentRound = "current_round"
        case totalRounds = "total_rounds"
        case matches
    }
}

// MARK: - AI Coach

struct AIInsight: Codable, Identifiable {
    let id: String
    let insightType: String
    let priority: String
    let title: String
    let message: String
    let details: [String: String]?
    let suggestedActions: [String]
    let drillsRecommended: [String]
    let confidence: Double
    let isRead: Bool
    let isDismissed: Bool
    let createdAt: String
    let expiresAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case insightType = "insight_type"
        case priority, title, message, details
        case suggestedActions = "suggested_actions"
        case drillsRecommended = "drills_recommended"
        case confidence
        case isRead = "is_read"
        case isDismissed = "is_dismissed"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

struct PerformancePrediction: Codable, Identifiable {
    let id: String
    let predictionType: String
    let performanceIndex: Double
    let readinessScore: Double
    let confidence: Double
    let factors: [String: Double]
    let predictionDate: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case predictionType = "prediction_type"
        case performanceIndex = "performance_index"
        case readinessScore = "readiness_score"
        case confidence, factors
        case predictionDate = "prediction_date"
    }
}

struct ReadinessScore: Codable {
    let sport: String
    let readinessScore: Double
    let status: String
    let recommendation: String
    let factors: [String: Double]
    
    enum CodingKeys: String, CodingKey {
        case sport
        case readinessScore = "readiness_score"
        case status, recommendation, factors
    }
}

struct TrainingPlan: Codable {
    let userId: String
    let sport: String
    let startDate: String
    let durationDays: Int
    let dailyPlans: [DailyTrainingPlan]
    let weeklyFocus: String
    let progressionStrategy: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case sport
        case startDate = "start_date"
        case durationDays = "duration_days"
        case dailyPlans = "daily_plans"
        case weeklyFocus = "weekly_focus"
        case progressionStrategy = "progression_strategy"
    }
}

struct DailyTrainingPlan: Codable, Identifiable {
    let id = UUID()
    let date: String
    let intensity: String
    let focusAreas: [String]
    let drills: [Drill]
    let durationMinutes: Int
    let notes: String
    
    enum CodingKeys: String, CodingKey {
        case date, intensity
        case focusAreas = "focus_areas"
        case drills
        case durationMinutes = "duration_minutes"
        case notes
    }
}

struct Drill: Codable, Identifiable {
    let id = UUID()
    let name: String
    let intensity: String
    let description: String
    let durationMinutes: Int?
    
    enum CodingKeys: String, CodingKey {
        case name, intensity, description
        case durationMinutes = "duration_minutes"
    }
}

// MARK: - Weekly Drills (Premium)

struct WeeklyDrillsPlan: Codable, Identifiable {
    let id: String
    let userId: String
    let sport: String
    let weekStartDate: String
    let weekEndDate: String
    let drills: [PersonalizedDrill]
    let weeklyFocus: String
    let personalizationContext: PersonalizationContext
    let generatedAt: String
    let isActive: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sport
        case weekStartDate = "week_start_date"
        case weekEndDate = "week_end_date"
        case drills
        case weeklyFocus = "weekly_focus"
        case personalizationContext = "personalization_context"
        case generatedAt = "generated_at"
        case isActive = "is_active"
    }
}

struct PersonalizedDrill: Codable, Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let difficulty: String
    let description: String
    let durationMinutes: Int
    let equipment: [String]
    let keyPoints: [String]
    let progressionTips: [String]
    let whyThisDrill: String
    
    enum CodingKeys: String, CodingKey {
        case name, category, difficulty, description
        case durationMinutes = "duration_minutes"
        case equipment
        case keyPoints = "key_points"
        case progressionTips = "progression_tips"
        case whyThisDrill = "why_this_drill"
    }
}

struct PersonalizationContext: Codable {
    let skillLevel: String
    let weakPoints: [String]
    let recentActivity: String?
    let goals: [String]
    let readinessScore: Double?
    
    enum CodingKeys: String, CodingKey {
        case skillLevel = "skill_level"
        case weakPoints = "weak_points"
        case recentActivity = "recent_activity"
        case goals
        case readinessScore = "readiness_score"
    }
}
