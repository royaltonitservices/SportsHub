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
    
    /// User-facing message that avoids leaking backend internals
    var userFriendlyMessage: String {
        switch self {
        case .invalidURL, .invalidResponse, .malformedResponse, .decodingError:
            return "Something unexpected happened. Please try again."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .forbidden:
            return "You don't have permission to do that."
        case .notFound:
            return "The requested resource was not found."
        case .conflict:
            return "This action conflicts with something that already exists."
        case .unprocessableEntity:
            return "Please check your input and try again."
        case .serverError(let message):
            // Only surface moderation/account messages; hide everything else
            if message.contains("Account is") || message.contains("suspended") || message.contains("banned") {
                return message
            }
            return "Something went wrong on our end. Please try again."
        case .noConnection:
            return "No internet connection. Please check your network and try again."
        case .timeout:
            return "The request timed out. Please try again."
        case .cannotConnectToHost:
            return "Unable to reach the server. Please try again later."
        case .dnsLookupFailed:
            return "Unable to reach the server. Please check your connection."
        case .networkError:
            return "A network error occurred. Please check your connection and try again."
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
    
    // MARK: - Retry Configuration
    
    /// Maximum number of retries for transient network errors
    private static let maxRetries = 2
    /// Base delay between retries (doubles each attempt)
    private static let retryBaseDelay: UInt64 = 500_000_000 // 0.5 seconds
    
    /// Whether an error is transient and worth retrying
    private func isTransientError(_ error: APIError) -> Bool {
        switch error {
        case .cannotConnectToHost, .timeout, .noConnection:
            return true
        case .networkError(let msg):
            // Retry on connection-level failures, not on cancellations
            return !msg.contains("cancel") && !msg.contains("Cancel")
        default:
            return false
        }
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
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add auth header if needed
        if requiresAuth, let token = authToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Encode body if present
        if let body = body {
            do {
                urlRequest.httpBody = try JSONEncoder().encode(body)
            } catch {
                logError("Failed to encode request body: \(error)")
                throw APIError.networkError("Failed to encode request: \(error.localizedDescription)")
            }
        }
        
        // Log request (safe - no credentials)
        logRequest(method: method, url: url, hasAuth: requiresAuth && authToken != nil)
        
        // Execute with retry for transient errors
        var lastError: APIError = .networkError("Request failed")
        
        for attempt in 0...Self.maxRetries {
            do {
                let (data, response) = try await session.data(for: urlRequest)
                
                // Validate HTTP response
                guard let httpResponse = response as? HTTPURLResponse else {
                    logError("Response is not HTTPURLResponse")
                    throw APIError.invalidResponse
                }
                
                logResponse(statusCode: httpResponse.statusCode, url: url)
                
                // Handle HTTP status codes
                return try handleHTTPResponse(httpResponse: httpResponse, data: data)
                
            } catch let error as APIError {
                lastError = error
                
                // Only retry on transient network errors
                if isTransientError(error) && attempt < Self.maxRetries {
                    let delay = Self.retryBaseDelay * UInt64(1 << attempt) // exponential: 0.5s, 1s
                    logError("Transient error on attempt \(attempt + 1)/\(Self.maxRetries + 1), retrying in \(delay / 1_000_000)ms: \(error)")
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                
                throw error
                
            } catch {
                // Map network-level errors
                let apiError = mapNetworkError(error)
                lastError = apiError
                
                if isTransientError(apiError) && attempt < Self.maxRetries {
                    let delay = Self.retryBaseDelay * UInt64(1 << attempt)
                    logError("Transient error on attempt \(attempt + 1)/\(Self.maxRetries + 1), retrying in \(delay / 1_000_000)ms: \(apiError)")
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                
                throw apiError
            }
        }
        
        throw lastError
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
        // Log full URL so it's immediately obvious which host/port is being targeted
        print("▶️ [\(method.rawValue)] \(url.absoluteString) (auth: \(hasAuth ? "yes" : "no"))")
    }
    
    private func logResponse(statusCode: Int, url: URL) {
        guard APIConfig.enableDebugLogging else { return }
        let emoji = statusCode >= 200 && statusCode < 300 ? "✅" : "❌"
        print("\(emoji) [\(statusCode)] \(url.absoluteString)")
    }
    
    private func logError(_ message: String) {
        guard APIConfig.enableDebugLogging else { return }
        print("⚠️ [APIClient] \(message)")
    }
    
    // MARK: - Startup Connectivity Check
    
    /// Call once at app startup to confirm backend is reachable.
    /// Logs clearly so connection problems are immediately visible in the Xcode console.
    /// Does not throw — purely diagnostic.
    func checkConnectivity() async {
        guard APIConfig.enableDebugLogging else { return }
        guard let url = URL(string: APIConfig.baseURL + "/health") else {
            print("🔴 [APIClient] CONNECTIVITY: Malformed baseURL — \(APIConfig.baseURL)")
            return
        }
        print("🔍 [APIClient] Checking backend reachability at \(url.absoluteString)")
        do {
            var req = URLRequest(url: url, timeoutInterval: 5)
            req.httpMethod = "GET"
            let (data, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            print("🟢 [APIClient] CONNECTIVITY OK — HTTP \(code) — \(body)")
        } catch {
            let ns = error as NSError
            print("🔴 [APIClient] CONNECTIVITY FAILED — \(ns.domain) \(ns.code): \(ns.localizedDescription)")
            if ns.code == NSURLErrorCannotConnectToHost {
                print("   → Backend is not running on \(APIConfig.baseURL). Start it with:")
                print("   → cd backend && uvicorn main:app --host 0.0.0.0 --port 8000 --reload")
                print("   → If on a physical device, change APIConfig.baseURL to your Mac's LAN IP.")
            }
        }
    }
    
    /// Lightweight backend availability check with a 3-second timeout.
    /// Used by SessionManager to set backendAvailable state.
    /// Not debug-only — runs in production.
    func isBackendReachable() async -> Bool {
        guard let url = URL(string: APIConfig.baseURL + "/health") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
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
        
        // Execute request with retry for transient errors
        var lastError: APIError = .networkError("Login request failed")
        var data: Data = Data()
        var statusCode: Int = 0
        
        for attempt in 0...Self.maxRetries {
            do {
                let (respData, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    logError("Login: Response is not HTTPURLResponse")
                    throw APIError.invalidResponse
                }
                
                data = respData
                statusCode = httpResponse.statusCode
                logResponse(statusCode: statusCode, url: url)
                break // Success — exit retry loop
                
            } catch let error as APIError {
                lastError = error
                if isTransientError(error) && attempt < Self.maxRetries {
                    let delay = Self.retryBaseDelay * UInt64(1 << attempt)
                    logError("Login: transient error on attempt \(attempt + 1), retrying in \(delay / 1_000_000)ms")
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                throw error
            } catch {
                let apiError = mapNetworkError(error)
                lastError = apiError
                if isTransientError(apiError) && attempt < Self.maxRetries {
                    let delay = Self.retryBaseDelay * UInt64(1 << attempt)
                    logError("Login: transient error on attempt \(attempt + 1), retrying in \(delay / 1_000_000)ms")
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                throw apiError
            }
        }
        
        // If we never got a response (all retries exhausted), throw the last error
        guard statusCode != 0 else {
            throw lastError
        }
        
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
    
    func checkUsernameAvailability(username: String) async throws -> Bool {
        let response: UsernameAvailabilityResponse = try await get("/users/check-username/\(username)")
        return response.available
    }
    
    func updateUsername(newUsername: String) async throws {
        let _: EmptyResponse = try await put("/users/me/username", body: ["new_username": newUsername])
    }
    
    func updateDisplayName(newDisplayName: String) async throws {
        let _: EmptyResponse = try await put("/users/me/display-name", body: ["new_display_name": newDisplayName])
    }
    
    func updateBio(bio: String) async throws {
        let _: EmptyResponse = try await put("/users/me/bio", body: ["bio": bio])
    }
    
    /// Get current user's subscription status from backend
    /// This is critical for syncing Premium state between backend and iOS
    func getSubscriptionStatus() async throws -> SubscriptionStatusResponse {
        try await get("/users/me/subscription")
    }

    func getTrustScore() async throws -> TrustScoreResponse {
        try await get("/users/me/trust-score")
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
    
    func declineChallenge(challengeId: String) async throws -> MessageResponse {
        try await post("/challenges/\(challengeId)/decline", body: nil as String?)
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

    /// Step 1 of 2: Upload the raw file bytes to the server.
    /// Returns a FileUploadToken containing the server-generated upload_id and canonical URL.
    /// Pass the upload_id to associateEvidence(challengeId:uploadId:...) to link the file to a match.
    func uploadEvidenceFile(data: Data, mimeType: String) async throws -> FileUploadToken {
        guard let url = URL(string: APIConfig.baseURL + "/evidence/upload") else {
            throw APIError.invalidURL
        }

        let ext: String
        switch mimeType {
        case "video/mp4":       ext = ".mp4"
        case "video/quicktime": ext = ".mov"
        case "image/png":       ext = ".png"
        case "image/gif":       ext = ".gif"
        default:                ext = ".jpg"
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"evidence\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        request.timeoutInterval = 120  // 2 minutes for large files

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError("Evidence file upload failed (\(httpResponse.statusCode))")
        }
        do {
            let token = try JSONDecoder().decode(FileUploadToken.self, from: responseData)
            #if DEBUG
            token.assertValid(context: "uploadEvidenceFile")
            #endif
            return token
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Step 2 of 2: Associate a previously uploaded file (by upload_id) with a specific challenge.
    func associateEvidence(
        challengeId: String,
        uploadId: String,
        evidenceType: String,
        description: String?
    ) async throws -> EvidenceUploadResponse {
        var components = URLComponents(string: APIConfig.baseURL + "/evidence/upload/\(challengeId)")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "evidence_type", value: evidenceType),
            URLQueryItem(name: "upload_id",     value: uploadId),
        ]
        if let desc = description, !desc.isEmpty {
            queryItems.append(URLQueryItem(name: "description", value: desc))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = APIConfig.timeout

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return try handleHTTPResponse(httpResponse: httpResponse, data: responseData)
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
    
    func getFriends() async throws -> [FriendshipResponse] {
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
        try await get("/posts/feed?limit=\(limit)&skip=\(offset)")
    }
    
    func createPost(request: CreatePostRequest) async throws -> PostResponse {
        try await post("/posts/create", body: request)
    }
    
    func likePost(postId: String) async throws -> MessageResponse {
        try await post("/posts/\(postId)/like", body: nil as String?)
    }
    
    func unlikePost(postId: String) async throws -> MessageResponse {
        try await delete("/posts/\(postId)/like")
    }
    
    func deletePost(postId: String) async throws -> MessageResponse {
        try await delete("/posts/\(postId)")
    }
}

// MARK: - Comments API
extension APIClient {
    func getPostComments(postId: String) async throws -> [CommentResponse] {
        try await get("/comments/post/\(postId)")
    }
    
    func createComment(request: CreateCommentRequest) async throws -> CommentResponse {
        try await post("/comments/create", body: request)
    }
    
    func deleteComment(commentId: String) async throws -> MessageResponse {
        try await delete("/comments/\(commentId)")
    }
    
    func likeComment(commentId: String) async throws -> MessageResponse {
        try await post("/comments/like/\(commentId)", body: nil as String?)
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
        try await post("/clips/create", body: request)
    }
    
    func uploadClipVideo(videoURL: URL, title: String, sport: String, description: String?) async throws -> ClipResponse {
        // Read video data
        let videoData = try Data(contentsOf: videoURL)
        
        // Create multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        
        // Add title field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"title\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(title)\r\n".data(using: .utf8)!)
        
        // Add sport field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"sport\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(sport)\r\n".data(using: .utf8)!)
        
        // Add description if present
        if let description = description, !description.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"description\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(description)\r\n".data(using: .utf8)!)
        }
        
        // Add video file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        let filename = videoURL.lastPathComponent
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Create request
        var request = URLRequest(url: URL(string: "\(APIConfig.baseURL)/clips/upload")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken ?? "")", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 120  // 2 minutes for video upload
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse.detail)
            }
            throw APIError.serverError("Upload failed with status \(httpResponse.statusCode)")
        }
        
        return try JSONDecoder().decode(ClipResponse.self, from: data)
    }
    func uploadProfilePicture(imageData: Data) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        var request = URLRequest(url: URL(string: "\(APIConfig.baseURL)/users/me/avatar")!)
        request.httpMethod = "PUT"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken ?? "")", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Avatar upload failed")
        }
        
        struct AvatarResponse: Decodable { let avatarUrl: String; enum CodingKeys: String, CodingKey { case avatarUrl = "avatar_url" } }
        let decoded = try JSONDecoder().decode(AvatarResponse.self, from: data)
        return decoded.avatarUrl
    }
}

// MARK: - Activity API
extension APIClient {
    func getActivityFeed(limit: Int = 50) async throws -> [ActivityItem] {
        try await get("/activity/feed?limit=\(limit)")
    }
    
    /// Fetch completed match history for the current user.
    /// Uses /activity/recent-matches which returns completed Challenge records.
    func getRecentMatches(sport: String? = nil, limit: Int = 20) async throws -> [ChallengeResponse] {
        var endpoint = "/activity/recent-matches?limit=\(limit)"
        if let sport = sport {
            endpoint += "&sport=\(sport)"
        }
        return try await get(endpoint)
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

// MARK: - Group Chat API
private struct CreateGroupRequest: Encodable {
    let name: String
    let description: String?
    let memberIds: [String]
    enum CodingKeys: String, CodingKey {
        case name, description
        case memberIds = "member_ids"
    }
}

extension APIClient {
    func getGroups() async throws -> [GroupChat] {
        try await get("/messages/groups")
    }
    
    func createGroup(name: String, description: String?, memberIds: [String]) async throws -> GroupChat {
        let body = CreateGroupRequest(name: name, description: description, memberIds: memberIds)
        return try await post("/messages/groups/create", body: body)
    }
    
    func getGroupMessages(groupId: String) async throws -> [GroupMessage] {
        try await get("/messages/groups/\(groupId)/messages")
    }
    
    func sendGroupMessage(groupId: String, content: String) async throws -> GroupMessage {
        try await post("/messages/groups/\(groupId)/send", body: ["content": content])
    }
}

// MARK: - Teams API
extension APIClient {
    func createTeam(name: String, sport: String) async throws -> TeamResponse {
        struct CreateTeamBody: Encodable {
            let name: String
            let sport: String
        }
        return try await post("/teams/create", body: CreateTeamBody(name: name, sport: sport))
    }

    func getMyTeams() async throws -> [TeamResponse] {
        try await get("/teams/my-teams")
    }

    func getOpenTeams(sport: String) async throws -> [OpenTeamResponse] {
        try await get("/teams/open?sport=\(sport)")
    }
}

// MARK: - Highlights API
extension APIClient {
    func getHighlightsFeed() async throws -> [HighlightFeedItem] {
        try await get("/highlights/feed")
    }

    func getUserHighlights(userId: String) async throws -> [Highlight] {
        try await get("/highlights/user/\(userId)")
    }

    func uploadHighlightMedia(imageData: Data) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"media\"; filename=\"highlight.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "\(APIConfig.baseURL)/highlights/upload")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken ?? "")", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError("Media upload failed")
        }
        let json = try JSONDecoder().decode([String: String].self, from: data)
        guard let mediaUrl = json["media_url"] else { throw APIError.serverError("No media URL returned") }
        return mediaUrl
    }

    func createHighlight(mediaUrl: String, caption: String?, sport: String?) async throws -> HighlightResponse {
        struct CreateHighlightBody: Encodable {
            let mediaUrl: String
            let caption: String?
            let sport: String?
            enum CodingKeys: String, CodingKey {
                case mediaUrl = "media_url"
                case caption, sport
            }
        }
        return try await post("/highlights/create", body: CreateHighlightBody(mediaUrl: mediaUrl, caption: caption, sport: sport))
    }

    func deleteHighlight(id: String) async throws {
        let _: MessageResponse = try await delete("/highlights/\(id)")
    }
}

// MARK: - AI Coach Conversation API (Premium)
extension APIClient {
    /// Check if AI Coach backend is available
    func checkAICoachHealth() async -> Bool {
        do {
            // Try a simple health check endpoint
            let _: MessageResponse = try await get("/health", requiresAuth: false)
            return true
        } catch {
            print("⚠️ [APIClient] AI Coach health check failed: \(error)")
            return false
        }
    }
    
    /// Send message to AI Coach and get response
    func sendCoachMessage(sport: Sport, message: String, context: CoachContext? = nil, conversationHistory: [ConversationMessage]? = nil) async throws -> CoachMessageResponse {
        print("🤖 [APIClient] Building coach message request...")
        
        // MOCK MODE: If explicitly enabled, return simulated response
        #if DEBUG
        if DebugSettings.useAICoachMockMode {
            print("🤖 [APIClient] MOCK MODE ENABLED - Returning simulated response")
            return generateLocalCoachResponse(for: message, sport: sport, context: context)
        }
        #endif
        
        let request = CoachMessageRequest(message: message, sport: sport.rawValue, context: context, conversationHistory: conversationHistory)
        
        // Log request details
        if let requestData = try? JSONEncoder().encode(request),
           let requestString = String(data: requestData, encoding: .utf8) {
            print("🤖 [APIClient] Request body: \(requestString)")
        }
        
        print("🤖 [APIClient] Sending POST to /ai/coach/message...")
        
        do {
            let response: CoachMessageResponse = try await post("/ai/coach/message", body: request)
            print("✅ [APIClient] Successfully received coach response")
            print("✅ [APIClient] Response preview: \(response.response.prefix(100))...")
            return response
        } catch let error as APIError {
            print("❌ [APIClient] APIError in sendCoachMessage: \(error)")
            print("❌ [APIClient] Error description: \(error.errorDescription ?? "none")")
            
            // If it's a 404, the endpoint doesn't exist yet
            if case .notFound = error {
                print("❌ [APIClient] Endpoint /ai/coach/message not found on backend!")
                print("💡 [APIClient] Hint: Make sure the backend server is running and has the AI Coach endpoint implemented")
                #if DEBUG
                print("💡 [APIClient] You can enable mock mode by setting DebugSettings.useAICoachMockMode = true")
                #endif
            }
            
            throw error
        } catch {
            print("❌ [APIClient] Unexpected error in sendCoachMessage: \(error)")
            throw error
        }
    }
    
    /// Generate context-aware coaching response using the local coaching engine.
    /// Delivers real coaching value based on sport, message content,
    /// and available context (weak points, goals, wearable data).
    /// Used when backend AI is unavailable, or when explicitly enabled via DebugSettings.
    func generateLocalCoachResponse(for message: String, sport: Sport, context: CoachContext? = nil, conversationHistory: [ConversationMessage] = []) -> CoachMessageResponse {
        // Use var so context enrichment can augment the routing signal
        var lowercased = message.lowercased()

        // ── Context enrichment ────────────────────────────────────────────────────────────
        // For vague messages (short, no explicit sport/workout keyword), prepend the latest
        // concern and semantic concepts so that keyword-based routing works correctly.
        // Example: user says "help me" + latestConcern="conditioning"
        //          → lowercased becomes "conditioning help me" → conditioning handler fires.
        let contextConcern = context?.latestConcern?.lowercased() ?? ""
        let contextSemanticConcepts = (context?.semanticConcepts ?? []).map { $0.lowercased() }
        let allContextSignals = ([contextConcern] + contextSemanticConcepts).filter { !$0.isEmpty }

        let hasExplicitTopicKeyword = lowercased.contains("workout") || lowercased.contains("drill") ||
            lowercased.contains("game") || lowercased.contains("match") ||
            lowercased.contains("prepare") || lowercased.contains("today") ||
            lowercased.contains("shoot") || lowercased.contains("dribble") ||
            lowercased.contains("serve") || lowercased.contains("pass") ||
            lowercased.contains("route") || lowercased.contains("catching") ||
            lowercased.contains("volley") || lowercased.contains("forehand") ||
            lowercased.contains("backhand")
        let isVague = !hasExplicitTopicKeyword && lowercased.split(separator: " ").count < 12

        if isVague && !allContextSignals.isEmpty {
            lowercased = allContextSignals.joined(separator: " ") + " " + lowercased
            print("📱 [Local Coach] Context-enriched routing: '\(lowercased.prefix(80))'")
        }

        // Build wearable context string if available
        var wearableInsight = ""
        if let w = context?.wearableData {
            var parts: [String] = []
            if let rhr = w.restingHeartRate { parts.append("resting HR \(Int(rhr)) bpm") }
            if let hrv = w.hrv { parts.append("HRV \(Int(hrv)) ms") }
            if let sleep = w.sleepHours { parts.append(String(format: "%.1f hours of sleep", sleep)) }
            if let steps = w.stepsToday { parts.append("\(steps) steps today") }
            if !parts.isEmpty {
                wearableInsight = "\n\n📊 Based on your wearable data (\(parts.joined(separator: ", ")))"
            }
        }
        
        // Build readiness context
        var readinessInsight = ""
        if let readiness = context?.readinessLevel {
            readinessInsight = "\n\nYour readiness level is \(readiness), so I've factored that into my recommendation."
        }

        // Build weak point insight — injected at the end of every local response
        var weakPointInsight = ""
        if let wp = context?.weakPoints, !wp.isEmpty {
            let focused = wp.prefix(3).map { $0.capitalized }.joined(separator: ", ")
            weakPointInsight = "\n\n🎯 **Coaching focus:** Based on what you've shared, prioritize \(focused) in this session."
        }

        // Follow-up detection: these phrases reference the coach's prior message, not a new topic.
        // Route to continuation logic instead of re-matching keywords in a new sport branch.
        let followUpTriggers = [
            "expand on", "elaborate", "what you said", "what you just said", "based on that",
            "based on what you", "what do you mean", "can you explain", "go deeper",
            "dive deeper", "more detail", "make it shorter", "make it simpler",
            "shorter version", "simpler version", "tl;dr", "tldr",
            "turn that into drills", "turn that into",
            "what about tomorrow", "what if i only have", "only have", "just have time",
            "focus on first", "start with first", "on what i said", "use what i said",
            "said before", "said earlier"
        ]
        let isFollowUp = followUpTriggers.contains { lowercased.contains($0) }
        if isFollowUp {
            let priorContent = conversationHistory.reversed().first(where: { $0.role == "assistant" })?.content ?? ""
            return buildFollowUpResponse(
                lowercased: lowercased,
                priorContent: priorContent,
                sport: sport,
                wearableInsight: wearableInsight,
                weakPointInsight: weakPointInsight
            )
        }

        var response = ""
        var actions: [String] = []
        var followUps: [String] = []
        var tone = "supportive"
        
        // Athletic development detection — catches speed/strength/conditioning/agility queries
        // across ALL sports before entering sport-specific branches. This prevents e.g.
        // "my speed is weak" from accidentally triggering the basketball weak-hand handler.
        let athleticTermsToMatch = ["speed", "faster", "quicker", "explosive", "explosiveness",
                                    "strength", "stronger", "conditioning", "conditioned",
                                    "endurance", "stamina", "agility", "agile", "vertical",
                                    "flexibility", "power", "athleticism", "athletic",
                                    "in shape", "out of shape", "cardio", "get tired",
                                    "run out of gas", "wind", "lung capacity"]
        let hasAthleticTerm = athleticTermsToMatch.contains { lowercased.contains($0) }
        // Guard: don't intercept if the user is asking about a specific sport skill —
        // in that case the skill-specific branch gives more targeted advice.
        let hasSkillTerm = lowercased.contains("shoot") || lowercased.contains("dribble") ||
                           lowercased.contains("serve") || lowercased.contains("pass") ||
                           lowercased.contains("route") || lowercased.contains("catching") ||
                           lowercased.contains("volley") || lowercased.contains("forehand") ||
                           lowercased.contains("backhand")
        if hasAthleticTerm && !hasSkillTerm {
            return buildAthleticDevelopmentResponse(
                sport: sport,
                lowercased: lowercased,
                wearableInsight: wearableInsight,
                weakPointInsight: weakPointInsight
            )
        }

        // Sport-specific coaching responses
        switch sport {
        case .basketball:
            if lowercased.contains("workout") || lowercased.contains("drill") || lowercased.contains("20-minute") || lowercased.contains("20 minute") {
                let duration = extractDuration(from: lowercased) ?? 20
                response = "Here's your \(duration)-minute basketball workout:\n\n🏀 **Warm-Up** (3 min)\n• Ball handling: crossovers, between legs, behind back\n• Light jogging with the ball\n\n🎯 **Shooting** (\(max(duration/3, 5)) min)\n• 5 spots around the arc — 5 makes from each\n• Free throws: shoot 10, track your percentage\n\n💪 **Ball Handling** (\(max(duration/3, 5)) min)\n• Pound dribble series (right, left, alternating)\n• Full-court dribble drives — finish with layup\n\n🏃 **Conditioning** (\(max(duration/4, 3)) min)\n• Defensive slides baseline to baseline\n• Sprint-jog intervals\(wearableInsight)\(readinessInsight)\n\nStay locked in — consistency beats intensity."
                actions = ["Log This Workout", "View Drill Library", "Start Timer"]
                followUps = ["Want me to adjust the intensity?", "Which part of your game needs the most work?"]
            } else if lowercased.contains("shoot") || lowercased.contains("three") || lowercased.contains("jumper") {
                response = "Shooting is all about repetition with good form. Here's what I recommend:\n\n1. **Form Shooting** — Start 5 feet from the basket. Focus on:\n   • Feet shoulder-width apart, slight stagger\n   • Ball on fingertips, not palm\n   • Follow through — hold it like you're reaching into a cookie jar\n\n2. **Spot Shooting** — 5 spots, 5 makes each\n   Start from the block, then elbow, free throw line, wing, corner\n\n3. **Off-the-Dribble** — Pull-up jumpers from the wing\n   One dribble → plant → shoot\n\nTrack your makes. You should aim for 60%+ from mid-range before extending to three.\(wearableInsight)"
                actions = ["Start Shooting Drill", "Track My Percentage"]
                followUps = ["What's your current shooting percentage?", "Do you have someone to rebound for you?"]
            } else if lowercased.contains("left hand") || lowercased.contains("off hand") || lowercased.contains("weak hand") ||
                      ((lowercased.contains("weak") || lowercased.contains("struggle")) &&
                       (lowercased.contains("hand") || lowercased.contains("dribble") || lowercased.contains("handle") ||
                        lowercased.contains("crossover") || lowercased.contains("layup") || lowercased.contains("finish"))) {
                response = "Good — identifying weak spots is what separates serious players from casual ones.\n\nFor your weak hand (off-hand):\n\n**Daily 10-Minute Routine:**\n1. Pound dribble with weak hand only — 1 minute\n2. Crossover to weak hand finish — 10 reps each side\n3. Weak-hand layups from both sides — 10 makes\n4. Behind-the-back to weak-hand finish — 5 makes\n\n**In-Game Rule:**\nDuring pickup, force yourself to finish with your weak hand at least 50% of the time.\n\nWithin 2-3 weeks of daily work, you'll notice a real difference.\(wearableInsight)"
                actions = ["Start Off-Hand Drill", "Set Daily Reminder"]
                followUps = ["How often do you play pickup?", "What other areas feel weak?"]
                tone = "motivational"
            } else if lowercased.contains("today") || lowercased.contains("what should") || lowercased.contains("recommend") {
                response = "Here's what I'd focus on today:\n\n"
                if let w = context?.wearableData, let rhr = w.restingHeartRate, rhr > 70 {
                    response += "Your resting heart rate is a bit elevated (\(Int(rhr)) bpm), so I'd keep it moderate.\n\n"
                    response += "**Recommended Session: Skill Work (Low Intensity)**\n• Ball handling combos — 10 min\n• Form shooting — 10 min\n• Free throws — 5 min\n\nSave the hard conditioning for tomorrow when you're more recovered."
                    tone = "caring"
                } else {
                    response += "**Recommended Session: Full Practice**\n• Dynamic warm-up — 5 min\n• Skill work (ball handling + finishing) — 15 min\n• Shooting (spot + off-dribble) — 15 min\n• Game situations or 1v1 — 10 min\n• Cool down + stretching — 5 min\(wearableInsight)"
                }
                actions = ["Start This Workout", "Customize Duration"]
                followUps = ["How much time do you have?", "Any specific skills to focus on?"]
            } else if lowercased.contains("match") || lowercased.contains("game") || lowercased.contains("prepare") {
                response = "Game prep is about peaking at the right time. Here's your pre-game plan:\n\n**Day Before:**\n• Light shooting — form shots only, 15 min max\n• Visualization — walk through your offensive moves mentally\n• Good sleep (8+ hours) and hydration\n\n**Game Day:**\n• Dynamic warm-up 30 min before\n• Layup lines + mid-range shots to find your touch\n• No heavy conditioning\n\n**Mental:**\n• Focus on 1-2 things you do well\n• Don't try new moves — trust your training\n• Play your game, not someone else's\(wearableInsight)"
                actions = ["Set Game Day Reminder", "View Warm-Up Routine"]
                followUps = ["When is your game?", "What's your role on the team?"]
            } else {
                response = "I'm your basketball coach — let's get to work! 🏀\n\nI can help you with:\n• **Custom workouts** tailored to your time and goals\n• **Skill development** — shooting, handles, defense, finishing\n• **Game preparation** and mental approach\n• **Weakness identification** and targeted improvement\n• **Recovery guidance** based on your fitness data\n\nWhat do you want to work on?\(wearableInsight)"
                actions = ["Get a Workout", "Work on Weaknesses", "Prepare for a Game"]
                followUps = ["What's your biggest goal right now?", "How many days a week do you train?"]
            }
            
        case .football:
            if lowercased.contains("workout") || lowercased.contains("drill") || lowercased.contains("minute") {
                let duration = extractDuration(from: lowercased) ?? 20
                response = "Here's your \(duration)-minute football workout:\n\n🏈 **Warm-Up** (3 min)\n• High knees, butt kicks, karaoke\n• Arm circles and dynamic stretching\n\n⚡ **Speed & Agility** (\(max(duration/3, 5)) min)\n• 5-10-5 shuttle drill — 4 reps\n• Cone weave — 3 sets\n• Backpedal-to-sprint transitions — 5 reps\n\n💪 **Position Work** (\(max(duration/3, 5)) min)\n• Route running (WR) / Drop-back footwork (QB) / Tackling form (DEF)\n• Catching: 10 over-the-shoulder, 10 crossing routes\n\n🏃 **Conditioning** (\(max(duration/4, 3)) min)\n• 40-yard sprints with 30s rest — 4 reps\n• Bear crawls 20 yards — 3 sets\(wearableInsight)\(readinessInsight)"
                actions = ["Log This Workout", "View Drill Library"]
                followUps = ["What position do you play?", "Want more position-specific work?"]
            } else if lowercased.contains("today") || lowercased.contains("what should") || lowercased.contains("recommend") {
                response = "Here's today's football session:\n\n🏈 **Warm-Up** (5 min)\n• High knees, butt kicks, karaoke steps, hip circles\n• Burst sprints: 3× 10 yards at 70%\n\n⚡ **Speed & Short-Area Quickness** (10 min)\n• 5-10—5 pro agility shuttle — 4 reps (the most football-relevant short-area drill)\n• Cone weave with hard plant-and-cut — 3 sets\n• Backpedal → hip flip → sprint — 5 reps each direction\n\n🎯 **Route Running & Hands** (10 min)\n• 5 routes: out, in, post, corner, seam — 3 clean reps each\n• Concentration catches: toss high, catch at your peak, hands only\n• Contested-catch body control — 3 reps each side\n\n🏃 **Conditioning** (5 min)\n• 40-yard sprints × 4 with 45s recovery\n• Sideline-to-sideline gassers × 2\(wearableInsight)\n\nTell me your position and I'll make this far more targeted."
                actions = ["Log This Workout", "Customize for My Position"]
                followUps = ["What position do you play?", "Any specific football skill you want to prioritize?"]
            } else {
                response = "Let's get after it! 🏈\n\nI can help with:\n• **Route running** — getting open, break sharpness, release vs. coverage\n• **Speed & agility** — 5-10-5 shuttle, cone drills, first-step explosiveness\n• **Throwing mechanics** — grip, drop, release timing, touch vs. velocity\n• **Catching** — concentration catches, contested balls, YAC after the catch\n• **Conditioning** — 40-yard conditioning, position-specific work\n\nWhat do you want to work on?\(wearableInsight)"
                actions = ["Get a Workout", "Position Drills", "Speed Training"]
                followUps = ["What position do you play?", "When's your next game or tryout?"]
            }
            
        case .soccer:
            if lowercased.contains("workout") || lowercased.contains("drill") || lowercased.contains("minute") {
                let duration = extractDuration(from: lowercased) ?? 20
                response = "Here's your \(duration)-minute soccer workout:\n\n⚽ **Warm-Up** (3 min)\n• Jog with ball at feet\n• Inside-outside touches while moving\n\n🎯 **Technical** (\(max(duration/3, 5)) min)\n• Ball mastery: toe taps, rolls, Cruyff turns\n• Passing against a wall — inside foot, 2-touch rhythm\n\n⚡ **1v1 Skills** (\(max(duration/3, 5)) min)\n• Step-overs into acceleration — 5 each direction\n• Cut inside + shot — 10 reps\n• Body feint to beat a cone defender — 10 reps\n\n🏃 **Fitness** (\(max(duration/4, 3)) min)\n• Box-to-box sprints with recovery jog — 4 reps\n• Shuttle runs with ball — 3 sets\(wearableInsight)\(readinessInsight)"
                actions = ["Log This Workout", "View Drill Library"]
                followUps = ["What position do you play?", "Want to focus on shooting or passing?"]
            } else if lowercased.contains("today") || lowercased.contains("what should") || lowercased.contains("recommend") {
                response = "Here's today's soccer session:\n\n⚽ **Activation** (5 min)\n• Jog with ball at feet, inside-outside touches\n• Rondos with yourself: pass against a wall 1-2 touch\n\n🎯 **Technical Block** (12 min)\n• First touch control: toss ball in air, settle with every surface — foot, thigh, chest (3 min)\n• Passing accuracy: 10 targets on a wall or fence — aim for exact spots (3 min)\n• Weak foot only: dribble figure-8 around 2 cones, 5 full minutes on weak foot (5 min, no shortcuts)\n\n⚡ **1v1 & Finishing** (8 min)\n• Step-over + acceleration: 5 reps each direction\n• Near-post finish from the angle: 10 shots\n• Far-post curl: 5 shots each foot\n\n🏃 **Fitness** (5 min)\n• Box-to-box sprints × 4 with ball at feet\n• Lateral shuffle 20 yards → sprint forward — 4 reps\(wearableInsight)\n\nWhat position do you play? I can target the session to that."
                actions = ["Log This Workout", "View Drill Library"]
                followUps = ["What position do you play?", "Is your weak foot or first touch the bigger gap right now?"]
            } else {
                response = "Let's level up your game! ⚽\n\nI can help with:\n• **First touch** — controlling every ball surface, turning quickly\n• **Passing** — accuracy, weight, one-touch combinations, switches\n• **Weak foot** — making your non-dominant foot a weapon, not a liability\n• **Dribbling** — 1v1 moves, acceleration, tight-space control\n• **Finishing** — near-post, far-post curl, volleys, composure in front of goal\n• **Conditioning** — soccer-specific speed and repeated sprint fitness\n\nWhat do you want to work on?\(wearableInsight)"
                actions = ["Get a Workout", "Work on Weak Foot", "Finishing Drills"]
                followUps = ["What position do you play?", "What's the biggest gap in your game right now?"]
            }
            
        case .tennis:
            if lowercased.contains("workout") || lowercased.contains("drill") || lowercased.contains("minute") {
                let duration = extractDuration(from: lowercased) ?? 20
                response = "Here's your \(duration)-minute tennis workout:\n\n🎾 **Warm-Up** (3 min)\n• Shadow swings — forehand + backhand\n• Light rally (mini-tennis inside service box)\n\n🎯 **Groundstrokes** (\(max(duration/3, 5)) min)\n• Cross-court forehands — 20 balls\n• Cross-court backhands — 20 balls\n• Down-the-line alternating — 20 balls\n\n💪 **Serve Practice** (\(max(duration/3, 5)) min)\n• Flat serves — 10 to deuce, 10 to ad\n• Kick serves — 10 total\n• Serve + first ball — 5 point plays\n\n⚡ **Movement** (\(max(duration/4, 3)) min)\n• Split-step + recovery drill\n• Approach shot → volley → overhead — 10 reps\(wearableInsight)\(readinessInsight)"
                actions = ["Log This Workout", "View Drill Library"]
                followUps = ["Do you have a hitting partner?", "What shot needs the most work?"]
            } else if lowercased.contains("serve") {
                response = "The serve is the most important shot in tennis — you control it 100%.\n\n**Key Fundamentals:**\n1. **Grip**: Continental (like holding a hammer)\n2. **Toss**: In front, slightly to your right (right-handers), at full arm extension height\n3. **Trophy Position**: Racket behind your head, weight on back foot\n4. **Contact**: Reach up and slightly forward — full extension\n5. **Follow Through**: Racket finishes on opposite hip\n\n**Practice Routine:**\n• 10 serves focusing on toss only (catch it, don't swing)\n• 10 serves at 50% power — focus on contact point\n• 10 serves at 75% power — add placement\n• 10 serves match-intensity\n\nConsistency > power. A reliable 85% serve beats a 50% rocket.\(wearableInsight)"
                actions = ["Start Serve Drill", "Work on Kick Serve"]
                followUps = ["What's your first serve percentage?", "Any shoulder pain when serving?"]
            } else {
                response = "Let's sharpen your game! 🎾\n\nI can help with:\n• **Stroke technique** — forehand, backhand, volleys, serve\n• **Match strategy** — patterns, shot selection, mental game\n• **Physical conditioning** — court movement, endurance, explosiveness\n• **Point construction** — how to build and finish points\n• **Match preparation** — warm-up routines, pre-match plans\n\nWhat do you want to work on?\(wearableInsight)"
                actions = ["Get a Workout", "Improve My Serve", "Match Strategy"]
                followUps = ["What's your playing level (NTRP/UTR)?", "What shot do you rely on most?"]
            }
        }
        
        // Append weak point focus note to every response path
        if !weakPointInsight.isEmpty && !response.isEmpty {
            response += weakPointInsight
        }

        return CoachMessageResponse(
            response: response,
            suggestedActions: actions,
            tone: tone,
            followUpQuestions: followUps,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }
    
    /// Extract duration in minutes from a message like "20-minute" or "30 minutes"
    private func extractDuration(from text: String) -> Int? {
        let patterns = [
            try? NSRegularExpression(pattern: "(\\d+)[- ]?min"),
            try? NSRegularExpression(pattern: "(\\d+)[- ]?minute")
        ]
        for pattern in patterns.compactMap({ $0 }) {
            if let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return Int(text[range])
            }
        }
        return nil
    }
    
    // MARK: - Follow-Up Continuation (local coaching engine)

    /// Called when the user's message is a follow-up to the coach's previous response.
    /// Never resets to a generic intro — always continues the thread.
    private func buildFollowUpResponse(
        lowercased: String,
        priorContent: String,
        sport: Sport,
        wearableInsight: String,
        weakPointInsight: String
    ) -> CoachMessageResponse {
        let sportName = sport.rawValue.capitalized
        var response = ""
        var actions = sportActions(for: sport)

        // "Expand" / "more detail" / "go deeper"
        if lowercased.contains("expand") || lowercased.contains("more detail") || lowercased.contains("go deeper")
            || lowercased.contains("elaborate") || lowercased.contains("dive deeper") {
            response = "Let me go deeper on that.\n\n\(sportDepthContent(sport: sport))\(wearableInsight)\(weakPointInsight)"

        // "Make it shorter" / "simpler" / "tl;dr"
        } else if lowercased.contains("shorter") || lowercased.contains("simpler")
            || lowercased.contains("tl;dr") || lowercased.contains("tldr") || lowercased.contains("simple version") {
            let bullets = priorContent
                .components(separatedBy: "\n")
                .filter { $0.hasPrefix("•") || $0.hasPrefix("-") || $0.hasPrefix("**") }
                .prefix(5)
                .joined(separator: "\n")
            let condensed = bullets.isEmpty ? sportKeyTakeaway(sport: sport) : bullets
            response = "Here's the condensed version:\n\n\(condensed)\n\nKey rule: quality reps beat quantity every time."

        // "Turn that into drills"
        } else if lowercased.contains("drill") || lowercased.contains("turn that into") {
            response = "Here are those points formatted as drills:\n\n\(sportDrillBreakdown(sport: sport))"
            actions = ["View Drill Library", "Log This Workout"]

        // "What about tomorrow"
        } else if lowercased.contains("tomorrow") {
            response = "For tomorrow — complementary to today's work:\n\n\(sportTomorrowContent(sport: sport))\(wearableInsight)"

        // Time constraint: "only have 10 minutes" / "what if I only have"
        } else if lowercased.contains("only have") || lowercased.contains("only got") || lowercased.contains("just have") {
            let mins = extractDuration(from: lowercased) ?? 10
            response = "With \(mins) minutes, go straight to the highest-leverage item:\n\n\(sportCondensedPlan(sport: sport, minutes: mins))\(wearableInsight)"
            actions = ["Start Timer", "Log This Workout"]

        // "Focus on first" / "start with"
        } else if lowercased.contains("first") || lowercased.contains("start with") || lowercased.contains("priority") {
            response = "Start here — this is the highest-leverage thing for \(sportName):\n\n\(sportTopPriority(sport: sport))\(weakPointInsight)"
            actions = ["Start Timer"] + sportActions(for: sport).prefix(1)

        // Generic: "based on that", "what you said", "on what I said"
        } else {
            response = "Building on that:\n\n\(sportGenericContinuation(sport: sport))\(wearableInsight)\(weakPointInsight)"
        }

        return CoachMessageResponse(
            response: response,
            suggestedActions: actions,
            tone: "supportive",
            followUpQuestions: ["Want me to adjust anything about this?", "Any specific part you want me to drill down on?"],
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Sport-specific action buttons — never default to basketball actions in a football/soccer/tennis session
    private func sportActions(for sport: Sport) -> [String] {
        switch sport {
        case .basketball: return ["Log This Workout", "View Drill Library", "Start Timer"]
        case .football:   return ["Log This Workout", "Position Drills", "Speed Training"]
        case .soccer:     return ["Log This Workout", "View Drill Library", "Start Timer"]
        case .tennis:     return ["Log This Workout", "Serve Practice", "Find a Court"]
        }
    }

    private func sportDepthContent(sport: Sport) -> String {
        switch sport {
        case .basketball:
            return "**Shooting — the details most guides skip:**\n• Your shot starts at your feet. Misaligned stance creates upper-body compensation and an inconsistent arc.\n• Elbow: tucked directly under the ball, not flared outward.\n• Follow through: hold your release for a full second — trains arc muscle memory.\n• BEEF: Balance → Eyes on rim → Elbow tucked → Follow through.\n\n**Ball Handling — going further:**\n• Every crossover should have a convincing head-and-shoulder fake first. The ball move alone won't beat a good defender.\n• Weak-hand development: 10 minutes daily, weak hand only. No exceptions. Results in 3 weeks.\n• Game speed in practice: dribble at game pace or you're training the wrong speed."
        case .football:
            return "**Route Running — what separates good from great:**\n• Your stem (the straight part before the break) must look identical on every route. If you slow down early, the DB knows the route.\n• Sell vertical before you break. Make the defensive back think you're going deep.\n• At the break: plant hard on your outside foot, drive off that plant. Soft breaks = no separation.\n\n**Catching — the concentration side:**\n• Watch the ball all the way into your hands. Every time. Even in practice.\n• Catch with your hands, not your body. Let the ball come to you.\n• Bad hands in practice become bad hands in games. There are no shortcuts."
        case .soccer:
            return "**First Touch — what elite players do differently:**\n• They angle their body before the ball arrives so their first touch already points toward where they want to go.\n• On a driven pass: firm surface (inside of foot), absorb by pulling back slightly at contact.\n• On a bouncing ball: don't rush. Let it come to you. One extra half-second sets up a clean second touch.\n\n**Weak Foot — the honest truth:**\n• Your weak foot feels bad because you've done 95% of your reps with your strong foot. It's a volume problem.\n• Fix: enforce weak-foot-only sessions. 20 minutes, no exceptions. In three weeks you'll see a real change.\n• Game rule: in training, any time you'd naturally use your strong foot, force the weak foot instead."
        case .tennis:
            return "**Forehand — the mechanics that matter most:**\n• Unit turn: your shoulders rotate as a unit, not your arm in isolation. This loads power before you swing.\n• Swing path: low to high creates topspin. The more vertical, the higher bounce.\n• Contact point: in front and to your side, not beside your hip. Late contact = no power, no control.\n\n**Serve — the one detail that unlocks everything:**\n• The toss is the serve. If your toss is consistent, everything else is repeatable.\n• Practice the toss alone: 20 tosses, no swing, catching at the peak. Get it to land in the same place every time.\n• Continental grip. Everything else follows from that — slice, flat, kick."
        }
    }

    private func sportKeyTakeaway(sport: Sport) -> String {
        switch sport {
        case .basketball: return "Shoot more, handle under pressure, and lock in on defense. Everything else follows."
        case .football: return "Sharp route breaks, clean hands, explosive first step. That's what creates separation."
        case .soccer: return "First touch, weak foot, and reading space. Get those right and your whole game lifts."
        case .tennis: return "Consistent toss on the serve, reliable cross-court rally ball, and a disciplined between-point routine."
        }
    }

    private func sportDrillBreakdown(sport: Sport) -> String {
        switch sport {
        case .basketball:
            return "**Drill 1: Mikan Drill** (5 min)\n• Alternate layups off the glass from both sides without stopping. Left, right, left, right. Develops weak-hand finishing under the basket.\n\n**Drill 2: 5-Spot Shooting** (10 min)\n• 5 spots on the arc — corner, wing, top, other wing, other corner — 5 makes each before moving.\n\n**Drill 3: Chair Dribbling** (5 min)\n• Stationary crossover series: crossover, through-legs, behind-back, hesitation. 1 min each move."
        case .football:
            return "**Drill 1: 5-10-5 Pro Agility** (10 min)\n• Start in 3-point stance, sprint 5 yards right, plant, sprint 10 yards left, plant, sprint 5 yards back. 4 reps.\n\n**Drill 2: Route + Catch** (10 min)\n• Run your 5 core routes (out, in, post, corner, seam). Focus on sharp breaks and hands-only catches.\n\n**Drill 3: 40-Yard Sprint** (5 min)\n• 4 full-effort 40s with 60s rest. Time yourself if possible."
        case .soccer:
            return "**Drill 1: Wall Passing** (8 min)\n• 1-touch and 2-touch passes against a wall. Both feet. Count your streak of clean first touches.\n\n**Drill 2: Weak Foot Figure-8** (8 min)\n• Dribble figure-8 around 2 cones, weak foot only. Tight control, ball close to your feet.\n\n**Drill 3: Finishing** (10 min)\n• 5 shots near-post from the angle, 5 shots far-post curl. Both feet. Track makes vs. attempts."
        case .tennis:
            return "**Drill 1: Cross-Court Rally** (10 min)\n• With a partner or ball machine: 30-ball cross-court forehand and backhand rallies. Focus on depth.\n\n**Drill 2: Serve Routine** (10 min)\n• 10 serves: toss only (no swing), 10 at 50% power, 10 at 75% placement, 10 match-intensity.\n\n**Drill 3: Approach → Volley** (5 min)\n• Approach shot from mid-court → move to net → volley → overhead. 10 sequences."
        }
    }

    private func sportTomorrowContent(sport: Sport) -> String {
        switch sport {
        case .basketball: return "**Tomorrow: Recovery + Shot Work**\n• Light stretching 10 min\n• Form shooting from 5 feet — 50 makes with perfect mechanics\n• Free throws: 25 shots, track percentage\n• No heavy conditioning — let your legs recover."
        case .football:   return "**Tomorrow: Film + Mental Reps**\n• Watch 15 min of your sport at the position you play — study one specific aspect\n• Walk through your routes mentally — 10 full routes in your head with perfect detail\n• Light stretch and mobility work only — let your explosiveness recover."
        case .soccer:     return "**Tomorrow: Touch + Fitness**\n• 10 min of weak-foot juggling (just your weak foot)\n• 15 min of passing patterns against a wall\n• 2×10 min runs at 70% effort — soccer-specific aerobic base work."
        case .tennis:     return "**Tomorrow: Serve + Movement**\n• 30-minute serve session only — placement and consistency focus\n• Footwork patterns on court: split step → recovery shuffle × 20 reps each side\n• No full point play — keep intensity low so your arm recovers."
        }
    }

    private func sportCondensedPlan(sport: Sport, minutes: Int) -> String {
        switch sport {
        case .basketball: return "🏀 **\(minutes)-Minute Express**\n• Warm up with ball (2 min)\n• 5-spot shooting: 3 makes per spot, keep moving (\(max(minutes/2, 5)) min)\n• Free throws: 10 shots to finish (\(max(minutes/4, 3)) min)"
        case .football:   return "🏈 **\(minutes)-Minute Express**\n• Dynamic warm-up: 10 high knees, 10 butt kicks, 2 build-up sprints (3 min)\n• 5-10-5 shuttle × 3 reps (3 min)\n• Route running: your 2 best routes, 5 reps each (remaining time)"
        case .soccer:     return "⚽ **\(minutes)-Minute Express**\n• Juggling warm-up: strong foot then weak foot (2 min)\n• Wall passing 1-touch: 50 touches (3 min)\n• Finishing drill: 10 near-post shots from the angle (remaining time)"
        case .tennis:     return "🎾 **\(minutes)-Minute Express**\n• Shadow swings: forehand + backhand (2 min)\n• Serve routine: 10 tosses + 10 serves at 75% (5 min)\n• 5 forehand and 5 backhand cross-court rallies if partner available (remaining time)"
        }
    }

    private func sportTopPriority(sport: Sport) -> String {
        switch sport {
        case .basketball: return "**Shooting form** — everything else is secondary. Set up proper foot alignment, elbow tuck, and follow through. Do 25 form shots from 5 feet before any other drill. If your form is off, distance and volume make it worse, not better."
        case .football:   return "**Explosive first step** — most plays in football are decided in the first 3 yards. Work your 5-10-5 shuttle first. Then route running. Conditioning comes last, not first."
        case .soccer:     return "**Weak foot control** — it's probably your biggest gap. Spend the first 10 minutes dribbling and passing with your weak foot only, before you touch your strong foot. This is the highest-leverage use of limited time."
        case .tennis:     return "**Serve toss consistency** — everything else in your game flows from a consistent toss. Before you hit anything else, do 20 tosses catching at the peak. Then 10 serves at 50% power focusing only on toss placement."
        }
    }

    private func sportGenericContinuation(sport: Sport) -> String {
        switch sport {
        case .basketball: return "The core principle in basketball development: reps with intention beat volume without focus. Work on your shooting first (the highest-leverage skill), then handles, then conditioning. What specifically did you want to go deeper on?"
        case .football:   return "In football, your biggest competitive edge comes from short-area quickness and hands. Route sharpness → catching reliability → explosiveness. These are the skills that separate players at any level. What part of the game feels most underdeveloped?"
        case .soccer:     return "In soccer, technical quality is the foundation — everything tactical sits on top of it. First touch, weak foot, and passing weight. Get those airtight and everything else becomes easier. Where do you feel the biggest gap right now?"
        case .tennis:     return "Tennis improvement follows a clear path: serve reliability → forehand depth → backhand consistency → footwork. Most players neglect serve practice. If you're not spending 20–30% of your session on serve, that's the first thing to fix. What do you want to dig into?"
        }
    }

    /// Handles queries about athletic development — speed, strength, conditioning, agility, vertical, flexibility.
    /// Called before sport-specific branches so athleticism queries don't accidentally hit skill keyword matches.
    private func buildAthleticDevelopmentResponse(
        sport: Sport,
        lowercased: String,
        wearableInsight: String,
        weakPointInsight: String
    ) -> CoachMessageResponse {
        let speedFocused = lowercased.contains("speed") || lowercased.contains("faster") || lowercased.contains("quicker")
        let strengthFocused = lowercased.contains("strength") || lowercased.contains("stronger") || lowercased.contains("power")
        let verticalFocused = lowercased.contains("vertical")
        let agilityFocused = lowercased.contains("agility") || lowercased.contains("agile")

        var response = ""
        var actions = sportActions(for: sport)
        var followUps: [String] = []

        switch sport {
        case .basketball:
            if verticalFocused {
                response = "Increasing your vertical is very doable — here's what actually works:\n\n**Plyometric Foundation (3× per week):**\n• Box jumps: 3 sets × 5 reps — land softly, reset fully between reps\n• Depth drops: step off a box, land in athletic position — trains reactive strength\n• Broad jumps: 3 sets × 5 reps — maximum horizontal-to-vertical power\n\n**Strength Base (2× per week):**\n• Squats: 3 sets × 5 reps, heavy — glutes and quads drive jump height\n• Bulgarian split squats: single-leg stability to fix imbalances\n• Calf raises: 3 sets × 15 reps, slow and controlled\n\n**Key Rule:**\nVertical gains come from both reactive strength (plyos) and raw leg power (squats). Plyos alone plateau fast. You need both.\n\nExpect 2–4 inches gained in 8–12 weeks of consistent work.\(wearableInsight)"
                actions = ["Log This Workout", "View Drill Library"]
                followUps = ["Do you have access to a gym or weight room?", "How many days a week can you commit to this?"]
            } else if speedFocused || agilityFocused {
                response = "On-court speed for basketball is about first-step quickness, change-of-direction, and defensive foot speed — not 40-yard dash speed.\n\n**Speed & Agility Circuit (3× per week):**\n• Defensive slides baseline-to-baseline: 3 sets — stay low, don't cross your feet\n• Suicide runs × 4: touch baseline, near elbow, half-court, far elbow, far baseline\n• 5-cone star drill: burst to each cone, back to center — 3 sets\n• First-step accelerations: 3-cone sprints × 6 — explosiveness from a standing start\n\n**The Key Principle:**\nYour first step off a defensive stance or post-catch is what decides plays. Always train from a 0-to-full-speed start — never a running start.\(wearableInsight)"
                actions = ["Log This Workout", "Start Timer"]
                followUps = ["Are you working on offensive speed or defensive quickness?", "Do you have access to a court?"]
            } else if strengthFocused {
                response = "Basketball strength shows up as finishing through contact, holding position on defense, and not getting outmuscled in the post.\n\n**Basketball-Specific Strength (2–3× per week):**\n• Squats: 3 × 5 — leg drive for jumping and posting up\n• Romanian deadlifts: 3 × 8 — posterior chain for stability and injury prevention\n• Push-ups + rows: 3 × 12 each — balanced upper body that keeps your shot clean\n• Planks: 3 × 45 seconds — core stability translates directly to finishing through contact\n\n**Key Rule:**\nDon't train like a powerlifter. The 5–8 rep range is your sweet spot — heavy enough to build real strength, light enough to stay explosive.\(wearableInsight)"
                actions = ["Log This Workout", "View Drill Library"]
                followUps = ["Do you have gym access?", "Are you building strength for offense, defense, or both?"]
            } else {
                response = "Basketball conditioning is repeated-sprint fitness — you need to recover fast between explosive efforts, not just run long distances.\n\n**Basketball Conditioning (3× per week, non-consecutive days):**\n• Suicide runs × 5 with 60s rest — track your time, aim to stay consistent across all 5\n• 17s drill: baseline-to-baseline 17 times in 60 seconds × 3 sets (NBA conditioning standard)\n• Defensive slide series: baseline to half-court and back × 4 — lateral cardio\n• Jump rope: 3 × 2 minutes with 1 min rest — footwork and wind simultaneously\n\n**Honest Timeline:**\nIn 3 weeks of consistent work, your recovery between plays will noticeably improve. In 6 weeks, late-game energy becomes a real competitive advantage.\(wearableInsight)"
                actions = ["Log This Workout", "Start Timer"]
                followUps = ["How many days a week can you commit to conditioning?", "Are you gassing out early or late in games?"]
            }

        case .football:
            if speedFocused || agilityFocused {
                response = "Football speed development focuses on the first 10 yards — most plays are decided in the first 3 yards off the line, not the 40-yard dash.\n\n**Speed Development (3× per week):**\n• Resisted sprints: 4 × 20 yards with a resistance band or sled — builds drive-phase power\n• 5-10-5 pro agility shuttle: 6 reps, full recovery — the most game-relevant short-area drill\n• Wall drills: drive your knee while bracing against a wall — trains proper sprint mechanics\n• Flying 20s: jog 10 yards → sprint 20 yards full effort — 5 reps with full recovery\n\n**Position Note:**\nFor skill positions (WR, DB, RB): first-step quickness and COD matter more than top speed. For linemen: power and 5-yard burst are what translate.\(wearableInsight)"
                actions = ["Log This Workout", "Position Drills", "Speed Training"]
                followUps = ["What position do you play?", "Are you training for a tryout or in-season improvement?"]
            } else if strengthFocused {
                response = "Football strength is functional — blocking power, tackle-breaking ability, and driving through contact at full speed.\n\n**Football Strength Program (3× per week):**\n• Barbell squats: 3 × 5, heavy — lower body explosion off the line\n• Bench press: 3 × 5 — blocking and hand-fighting strength\n• Trap bar deadlifts: 3 × 5 — most position-applicable lower-body pull\n• Power cleans: 3 × 3 — teaches your body to generate force explosively\n• Farmer's carries: 40 yards × 4 — grip, core, and functional conditioning\n\n**Key Principle:**\nStrength without explosive expression is wasted in football. Pair strength days with explosive drill work in the same session.\(wearableInsight)"
                actions = ["Log This Workout", "Position Drills"]
                followUps = ["What position do you play?", "Do you have access to a weight room?"]
            } else {
                response = "Football conditioning is interval-based — you need to explode, recover briefly, and explode again, repeatedly.\n\n**Football Conditioning (2–3× per week):**\n• 40-yard sprints × 6 with 45s rest — game-speed conditioning\n• Gassers (sideline-to-sideline × 4) × 3 sets — full-field endurance\n• Bear crawl 20 yards → sprint 20 yards → bear crawl back: 3 reps — positional conditioning\n• Jump rope: 3 × 90 seconds — footwork and cardio\n\n**Position Tip:**\nLinemen: lean toward gassers and bear crawls. Skill positions: 40-yard sprints and short-area agility dominate.\(wearableInsight)"
                actions = ["Log This Workout", "Speed Training"]
                followUps = ["What position do you play?", "Do you have a season or tryout coming up?"]
            }

        case .soccer:
            if speedFocused || agilityFocused {
                response = "Soccer speed is about acceleration with the ball and without it — and recovery speed getting back into defensive position.\n\n**Speed Development for Soccer (3× per week):**\n• Sprint-dribble: 30 yards at full pace with ball, 5 reps each foot\n• 10-yard acceleration × 8 from a standing start — explosive first step\n• Resistance band runs: 10-yard drive-phase sprints × 6\n• Plant-and-cut: sprint 15 yards, hard plant, cut left or right — 5 reps each direction\n\n**Training Truth:**\nSpeed with the ball and speed without it are different skills. You need to train both. A player who's fast off-ball but slow on-ball loses the advantage immediately.\(wearableInsight)"
                actions = ["Log This Workout", "View Drill Library"]
                followUps = ["What position do you play?", "Do you play on natural grass or turf?"]
            } else if strengthFocused {
                response = "Soccer strength is functional — winning aerial duels, shielding the ball, and staying balanced under defensive pressure.\n\n**Soccer Strength (2–3× per week):**\n• Bulgarian split squats: 3 × 8 each leg — single-leg stability for striking and turning\n• Nordic hamstring curls: 3 × 5 — the best injury-prevention exercise in soccer\n• Core circuit: dead bugs, pallof press, side planks — 3 rounds\n• Upper body: rows and push-ups — maintain posture when pressed from behind\n\n**Injury Prevention Note:**\nHamstring and groin injuries are the most common in soccer. Nordic curls and targeted hip work are the most evidence-backed prevention. Don't skip them.\(wearableInsight)"
                actions = ["Log This Workout", "View Drill Library"]
                followUps = ["Are you dealing with any current injuries?", "Do you have access to a gym?"]
            } else {
                response = "Soccer conditioning is 90-minute mixed-intensity fitness — you need both aerobic base AND repeated-sprint capacity.\n\n**Soccer Conditioning (3× per week):**\n• Box-to-box runs: sprint half-field, jog back × 6 — mimics in-game demands\n• Fartlek: 20-minute run alternating 2 min steady + 1 min hard sprint — aerobic base\n• Ball circuit: dribble + sprint + pass sequence × 5 reps — conditioning with technique\n• Lateral shuttle with ball: 20 yards each direction × 5 sets — soccer-specific lateral work\n\n**Recovery Tip:**\nPost-session, 5 minutes of static stretching on hip flexors, hamstrings, and calves. These tighten first and affect your next session most.\(wearableInsight)"
                actions = ["Log This Workout", "View Drill Library"]
                followUps = ["How many practices per week do you already have?", "Are you in-season or off-season?"]
            }

        case .tennis:
            if speedFocused || agilityFocused {
                response = "Court speed in tennis is lateral agility and split-step timing — not straight-line speed.\n\n**Court Movement Training (3× per week):**\n• Split-step drill: shadow every shot with proper split-step → recovery shuffle → split-step — 15 min\n• Lateral shuffle baseline: 10 lengths at full intensity with 30s rest — pure lateral conditioning\n• Spider drill: start at center mark, sprint to each corner and sideline, recover to center — 5 reps\n• Reaction footwork: ladder or cone patterns — 10 min under fatigue\n\n**Most-Missed Detail:**\nThe split-step timing is everything. Most players forget to split-step consistently and start every point flat-footed. Your split should fire as your opponent makes contact — not before, not after.\(wearableInsight)"
                actions = ["Log This Workout", "Find a Court"]
                followUps = ["Is your main gap lateral speed or first-step quickness to the ball?", "Do you have court access to work on movement?"]
            } else if strengthFocused {
                response = "Tennis strength training is about rotational power, shoulder stability, and injury prevention — not size.\n\n**Tennis Strength (2× per week):**\n• Rotational med ball throws: 3 × 8 each side — mimics forehand and serve power transfer\n• Romanian deadlifts: 3 × 8 — leg drive for serve and groundstrokes\n• External rotation (rotator cuff): 3 × 15 each arm — shoulder injury prevention\n• Wrist and forearm work: rice bucket or reverse wrist curls — prevents tennis elbow\n\n**Warning:**\nDon't skip shoulder health work. Rotator cuff injuries are the most common career-limiting injuries in tennis. External rotation with a light band 2–3× per week is prevention, not optional.\(wearableInsight)"
                actions = ["Log This Workout", "Serve Practice"]
                followUps = ["Have you had any shoulder or elbow issues?", "Do you have gym access?"]
            } else {
                response = "Tennis conditioning is short bursts with quick recovery — points average 4–10 seconds, then 20–25 seconds rest between points.\n\n**Tennis-Specific Conditioning (3× per week):**\n• 10-second sprint, 20-second jog, repeat × 20 — mirrors actual match energy demands\n• Court sprints: baseline-to-net and back × 10 with 30s rest — conditioning and footwork combined\n• Jump rope: 3 × 2 minutes — footwork and cardio base\n• Match simulation: 5 points at full effort with point-length rest between each\n\n**Aerobic Base:**\nAlso do 1–2 moderate sessions per week (30-min jog or bike). A stronger aerobic base makes your 25-second recovery windows between points more effective.\(wearableInsight)"
                actions = ["Log This Workout", "Find a Court"]
                followUps = ["Do you have a practice partner for conditioning sets?", "How long are your typical matches?"]
            }
        }

        if !weakPointInsight.isEmpty {
            response += weakPointInsight
        }

        return CoachMessageResponse(
            response: response,
            suggestedActions: actions,
            tone: "motivational",
            followUpQuestions: followUps,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
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
    
    // MARK: - Training API

    /// Fetch curated drill catalog for a sport, optionally filtered by focus area.
    func getTrainingDrills(sport: String, focusArea: String? = nil, difficulty: String? = nil) async throws -> [APIDrillResponse] {
        var endpoint = "/training/drills?sport=\(sport)"
        if let area = focusArea { endpoint += "&focus_area=\(area)" }
        if let diff = difficulty { endpoint += "&difficulty=\(diff)" }
        return try await get(endpoint)
    }

    /// Fetch drill categories for a sport.
    func getTrainingDrillCategories(sport: String) async throws -> DrillCategoriesResponse {
        return try await get("/training/drills/categories?sport=\(sport)")
    }

    /// Persist a completed training session to the backend.
    /// drills: array of DrillLogEntryRequest objects.
    /// aiAnalysis: optional dict from analyzeTrainingSession (pass nil if AI call fails).
    func logTrainingSession(
        sport: Sport,
        drills: [DrillEntry],
        notes: String?,
        aiAnalysis: TrainingAnalysisResponse? = nil
    ) async throws -> TrainingSessionResponse {
        struct DrillPayload: Encodable {
            let drill_name: String
            let drill_order: Int
            let duration: Int
            let effort: String?
            let metric_type: String?
            let metric_value: String?
            let notes: String?
        }
        struct Body: Encodable {
            let sport: String
            let drills: [DrillPayload]
            let notes: String?
            let ai_performance_rating: Double?
            let ai_insights: [String]?
            let ai_areas_to_improve: [String]?
            let ai_next_session_recs: [String]?
        }
        let drillPayloads = drills.enumerated().map { idx, d in
            DrillPayload(
                drill_name: d.drillName,
                drill_order: idx,
                duration: d.duration,
                effort: d.effort.rawValue,
                metric_type: d.metricType?.rawValue,
                metric_value: d.metricValue.isEmpty ? nil : d.metricValue,
                notes: d.notes.isEmpty ? nil : d.notes
            )
        }
        let body = Body(
            sport: sport.rawValue,
            drills: drillPayloads,
            notes: notes?.isEmpty == true ? nil : notes,
            ai_performance_rating: aiAnalysis?.performanceRating,
            ai_insights: aiAnalysis?.insights,
            ai_areas_to_improve: aiAnalysis?.areasToImprove,
            ai_next_session_recs: aiAnalysis?.nextSessionRecommendations
        )
        return try await post("/training/sessions", body: body)
    }

    /// Fetch training session history for the current user.
    func getTrainingHistory(sport: Sport? = nil, limit: Int = 20) async throws -> [TrainingSessionResponse] {
        var endpoint = "/training/sessions?limit=\(limit)"
        if let s = sport { endpoint += "&sport=\(s.rawValue)" }
        return try await get(endpoint)
    }

    /// Save a custom workout plan.
    func saveWorkout(name: String, sport: Sport, drills: [DrillEntry], description: String? = nil) async throws -> SavedWorkoutResponse {
        struct DrillDict: Encodable {
            let drill_name: String; let duration: Int; let effort: String?
        }
        struct Body: Encodable {
            let sport: String; let name: String; let description: String?
            let drills: [[String: String]]
        }
        let drillDicts: [[String: String]] = drills.map { d in
            var dict: [String: String] = ["drill_name": d.drillName, "duration": "\(d.duration)", "effort": d.effort.rawValue]
            if let mt = d.metricType { dict["metric_type"] = mt.rawValue }
            if !d.metricValue.isEmpty { dict["metric_value"] = d.metricValue }
            return dict
        }
        let body = Body(sport: sport.rawValue, name: name, description: description, drills: drillDicts)
        return try await post("/training/workouts", body: body)
    }

    /// Fetch user's saved workout plans.
    func getSavedWorkouts(sport: Sport? = nil) async throws -> [SavedWorkoutResponse] {
        var endpoint = "/training/workouts"
        if let s = sport { endpoint += "?sport=\(s.rawValue)" }
        return try await get(endpoint)
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

struct ConversationMessage: Codable {
    let role: String   // "user" or "assistant"
    let content: String
}

struct CoachMessageRequest: Codable {
    let message: String
    let sport: String
    var context: CoachContext?
    var conversationHistory: [ConversationMessage]?

    enum CodingKeys: String, CodingKey {
        case message, sport, context
        case conversationHistory = "conversation_history"
    }
}

struct CoachContext: Codable {
    var weakPoints: [String]?
    var goals: [String]?
    var availableTime: Int?
    var readinessLevel: String?
    var recentTraining: String?
    var wearableData: WearableContext?
    var latestConcern: String?      // Most recently mentioned weak area — highest-priority coaching signal
    var inferredIntent: String?     // What the user is trying to do ("weakness_help", "elaboration", etc.)
    var semanticConcepts: [String]? // Athletic/skill concepts inferred from natural-language phrasing
    var coachingBrief: String?      // Pre-analyzed reasoning brief: weakness type, impact, plan, constraints — ready for GPT-4
    // Onboarding survey fields — first-class coaching context from day one
    var surveyMainSport: String?
    var surveySkillRatings: [String: Int]?  // e.g. {"shooting": 7, "dribbling": 5}
    var surveyStrengths: [String]?
    var surveyWeaknesses: [String]?         // Seeded into coaching brief as baseline weak areas
    /// When true, backend injects strict contract rules into the GPT system prompt.
    /// Set by iOS when the first GPT response failed post-response validation.
    /// Triggers one final constrained GPT attempt before falling back to local coaching.
    var constrainedMode: Bool?

    enum CodingKeys: String, CodingKey {
        case weakPoints = "weak_points"
        case goals
        case availableTime = "available_time"
        case readinessLevel = "readiness_level"
        case recentTraining = "recent_training"
        case wearableData = "wearable_data"
        case latestConcern = "latest_concern"
        case inferredIntent = "inferred_intent"
        case semanticConcepts = "semantic_concepts"
        case coachingBrief = "coaching_brief"
        case surveyMainSport = "survey_main_sport"
        case surveySkillRatings = "survey_skill_ratings"
        case surveyStrengths = "survey_strengths"
        case surveyWeaknesses = "survey_weaknesses"
        case constrainedMode = "constrained_mode"
    }
}

struct WearableContext: Codable {
    var restingHeartRate: Double?
    var hrv: Double?
    var sleepHours: Double?
    var stepsToday: Int?
    var recoveryScore: String?
    
    enum CodingKeys: String, CodingKey {
        case restingHeartRate = "resting_heart_rate"
        case hrv
        case sleepHours = "sleep_hours"
        case stepsToday = "steps_today"
        case recoveryScore = "recovery_score"
    }
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

// MARK: - Matchmaking Availability
extension APIClient {
    func updateAvailability(sport: String, available: Bool) async throws {
        // Availability status update - if backend endpoint doesn't exist yet, this will gracefully fail
        struct AvailabilityRequest: Codable {
            let sport: String
            let available: Bool
        }
        let request = AvailabilityRequest(sport: sport, available: available)
        let _: EmptyResponse? = try? await put("/matchmaking/availability", body: request)
    }
}

// MARK: - Smartwatch/Wearable Sync API
// Backend router: /smartwatch (smartwatch.py)
// Endpoints: connect, connection, disconnect, sync, data/recent, recovery-status
extension APIClient {
    /// Get current smartwatch connection status
    func getSmartwatchConnection() async throws -> SmartwatchConnection {
        try await get("/smartwatch/connection")
    }
    
    /// Connect a smartwatch/fitness tracker
    func connectSmartwatch(request: ConnectDeviceRequest) async throws -> SmartwatchConnection {
        print("🔗 [APIClient] Connecting smartwatch: \(request.deviceType)")
        
        // Simulator: HealthKit available but no real watch data — use simulator connection
        #if DEBUG
        if isSimulator() {
            print("📱 [APIClient] Running in simulator — using simulator connection data")
            return createSimulatorConnection(deviceType: request.deviceType)
        }
        #endif
        
        do {
            let connection: SmartwatchConnection = try await post("/smartwatch/connect", body: request)
            print("✅ [APIClient] Smartwatch connected: \(connection.deviceName ?? "Unknown")")
            return connection
        } catch let error as APIError {
            print("❌ [APIClient] Smartwatch connection failed: \(error)")
            
            // If backend is unavailable in DEBUG, allow local-only operation
            if case .notFound = error {
                print("⚠️ [APIClient] Smartwatch endpoint not found — check backend is running")
                #if DEBUG
                return createSimulatorConnection(deviceType: request.deviceType)
                #else
                throw error
                #endif
            }
            
            throw error
        }
    }
    
    /// Disconnect smartwatch
    func disconnectSmartwatch() async throws -> MessageResponse {
        try await delete("/smartwatch/disconnect")
    }
    
    /// Sync biometric data to backend. Returns the server-processed data with AI metrics.
    @discardableResult
    func syncBiometricData(data: BiometricData) async throws -> BiometricData {
        print("📊 [APIClient] Syncing biometric data...")
        
        // Simulator: skip backend sync, data persisted locally by SmartwatchSyncView
        #if DEBUG
        if isSimulator() {
            print("📱 [APIClient] Simulator — data persisted locally, skipping backend sync")
            return data
        }
        #endif
        
        do {
            let response: BiometricData = try await post("/smartwatch/sync", body: data)
            print("✅ [APIClient] Biometric data synced to backend")
            return response
        } catch let error as APIError {
            if case .notFound = error {
                print("⚠️ [APIClient] Sync endpoint not found — data stored locally only")
                #if DEBUG
                return data
                #else
                throw error
                #endif
            }
            throw error
        }
    }
    
    /// Get recovery status and recommendations
    func getRecoveryStatus() async throws -> RecoveryStatus {
        print("🏃 [APIClient] Fetching recovery status...")
        
        #if DEBUG
        if isSimulator() {
            print("📱 [APIClient] Simulator — generating recovery status from local data")
            return createSimulatorRecoveryStatus()
        }
        #endif
        
        do {
            let status: RecoveryStatus = try await get("/smartwatch/recovery-status")
            print("✅ [APIClient] Recovery status received from backend")
            return status
        } catch let error as APIError {
            if case .notFound = error {
                #if DEBUG
                print("⚠️ [APIClient] Recovery endpoint not available — using local calculation")
                return createSimulatorRecoveryStatus()
                #else
                throw error
                #endif
            }
            throw error
        }
    }
    
    /// Get recent biometric data
    func getRecentBiometricData(days: Int = 7) async throws -> [BiometricData] {
        print("📈 [APIClient] Fetching recent biometric data (last \(days) days)...")
        
        #if DEBUG
        if isSimulator() {
            print("📱 [APIClient] Simulator — generating biometric history")
            return createSimulatorBiometricData(days: days)
        }
        #endif
        
        do {
            let data: [BiometricData] = try await get("/smartwatch/data/recent?days=\(days)")
            print("✅ [APIClient] Received \(data.count) data points from backend")
            return data
        } catch let error as APIError {
            if case .notFound = error {
                #if DEBUG
                print("⚠️ [APIClient] Data endpoint not available — using local data")
                return createSimulatorBiometricData(days: days)
                #else
                throw error
                #endif
            }
            throw error
        }
    }
    
    // MARK: - Simulator Data for Development
    
    #if DEBUG
    private func isSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    private func createSimulatorConnection(deviceType: String) -> SmartwatchConnection {
        let provider = WearableProvider(rawValue: deviceType) ?? .appleWatch
        return SmartwatchConnection(
            id: "mock_connection_\(UUID().uuidString)",
            userId: "current_user",
            deviceType: deviceType,
            deviceName: provider.displayName,
            deviceId: "MOCK_DEVICE_ID",
            provider: provider,
            isActive: true,
            lastSync: ISO8601DateFormatter().string(from: Date()),
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
    
    private func createSimulatorRecoveryStatus() -> RecoveryStatus {
        let readiness = Double.random(in: 65...95)
        let fatigue: String
        
        if readiness >= 85 {
            fatigue = "low"
        } else if readiness >= 70 {
            fatigue = "medium"
        } else {
            fatigue = "high"
        }
        
        let recommendations = [
            "low": "You're well-rested and ready for high-intensity training. Consider pushing your limits today.",
            "medium": "Good recovery. Suitable for moderate training with some intensity. Avoid back-to-back hard sessions.",
            "high": "Your body needs recovery. Focus on light training, mobility work, or active recovery today."
        ]
        
        let hrvStatusValue: String
        if readiness >= 85 { hrvStatusValue = "optimal" }
        else if readiness >= 70 { hrvStatusValue = "normal" }
        else { hrvStatusValue = "below_normal" }
        
        let now = ISO8601DateFormatter().string(from: Date())
        
        return RecoveryStatus(
            id: "mock_recovery_\(UUID().uuidString)",
            userId: "current_user",
            date: now,
            recoveryScore: Double.random(in: 50...95),
            readinessScore: readiness,
            fatigueLevel: fatigue,
            sleepQuality: Double.random(in: 60...95),
            hrv: Int.random(in: 40...80),
            restingHeartRate: Int.random(in: 50...70),
            hrvStatus: hrvStatusValue,
            recommendation: recommendations[fatigue] ?? "Monitor your recovery and adjust training accordingly.",
            lastUpdated: now,
            createdAt: now
        )
    }
    
    private func createSimulatorBiometricData(days: Int) -> [BiometricData] {
        let calendar = Calendar.current
        var data: [BiometricData] = []
        
        for day in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -day, to: Date()) else { continue }
            
            let readiness = Double.random(in: 60...95)
            let fatigueLevel: String
            if readiness >= 85 { fatigueLevel = "low" }
            else if readiness >= 70 { fatigueLevel = "medium" }
            else { fatigueLevel = "high" }
            
            let item = BiometricData(
                id: "mock_\(day)_\(UUID().uuidString)",
                date: ISO8601DateFormatter().string(from: date),
                restingHeartRate: Int.random(in: 50...70),
                avgHeartRate: Int.random(in: 70...90),
                maxHeartRate: Int.random(in: 140...180),
                heartRateVariability: Int.random(in: 40...80),
                sleepDuration: Int.random(in: 360...540), // 6-9 hours in minutes
                deepSleep: Int.random(in: 60...120),
                remSleep: Int.random(in: 90...150),
                lightSleep: Int.random(in: 180...270),
                sleepQualityScore: Double.random(in: 60...95),
                steps: Int.random(in: 4000...12000),
                activeCalories: Int.random(in: 300...800),
                totalCalories: Int.random(in: 1800...2500),
                exerciseMinutes: Int.random(in: 20...90),
                recoveryScore: Double.random(in: 60...95),
                trainingStrain: Double.random(in: 8...18),
                dayStrain: Double.random(in: 10...20),
                readinessScore: readiness,
                fatigueLevel: fatigueLevel,
                performancePrediction: nil,
                createdAt: ISO8601DateFormatter().string(from: date)
            )
            
            data.append(item)
        }
        
        return data.sorted { $0.date > $1.date }
    }
    #endif
}

// MARK: - Wearable Model Definitions (CANONICAL SOURCE)
// These models are defined here to ensure single source of truth

enum WearableProvider: String, Codable, CaseIterable {
    case appleWatch = "apple_watch"
    case wearOS = "wear_os"
    case fitbit = "fitbit"
    case garmin = "garmin"
    case whoop = "whoop"
    case oura = "oura"
    
    var displayName: String {
        switch self {
        case .appleWatch: return "Apple Watch"
        case .wearOS: return "Wear OS"
        case .fitbit: return "Fitbit"
        case .garmin: return "Garmin"
        case .whoop: return "WHOOP"
        case .oura: return "Oura Ring"
        }
    }
    
    var icon: String {
        switch self {
        case .appleWatch: return "applewatch"
        case .wearOS: return "watchface.watch"
        case .fitbit: return "figure.run.circle"
        case .garmin: return "location.circle.fill"
        case .whoop: return "waveform.path.ecg"
        case .oura: return "circle.hexagongrid.circle.fill"
        }
    }
    
    var isCurrentlySupported: Bool {
        return self == .appleWatch
    }
}

struct SmartwatchConnection: Codable, Identifiable {
    let id: String
    let userId: String
    let deviceType: String
    let deviceName: String?
    let deviceId: String?
    let provider: WearableProvider?
    let isActive: Bool
    let lastSync: String?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case deviceType = "device_type"
        case deviceName = "device_name"
        case deviceId = "device_id"
        case provider
        case isActive = "is_active"
        case isConnected = "is_connected"
        case lastSync = "last_sync"
        case createdAt = "created_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? ""
        deviceType = try container.decode(String.self, forKey: .deviceType)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
        provider = try container.decodeIfPresent(WearableProvider.self, forKey: .provider)
        // Backend sends "is_connected", accept both "is_active" and "is_connected"
        if let active = try? container.decode(Bool.self, forKey: .isActive) {
            isActive = active
        } else if let connected = try? container.decode(Bool.self, forKey: .isConnected) {
            isActive = connected
        } else {
            isActive = false
        }
        lastSync = try container.decodeIfPresent(String.self, forKey: .lastSync)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ISO8601DateFormatter().string(from: Date())
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(deviceType, forKey: .deviceType)
        try container.encodeIfPresent(deviceName, forKey: .deviceName)
        try container.encodeIfPresent(deviceId, forKey: .deviceId)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(lastSync, forKey: .lastSync)
        try container.encode(createdAt, forKey: .createdAt)
    }
    
    // Memberwise init for local construction
    init(id: String, userId: String, deviceType: String, deviceName: String?,
         deviceId: String?, provider: WearableProvider?, isActive: Bool,
         lastSync: String?, createdAt: String) {
        self.id = id
        self.userId = userId
        self.deviceType = deviceType
        self.deviceName = deviceName
        self.deviceId = deviceId
        self.provider = provider
        self.isActive = isActive
        self.lastSync = lastSync
        self.createdAt = createdAt
    }
}

struct ConnectDeviceRequest: Codable {
    let deviceType: String
    let deviceName: String?
    let deviceId: String?
    let accessToken: String?
    let refreshToken: String?
    
    enum CodingKeys: String, CodingKey {
        case deviceType = "device_type"
        case deviceName = "device_name"
        case deviceId = "device_id"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

struct BiometricData: Codable, Identifiable {
    let id: String
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
    let dayStrain: Double?
    let readinessScore: Double?
    let fatigueLevel: String?
    let performancePrediction: String?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, date
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
        case dayStrain = "day_strain"
        case readinessScore = "readiness_score"
        case fatigueLevel = "fatigue_level"
        case performancePrediction = "performance_prediction"
        case createdAt = "created_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        date = try container.decode(String.self, forKey: .date)
        restingHeartRate = try container.decodeIfPresent(Int.self, forKey: .restingHeartRate)
        avgHeartRate = try container.decodeIfPresent(Int.self, forKey: .avgHeartRate)
        maxHeartRate = try container.decodeIfPresent(Int.self, forKey: .maxHeartRate)
        heartRateVariability = try container.decodeIfPresent(Int.self, forKey: .heartRateVariability)
        sleepDuration = try container.decodeIfPresent(Int.self, forKey: .sleepDuration)
        deepSleep = try container.decodeIfPresent(Int.self, forKey: .deepSleep)
        remSleep = try container.decodeIfPresent(Int.self, forKey: .remSleep)
        lightSleep = try container.decodeIfPresent(Int.self, forKey: .lightSleep)
        sleepQualityScore = try container.decodeIfPresent(Double.self, forKey: .sleepQualityScore)
        steps = try container.decodeIfPresent(Int.self, forKey: .steps)
        activeCalories = try container.decodeIfPresent(Int.self, forKey: .activeCalories)
        totalCalories = try container.decodeIfPresent(Int.self, forKey: .totalCalories)
        exerciseMinutes = try container.decodeIfPresent(Int.self, forKey: .exerciseMinutes)
        recoveryScore = try container.decodeIfPresent(Double.self, forKey: .recoveryScore)
        trainingStrain = try container.decodeIfPresent(Double.self, forKey: .trainingStrain)
        dayStrain = try container.decodeIfPresent(Double.self, forKey: .dayStrain)
        readinessScore = try container.decodeIfPresent(Double.self, forKey: .readinessScore)
        fatigueLevel = try container.decodeIfPresent(String.self, forKey: .fatigueLevel)
        // Backend sends performance_prediction as float, accept both float and string
        if let floatVal = try? container.decodeIfPresent(Double.self, forKey: .performancePrediction) {
            performancePrediction = String(format: "%.1f%%", floatVal)
        } else {
            performancePrediction = try container.decodeIfPresent(String.self, forKey: .performancePrediction)
        }
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ISO8601DateFormatter().string(from: Date())
    }
    
    // Memberwise init for local construction
    init(id: String, date: String, restingHeartRate: Int?, avgHeartRate: Int?,
         maxHeartRate: Int?, heartRateVariability: Int?, sleepDuration: Int?,
         deepSleep: Int?, remSleep: Int?, lightSleep: Int?, sleepQualityScore: Double?,
         steps: Int?, activeCalories: Int?, totalCalories: Int?, exerciseMinutes: Int?,
         recoveryScore: Double?, trainingStrain: Double?, dayStrain: Double?,
         readinessScore: Double?, fatigueLevel: String?, performancePrediction: String?,
         createdAt: String) {
        self.id = id; self.date = date
        self.restingHeartRate = restingHeartRate; self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate; self.heartRateVariability = heartRateVariability
        self.sleepDuration = sleepDuration; self.deepSleep = deepSleep
        self.remSleep = remSleep; self.lightSleep = lightSleep
        self.sleepQualityScore = sleepQualityScore; self.steps = steps
        self.activeCalories = activeCalories; self.totalCalories = totalCalories
        self.exerciseMinutes = exerciseMinutes; self.recoveryScore = recoveryScore
        self.trainingStrain = trainingStrain; self.dayStrain = dayStrain
        self.readinessScore = readinessScore; self.fatigueLevel = fatigueLevel
        self.performancePrediction = performancePrediction; self.createdAt = createdAt
    }
}

struct RecoveryStatus: Codable, Identifiable {
    let id: String
    let userId: String?
    let date: String?
    let recoveryScore: Double?
    let readinessScore: Double?
    let fatigueLevel: String
    let sleepQuality: Double?
    let hrv: Int?
    let restingHeartRate: Int?
    let hrvStatus: String?
    let recommendation: String
    let lastUpdated: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case recoveryScore = "recovery_score"
        case readinessScore = "readiness_score"
        case fatigueLevel = "fatigue_level"
        case sleepQuality = "sleep_quality"
        case hrv
        case restingHeartRate = "resting_heart_rate"
        case hrvStatus = "hrv_status"
        case recommendation
        case lastUpdated = "last_updated"
        case createdAt = "created_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Backend may not send id — generate one if missing
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        recoveryScore = try container.decodeIfPresent(Double.self, forKey: .recoveryScore)
        readinessScore = try container.decodeIfPresent(Double.self, forKey: .readinessScore)
        fatigueLevel = try container.decodeIfPresent(String.self, forKey: .fatigueLevel) ?? "unknown"
        sleepQuality = try container.decodeIfPresent(Double.self, forKey: .sleepQuality)
        hrv = try container.decodeIfPresent(Int.self, forKey: .hrv)
        restingHeartRate = try container.decodeIfPresent(Int.self, forKey: .restingHeartRate)
        hrvStatus = try container.decodeIfPresent(String.self, forKey: .hrvStatus)
        recommendation = try container.decodeIfPresent(String.self, forKey: .recommendation) ?? "Monitor your recovery and adjust training accordingly."
        lastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
    
    // Memberwise init for local construction
    init(id: String, userId: String?, date: String?, recoveryScore: Double?,
         readinessScore: Double?, fatigueLevel: String, sleepQuality: Double?,
         hrv: Int?, restingHeartRate: Int?, hrvStatus: String?,
         recommendation: String, lastUpdated: String?, createdAt: String?) {
        self.id = id
        self.userId = userId
        self.date = date
        self.recoveryScore = recoveryScore
        self.readinessScore = readinessScore
        self.fatigueLevel = fatigueLevel
        self.sleepQuality = sleepQuality
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
        self.hrvStatus = hrvStatus
        self.recommendation = recommendation
        self.lastUpdated = lastUpdated
        self.createdAt = createdAt
    }
}

// MARK: - Admin API
extension APIClient {
    func getAdminStats() async throws -> AdminStatsResponse {
        try await get("/admin/stats")
    }
    
    func getAdminActions(limit: Int = 20) async throws -> [AdminActionResponse] {
        try await get("/admin/actions?limit=\(limit)")
    }
}

// MARK: - Email Verification API
extension APIClient {
    /// Send a 6-digit verification code to the current user's email.
    /// Returns masked email for display. Call this right after signup.
    func sendVerificationCode() async throws -> SendCodeResponse {
        try await post("/auth/send-code", body: EmptyBody())
    }

    /// Verify the 6-digit code entered by the user.
    /// On success returns a fresh JWT — store it immediately (replaces the signup token).
    func verifyCode(_ code: String) async throws -> LoginResponse {
        let body = VerifyCodeRequest(code: code)
        return try await post("/auth/verify-code", body: body)
    }

    /// Resend the code (enforces 60-second cooldown server-side).
    func resendVerificationCode() async throws -> SendCodeResponse {
        try await post("/auth/resend-code", body: EmptyBody())
    }
}

// MARK: - Onboarding Survey API
extension APIClient {
    /// Submit (or update) the onboarding survey after verification.
    func submitOnboardingSurvey(_ request: OnboardingSurveyRequest) async throws {
        let _: EmptyResponse = try await post("/onboarding/survey", body: request)
    }

    /// Fetch the user's survey — used to seed AI Coach context.
    func getOnboardingSurvey() async throws -> OnboardingSurveyResponse {
        try await get("/onboarding/survey")
    }

    // MARK: - Skill Progression Sync

    /// Fetch the stored skill snapshot for a sport (404 → nil, not a throw).
    func getSkillSnapshot(sport: String) async throws -> SkillSnapshotResponse? {
        do {
            return try await get("/skill-progression/\(sport.lowercased())")
        } catch APIError.notFound {
            return nil
        }
    }

    /// Upsert the full skill snapshot for a sport.
    func syncSkillSnapshot(sport: String, skills: [[String: Any]]) async throws -> SkillSnapshotResponse {
        struct SyncBody: Encodable {
            struct SkillEntry: Encodable {
                let category: String
                let score: Double
                let trend: String
                let last_updated: String?
                let data_points: Int
            }
            let skills: [SkillEntry]
        }
        // skills is already the serialised form from SkillProgressionEngine
        // re-encode via Encodable wrapper so we don't depend on JSON hacks
        let entries = skills.compactMap { dict -> SyncBody.SkillEntry? in
            guard
                let cat = dict["category"] as? String,
                let score = dict["score"] as? Double,
                let trend = dict["trend"] as? String
            else { return nil }
            return SyncBody.SkillEntry(
                category: cat,
                score: score,
                trend: trend,
                last_updated: dict["lastUpdated"] as? String ?? dict["last_updated"] as? String,
                data_points: dict["dataPoints"] as? Int ?? dict["data_points"] as? Int ?? 0
            )
        }
        let body = SyncBody(skills: entries)
        return try await put("/skill-progression/\(sport.lowercased())", body: body)
    }

    // MARK: - Password Reset

    /// Request a 6-digit password reset code be sent to the given email.
    func forgotPassword(email: String) async throws {
        struct ForgotBody: Encodable { let email: String }
        let _: EmptyResponse = try await post("/auth/forgot-password", body: ForgotBody(email: email))
    }

    /// Submit the reset code and new password.
    func resetPassword(email: String, code: String, newPassword: String) async throws {
        struct ResetBody: Encodable {
            let email: String
            let code: String
            let new_password: String
        }
        let _: EmptyResponse = try await post("/auth/reset-password", body: ResetBody(email: email, code: code, new_password: newPassword))
    }
}

/// Used when an endpoint accepts an empty POST body.
private struct EmptyBody: Codable {}
