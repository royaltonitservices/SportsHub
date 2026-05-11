//
//  APIModels.swift
//  SportsHub
//
//  API response models matching backend schemas
//

import Foundation

// MARK: - Auth Models
struct LoginResponse: Codable {
    let accessToken: String
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
    }
}

struct SignupRequest: Codable {
    let email: String
    let username: String
    let password: String
    let displayName: String
    let dateOfBirth: String
    let parentEmail: String?
    
    enum CodingKeys: String, CodingKey {
        case email, username, password
        case displayName = "display_name"
        case dateOfBirth = "date_of_birth"
        case parentEmail = "parent_email"
    }
}

struct UserResponse: Codable {
    let id: String
    let email: String
    let username: String
    let displayName: String
    let fullName: String?
    let isAdmin: Bool
    let createdAt: String
    let emailVerified: Bool
    let surveyCompleted: Bool
    let isLegacyAccount: Bool

    enum CodingKeys: String, CodingKey {
        case id, email, username
        case displayName = "display_name"
        case fullName = "full_name"
        case isAdmin = "is_admin"
        case createdAt = "created_at"
        case emailVerified = "email_verified"
        case surveyCompleted = "survey_completed"
        case isLegacyAccount = "is_legacy_account"
    }
}

struct UsernameAvailabilityResponse: Codable {
    let available: Bool
}

struct EmptyResponse: Codable {
    // Used for endpoints that return no data (just success/failure)
}

// MARK: - Sport Profile Models
struct SportProfileResponse: Codable {
    let id: String
    let userId: String
    let sport: String
    let rating: Int
    let gamesPlayed: Int
    let wins: Int
    let losses: Int
    let winStreak: Int
    let highestRating: Int
    let rankTier: String
    let isProvisional: Bool
    let provisionalGames: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sport, rating
        case gamesPlayed = "games_played"
        case wins, losses
        case winStreak = "win_streak"
        case highestRating = "highest_rating"
        case rankTier = "rank_tier"
        case isProvisional = "is_provisional"
        case provisionalGames = "provisional_games"
    }
    
    var winRate: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(wins) / Double(gamesPlayed) * 100
    }
}

// MARK: - Matchmaking Models
struct OpponentResponse: Codable {
    let userId: String
    let username: String
    let fullName: String
    let rating: Int
    let gamesPlayed: Int
    let wins: Int
    let losses: Int
    let rankTier: String
    let matchQuality: String?
    let availableNow: Bool?
    let lastActive: String?
    let trustScore: Double?
    let completionRate: Double?
    let matchesCompleted: Int?
    let trustTier: String?  // Phase 4: "trusted", "standard", "caution", "restricted"
    let disputeRate: Double?  // Phase 4: Percentage of matches disputed

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case fullName = "full_name"
        case rating
        case gamesPlayed = "games_played"
        case wins, losses
        case rankTier = "rank_tier"
        case matchQuality = "match_quality"
        case availableNow = "available_now"
        case lastActive = "last_active"
        case trustScore = "trust_score"
        case completionRate = "completion_rate"
        case matchesCompleted = "matches_completed"
        case trustTier = "trust_tier"
        case disputeRate = "dispute_rate"
    }

    var winRate: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(wins) / Double(gamesPlayed) * 100
    }
}

// MARK: - Leaderboard Models
struct LeaderboardEntry: Codable {
    let rank: Int
    let userId: String
    let username: String
    let fullName: String
    let rating: Int
    let gamesPlayed: Int
    let wins: Int
    let losses: Int
    let rankTier: String
    
    enum CodingKeys: String, CodingKey {
        case rank
        case userId = "user_id"
        case username
        case fullName = "full_name"
        case rating
        case gamesPlayed = "games_played"
        case wins, losses
        case rankTier = "rank_tier"
    }
}

// MARK: - Challenge Models
struct CreateChallengeRequest: Codable {
    let opponentId: String
    let sport: String
    /// Must be "ranked" or "unranked" — the only values the backend MatchType enum accepts.
    let matchType: String

    enum CodingKeys: String, CodingKey {
        case opponentId = "opponent_id"
        case sport
        case matchType = "match_type"
    }
}

struct ChallengeResponse: Codable, Identifiable {
    let id: String
    let challengerId: String
    let opponentId: String
    let sport: String
    let matchType: String
    let status: String
    let createdAt: String

