//
//  APIClient.swift
//  SportsHub
//
//  Production-quality API networking layer for backend communication
//  Robust error handling, clear HTTP status distinction, safe credential handling
//

import Foundation

// MARK: - API Configuration
struct APIConfig {
    static let baseURL = "http://localhost:8000"
    static let timeout: TimeInterval = 30.0
    
    /// Whether to enable debug logging (disable in production)
    #if DEBUG
    static let enableDebugLogging = true
    #else
    static let enableDebugLogging = false
    #endif
}

// MARK: - API Error
enum APIError: Error, LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case unauthorized              // 401
    case forbidden                 // 403
    case notFound                  // 404
    case conflict                  // 409 (e.g., username taken)
    case unprocessableEntity       // 422 (validation error)
    case serverError(String)       // 4xx/5xx with message
    case decodingError(String)     // JSON decoding failed
    case malformedResponse         // Couldn't parse error body
    
    // Network-level errors (transport layer)
    case noConnection              // Offline
    case timeout                   // Request timed out
    case cannotConnectToHost       // Server unreachable
    case dnsLookupFailed           // Cannot resolve hostname
    case networkError(String)      // Other network errors
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL configuration"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized - please log in again"
        case .forbidden:
            return "Access forbidden"
        case .notFound:
            return "Resource not found"
        case .conflict:
            return "Conflict - resource already exists"
        case .unprocessableEntity:
            return "Invalid request data"
        case .serverError(let message):
            return message
        case .decodingError(let detail):
            return "Failed to decode response: \(detail)"
        case .malformedResponse:
            return "Server returned malformed response"
        case .noConnection:
            return "No internet connection"
        case .timeout:
            return "Request timed out"
        case .cannotConnectToHost:
            return "Cannot connect to server"
        case .dnsLookupFailed:
            return "Cannot resolve server address"
        case .networkError(let detail):
            return "Network error: \(detail)"
        }
    }
    
    // Equatable conformance
    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL),
             (.invalidResponse, .invalidResponse),
             (.unauthorized, .unauthorized),
             (.forbidden, .forbidden),
             (.notFound, .notFound),
             (.conflict, .conflict),
             (.unprocessableEntity, .unprocessableEntity),
             (.malformedResponse, .malformedResponse),
             (.noConnection, .noConnection),
             (.timeout, .timeout),
             (.cannotConnectToHost, .cannotConnectToHost),
             (.dnsLookupFailed, .dnsLookupFailed):
            return true
        case (.serverError(let lhs), .serverError(let rhs)),
             (.decodingError(let lhs), .decodingError(let rhs)),
             (.networkError(let lhs), .networkError(let rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

// MARK: - HTTP Method
enum HTTPMethod: String {
    case GET, POST, PUT, DELETE, PATCH
}

// MARK: - API Client
@MainActor
class APIClient {
    static let shared = APIClient()
    
    private let session: URLSession
    private var authToken: String?
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.timeout
        config.timeoutIntervalForResource = APIConfig.timeout
        self.session = URLSession(configuration: config)
    }
    
    func setAuthToken(_ token: String?) {
        self.authToken = token
    }
    
    // MARK: - Generic Request
    func request<T: Decodable>(
        _ endpoint: String,
        method: HTTPMethod = .GET,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        // Construct URL safely
        guard let url = URL(string: APIConfig.baseURL + endpoint) else {
            logError("Invalid URL constructed from base: \(APIConfig.baseURL) + endpoint: \(endpoint)")
            throw APIError.invalidURL
        }
        
        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add auth header if needed
        if requiresAuth, let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Encode body if present
        if let body = body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                logError("Failed to encode request body: \(error)")
                throw APIError.networkError("Failed to encode request: \(error.localizedDescription)")
            }
        }
        
        // Log request (safe - no credentials)
        logRequest(method: method, url: url, hasAuth: requiresAuth && authToken != nil)
        
        // Execute request
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Map network-level errors
            throw mapNetworkError(error)
        }
        
        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            logError("Response is not HTTPURLResponse")
            throw APIError.invalidResponse
        }
        
        logResponse(statusCode: httpResponse.statusCode, url: url)
        
        // Handle HTTP status codes
        return try handleHTTPResponse(httpResponse: httpResponse, data: data)
    }
    
    // MARK: - HTTP Response Handling
    
    private func handleHTTPResponse<T: Decodable>(httpResponse: HTTPURLResponse, data: Data) throws -> T {
        let statusCode = httpResponse.statusCode
        
        switch statusCode {
        case 200...299:
            // Success - decode response
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                let dataString = String(data: data, encoding: .utf8) ?? "<binary data>"
                logError("Decoding failed for success response. Error: \(error). Data: \(dataString)")
                throw APIError.decodingError("Could not parse server response: \(error.localizedDescription)")
            }
            
        case 400:
            // Bad Request - try to extract server message
            throw try extractServerError(from: data, fallback: "Bad request - invalid input")
            
        case 401:
            // Unauthorized
            throw try extractServerError(from: data, fallback: APIError.unauthorized)
            
        case 403:
            // Forbidden
            throw try extractServerError(from: data, fallback: APIError.forbidden)
            
        case 404:
            // Not Found
            throw try extractServerError(from: data, fallback: APIError.notFound)
            
        case 409:
            // Conflict (e.g., username already exists)
            throw try extractServerError(from: data, fallback: APIError.conflict)
            
        case 422:
            // Unprocessable Entity (validation error)
            throw try extractServerError(from: data, fallback: APIError.unprocessableEntity)
            
        case 500...599:
            // Server Error
            throw try extractServerError(from: data, fallback: "Server error (HTTP \(statusCode))")
            
        default:
            // Unexpected status code
            logError("Unexpected HTTP status code: \(statusCode)")
            throw APIError.serverError("Unexpected server response (HTTP \(statusCode))")
        }
    }
    
    // MARK: - Error Extraction
    
    private func extractServerError(from data: Data, fallback: String) throws -> APIError {
        // Try to decode structured error response
        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            logError("Server error: \(errorResponse.detail)")
            return .serverError(errorResponse.detail)
        }
        
        // Try to extract plain text error
        if let errorString = String(data: data, encoding: .utf8), !errorString.isEmpty {
            logError("Server error (plain text): \(errorString)")
            return .serverError(errorString)
        }
        
        // Fallback to generic message
        logError("Server error with no parseable body")
        return .serverError(fallback)
    }
    
    private func extractServerError(from data: Data, fallback: APIError) throws -> APIError {
        // Try to decode structured error response
        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            logError("Server error: \(errorResponse.detail)")
            return .serverError(errorResponse.detail)
        }
        
        // Fallback to provided error
        return fallback
    }
    
    // MARK: - Network Error Mapping
    
    private func mapNetworkError(_ error: Error) -> APIError {
        let nsError = error as NSError
        
        logError("Network error: domain=\(nsError.domain) code=\(nsError.code)")
        
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return .noConnection
            
        case NSURLErrorTimedOut:
            return .timeout
            
        case NSURLErrorCannotConnectToHost:
            return .cannotConnectToHost
            
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return .dnsLookupFailed
            
        case NSURLErrorCancelled:
            return .networkError("Request cancelled")
            
        case NSURLErrorBadURL:
            return .invalidURL
            
        case NSURLErrorSecureConnectionFailed:
            return .networkError("Secure connection failed")
            
        default:
            return .networkError("\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)")
        }
    }
    
    // MARK: - Logging
    
    private func logRequest(method: HTTPMethod, url: URL, hasAuth: Bool) {
        guard APIConfig.enableDebugLogging else { return }
        print("▶️ [\(method.rawValue)] \(url.path) (auth: \(hasAuth ? "yes" : "no"))")
    }
    
    private func logResponse(statusCode: Int, url: URL) {
        guard APIConfig.enableDebugLogging else { return }
        let emoji = statusCode >= 200 && statusCode < 300 ? "✅" : "❌"
        print("\(emoji) [\(statusCode)] \(url.path)")
    }
    
    private func logError(_ message: String) {
        guard APIConfig.enableDebugLogging else { return }
        print("⚠️ [APIClient] \(message)")
    }
    
    // MARK: - Convenience Methods
    func get<T: Decodable>(_ endpoint: String, requiresAuth: Bool = true) async throws -> T {
        try await request(endpoint, method: .GET, requiresAuth: requiresAuth)
    }
    
    func post<T: Decodable>(_ endpoint: String, body: Encodable? = nil, requiresAuth: Bool = true) async throws -> T {
        try await request(endpoint, method: .POST, body: body, requiresAuth: requiresAuth)
    }
    
    func put<T: Decodable>(_ endpoint: String, body: Encodable? = nil, requiresAuth: Bool = true) async throws -> T {
        try await request(endpoint, method: .PUT, body: body, requiresAuth: requiresAuth)
    }
    
    func delete<T: Decodable>(_ endpoint: String, requiresAuth: Bool = true) async throws -> T {
        try await request(endpoint, method: .DELETE, requiresAuth: requiresAuth)
    }
}

