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
    
    // Per-attempt state for the in-flight authorization. Set immediately before
    // performRequests() and read once in the delegate callback; `isAuthenticating` gates
    // against overlapping authorizations so these are never clobbered mid-flight.
    private var currentNonce: String?
    private var currentAttemptId: String?
    private var appleSignInCompletion: ((Result<AppleSignInResult, Error>) -> Void)?

    // Each authorization gets a monotonically increasing token, and its controller is
    // recorded. A delegate callback is honored only when it belongs to the CURRENT
    // authorization — a late callback from a cancelled/superseded attempt can neither
    // resolve nor clear a newer attempt's completion or state.
    private var currentAuthToken: Int = 0
    private weak var activeAuthController: ASAuthorizationController?

    /// Fetches a server-bound attempt (id + raw nonce) before Apple authorization.
    /// Injectable so the ownership/attempt lifecycle is unit-testable without a network; in
    /// production it calls the backend `/auth/oauth/apple/attempt` endpoint.
    private var attemptProvider: (() async throws -> (attemptId: String, nonce: String))!

    private override init() {
        super.init()
        attemptProvider = { [weak self] in
            guard let self else { throw OAuthError.authorizationInProgress }
            return try await self.beginAppleAttempt()
        }
    }

    #if DEBUG
    /// Test-only instance (NOT `shared`) with an injected attempt provider — lets tests
    /// drive overlap/ownership/reset logic deterministically without Apple or the network.
    init(testAttemptProvider: @escaping () async throws -> (attemptId: String, nonce: String)) {
        super.init()
        attemptProvider = testAttemptProvider
    }

    var _testCurrentAttemptId: String? { currentAttemptId }
    var _testCurrentNonce: String? { currentNonce }
    #endif
    
    // MARK: - Apple Sign In
    
    func signInWithApple(presentationAnchor: ASPresentationAnchor) async throws -> AppleSignInResult {
        // Take exclusive authorization ownership + a fresh server-bound attempt (Gate 1.3).
        let attempt = try await acquireAppleAttempt()
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let request = ASAuthorizationAppleIDProvider().createRequest()
                request.requestedScopes = [.fullName, .email]
                request.nonce = sha256(attempt.nonce)   // hash of the SERVER-issued nonce

                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self

                // Tag THIS authorization; the delegate delivers results keyed to this token so
                // only the current authorization's callback can resolve the continuation.
                currentAuthToken += 1
                activeAuthController = controller
                appleSignInCompletion = { result in continuation.resume(with: result) }
                controller.performRequests()
            }
        } catch {
            isAuthenticating = false
            appleSignInCompletion = nil
            throw error
        }
    }

    /// Deliver an authorization outcome for a specific attempt `token`. Honors it only when
    /// it matches the CURRENT authorization and a completion is still pending — so a late
    /// callback from a cancelled/superseded attempt is ignored, and a duplicate callback
    /// cannot complete twice. Resets ownership + per-callback state on the honored delivery.
    /// Returns true iff the delivery was honored.
    @discardableResult
    func deliverAppleResult(token: Int, _ result: Result<AppleSignInResult, Error>) -> Bool {
        guard token == currentAuthToken, let completion = appleSignInCompletion else {
            return false
        }
        isAuthenticating = false
        appleSignInCompletion = nil
        activeAuthController = nil
        completion(result)
        return true
    }

    /// Build the result for the CURRENT authorization, stamping the per-attempt nonce +
    /// attempt id captured at acquisition time so the callback carries its own attempt.
    private func makeAppleResult(identityToken: String, userIdentifier: String,
                                 email: String?, fullName: String?) -> AppleSignInResult {
        AppleSignInResult(identityToken: identityToken, userIdentifier: userIdentifier,
                          email: email, fullName: fullName,
                          nonce: currentNonce, attemptId: currentAttemptId)
    }

    /// Token the delegate should stamp a callback with, derived from the controller it came
    /// from. A callback from a controller that is no longer active yields a non-matching
    /// token, so `deliverAppleResult` ignores it.
    private func token(for controller: ASAuthorizationController) -> Int {
        controller === activeAuthController ? currentAuthToken : -1
    }

    #if DEBUG
    /// Test seam: register an in-flight authorization completion (mirrors the continuation
    /// setup in `signInWithApple`) and return its token. Lets tests drive the real
    /// `deliverAppleResult` dispatch without Apple/UI.
    func _testRegisterAuthorization(_ completion: @escaping (Result<AppleSignInResult, Error>) -> Void) -> Int {
        currentAuthToken += 1
        isAuthenticating = true
        appleSignInCompletion = completion
        return currentAuthToken
    }
    var _testIsAuthenticating: Bool { isAuthenticating }
    var _testHasPendingCompletion: Bool { appleSignInCompletion != nil }
    func _testMakeAppleResult(identityToken: String, userIdentifier: String,
                              email: String?, fullName: String?) -> AppleSignInResult {
        makeAppleResult(identityToken: identityToken, userIdentifier: userIdentifier,
                        email: email, fullName: fullName)
    }
    #endif

    /// Take exclusive authorization ownership and acquire a fresh server-bound attempt.
    /// Throws `.authorizationInProgress` — BEFORE creating another attempt — if one is
    /// already in flight, so the per-attempt nonce/attemptId can never be clobbered by a
    /// concurrent request. On any attempt-fetch failure it releases ownership and clears
    /// per-attempt state so a subsequent fresh login starts clean. Isolated from the UI so
    /// the ownership/reset logic is unit-testable.
    func acquireAppleAttempt() async throws -> (attemptId: String, nonce: String) {
        guard !isAuthenticating else { throw OAuthError.authorizationInProgress }
        isAuthenticating = true
        do {
            let attempt = try await attemptProvider()
            currentNonce = attempt.nonce
            currentAttemptId = attempt.attemptId
            return attempt
        } catch {
            isAuthenticating = false
            currentNonce = nil
            currentAttemptId = nil
            throw error
        }
    }

    /// Mint a server-bound authentication attempt before invoking Apple. Returns the
    /// unpredictable attempt id + raw nonce the backend will require the id_token to bind to.
    private func beginAppleAttempt() async throws -> (attemptId: String, nonce: String) {
        struct _Empty: Codable {}
        let resp: AppleAttemptResponse = try await APIClient.shared.post(
            "/auth/oauth/apple/attempt", body: _Empty(), requiresAuth: false)
        return (resp.attemptId, resp.nonce)
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
            attemptId: appleResult.attemptId,   // redeem the server-bound attempt
            nonce: appleResult.nonce,           // raw nonce (server compares to its stored attempt nonce)
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
        let authToken = token(for: controller)   // callback is bound to its originating attempt
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            deliverAppleResult(token: authToken, .failure(OAuthError.invalidCredentials))
            return
        }

        let result = makeAppleResult(
            identityToken: tokenString,
            userIdentifier: appleIDCredential.user,
            email: appleIDCredential.email,
            fullName: [appleIDCredential.fullName?.givenName, appleIDCredential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
        )

        deliverAppleResult(token: authToken, .success(result))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        deliverAppleResult(token: token(for: controller), .failure(error))
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
    /// RAW per-authorization nonce whose SHA-256 was placed in the ASAuthorization
    /// request; travels WITH the token so the server nonce-binding check does not depend
    /// on mutable singleton state across the two-phase (DOB) flow.
    var nonce: String? = nil
    /// Server-bound attempt id this token must redeem (Gate 1.3). Travels with the result
    /// so the same attempt is used across the two-phase DOB completion.
    var attemptId: String? = nil
}

// MARK: - Server-bound attempt response
struct AppleAttemptResponse: Codable {
    let attemptId: String
    let nonce: String
    enum CodingKeys: String, CodingKey {
        case attemptId = "attempt_id"
        case nonce
    }
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
    var attemptId: String? = nil     // server-bound attempt id (Gate 1.3)
    let nonce: String?
    let email: String?
    let fullName: String?
    var dateOfBirth: String? = nil   // ISO-8601; sent only on first-time onboarding retry

    enum CodingKeys: String, CodingKey {
        case provider
        case idToken = "id_token"
        case attemptId = "attempt_id"
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
    case authorizationInProgress

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid credentials received from provider"
        case .notImplemented(let message):
            return message
        case .cancelled:
            return "Sign in was cancelled"
        case .authorizationInProgress:
            return "A sign-in is already in progress. Please wait."
        }
    }
}

// MARK: - SHA256 Helper
import CryptoKit
