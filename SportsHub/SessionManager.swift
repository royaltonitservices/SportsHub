//
//  SessionManager.swift
//  SportsHub
//
//  Production-quality session/auth manager
//  Robust state management, proper async safety, clean error handling
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SessionManager: ObservableObject {
    static let shared = SessionManager()

    // MARK: - Published State

    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUser: User?
    @Published var showAuthFlow = false
    @Published private(set) var isAdmin = false
    @Published private(set) var isLoading = false

    // New-user onboarding flow states
    /// Non-nil when the current session has a pending email verification.
    /// Contains the masked email to display in EmailVerificationView.
    @Published private(set) var pendingVerificationEmail: String? = nil
    /// True when the user is authenticated but has not yet completed the onboarding survey.
    @Published private(set) var requiresSurvey = false
    /// Set when a background bio-sync to the backend fails; cleared after user dismisses alert.
    @Published var bioSyncError: String? = nil

    // MARK: - Private State

    private let apiClient = APIClient.shared
    private let keychainKey = "sportshub_auth_token"
    private let cachedUserKey = "cached_user"

    // Prevent duplicate concurrent auth operations
    private var authTask: Task<Void, Error>?

    private init() {
        // Attempt session restoration on init
        Task {
            await restoreSession()
        }
    }

    // MARK: - Session Restoration

    /// Attempt to restore session from saved token
    /// Called automatically on init
    ///
    /// IMPORTANT: Only clears the token on confirmed auth rejection (401).
    /// Network errors preserve the saved token and cached user so the session
    /// survives temporary backend outages.
    private func restoreSession() async {
        guard let token = KeychainHelper.get(key: keychainKey) else {
            // No saved token - start in logged-out state
            clearSessionState()
            return
        }

        // Have token - try to verify it
        apiClient.setAuthToken(token)

        do {
            let userResponse: UserResponse = try await apiClient.getCurrentUser()
            // Success - restore session from live server data
            setAuthenticatedState(from: userResponse, token: token)
        } catch let error as APIError {
            switch error {
            case .unauthorized, .forbidden:
                // Token is definitively invalid — clear it
                await clearSessionCompletely()
            default:
                // Network error, timeout, server down, etc.
                // Keep the token and try to restore from cached user data
                restoreFromCache(token: token)
            }
        } catch {
            // Unknown error — still preserve the token, restore from cache
            restoreFromCache(token: token)
        }
    }
    
    /// Restore session from cached UserDefaults data when the server is unreachable.
    /// This keeps the user logged in with stale-but-valid data until connectivity returns.
    private func restoreFromCache(token: String) {
        apiClient.setAuthToken(token)
        
        if let userData = UserDefaults.standard.data(forKey: cachedUserKey),
           let cachedUser = try? JSONDecoder().decode(User.self, from: userData) {
            self.currentUser = cachedUser
            self.isAuthenticated = true
            self.isAdmin = cachedUser.role == .admin
            
            // Ensure account-level Premium entitlement is recognized from cache
            StoreManager.shared.setAuthenticatedUser(email: cachedUser.email)
        } else {
            // No cached user AND server unreachable — can't restore
            clearSessionState()
        }
    }

    // MARK: - Login

    func login(email: String, password: String) async throws {
        // Cancel any stale previous auth task before starting a new one
        authTask?.cancel()
        authTask = nil

        // Create new auth task
        authTask = Task {
            isLoading = true
            defer { isLoading = false }

            do {
                // Step 1: Authenticate and get token
                let loginResponse = try await apiClient.login(email: email, password: password)
                let token = loginResponse.accessToken

                // Step 2: Fetch user details with new token
                // IMPORTANT: Don't persist anything until we know the full auth succeeded
                apiClient.setAuthToken(token)
                let userResponse: UserResponse = try await apiClient.getCurrentUser()

                // Step 3: ONLY NOW save token and update state (all-or-nothing)
                KeychainHelper.save(key: keychainKey, value: token)
                setAuthenticatedState(from: userResponse, token: token)

                // Success - dismiss auth flow
                showAuthFlow = false

            } catch let error as APIError {
                // Don't destroy existing session state on login failure.
                // Login is an attempt to create a NEW session — if it fails,
                // just clear the partial in-flight token (not the whole session).
                apiClient.setAuthToken(nil)
                throw mapAPIError(error)
            } catch {
                apiClient.setAuthToken(nil)
                throw mapGenericError(error)
            }
        }

        // Await the task
        try await authTask?.value
    }

    // MARK: - Sign Up

    func signUp(email: String, username: String, password: String, dateOfBirth: Date, parentEmail: String? = nil) async throws {
        // Cancel any stale previous auth task before starting a new one
        authTask?.cancel()
        authTask = nil

        // Validate age client-side first
        let age = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
        guard age >= 13 else {
            throw AuthError.underAge
        }
        
        // Under-18 users must provide a parent email
        if age < 18 {
            guard let parentEmail, !parentEmail.isEmpty else {
                throw AuthError.serverError("A parent or guardian email is required for users under 18.")
            }
        }

        authTask = Task {
            isLoading = true
            defer { isLoading = false }

            do {
                // Step 1: Create account
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime]
                let dateString = dateFormatter.string(from: dateOfBirth)

                let request = SignupRequest(
                    email: email,
                    username: username,
                    password: password,
                    displayName: username, // Use username as initial display name
                    dateOfBirth: dateString,
                    parentEmail: parentEmail
                )

                _ = try await apiClient.signup(request: request)

                // Step 2: Auto-login after successful signup
                // This will handle token + user fetch + state update
                try await login(email: email, password: password)

            } catch let error as APIError {
                // Don't destroy state — signup failure shouldn't wipe anything
                apiClient.setAuthToken(nil)
                throw mapAPIError(error, isSignup: true)
            } catch let error as AuthError {
                // Re-throw auth errors (like from auto-login)
                throw error
            } catch {
                apiClient.setAuthToken(nil)
                throw mapGenericError(error)
            }
        }

        try await authTask?.value
    }

    // MARK: - Logout

    func logout() {
        // Cancel any ongoing auth operations
        authTask?.cancel()
        authTask = nil

        Task {
            await clearSessionCompletely()
        }
    }

    // MARK: - OAuth Support

    func updateUserFromOAuth(from response: UserResponse, token: String) {
        KeychainHelper.save(key: keychainKey, value: token)
        setAuthenticatedState(from: response, token: token)
        showAuthFlow = false
    }
    
    // MARK: - User Profile Updates
    
    /// Update the current user's bio
    func updateBio(_ bio: String?) {
        guard var user = currentUser else { return }
        
        user.bio = bio
        self.currentUser = user
        
        // Persist to UserDefaults
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: cachedUserKey)
        }
        
        // Sync to backend (best-effort).  Failure is surfaced via bioSyncError.
        Task {
            do {
                try await APIClient.shared.updateBio(bio: bio ?? "")
            } catch {
                bioSyncError = "Bio saved locally. Backend sync failed — changes may not appear on other devices."
            }
        }
    }
    
    /// Update the current user's username
    func updateUsername(_ newUsername: String) {
        guard var user = currentUser else { return }
        
        user.username = newUsername
        self.currentUser = user
        
        // Persist to UserDefaults
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: cachedUserKey)
        }
    }
    
    /// Update the current user's display name
    func updateDisplayName(_ newDisplayName: String) {
        guard var user = currentUser else { return }
        
        user.displayName = newDisplayName
        self.currentUser = user
        
        // Persist to UserDefaults
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: cachedUserKey)
        }
    }

    // MARK: - State Management (Private)

    /// Set fully authenticated state.
    /// ONLY call this when auth is fully successful.
    private func setAuthenticatedState(from response: UserResponse, token: String) {
        apiClient.setAuthToken(token)

        let isAdminUser = response.isAdmin
        let user = User(
            id: UUID(uuidString: response.id) ?? UUID(),
            email: response.email,
            username: response.username,
            displayName: response.displayName,
            role: isAdminUser ? .admin : .user
        )

        // Update all state atomically
        self.currentUser = user
        self.isAuthenticated = true
        self.isAdmin = isAdminUser

        // Determine onboarding flow state.
        // Legacy accounts bypass both verification and survey.
        let isLegacy = response.isLegacyAccount
        let emailVerified = response.emailVerified
        let surveyDone = response.surveyCompleted

        if !isLegacy && !emailVerified {
            self.pendingVerificationEmail = maskedEmail(response.email)
            self.requiresSurvey = false
        } else if !isLegacy && !surveyDone {
            self.pendingVerificationEmail = nil
            self.requiresSurvey = true
        } else {
            self.pendingVerificationEmail = nil
            self.requiresSurvey = false
        }

        // Persist user to UserDefaults
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: cachedUserKey)
        }

        // Recognize account-level Premium entitlement by email
        StoreManager.shared.setAuthenticatedUser(email: response.email)

        // Sync Premium subscription status from backend
        Task {
            await StoreManager.shared.syncBackendSubscription()
        }
    }

    // MARK: - Verification + Survey Handlers

    /// Called by EmailVerificationView on successful code verification.
    /// Stores the fresh JWT and re-fetches user to determine next step.
    func handleVerificationSuccess(token: String) async {
        KeychainHelper.save(key: keychainKey, value: token)
        apiClient.setAuthToken(token)
        do {
            let userResponse: UserResponse = try await apiClient.getCurrentUser()
            setAuthenticatedState(from: userResponse, token: token)
        } catch {
            // Best-effort: proceed to survey even if re-fetch fails
            self.pendingVerificationEmail = nil
            self.requiresSurvey = true
        }
    }

    /// Called by OnboardingSurveyView when the survey is submitted successfully.
    func handleSurveyCompletion() {
        self.requiresSurvey = false
    }

    // MARK: - Internal Helpers

    private func maskedEmail(_ email: String) -> String {
        let parts = email.split(separator: "@")
        guard parts.count == 2 else { return email }
        let name = String(parts[0])
        let domain = String(parts[1])
        let visible = name.prefix(2)
        let masked = visible + String(repeating: "*", count: max(0, name.count - 2))
        return "\(masked)@\(domain)"
    }

    /// Clear session state (unauthenticated but don't clear persistence)
    private func clearSessionState() {
        self.currentUser = nil
        self.isAuthenticated = false
        self.isAdmin = false
        self.pendingVerificationEmail = nil
        self.requiresSurvey = false
        apiClient.setAuthToken(nil)
    }

    /// Completely clear session including all persistence
    private func clearSessionCompletely() async {
        KeychainHelper.delete(key: keychainKey)
        UserDefaults.standard.removeObject(forKey: cachedUserKey)
        apiClient.setAuthToken(nil)

        // Clear account-level Premium entitlement
        StoreManager.shared.clearAccountEntitlement()

        await MainActor.run {
            self.currentUser = nil
            self.isAuthenticated = false
            self.isAdmin = false
            self.pendingVerificationEmail = nil
            self.requiresSurvey = false
        }
    }

    // MARK: - Error Mapping

    private func mapAPIError(_ error: APIError, isSignup: Bool = false) -> AuthError {
        switch error {
        // MARK: Auth-level errors
        case .unauthorized:
            return .invalidCredentials

        case .forbidden:
            return .serverError("Access denied. Please try logging in again.")

        case .conflict:
            if isSignup {
                return .usernameTaken
            }
            return .serverError("A conflict occurred. Please try again.")

        case .unprocessableEntity:
            if isSignup {
                return .serverError("Please check your information and try again.")
            }
            return .invalidCredentials

        // MARK: Server message errors
        case .serverError(let message):
            // Parse specific server messages
            if message.contains("Username already taken") || (message.contains("username") && message.contains("exists")) {
                return .usernameTaken
            } else if message.contains("email") && (message.contains("exists") || message.contains("already registered")) {
                return .serverError("An account with this email already exists.")
            } else if message.contains("Must be at least 13") || message.contains("age") {
                return .underAge
            } else if message.contains("Account is") || message.contains("suspended") || message.contains("banned") {
                return .serverError(message)
            } else if message.contains("temporarily unavailable") || message.contains("maintenance") {
                return .serviceUnavailable
            } else if message.contains("Invalid email or password") || message.contains("Incorrect") {
                return .invalidCredentials
            } else if message.contains("Server error") || message.contains("Database") || message.contains("Internal") {
                return .serviceUnavailable
            } else {
                return .serverError(message)
            }

        // MARK: Decoding / response errors
        case .decodingError:
            return .serviceUnavailable

        case .invalidResponse, .malformedResponse:
            return .serviceUnavailable

        case .invalidURL:
            return .serverError("App configuration error. Please update the app or try again later.")

        case .notFound:
            if isSignup {
                return .serverError("Sign-up service is currently unavailable. Please try again later.")
            }
            return .invalidCredentials

        // MARK: Network-level errors
        case .noConnection:
            return .noConnection

        case .timeout:
            return .timeout

        case .cannotConnectToHost:
            return .serverUnavailable

        case .dnsLookupFailed:
            return .serverUnavailable

        case .networkError(let errorMessage):
            if errorMessage.contains("No internet connection") || errorMessage.contains("network connection lost") {
                return .noConnection
            } else if errorMessage.contains("timed out") {
                return .timeout
            } else if errorMessage.contains("Cancel") || errorMessage.contains("cancel") {
                return .networkError
            } else {
                return .networkError
            }
        }
    }

    private func mapGenericError(_ error: Error) -> AuthError {
        // Check if it's already an AuthError
        if let authError = error as? AuthError {
            return authError
        }

        // Map NSError codes
        let nsError = error as NSError
        return mapNetworkError(nsError)
    }

    private func mapNetworkError(_ error: Error) -> AuthError {
        let nsError = error as NSError

        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return .noConnection
        case NSURLErrorTimedOut:
            return .timeout
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            return .serverUnavailable
        default:
            return .networkError
        }
    }
}