// MARK: - Error Response Model
struct ErrorResponse: Decodable {
    let detail: String
}

// MARK: - Auth API
extension APIClient {
    /// Login with email and password
    /// IMPORTANT: Password is preserved exactly as entered, including special characters
    func login(email: String, password: String) async throws -> LoginResponse {
        guard let url = URL(string: APIConfig.baseURL + "/auth/login") else {
            logError("Invalid login URL")
            throw APIError.invalidURL
        }
        
        // Build form-urlencoded body
        // CRITICAL: URLComponents.percentEncodedQuery properly encodes special chars ($, #, &, etc.)
        // This preserves the password exactly as entered while making it URL-safe
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "username", value: email),
            URLQueryItem(name: "password", value: password)
        ]
        
        guard let formBody = components.percentEncodedQuery else {
            logError("Failed to encode login form data")
            throw APIError.networkError("Failed to encode credentials")
        }
        
        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody.data(using: .utf8)
        
        // Safe logging (no credentials in logs)
        if APIConfig.enableDebugLogging {
            print("▶️ [POST] /auth/login (credentials: email=\(email.isEmpty ? "empty" : "provided"), password=\(password.isEmpty ? "empty" : "provided"))")
        }
        
        // Execute request
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Map network errors
            throw mapNetworkError(error)
        }
        
        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            logError("Login: Response is not HTTPURLResponse")
            throw APIError.invalidResponse
        }
        
        let statusCode = httpResponse.statusCode
        logResponse(statusCode: statusCode, url: url)
        
        // Handle response
        switch statusCode {
        case 200:
            // Success - decode and set token
            do {
                let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
                setAuthToken(loginResponse.accessToken)
                if APIConfig.enableDebugLogging {
                    print("✅ Login successful, token set")
                }
                return loginResponse
            } catch {
                logError("Failed to decode login response: \(error)")
                throw APIError.decodingError("Could not parse login response")
            }
            
        case 400:
            // Bad Request - likely invalid credentials format
            throw try extractServerError(from: data, fallback: "Invalid email or password format")
            
        case 401:
            // Unauthorized - wrong credentials
            throw try extractServerError(from: data, fallback: APIError.unauthorized)
            
        case 500...599:
            // Server Error
            throw try extractServerError(from: data, fallback: "Server error. Please try again later.")
            
        default:
            // Unexpected status
            throw try extractServerError(from: data, fallback: "Login failed (HTTP \(statusCode))")
        }
    }
    
    func signup(request: SignupRequest) async throws -> UserResponse {
        let response: UserResponse = try await post("/auth/signup", body: request, requiresAuth: false)
        return response
    }
    
    func getCurrentUser() async throws -> UserResponse {
        try await get("/users/me")
    }
}