    // Phase 3: Submission tracking
    let challengerSubmittedScore: String?  // Format: "21-18" or null
    let opponentSubmittedScore: String?    // Format: "21-18" or null
    let acceptedAt: String?
    let completedAt: String?

    let winnerUserId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case challengerId = "challenger_id"
        case opponentId = "opponent_id"
        case sport
        case matchType = "match_type"
        case status
        case createdAt = "created_at"
        case challengerSubmittedScore = "challenger_submitted_score"
        case opponentSubmittedScore = "opponent_submitted_score"
        case acceptedAt = "accepted_at"
        case completedAt = "completed_at"
        case winnerUserId = "winner_user_id"
    }
}

struct SubmitResultRequest: Codable {
    let score: Int
    let opponentScore: Int
    
    enum CodingKeys: String, CodingKey {
        case score
        case opponentScore = "opponent_score"
    }
}

struct SubmitMatchResultRequest: Codable {
    let challengeId: String
    let winnerId: String
    let scoreData: String?

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case winnerId = "winner_id"
        case scoreData = "score_data"
    }
}

// MARK: - Dispute Models (Phase 3)
struct DisputeResponse: Codable, Identifiable {
    let id: String
    let challengeId: String
    let initiatorId: String
    let reason: String
    let status: String  // "pending", "under_review", "resolved", "rejected"
    let adminNotes: String?
    let createdAt: String
    let resolvedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case challengeId = "challenge_id"
        case initiatorId = "initiator_id"
        case reason, status
        case adminNotes = "admin_notes"
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
    }
}

struct CreateDisputeRequest: Codable {
    let challengeId: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case reason
    }
}

// MARK: - Phase 4 Evidence Models
struct EvidenceRequirementResponse: Codable {
    let challengeId: String
    let requirement: String  // "optional", "recommended", "required"
    let reason: String
    let isDisputed: Bool
    let userTrustTier: String
    let opponentTrustTier: String

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case requirement, reason
        case isDisputed = "is_disputed"
        case userTrustTier = "user_trust_tier"
        case opponentTrustTier = "opponent_trust_tier"
    }
}

struct EvidenceUploadResponse: Codable {
    let message: String
    let evidenceId: String
    let wasRequired: Bool
    let status: String

    enum CodingKeys: String, CodingKey {
        case message
        case evidenceId = "evidence_id"
        case wasRequired = "was_required"
        case status
    }
}

struct EvidenceResponse: Codable, Identifiable {
    let id: String
    let challengeId: String
    let submitterId: String
    let evidenceType: String
    let fileUrl: String
    let thumbnailUrl: String?
    let description: String?
    let status: String
    let isRequired: Bool
    let reviewNotes: String?
    let createdAt: String
    let reviewedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case challengeId = "challenge_id"
        case submitterId = "submitter_id"
        case evidenceType = "evidence_type"
        case fileUrl = "file_url"
        case thumbnailUrl = "thumbnail_url"
        case description, status
        case isRequired = "is_required"
        case reviewNotes = "review_notes"
        case createdAt = "created_at"
        case reviewedAt = "reviewed_at"
    }
}

// MARK: - Friends Models
struct FriendshipResponse: Codable, Identifiable {
    let id: String
    let userAId: String
    let userBId: String
    let status: String  // pending, accepted, blocked, declined
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userAId = "user_a_id"
        case userBId = "user_b_id"
        case status
        case createdAt = "created_at"
    }
}

struct FriendStatusResponse: Codable {
    let status: String  // none, pending, accepted, blocked, declined
    let isFriend: Bool
    let isPending: Bool
    let isBlocked: Bool
    let initiatedByMe: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case isFriend = "is_friend"
        case isPending = "is_pending"
        case isBlocked = "is_blocked"
        case initiatedByMe = "initiated_by_me"
    }
}

struct FriendRequest: Codable {
    let targetUserId: String

    enum CodingKeys: String, CodingKey {
        case targetUserId = "target_user_id"
    }
}

// MARK: - Messages Models
struct DirectMessageResponse: Codable, Identifiable {
    let id: String
    let senderId: String
    let receiverId: String
    let content: String
    let sentAt: String
    let readAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case receiverId = "receiver_id"
        case content
        case sentAt = "sent_at"
        case readAt = "read_at"
    }
}

struct MessageCreateRequest: Codable {
    let receiverId: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case receiverId = "receiver_id"
        case content
    }
}