// MARK: - User Model

struct User: Identifiable, Codable, Equatable {
    let id: UUID
    let email: String
    var username: String
    var displayName: String
    let role: UserRole
    var bio: String?
    var dateOfBirth: Date?
    var parentEmail: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case username
        case displayName = "display_name"
        case role
        case bio
        case dateOfBirth
        case parentEmail
    }
}

enum UserRole: String, Codable {
    case user = "User"
    case admin = "Admin"
}

// MARK: - Auth Errors

enum AuthError: LocalizedError, Equatable {
    case underAge
    case invalidCredentials
    case networkError
    case serverError(String)
    case usernameTaken
    case serviceUnavailable
    case serverUnavailable
    case timeout
    case noConnection

    var errorDescription: String? {
        switch self {
        case .underAge:
            return "You must be 13 or older to create an account"
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError:
            return "Network connection error. Please check your internet connection."
        case .serverError(let message):
            return message
        case .usernameTaken:
            return "This username is already taken. Please choose a different one."
        case .serviceUnavailable:
            return "Service temporarily unavailable. Please try again in a moment."
        case .serverUnavailable:
            return "Cannot connect to server. Please try again later."
        case .timeout:
            return "Request timed out. Please try again."
        case .noConnection:
            return "No internet connection. Please check your network settings."
        }
    }

