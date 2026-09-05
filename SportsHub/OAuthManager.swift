//
//  OAuthManager.swift
//  SportsHub
//
//  OAuth authentication manager for Google and Apple Sign-In
//

import Foundation
import AuthenticationServices
import Combine

@MainActor
class OAuthManager: NSObject, ObservableObject {
    static let shared = OAuthManager()
    
    @Published var isAuthenticating = false
    @Published var authError: String?
    
    private var currentNonce: String?
    private var appleSignInCompletion: ((Result<AppleSignInResult, Error>) -> Void)?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Apple Sign In
    
    func signInWithApple(presentationAnchor: ASPresentationAnchor) async throws -> AppleSignInResult {
        return try await withCheckedThrowingContinuation { continuation in
            isAuthenticating = true
            
            let nonce = randomNonceString()
            currentNonce = nonce
            
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            
            appleSignInCompletion = { result in
                self.isAuthenticating = false
                continuation.resume(with: result)
            }
            
            controller.performRequests()
        }
    }
    
    // MARK: - Google Sign In
    
    func signInWithGoogle() async throws -> GoogleSignInResult {
        // TODO: Implement Google Sign-In
        // Requires Google Sign-In SDK: pod 'GoogleSignIn'
        // For now, return placeholder
        
        isAuthenticating = true
        
        // Simulate OAuth flow
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Mock result - replace with actual Google Sign-In
        isAuthenticating = false
        
        throw OAuthError.notImplemented("Google Sign-In requires Google SDK. Add 'GoogleSignIn' pod and configure OAuth client ID.")
    }
    
    // MARK: - Backend Integration
    
    /// Authenticate an Apple identity with the backend. Returns a typed outcome:
    /// the backend resolves the durable (apple, subject) identity and may require a
    /// first-time date of birth (dob_required), refuse a matching-email account
    /// (accountConflict — no auto-link), or need re-auth (identityIncomplete).
    /// Pass `dateOfBirth` (ISO-8601 "yyyy-MM-dd" / full ISO) on the first-time retry.
    func authenticateWithBackend(appleResult: AppleSignInResult,
                                 dateOfBirth: String? = nil) async throws -> OAuthOutcome {
        let request = OAuthLoginRequest(
            provider: "apple",
            idToken: appleResult.identityToken,
            nonce: currentNonce,
            email: appleResult.email,
            fullName: appleResult.fullName,
            dateOfBirth: dateOfBirth
        )

        let envelope: OAuthEnvelope = try await APIClient.shared.post(
            "/auth/oauth/apple",
            body: request,
            requiresAuth: false
        )

        switch envelope.status {
        case "authenticated":
            guard let token = envelope.accessToken else { throw OAuthError.invalidCredentials }
            return .authenticated(token: token)
        case "dob_required":      return .dobRequired
        case "account_conflict":  return .accountConflict
        case "identity_incomplete": return .identityIncomplete
        default:                  return .identityIncomplete
        }
    }
    
    func authenticateWithBackend(googleResult: GoogleSignInResult) async throws -> String {
        let apiClient = APIClient.shared
        
        let request = OAuthLoginRequest(
            provider: "google",
            idToken: googleResult.idToken,
            nonce: nil,
            email: googleResult.email,
            fullName: googleResult.fullName
        )
        
        let response: LoginResponse = try await apiClient.post(
            "/auth/oauth/google",
            body: request,
            requiresAuth: false
        )
        
        return response.accessToken
    }
    
    // MARK: - Helper Methods
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension OAuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            appleSignInCompletion?(.failure(OAuthError.invalidCredentials))
            return
        }
        
        let result = AppleSignInResult(
            identityToken: tokenString,
            userIdentifier: appleIDCredential.user,
            email: appleIDCredential.email,
            fullName: [appleIDCredential.fullName?.givenName, appleIDCredential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
        )
        
        appleSignInCompletion?(.success(result))
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        appleSignInCompletion?(.failure(error))
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension OAuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            fatalError("No active window scene")
        }
        return ASPresentationAnchor(windowScene: windowScene)
    }
}