struct ConversationPreview: Codable, Identifiable {
    let friendId: String
    let friendUsername: String
    let friendDisplayName: String
    let friendAvatarSeed: String?
    let lastMessage: String
    let lastMessageTime: String
    let unreadCount: Int

    var id: String { friendId }

    enum CodingKeys: String, CodingKey {
        case friendId = "friend_id"
        case friendUsername = "friend_username"
        case friendDisplayName = "friend_display_name"
        case friendAvatarSeed = "friend_avatar_seed"
        case lastMessage = "last_message"
        case lastMessageTime = "last_message_time"
        case unreadCount = "unread_count"
    }
}

// MARK: - Posts Models
struct PostResponse: Codable, Identifiable {
    let id: String
    let userId: String
    let username: String
    let content: String
    let sport: String?
    var likesCount: Int
    var commentsCount: Int
    let createdAt: String
    var isLiked: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case username, content, sport
        case likesCount = "likes_count"
        case commentsCount = "comments_count"
        case createdAt = "created_at"
        case isLiked = "is_liked"
    }
}

struct CreatePostRequest: Codable {
    let content: String
    let sport: String?
}

// MARK: - Comments Models
struct CommentResponse: Codable, Identifiable {
    let id: String
    let postId: String
    let authorId: String
    let content: String
    let parentCommentId: String?
    let likesCount: Int
    let createdAt: String
    
    // Populated by client
    var authorUsername: String?
    var replies: [CommentResponse]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case authorId = "author_id"
        case content
        case parentCommentId = "parent_comment_id"
        case likesCount = "likes_count"
        case createdAt = "created_at"
    }
}

struct CreateCommentRequest: Codable {
    let postId: String
    let content: String
    let parentCommentId: String?
    
    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case content
        case parentCommentId = "parent_comment_id"
    }
}

// MARK: - Clips Models
struct ClipResponse: Codable, Identifiable {
    let id: String
    let userId: String
    let username: String
    let title: String
    let description: String?
    let sport: String
    let videoUrl: String?  // nullable — seeded records and fresh uploads before backend processes them may have null
    let thumbnailUrl: String?
    let viewsCount: Int
    let likesCount: Int
    let createdAt: String
    let isLiked: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case username, title, description, sport
        case videoUrl = "video_url"
        case thumbnailUrl = "thumbnail_url"
        case viewsCount = "views_count"
        case likesCount = "likes_count"
        case createdAt = "created_at"
        case isLiked = "is_liked"
    }
}

struct CreateClipRequest: Codable {
    let title: String
    let description: String?
    let sport: String
    let videoUrl: String
    let thumbnailUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case title, description, sport
        case videoUrl = "video_url"
        case thumbnailUrl = "thumbnail_url"
    }
}

// MARK: - Trust Score
struct TrustScoreResponse: Codable {
    let trustScore: Double
    let trustTier: String
    let matchesPlayed: Int
    let disputesWon: Int
    let disputesLost: Int

    enum CodingKeys: String, CodingKey {
        case trustScore = "trust_score"
        case trustTier = "trust_tier"
        case matchesPlayed = "matches_played"
        case disputesWon = "disputes_won"
        case disputesLost = "disputes_lost"
    }
}

// MARK: - Activity Models
struct ActivityItem: Codable {
    let type: String
    let userId: String
    let username: String
    let sport: String
    let matchType: String?
    let opponentUsername: String?
    let winnerUsername: String?
    let userScore: Int?
    let opponentScore: Int?
    let ratingChange: Int?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case userId = "user_id"
        case username, sport
        case matchType = "match_type"
        case opponentUsername = "opponent_username"
        case winnerUsername = "winner_username"
        case userScore = "user_score"
        case opponentScore = "opponent_score"
        case ratingChange = "rating_change"
        case createdAt = "created_at"
    }
}

// MARK: - Badge Models
struct BadgeResponse: Codable {
    let id: String
    let name: String
    let description: String
    let category: String
    let rarity: String
    let icon: String
    let requirement: BadgeRequirement
    let isEarned: Bool
    let progress: Int
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, category, rarity, icon, requirement
        case isEarned = "is_earned"
        case progress
    }
}

struct BadgeRequirement: Codable {
    let type: String
    let value: Int
}

struct UserBadgeResponse: Codable {
    let badgeId: String
    let name: String
    let description: String
    let category: String
    let rarity: String
    let icon: String
    let sport: String
    let earnedAt: String
    
