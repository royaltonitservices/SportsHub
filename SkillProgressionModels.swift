//
//  SkillProgressionModels.swift
//  SportsHub
//
//  Skill Progression Intelligence Engine
//  Tracks athlete skill development and provides intelligent training recommendations
//

import Foundation

// MARK: - Sport-Specific Skill Categories

enum SkillCategory: String, Codable, CaseIterable {
    // Basketball skills
    case shooting
    case ballHandling
    case finishing
    case passing
    case defense
    case conditioning
    
    // Soccer skills
    case dribbling
    case soccerPassing
    case soccerShooting
    case firstTouch
    case positioning
    case soccerConditioning
    
    // Tennis skills
    case serve
    case forehand
    case backhand
    case footwork
    case netPlay
    case endurance
    
    // Football skills
    case agility
    case catching
    case throwing
    case routeRunning
    case blocking
    case footballConditioning
    
    var displayName: String {
        switch self {
        case .shooting: return "Shooting"
        case .ballHandling: return "Ball Handling"
        case .finishing: return "Finishing"
        case .passing: return "Passing"
        case .defense: return "Defense"
        case .conditioning: return "Conditioning"
        case .dribbling: return "Dribbling"
        case .soccerPassing: return "Passing"
        case .soccerShooting: return "Shooting"
        case .firstTouch: return "First Touch"
        case .positioning: return "Positioning"
        case .soccerConditioning: return "Conditioning"
        case .serve: return "Serve"
        case .forehand: return "Forehand"
        case .backhand: return "Backhand"
        case .footwork: return "Footwork"
        case .netPlay: return "Net Play"
        case .endurance: return "Endurance"
        case .agility: return "Agility"
        case .catching: return "Catching"
        case .throwing: return "Throwing"
        case .routeRunning: return "Route Running"
        case .blocking: return "Blocking"
        case .footballConditioning: return "Conditioning"
        }
    }
    
    static func categoriesForSport(_ sport: Sport) -> [SkillCategory] {
        switch sport {
        case .basketball:
            return [.shooting, .ballHandling, .finishing, .passing, .defense, .conditioning]
        case .soccer:
            return [.dribbling, .soccerPassing, .soccerShooting, .firstTouch, .positioning, .soccerConditioning]
        case .tennis:
            return [.serve, .forehand, .backhand, .footwork, .netPlay, .endurance]
        case .football:
            return [.agility, .catching, .throwing, .routeRunning, .blocking, .footballConditioning]
        }
    }
}

// MARK: - Skill Score

struct SkillScore: Codable, Identifiable {
    var id: String { category.rawValue }
    let category: SkillCategory
    var score: Double // 0-100
    var trend: SkillTrend
    var lastUpdated: Date
    var dataPoints: Int // Number of contributing events
    
    init(category: SkillCategory, score: Double = 50.0) {
        self.category = category
        self.score = score
        self.trend = .stable
        self.lastUpdated = Date()
        self.dataPoints = 0
    }
}

enum SkillTrend: String, Codable {
    case improving
    case stable
    case declining
    
    var displayName: String {
        switch self {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .declining: return "Declining"
        }
    }
    
    var icon: String {
        switch self {
        case .improving: return "arrow.up.circle.fill"
        case .stable: return "minus.circle.fill"
        case .declining: return "arrow.down.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .improving: return "green"
        case .stable: return "orange"
        case .declining: return "red"
        }
    }
}

// MARK: - Skill Profile

struct SkillProfile {
    let sport: Sport
    var skills: [SkillScore]
    var weakestSkill: SkillCategory?
    var strongestSkill: SkillCategory?
    var lastAnalyzed: Date
    
    init(sport: Sport) {
        self.sport = sport
        self.skills = SkillCategory.categoriesForSport(sport).map { SkillScore(category: $0) }
        self.lastAnalyzed = Date()
        self.weakestSkill = nil
        self.strongestSkill = nil
    }
    
    mutating func updateAnalysis() {
        // Find weakest and strongest skills
        if let weakest = skills.min(by: { $0.score < $1.score }) {
            weakestSkill = weakest.category
        }
        if let strongest = skills.max(by: { $0.score < $1.score }) {
            strongestSkill = strongest.category
        }
        lastAnalyzed = Date()
    }
    
    func skill(for category: SkillCategory) -> SkillScore? {
        return skills.first { $0.category == category }
    }
    
