// Premium API Client Extensions
// Network calls for all Premium features

import Foundation

extension APIClient {
    
    // MARK: - Goals Survey
    
    func getSkillOptions() async throws -> SkillOptions {
        return try await get("/goals/skill-options")
    }
    
    func submitGoalsSurvey(request: GoalsSurveyRequest) async throws -> SportGoals {
        return try await post("/goals/survey", body: request)
    }
    
    func getGoalsSurvey(sport: String) async throws -> SportGoals {
        return try await get("/goals/survey/\(sport)")
    }
    
    func getAllGoals() async throws -> [SportGoals] {
        return try await get("/goals/all")
    }
    
    func deleteGoalsSurvey(sport: String) async throws -> MessageResponse {
        return try await delete("/goals/survey/\(sport)")
    }
    
    // MARK: - Smartwatch Sync
    
    func connectSmartwatch(request: ConnectDeviceRequest) async throws -> SmartwatchConnection {
        return try await post("/smartwatch/connect", body: request)
    }
    
    func getSmartwatchConnection() async throws -> SmartwatchConnection {
        return try await get("/smartwatch/connection")
    }
    
    func disconnectSmartwatch() async throws -> MessageResponse {
        return try await delete("/smartwatch/disconnect")
    }
    
    func syncBiometricData(data: BiometricData) async throws -> BiometricData {
        return try await post("/smartwatch/sync", body: data)
    }
    
    func getRecentBiometricData(days: Int = 7) async throws -> [BiometricData] {
        return try await get("/smartwatch/data/recent?days=\(days)")
    }
    
    func getRecoveryStatus() async throws -> RecoveryStatus {
        return try await get("/smartwatch/recovery-status")
    }
    
    // MARK: - Tournaments
    
    func listTournaments(
        sport: String? = nil,
        status: String? = nil,
        tournamentType: String? = nil,
        isSchool: Bool? = nil,
        isRegional: Bool? = nil,
        region: String? = nil,
        skip: Int = 0,
        limit: Int = 20
    ) async throws -> [Tournament] {
        var queryParams: [String] = []
        
        if let sport = sport {
            queryParams.append("sport=\(sport)")
        }
        if let status = status {
            queryParams.append("status=\(status)")
        }
        if let tournamentType = tournamentType {
            queryParams.append("tournament_type=\(tournamentType)")
        }
        if let isSchool = isSchool {
            queryParams.append("is_school=\(isSchool)")
        }
        if let isRegional = isRegional {
            queryParams.append("is_regional=\(isRegional)")
        }
        if let region = region {
            queryParams.append("region=\(region)")
        }
        queryParams.append("skip=\(skip)")
        queryParams.append("limit=\(limit)")
        
        let query = queryParams.isEmpty ? "" : "?" + queryParams.joined(separator: "&")
        return try await get("/tournaments\(query)")
    }
    
    func getTournament(id: String) async throws -> Tournament {
        return try await get("/tournaments/\(id)")
    }
    
    func createTournament(request: CreateTournamentRequest) async throws -> Tournament {
        return try await post("/tournaments/create", body: request)
    }
    
    func registerForTournament(tournamentId: String, teamId: String? = nil) async throws -> TournamentParticipant {
        struct RegisterRequest: Codable {
            let teamId: String?
            
            enum CodingKeys: String, CodingKey {
                case teamId = "team_id"
            }
        }
        
        let request = RegisterRequest(teamId: teamId)
        return try await post("/tournaments/\(tournamentId)/register", body: request)
    }
    
    func unregisterFromTournament(tournamentId: String) async throws -> MessageResponse {
        return try await delete("/tournaments/\(tournamentId)/unregister")
    }
    
    func generateBracket(tournamentId: String) async throws -> MessageResponse {
        return try await post("/tournaments/\(tournamentId)/generate-bracket", body: EmptyRequest())
    }
    
    func getTournamentBracket(tournamentId: String) async throws -> TournamentBracket {
        return try await get("/tournaments/\(tournamentId)/bracket")
    }
    
    func submitMatchResult(
        tournamentId: String,
        matchId: String,
        participant1Score: Int,
        participant2Score: Int,
        winnerId: String
    ) async throws -> MessageResponse {
        struct SubmitMatchRequest: Codable {
            let participant1Score: Int
            let participant2Score: Int
            let winnerId: String
            
            enum CodingKeys: String, CodingKey {
                case participant1Score = "participant1_score"
                case participant2Score = "participant2_score"
                case winnerId = "winner_id"
            }
        }
        
        let request = SubmitMatchRequest(
            participant1Score: participant1Score,
            participant2Score: participant2Score,
            winnerId: winnerId
        )
        return try await post("/tournaments/\(tournamentId)/matches/\(matchId)/submit", body: request)
    }
    
    func getTournamentStandings(tournamentId: String) async throws -> [TournamentParticipant] {
        return try await get("/tournaments/\(tournamentId)/standings")
    }
    
    // MARK: - AI Coach
    
    func getDailyInsights(sport: String) async throws -> [AIInsight] {
        return try await get("/ai-coach/insights?sport=\(sport)")
    }
    
    func getUnreadInsights() async throws -> [AIInsight] {
        return try await get("/ai-coach/insights/unread")
    }
    
    func markInsightRead(insightId: String) async throws -> MessageResponse {
        return try await post("/ai-coach/insights/\(insightId)/read", body: EmptyRequest())
    }
    
    func dismissInsight(insightId: String) async throws -> MessageResponse {
        return try await post("/ai-coach/insights/\(insightId)/dismiss", body: EmptyRequest())
    }
    
    func getMatchReadiness(sport: String) async throws -> ReadinessScore {
        return try await get("/ai-coach/readiness?sport=\(sport)")
    }
    
    func predictPerformance(sport: String, opponentElo: Int) async throws -> PerformancePrediction {
        return try await get("/ai-coach/predict?sport=\(sport)&opponent_elo=\(opponentElo)")
    }
    
    func getPredictionHistory(sport: String? = nil, limit: Int = 10) async throws -> [PerformancePrediction] {
        var query = "?limit=\(limit)"
        if let sport = sport {
            query += "&sport=\(sport)"
        }
        return try await get("/ai-coach/predictions/history\(query)")
    }
    
    func getTrainingPlan(sport: String, durationDays: Int = 7) async throws -> TrainingPlan {
        return try await get("/ai-coach/training-plan?sport=\(sport)&duration_days=\(durationDays)")
    }
    
    func getRecommendedDrills(sport: String, limit: Int = 5) async throws -> [Drill] {
        return try await get("/ai-coach/drills?sport=\(sport)&limit=\(limit)")
    }
}

// Helper struct for empty POST/DELETE requests
private struct EmptyRequest: Codable {}