    enum CodingKeys: String, CodingKey {
        case badgeId = "badge_id"
        case name, description, category, rarity, icon, sport
        case earnedAt = "earned_at"
    }
}

// MARK: - Highlight API Models
struct HighlightResponse: Codable {
    let id: String
    let userId: String
    let mediaUrl: String
    let thumbnailUrl: String?
    let caption: String?
    let sport: String?
    let createdAt: String
    let expiresAt: String
    let viewsCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case mediaUrl = "media_url"
        case thumbnailUrl = "thumbnail_url"
        case caption, sport
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case viewsCount = "views_count"
    }
}

// MARK: - Open Team Response
struct OpenTeamResponse: Codable, Identifiable {
    let id: String
    let name: String
    let sport: String
    let captainId: String
    let captainUsername: String
    let rating: Int
    let gamesPlayed: Int
    let wins: Int
    let losses: Int
    let memberCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, sport
        case captainId = "captain_id"
        case captainUsername = "captain_username"
        case rating
        case gamesPlayed = "games_played"
        case wins, losses
        case memberCount = "member_count"
    }
}

// MARK: - Team Models
struct TeamResponse: Codable, Identifiable {
    let id: String
    let name: String
    let sport: String
    let captainId: String
    let rating: Int
    let gamesPlayed: Int
    let wins: Int
    let losses: Int
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, sport
        case captainId = "captain_id"
        case rating
        case gamesPlayed = "games_played"
        case wins, losses
        case createdAt = "created_at"
    }
}

// MARK: - Generic Response
struct MessageResponse: Codable {
    let message: String
}

// MARK: - Premium Subscription Models
struct SubscriptionStatusResponse: Codable {
    let hasPremium: Bool
    let tier: String
    let status: String?
    let expiresAt: String?
    let features: [String: Bool]
    
    enum CodingKeys: String, CodingKey {
        case hasPremium = "has_premium"
        case tier, status
        case expiresAt = "expires_at"
        case features
    }
}

// MARK: - Training API Models

struct APIDrillResponse: Codable, Identifiable {
    let id: String
    let name: String
    let category: String
    let difficulty: String
    let durationMinutes: Int
    let equipment: [String]
    let description: String
    let focusAreas: [String]
    let instructions: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, category, difficulty, description, equipment, instructions
        case durationMinutes = "duration_minutes"
        case focusAreas = "focus_areas"
    }
}

struct DrillCategoriesResponse: Codable {
    let sport: String
    let categories: [String]
}

struct DrillLogEntryRequest: Codable {
    let drillName: String
    let drillOrder: Int
    let duration: Int
    let effort: String?
    let metricType: String?
    let metricValue: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case duration, effort, notes
        case drillName = "drill_name"
        case drillOrder = "drill_order"
        case metricType = "metric_type"
        case metricValue = "metric_value"
    }
}

struct LogSessionRequest: Codable {
    let sport: String
    let drills: [DrillLogEntryRequest]
    let notes: String?
    let aiPerformanceRating: Double?
    let aiInsights: [String]?
    let aiAreasToImprove: [String]?
    let aiNextSessionRecs: [String]?

    enum CodingKeys: String, CodingKey {
        case sport, drills, notes
        case aiPerformanceRating = "ai_performance_rating"
        case aiInsights = "ai_insights"
        case aiAreasToImprove = "ai_areas_to_improve"
        case aiNextSessionRecs = "ai_next_session_recs"
    }
}

struct DrillLogEntryResponse: Codable, Identifiable {
    let id: String
    let drillName: String
    let drillOrder: Int
    let duration: Int
    let effort: String?
    let metricType: String?
    let metricValue: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, duration, effort, notes
        case drillName = "drill_name"
        case drillOrder = "drill_order"
        case metricType = "metric_type"
        case metricValue = "metric_value"
    }
}

struct TrainingSessionResponse: Codable, Identifiable {
    let id: String
    let sport: String
    let totalDuration: Int
    let notes: String?
    let effortRating: Double?
    let aiPerformanceRating: Double?
    let aiInsights: [String]?
    let aiAreasToImprove: [String]?
    let aiNextSessionRecs: [String]?
    let drills: [DrillLogEntryResponse]
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, sport, notes, drills
        case totalDuration = "total_duration"
        case effortRating = "effort_rating"
        case aiPerformanceRating = "ai_performance_rating"
        case aiInsights = "ai_insights"
        case aiAreasToImprove = "ai_areas_to_improve"
        case aiNextSessionRecs = "ai_next_session_recs"
        case createdAt = "created_at"
    }
}