// MARK: - Sports API
extension APIClient {
    func getSportProfile(sport: String) async throws -> SportProfileResponse {
        try await get("/sports/profile/\(sport)")
    }
    
    func createSportProfile(sport: String) async throws -> SportProfileResponse {
        try await post("/sports/profile", body: ["sport": sport])
    }
}

// MARK: - Matchmaking API
extension APIClient {
    func findOpponents(sport: String, matchType: String) async throws -> [OpponentResponse] {
        let body = ["sport": sport, "match_type": matchType]
        return try await post("/matchmaking/find-opponents", body: body)
    }
}

// MARK: - Leaderboard API
extension APIClient {
    func getLeaderboard(sport: String, limit: Int = 100) async throws -> [LeaderboardEntry] {
        try await get("/sports/leaderboard/\(sport)?limit=\(limit)")
    }
}

// MARK: - Challenges API
extension APIClient {
    func createChallenge(request: CreateChallengeRequest) async throws -> ChallengeResponse {
        try await post("/challenges/create", body: request)
    }
    
    func getPendingChallenges() async throws -> [ChallengeResponse] {
        try await get("/challenges/pending")
    }
    
    func acceptChallenge(challengeId: String) async throws -> ChallengeResponse {
        try await post("/challenges/\(challengeId)/accept", body: nil as String?)
    }
    