    var userFriendlyMessage: String {
        switch self {
        case .underAge:
            return "You must be 13 or older to create an account"
        case .invalidCredentials:
            return "Incorrect email or password. Please try again."
        case .networkError, .noConnection:
            return "Unable to connect. Check your internet connection and try again."
        case .timeout:
            return "The request took too long. Please try again."
        case .serverError(let message):
            if message.contains("Account is") || message.contains("suspended") || message.contains("banned") {
                return message
            }
            return "Something went wrong on our end. Please try again."
        case .usernameTaken:
            return "This username is already taken. Please choose a different one."
        case .serviceUnavailable:
            return "SportsHub is temporarily unavailable. Please try again in a moment."
        case .serverUnavailable:
            return "Unable to reach the server. Please check your connection and try again."
        }
    }
}

// MARK: - Keychain Helper

class KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Delete old value first
        SecItemDelete(query as CFDictionary)

        // Add new value
        let status = SecItemAdd(query as CFDictionary, nil)

        #if DEBUG
        if status != errSecSuccess {
            print("⚠️ Keychain save failed for key: \(key), status: \(status)")
        }
        #endif
    }

    static func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        #if DEBUG
        if status != errSecSuccess && status != errSecItemNotFound {
            print("⚠️ Keychain delete failed for key: \(key), status: \(status)")
        }
        #endif
    }
}
