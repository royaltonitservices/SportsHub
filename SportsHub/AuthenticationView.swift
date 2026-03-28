//
//  AuthenticationView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var oauthManager = OAuthManager.shared
    @State private var showSignUp = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: Spacing.xl) {
                    Spacer()
                    
                    // Logo / Branding
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "trophy.circle.fill")
                            .font(.system(size: 96))
                            .foregroundStyle(Color.appPrimary)
                        
                        Text("SportsHub")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(Color.appTextPrimary)
                        
                        Text("Your Athlete Journey Starts Here")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Spacer()
                    
                    // Auth Buttons
                    VStack(spacing: Spacing.md) {
                        // OAuth Buttons
                        Button(action: {
                            Task {
                                await handleAppleSignIn()
                            }
                        }) {
                            HStack {
                                Image(systemName: "apple.logo")
                                Text("Continue with Apple")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.md)
                            .background(Color.black)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                        }
                        
                        Button(action: {
                            Task {
                                await handleGoogleSignIn()
                            }
                        }) {
                            HStack {
                                Image(systemName: "g.circle.fill")
                                Text("Continue with Google")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.md)
                            .background(.white)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.medium)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        
                        // Divider
                        HStack {
                            Rectangle()
                                .fill(Color.appTextSecondary.opacity(0.3))
                                .frame(height: 1)
                            Text("or")
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary)
                                .padding(.horizontal, Spacing.sm)
                            Rectangle()
                                .fill(Color.appTextSecondary.opacity(0.3))
                                .frame(height: 1)
                        }
                        .padding(.vertical, Spacing.sm)
                        
                        Button(action: {
                            showSignUp = true
                        }) {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                Text("Create Account")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .primaryButton()
                        
                        NavigationLink(destination: LoginView()) {
                            Text("Sign In")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                        }
                        .secondaryButton()
                    }
                    .padding(.horizontal, Spacing.xl)
                    
                    Spacer()
                        .frame(height: 60)
                }
            }
            .sheet(isPresented: $showSignUp) {
                SignUpView()
            }
            .alert("Sign In Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func handleAppleSignIn() async {
        do {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first else {
                return
            }
            
            let result = try await oauthManager.signInWithApple(presentationAnchor: window)
            let token = try await oauthManager.authenticateWithBackend(appleResult: result)
            
            // Set token and fetch user
            APIClient.shared.setAuthToken(token)
            let userResponse: UserResponse = try await APIClient.shared.getCurrentUser()
            
            sessionManager.updateUserFromOAuth(from: userResponse, token: token)
        } catch {
            errorMessage = "We couldn't sign you in with Apple right now. Please try again or use a different sign-in method."
            showError = true
        }
    }
    
    private func handleGoogleSignIn() async {
        do {
            let result = try await oauthManager.signInWithGoogle()
            let token = try await oauthManager.authenticateWithBackend(googleResult: result)
            
            APIClient.shared.setAuthToken(token)
            let userResponse: UserResponse = try await APIClient.shared.getCurrentUser()
            
            sessionManager.updateUserFromOAuth(from: userResponse, token: token)
        } catch {
            errorMessage = "We couldn't sign you in with Google right now. Please try again or use a different sign-in method."
            showError = true
        }
    }
}

#Preview {
    AuthenticationView()
}