    func submitResult(challengeId: String, request: SubmitResultRequest) async throws -> ChallengeResponse {
        try await post("/challenges/\(challengeId)/result", body: request)
    }
    
    func submitMatchResult(challengeId: String, winnerId: String, scoreData: String?) async throws -> MessageResponse {
        let request = SubmitMatchResultRequest(
            challengeId: challengeId,
            winnerId: winnerId,
            scoreData: scoreData
        )
        return try await post("/matchmaking/submit-result", body: request)
    }
}

// MARK: - Disputes API (Phase 3)
extension APIClient {
    func getMyDisputes() async throws -> [DisputeResponse] {
        try await get("/disputes/my-disputes")
    }

    func createDispute(challengeId: String, reason: String) async throws -> DisputeResponse {
        let request = CreateDisputeRequest(challengeId: challengeId, reason: reason)
        return try await post("/disputes/create", body: request)
    }
}

// MARK: - Phase 4 Evidence API
extension APIClient {
    func checkEvidenceRequirement(challengeId: String) async throws -> EvidenceRequirementResponse {
        return try await get("/evidence/required/\(challengeId)")
    }

    func uploadEvidence(challengeId: String, evidenceType: String, fileUrl: String, description: String?) async throws -> EvidenceUploadResponse {
        struct UploadParams: Codable {
            let evidence_type: String
            let file_url: String
            let description: String?
        }

        let params = UploadParams(
            evidence_type: evidenceType,
            file_url: fileUrl,
            description: description
        )
        return try await post("/evidence/upload/\(challengeId)", body: params)
    }

    func getMatchEvidence(challengeId: String) async throws -> [EvidenceResponse] {
        return try await get("/evidence/match/\(challengeId)")
    }
}

// MARK: - Friends API
extension APIClient {
    // Friend requests
    func sendFriendRequest(targetUserId: String) async throws -> FriendshipResponse {
        let request = FriendRequest(targetUserId: targetUserId)
        return try await post("/friends/request", body: request)
    }

    func acceptFriendRequest(friendshipId: String) async throws -> FriendshipResponse {
        try await post("/friends/accept/\(friendshipId)", body: nil as String?)
    }

    func declineFriendRequest(friendshipId: String) async throws -> MessageResponse {
        try await post("/friends/decline/\(friendshipId)", body: nil as String?)
    }

    // Friend management
    func getFriendsList() async throws -> [FriendshipResponse] {
        try await get("/friends/list")
    }

    func getPendingRequests() async throws -> [FriendshipResponse] {
        try await get("/friends/requests/pending")
    }

    func getReceivedRequests() async throws -> [FriendshipResponse] {
        try await get("/friends/requests/received")
    }

    func removeFriend(friendshipId: String) async throws -> MessageResponse {
        try await delete("/friends/\(friendshipId)")
    }

    // Block management
    func blockUser(userId: String) async throws -> FriendshipResponse {
        try await post("/friends/block/\(userId)", body: nil as String?)
    }

    func unblockUser(userId: String) async throws -> MessageResponse {
        try await delete("/friends/unblock/\(userId)")
    }

    func getBlockedUsers() async throws -> [FriendshipResponse] {
        try await get("/friends/blocked")
    }

