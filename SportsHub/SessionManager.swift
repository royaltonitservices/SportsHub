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
            // Success - restore session
            setAuthenticatedState(from: userResponse, token: token)
        } catch {
            // Token invalid or network failure - clear everything
            await clearSessionCompletely()
        }
    }

    // MARK: - Login

    func login(email: String, password: String) async throws {
        // Prevent duplicate concurrent login requests
        if let existingTask = authTask, !existingTask.isCancelled {
            // Already logging in - wait for existing operation
            try await existingTask.value
            return
        }

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
                // Cleanup on failure
                await clearSessionCompletely()
                throw mapAPIError(error)
            } catch {
                // Cleanup on failure
                await clearSessionCompletely()
                throw mapGenericError(error)
            }
        }

        // Await the task
        try await authTask?.value
    }

    // MARK: - Sign Up

    func signUp(email: String, username: String, password: String, dateOfBirth: Date) async throws {
        // Prevent duplicate concurrent signup requests
        if let existingTask = authTask, !existingTask.isCancelled {
            try await existingTask.value
            return
        }

        // Validate age client-side first
        let age = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
        guard age >= 13 else {
            throw AuthError.underAge
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
                    dateOfBirth: dateString
                )

                _ = try await apiClient.signup(request: request)

                // Step 2: Auto-login after successful signup
                // This will handle token + user fetch + state update
                try await login(email: email, password: password)

            } catch let error as APIError {
                // Cleanup on failure
                await clearSessionCompletely()
                throw mapAPIError(error, isSignup: true)
            } catch let error as AuthError {
                // Re-throw auth errors (like from auto-login)
                throw error
            } catch {
                // Cleanup on failure
                await clearSessionCompletely()
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
        
        // TODO: Send to backend API
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

    /// Set fully authenticated state
    /// ONLY call this when auth is fully successful
    private func setAuthenticatedState(from response: UserResponse, token: String) {
        apiClient.setAuthToken(token)

        let isAdminUser = response.isAdmin
        let user = User(
            id: UUID(uuidString: response.id) ?? UUID(),
            email: response.email,
            username: response.username,
            displayName: response.fullName,
            role: isAdminUser ? .admin : .user
        )

        // Update all state atomically
        self.currentUser = user
        self.isAuthenticated = true
        self.isAdmin = isAdminUser

        // Persist user to UserDefaults
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: cachedUserKey)
        }
        
        // Sync Premium subscription status from backend
        // This ensures backend-granted Premium (e.g., admin accounts) is recognized
        Task {
            await StoreManager.shared.syncBackendSubscription()
        }
    }

    /// Clear session state (unauthenticated but don't clear persistence)
    private func clearSessionState() {
        self.currentUser = nil
        self.isAuthenticated = false
        self.isAdmin = false
        apiClient.setAuthToken(nil)
    }

    /// Completely clear session including all persistence
    private func clearSessionCompletely() async {
        KeychainHelper.delete(key: keychainKey)
        UserDefaults.standard.removeObject(forKey: cachedUserKey)
        apiClient.setAuthToken(nil)

        await MainActor.run {
            self.currentUser = nil
            self.isAuthenticated = false
            self.isAdmin = false
        }
    }

    // MARK: - Error Mapping

    private func mapAPIError(_ error: APIError, isSignup: Bool = false) -> AuthError {
        switch error {
        case .unauthorized:
            return .invalidCredentials

        case .serverError(let message):
            // Parse specific server messages
            if message.contains("Username already taken") || message.contains("username") && message.contains("exists") {
                return .usernameTaken
            } else if message.contains("Must be at least 13") || message.contains("age") {
                return .underAge
            } else if message.contains("Account is") || message.contains("suspended") || message.contains("banned") {
                return .serverError(message)
            } else if message.contains("temporarily unavailable") || message.contains("maintenance") {
                return .serviceUnavailable
            } else if message.contains("Invalid email or password") {
                return .invalidCredentials
            } else if message.contains("Server error") || message.contains("Database") {
                return .serviceUnavailable
            } else {
                return .serverError(message)
            }

        case .networkError(let errorMessage):
            // APIError.networkError now contains a string description
            // Parse it to determine the specific network error type
            if errorMessage.contains("No internet connection") || errorMessage.contains("network connection lost") {
                return .noConnection
            } else if errorMessage.contains("timed out") {
                return .timeout
            } else if errorMessage.contains("Cannot connect to") || errorMessage.contains("connection failed") {
                return .serverUnavailable
            } else {
                return .networkError
            }

        default:
            return .serverError("An unexpected error occurred")
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
