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
    
    func authenticateWithBackend(appleResult: AppleSignInResult) async throws -> String {
        // Send Apple credentials to backend for verification
        let apiClient = APIClient.shared
        
        let request = OAuthLoginRequest(
            provider: "apple",
            idToken: appleResult.identityToken,
            nonce: currentNonce,
            email: appleResult.email,
            fullName: appleResult.fullName
        )
        
        // TODO: Add OAuth endpoint to backend
        // For now, create account with Apple ID
        let response: LoginResponse = try await apiClient.post(
            "/auth/oauth/apple",
            body: request,
            requiresAuth: false
        )
        
        return response.accessToken
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
    
    enum CodingKeys: String, CodingKey {
        case provider
        case idToken = "id_token"
        case nonce
        case email
        case fullName = "full_name"
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