    // Friend status
    func getFriendStatus(userId: String) async throws -> FriendStatusResponse {
        try await get("/friends/status/\(userId)")
    }
}

// MARK: - Messaging API
extension APIClient {
    // Direct messaging
    func sendMessage(receiverId: String, content: String) async throws -> DirectMessageResponse {
        let request = MessageCreateRequest(receiverId: receiverId, content: content)
        return try await post("/messages/send", body: request)
    }

    func getConversation(withUserId userId: String, limit: Int = 50) async throws -> [DirectMessageResponse] {
        try await get("/messages/conversation/\(userId)?limit=\(limit)")
    }

    func getAllConversations() async throws -> [ConversationPreview] {
        try await get("/messages/conversations")
    }

    func deleteMessage(messageId: String) async throws -> MessageResponse {
        try await delete("/messages/\(messageId)")
    }
}

// MARK: - Posts API
extension APIClient {
    func getPosts(limit: Int = 50, offset: Int = 0) async throws -> [PostResponse] {
        try await get("/posts/?limit=\(limit)&offset=\(offset)")
    }
    
    func createPost(request: CreatePostRequest) async throws -> PostResponse {
        try await post("/posts/", body: request)
    }
    
    func likePost(postId: String) async throws -> MessageResponse {
        try await post("/posts/\(postId)/like", body: nil as String?)
    }
}

// MARK: - Clips API
extension APIClient {
    func getClips(sport: String? = nil, limit: Int = 50) async throws -> [ClipResponse] {
        var endpoint = "/clips/?limit=\(limit)"
        if let sport = sport {
            endpoint += "&sport=\(sport)"
        }
        return try await get(endpoint)
    }
    
    func createClip(request: CreateClipRequest) async throws -> ClipResponse {
        try await post("/clips/", body: request)
    }
}

// MARK: - Activity API
extension APIClient {
    func getActivityFeed(limit: Int = 50) async throws -> [ActivityItem] {
        try await get("/activity/feed?limit=\(limit)")
    }
}

// MARK: - Badges API
extension APIClient {
    func getAvailableBadges(sport: String) async throws -> [BadgeResponse] {
        try await get("/badges/available/\(sport)")
    }
    
    func getMyBadges() async throws -> [UserBadgeResponse] {
        try await get("/badges/my-badges")
    }
}

// MARK: - Teams API
extension APIClient {
    func createTeam(name: String, sport: String) async throws -> TeamResponse {
        let body = ["name": name, "sport": sport]
        return try await post("/teams/create", body: body)
    }
    
    func getMyTeams() async throws -> [TeamResponse] {
        try await get("/teams/my-teams")
    }
}

// MARK: - AI Coach Conversation API (Premium)
extension APIClient {
    /// Send message to AI Coach and get response
    func sendCoachMessage(sport: Sport, message: String) async throws -> CoachMessageResponse {
        let request = CoachMessageRequest(message: message, sport: sport.rawValue)
        return try await post("/ai/coach/message", body: request)
    }
    
    /// Get proactive AI Coach check-in
    func getProactiveCheckin(sport: Sport) async throws -> ProactiveCheckinResponse {
        try await get("/ai/coach/checkin?sport=\(sport.rawValue)")
    }
    
    /// Clear conversation history
    func clearCoachConversation(sport: Sport) async throws -> MessageResponse {
        try await delete("/ai/coach/history?sport=\(sport.rawValue)")
    }
    
    /// Generate AI-powered drill (available to all users)
    func generateDrill(sport: Sport, focusSkill: String? = nil, difficulty: String? = nil, duration: Int = 20) async throws -> DrillResponse {
        var request = DrillGenerationRequest(sport: sport.rawValue, duration_minutes: duration)
        request.focus_skill = focusSkill
        request.difficulty = difficulty
        return try await post("/ai/coach/drill/generate", body: request)
    }
    
    /// Generate AI-powered challenge (available to all users)
    func generateChallenge(sport: Sport, challengeType: String = "skill") async throws -> AIChallengeResponse {
        let request = AIChallengeGenerationRequest(sport: sport.rawValue, challenge_type: challengeType)
        return try await post("/ai/coach/challenge/generate", body: request)
    }
    
