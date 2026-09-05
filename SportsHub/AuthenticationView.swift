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
    // First-time Apple onboarding: the provider gave us a verified identity but we
    // still need a real date of birth (age gate) before an account is created. The
    // coordinator retains the first authorization result and re-uses it on completion
    // (no second ASAuthorization) — see AppleOnboardingCoordinator.
    @State private var appleOnboarding = AppleOnboardingCoordinator()
    @State private var showAppleDOBSheet = false
    @State private var onboardingDOB = Calendar.current.date(byAdding: .year, value: -16, to: Date()) ?? Date()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: Spacing.xl) {
                    // Session-expired notice — only shown after a mid-session
                    // 401 bounce, never on a normal signed-out launch or a
                    // failed login (those don't set sessionExpiredNotice).
                    if let notice = sessionManager.sessionExpiredNotice {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(Color.appTextSecondary)
                            Text(notice)
                                .font(.caption)
                                .foregroundStyle(Color.appTextPrimary)
                            Spacer()
                            Button {
                                sessionManager.sessionExpiredNotice = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundStyle(Color.appTextSecondary)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, Spacing.md)
                    }

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
                        .capabilityGated(.googleSignIn)
                        
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
            .sheet(isPresented: $showAppleDOBSheet) {
                appleDOBOnboardingSheet
            }
            .alert("Sign In Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // ISO-8601 date-only formatter for the DOB sent to the backend age gate.
    private static let dobFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    @ViewBuilder private var appleDOBOnboardingSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Text("One more step")
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)
                Text("Enter your date of birth to finish setting up your SportsHub account. You must be at least 13.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
                DatePicker("Date of birth", selection: $onboardingDOB,
                           in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                Button("Continue") {
                    let iso = Self.dobFormatter.string(from: onboardingDOB)
                    showAppleDOBSheet = false
                    Task { await completeAppleOnboarding(dateOfBirth: iso) }
                }
                .primaryButton()
                Spacer()
            }
            .padding(Spacing.lg)
            .background(Color.appBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAppleDOBSheet = false; appleOnboarding.cancel() }
                }
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
            let outcome = try await oauthManager.authenticateWithBackend(appleResult: result)
            try await handleAppleOutcome(outcome, result: result)
        } catch {
            if let apiError = error as? APIError {
                errorMessage = apiError.userFriendlyMessage
            } else {
                let nsError = error as NSError
                if nsError.code == NSURLErrorCannotConnectToHost || nsError.code == NSURLErrorCannotFindHost {
                    errorMessage = "Unable to reach the server. Please try again later."
                } else if nsError.code == NSURLErrorNotConnectedToInternet {
                    errorMessage = "No internet connection. Please check your network and try again."
                } else {
                    errorMessage = "We couldn't sign you in with Apple right now. Please try again or use a different sign-in method."
                }
            }
            showError = true
        }
    }
    
    private func handleAppleOutcome(_ outcome: OAuthOutcome, result: AppleSignInResult) async throws {
        switch appleOnboarding.stepForInitial(outcome, result: result) {
        case .authenticated(let token):
            try await finishAppleAuth(token: token)
        case .needsDateOfBirth:
            // First-time identity — collect a real DOB, then retry with the SAME result.
            showAppleDOBSheet = true
        case .accountConflict:
            // Email already belongs to an account; we never auto-link.
            errorMessage = "An account with this email already exists. Please sign in with your email and password instead."
            showError = true
        case .failed:
            errorMessage = "We couldn't complete Apple Sign-In. Please try again."
            showError = true
        }
    }

    private func finishAppleAuth(token: String) async throws {
        APIClient.shared.setAuthToken(token)
        let userResponse: UserResponse = try await APIClient.shared.getCurrentUser()
        sessionManager.updateUserFromOAuth(from: userResponse, token: token)
    }

    private func completeAppleOnboarding(dateOfBirth: String) async {
        // Re-use the SAME retained authorization result — never a second ASAuthorization.
        guard let result = appleOnboarding.resultForCompletion() else { return }
        do {
            let outcome = try await oauthManager.authenticateWithBackend(appleResult: result, dateOfBirth: dateOfBirth)
            switch appleOnboarding.stepForCompletion(outcome) {
            case .authenticated(let token):
                try await finishAppleAuth(token: token)
            case .accountConflict:
                errorMessage = "An account with this email already exists. Please sign in with your email and password instead."
                showError = true
            case .needsDateOfBirth, .failed:
                errorMessage = "We couldn't complete Apple Sign-In. Please try again."
                showError = true
            }
        } catch {
            // Expired token / 401 / network / under-13 (400): clear pending so a fresh
            // authorization is required — an expiry is never treated as success.
            appleOnboarding.completionFailed()
            errorMessage = (error as? APIError)?.userFriendlyMessage
                ?? "You must be at least 13 to use SportsHub."
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
            if let apiError = error as? APIError {
                errorMessage = apiError.userFriendlyMessage
            } else {
                let nsError = error as NSError
                if nsError.code == NSURLErrorCannotConnectToHost || nsError.code == NSURLErrorCannotFindHost {
                    errorMessage = "Unable to reach the server. Please try again later."
                } else if nsError.code == NSURLErrorNotConnectedToInternet {
                    errorMessage = "No internet connection. Please check your network and try again."
                } else {
                    errorMessage = "We couldn't sign you in with Google right now. Please try again or use a different sign-in method."
                }
            }
            showError = true
        }
    }
}

#Preview {
    AuthenticationView()
}