struct SaveWorkoutRequest: Codable {
    let sport: String
    let name: String
    let description: String?
    let estimatedDuration: Int?
    let difficulty: String?
    let focusAreas: [String]?
    let drills: [[String: String]]

    enum CodingKeys: String, CodingKey {
        case sport, name, description, difficulty, drills
        case estimatedDuration = "estimated_duration"
        case focusAreas = "focus_areas"
    }
}

struct SavedWorkoutResponse: Codable, Identifiable {
    let id: String
    let sport: String
    let name: String
    let description: String?
    let estimatedDuration: Int?
    let difficulty: String?
    let focusAreas: [String]
    let drills: [[String: String]]
    let timesUsed: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, sport, name, description, difficulty, drills
        case estimatedDuration = "estimated_duration"
        case focusAreas = "focus_areas"
        case timesUsed = "times_used"
        case createdAt = "created_at"
    }
}

// MARK: - Skill Progression Sync Models

struct SkillScorePayload: Codable {
    let category: String
    let score: Double
    let trend: String
    let lastUpdated: String?
    let dataPoints: Int

    enum CodingKeys: String, CodingKey {
        case category, score, trend
        case lastUpdated = "last_updated"
        case dataPoints = "data_points"
    }
}

struct SkillSnapshotResponse: Codable {
    let sport: String
    let skills: [SkillScorePayload]
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case sport, skills
        case updatedAt = "updated_at"
    }
}

// MARK: - Tennis Court Models
struct TennisCourt: Codable, Identifiable {
    let id: String
    let name: String
    let address: String
    let city: String
    let state: String
    let postalCode: String?
    let latitude: Double
    let longitude: Double
    
    // Venue access information
    let venueType: String
    let requiresReservation: Bool
    let requiresMembership: Bool
    let hourlyRate: Double?
    let currency: String?
    
    // Court details
    let surfaceType: String?
    let numCourts: Int
    let hasLights: Bool
    let indoor: Bool
    
    // Contact and availability
    let phone: String?
    let website: String?
    let hoursOfOperation: String?
    
    // Metadata
    let createdAt: String
    let isVerified: Bool
    let addedBy: String?
    
    // Optional distance field (populated by nearby search)
    let distanceMiles: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, name, address, city, state
        case postalCode = "postal_code"
        case latitude, longitude
        case venueType = "venue_type"
        case requiresReservation = "requires_reservation"
        case requiresMembership = "requires_membership"
        case hourlyRate = "hourly_rate"
        case currency
        case surfaceType = "surface_type"
        case numCourts = "num_courts"
        case hasLights = "has_lights"
        case indoor, phone, website
        case hoursOfOperation = "hours_of_operation"
        case createdAt = "created_at"
        case isVerified = "is_verified"
        case addedBy = "added_by"
        case distanceMiles = "distance_miles"
    }
}


// MARK: - Email Verification Models

struct SendCodeResponse: Codable {
    let message: String
    let email: String  // Masked email shown to user
}

struct VerifyCodeRequest: Codable {
    let code: String
}

// MARK: - Onboarding Survey Models

struct OnboardingSurveyRequest: Codable {
    let mainSport: String
    /// Skill ratings: {"shooting": 7, "dribbling": 5} — keys are sport-specific
    let skillRatings: [String: Int]
    let strengths: [String]
    let weaknesses: [String]
    /// Athlete training goals — e.g. ["make varsity", "improve athleticism"]
    let goals: [String]
    let onboardingVersion: Int

    enum CodingKeys: String, CodingKey {
        case mainSport = "main_sport"
        case skillRatings = "skill_ratings"
        case strengths
        case weaknesses
        case goals
        case onboardingVersion = "onboarding_version"
    }
}

struct OnboardingSurveyResponse: Codable {
    let id: String
    let userId: String
    let mainSport: String
    let skillRatings: [String: Int]
    let strengths: [String]
    let weaknesses: [String]
    /// Athlete training goals — empty array for surveys created before Phase 13
    let goals: [String]
    let onboardingVersion: Int
    let createdAt: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case mainSport = "main_sport"
        case skillRatings = "skill_ratings"
        case strengths
        case weaknesses
        case goals
        case onboardingVersion = "onboarding_version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