    /// Analyze training session (Premium)
    func analyzeTrainingSession(sport: Sport, sessionData: [String: Any]) async throws -> TrainingAnalysisResponse {
        let request = TrainingAnalysisRequest(sport: sport.rawValue, session_data: sessionData)
        return try await post("/ai/coach/analyze", body: request)
    }
    
    // MARK: - Tennis Courts
    
    /// Get nearby tennis courts
    func getNearbyTennisCourts(latitude: Double, longitude: Double, radiusMiles: Double = 10.0, limit: Int = 20) async throws -> [TennisCourt] {
        let endpoint = "/tennis-courts/nearby?latitude=\(latitude)&longitude=\(longitude)&radius_miles=\(radiusMiles)&limit=\(limit)"
        return try await get(endpoint)
    }
    
    /// Get specific tennis court details
    func getTennisCourtDetails(courtId: String) async throws -> TennisCourt {
        return try await get("/tennis-courts/\(courtId)")
    }
    
    /// Search tennis courts by city
    func searchTennisCourtsByCity(city: String, state: String? = nil, limit: Int = 20) async throws -> [TennisCourt] {
        var endpoint = "/tennis-courts/search/by-city?city=\(city)&limit=\(limit)"
        if let state = state {
            endpoint += "&state=\(state)"
        }
        return try await get(endpoint)
    }
}

// MARK: - AI Coach Models

struct CoachMessageRequest: Codable {
    let message: String
    let sport: String
}

struct CoachMessageResponse: Codable {
    let response: String
    let suggestedActions: [String]
    let tone: String
    let followUpQuestions: [String]
    let timestamp: String
    
    enum CodingKeys: String, CodingKey {
        case response
        case suggestedActions = "suggested_actions"
        case tone
        case followUpQuestions = "follow_up_questions"
        case timestamp
    }
}

struct ProactiveCheckinResponse: Codable {
    let message: String?
    let hasMessage: Bool
    
    enum CodingKeys: String, CodingKey {
        case message
        case hasMessage = "has_message"
    }
}

struct DrillGenerationRequest: Codable {
    let sport: String
    var focus_skill: String?
    var difficulty: String?
    let duration_minutes: Int
}

struct DrillResponse: Codable {
    let name: String
    let description: String
    let duration: Int
    let difficulty: String
    let instructions: [String]
    let equipmentNeeded: [String]
    let tips: [String]
    let skillFocus: String?
    
    enum CodingKeys: String, CodingKey {
        case name, description, duration, difficulty, instructions, tips
        case equipmentNeeded = "equipment_needed"
        case skillFocus = "skill_focus"
    }
}

struct AIChallengeGenerationRequest: Codable {
    let sport: String
    let challenge_type: String
}

struct AIChallengeResponse: Codable {
    let title: String
    let description: String
    let goal: String
    let difficulty: String
    let estimatedTime: Int
    let rewardPoints: Int
    let instructions: [String]
    let successMetric: String
    
    enum CodingKeys: String, CodingKey {
        case title, description, goal, difficulty, instructions
        case estimatedTime = "estimated_time"
        case rewardPoints = "reward_points"
        case successMetric = "success_metric"
    }
}

struct TrainingAnalysisRequest: Encodable {
    let sport: String
    let session_data: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case sport
        case session_data
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sport, forKey: .sport)
        // Convert [String: Any] to JSON data
        let jsonData = try JSONSerialization.data(withJSONObject: session_data)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
        try container.encode(jsonObject as? [String: String] ?? [:], forKey: .session_data)
    }
}

struct TrainingAnalysisResponse: Codable {
    let performanceRating: Double
    let insights: [String]
    let areasToImprove: [String]
    let nextSessionRecommendations: [String]
    
    enum CodingKeys: String, CodingKey {
        case performanceRating = "performance_rating"
        case insights
        case areasToImprove = "areas_to_improve"
        case nextSessionRecommendations = "next_session_recommendations"
    }
}