    mutating func updateSkill(category: SkillCategory, newScore: Double) {
        if let index = skills.firstIndex(where: { $0.category == category }) {
            skills[index].score = min(100, max(0, newScore))
            skills[index].lastUpdated = Date()
            skills[index].dataPoints += 1
        }
    }
}

// Custom Codable implementation
extension SkillProfile: Codable {
    enum CodingKeys: String, CodingKey {
        case sport, skills, weakestSkill, strongestSkill, lastAnalyzed
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sportString = try container.decode(String.self, forKey: .sport)
        self.sport = Sport(rawValue: sportString) ?? .basketball
        self.skills = try container.decode([SkillScore].self, forKey: .skills)
        self.weakestSkill = try container.decodeIfPresent(SkillCategory.self, forKey: .weakestSkill)
        self.strongestSkill = try container.decodeIfPresent(SkillCategory.self, forKey: .strongestSkill)
        self.lastAnalyzed = try container.decode(Date.self, forKey: .lastAnalyzed)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sport.rawValue, forKey: .sport)
        try container.encode(skills, forKey: .skills)
        try container.encodeIfPresent(weakestSkill, forKey: .weakestSkill)
        try container.encodeIfPresent(strongestSkill, forKey: .strongestSkill)
        try container.encode(lastAnalyzed, forKey: .lastAnalyzed)
    }
}

// MARK: - Skill Event (Data Collection)

struct SkillEvent {
    let id: String
    let userId: String
    let sport: Sport
    let category: SkillCategory
    let eventType: SkillEventType
    let performance: Double // 0-100 performance rating
    let timestamp: Date
    let metadata: [String: String]?
    
    init(userId: String, sport: Sport, category: SkillCategory, eventType: SkillEventType, performance: Double, metadata: [String: String]? = nil) {
        self.id = UUID().uuidString
        self.userId = userId
        self.sport = sport
        self.category = category
        self.eventType = eventType
        self.performance = performance
        self.timestamp = Date()
        self.metadata = metadata
    }
}

// Custom Codable implementation
extension SkillEvent: Codable {
    enum CodingKeys: String, CodingKey {
        case id, userId, sport, category, eventType, performance, timestamp, metadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.userId = try container.decode(String.self, forKey: .userId)
        let sportString = try container.decode(String.self, forKey: .sport)
        self.sport = Sport(rawValue: sportString) ?? .basketball
        self.category = try container.decode(SkillCategory.self, forKey: .category)
        self.eventType = try container.decode(SkillEventType.self, forKey: .eventType)
        self.performance = try container.decode(Double.self, forKey: .performance)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(sport.rawValue, forKey: .sport)
        try container.encode(category, forKey: .category)
        try container.encode(eventType, forKey: .eventType)
        try container.encode(performance, forKey: .performance)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

enum SkillEventType: String, Codable {
    case drillCompletion
    case challengeSuccess
    case challengeFailure
    case matchWin
    case matchLoss
    case trainingSession
    case userSubmittedStats
}

// MARK: - Skill Progression Analysis

struct SkillProgressionAnalysis {
    let timeframe: AnalysisTimeframe
    let improvingSkills: [SkillCategory]
    let stagnatingSkills: [SkillCategory]
    let decliningSkills: [SkillCategory]
    let overallTrend: String
    let recommendations: [String]
    
    enum AnalysisTimeframe: String {
        case weekly = "7 days"
        case monthly = "30 days"
        case seasonal = "90 days"
    }
}

// MARK: - AI Training Recommendation

struct AITrainingRecommendation: Identifiable {
    let id = UUID()
    let targetSkill: SkillCategory
    let reason: String
    let suggestedDrills: [String]
    let priority: RecommendationPriority
    let estimatedImpact: String
    
    enum RecommendationPriority: Int {
        case low = 1
        case medium = 2
        case high = 3
        case critical = 4
        
        var displayName: String {
            switch self {
            case .low: return "Low Priority"
            case .medium: return "Medium Priority"
            case .high: return "High Priority"
            case .critical: return "Critical"
            }
        }
        
        var color: String {
            switch self {
            case .low: return "gray"
            case .medium: return "orange"
            case .high: return "red"
            case .critical: return "purple"
            }
        }
    }
}

// MARK: - Skill Feedback Message

struct SkillFeedbackMessage: Identifiable {
    let id = UUID()
    let message: String
    let category: SkillCategory?
    let isPositive: Bool
    let timestamp: Date
    
    init(message: String, category: SkillCategory? = nil, isPositive: Bool = true) {
        self.message = message
        self.category = category
        self.isPositive = isPositive
        self.timestamp = Date()
    }
}