// MARK: - Result Types
struct AppleSignInResult {
    let identityToken: String
    let userIdentifier: String
    let email: String?
    let fullName: String?
}

struct GoogleSignInResult {
    let idToken: String
    let email: String
    let fullName: String?
}

// MARK: - Request Models
struct OAuthLoginRequest: Codable {
    let provider: String
    let idToken: String
    let nonce: String?
    let email: String?
    let fullName: String?
    var dateOfBirth: String? = nil   // ISO-8601; sent only on first-time onboarding retry

    enum CodingKeys: String, CodingKey {
        case provider
        case idToken = "id_token"
        case nonce
        case email
        case fullName = "full_name"
        case dateOfBirth = "date_of_birth"
    }
}

// MARK: - OAuth Outcome / Envelope

/// Typed result of a backend OAuth exchange (mirrors the server's envelope states).
enum OAuthOutcome {
    case authenticated(token: String)
    case dobRequired          // first-time identity — collect a real DOB and retry
    case accountConflict      // email already belongs to an account; no auto-link
    case identityIncomplete   // provider gave no usable durable identity; ask to retry
}

/// Minimal, UI-free state machine for the two-phase first-time Apple onboarding
/// (authorize → collect DOB → complete). Extracted from AuthenticationView so the
/// continuity invariant is deterministically testable without a running UI/network:
///
///   - the FIRST AppleSignInResult is retained when a DOB is required and RE-USED on
///     completion — the app never triggers a second ASAuthorization to finish signup;
///   - the pending result is cleared on success, conflict, hard failure, cancel, and
///     token-expiry/network failure, so a failed completion always requires a fresh
///     authorization and no expiry is ever treated as success.
@MainActor
final class AppleOnboardingCoordinator {
    /// The Apple authorization result awaiting a date of birth. `private(set)` so only
    /// this type mutates it; callers read it exclusively via `resultForCompletion()`.
    private(set) var pendingResult: AppleSignInResult?

    enum Step: Equatable {
        case authenticated(token: String)
        case needsDateOfBirth
        case accountConflict
        case failed
    }

    /// First-phase: map a backend outcome to a UI step, retaining the Apple result
    /// ONLY when a DOB is required.
    func stepForInitial(_ outcome: OAuthOutcome, result: AppleSignInResult) -> Step {
        switch outcome {
        case .authenticated(let token): pendingResult = nil;    return .authenticated(token: token)
        case .dobRequired:              pendingResult = result; return .needsDateOfBirth
        case .accountConflict:          pendingResult = nil;    return .accountConflict
        case .identityIncomplete:       pendingResult = nil;    return .failed
        }
    }

    /// The result to resubmit with a DOB — the SAME retained authorization, never a
    /// freshly requested one. Returns nil if there is nothing pending.
    func resultForCompletion() -> AppleSignInResult? { pendingResult }

    /// Second-phase: map the DOB-completion outcome to a UI step. Always clears the
    /// pending result — the retry is one-shot.
    func stepForCompletion(_ outcome: OAuthOutcome) -> Step {
        defer { pendingResult = nil }
        switch outcome {
        case .authenticated(let token): return .authenticated(token: token)
        case .accountConflict:          return .accountConflict
        case .dobRequired, .identityIncomplete: return .failed
        }
    }

    /// Completion failed to reach a decision (expired token / 401 / network). Clear
    /// pending state so the user must authorize again — never a partial success.
    func completionFailed() { pendingResult = nil }

    /// The user dismissed the DOB step.
    func cancel() { pendingResult = nil }
}

private struct OAuthEnvelope: Codable {
    let status: String
    let accessToken: String?
    enum CodingKeys: String, CodingKey {
        case status
        case accessToken = "access_token"
    }
}

// MARK: - Errors
enum OAuthError: LocalizedError {
    case invalidCredentials
    case notImplemented(String)
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid credentials received from provider"
        case .notImplemented(let message):
            return message
        case .cancelled:
            return "Sign in was cancelled"
        }
    }
}

// MARK: - SHA256 Helper
import CryptoKit
