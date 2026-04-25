//
//  LoginView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: SessionManager
    @FocusState private var focusedField: Field?

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false
    @State private var emailError: String?
    @State private var showForgotPassword = false
    
    enum Field {
        case email, password
    }
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    // Header
                    VStack(spacing: Spacing.md) {
                        Text("Welcome Back")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.appTextPrimary)
                        
                        Text("Sign in to continue your journey")
                            .font(.body)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    .padding(.top, 60)
                    
                    // Form
                    VStack(spacing: Spacing.lg) {
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appTextPrimary)
                            
                            TextField("your@email.com", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .textInputAutocapitalization(.never)
                                .submitLabel(.next)
                                .focused($focusedField, equals: .email)
                                .padding(Spacing.md)
                                .background(Color.appSurface)
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                                .foregroundStyle(Color.appTextPrimary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                                        .strokeBorder(
                                            emailError != nil ? Color.red.opacity(0.5) : 
                                            focusedField == .email ? Color.appPrimary.opacity(0.5) : Color.clear,
                                            lineWidth: 1.5
                                        )
                                )
                                .onChange(of: email) { _, _ in
                                    // Clear all errors when user starts typing
                                    errorMessage = nil
                                    emailError = nil
                                }
                                .onSubmit {
                                    focusedField = .password
                                }
                            
                            if let emailError {
                                Text(emailError)
                                    .font(.caption)
                                    .foregroundStyle(Color.red)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        
                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Password")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.appTextPrimary)
                                Spacer()
                                Button("Forgot password?") {
                                    showForgotPassword = true
                                }
                                .font(.subheadline)
                                .foregroundStyle(Color.appPrimary)
                            }
                            
                            HStack(spacing: 0) {
                                Group {
                                    if showPassword {
                                        TextField("", text: $password)
                                            .textContentType(.password)
                                    } else {
                                        SecureField("", text: $password)
                                            .textContentType(.password)
                                    }
                                }
                                .foregroundStyle(Color.appTextPrimary)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .submitLabel(.go)
                                .focused($focusedField, equals: .password)
                                .onChange(of: password) { _, _ in
                                    // Clear all errors when user starts typing
                                    errorMessage = nil
                                    emailError = nil
                                }
                                .onSubmit {
                                    focusedField = nil
                                    signIn()
                                }
                                
                                Button(action: {
                                    showPassword.toggle()
                                }) {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundStyle(Color.appTextSecondary)
                                        .font(.body)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                            }
                            .padding(.leading, Spacing.md)
                            .background(Color.appSurface)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.medium)
                                    .strokeBorder(
                                        focusedField == .password ? Color.appPrimary.opacity(0.5) : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                        }
                        
                        // Error Message
                        if let errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.subheadline)
                                Text(errorMessage)
                                    .font(.subheadline)
                            }
                            .foregroundStyle(Color.red)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        // Sign In Button
                        Button(action: {
                            focusedField = nil
                            signIn()
                        }) {
                            HStack(spacing: Spacing.sm) {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Signing In...")
                                        .fontWeight(.semibold)
                                } else {
                                    Text("Sign In")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .primaryButton()
                        .disabled(isLoading)
                        .opacity(isLoading ? 0.7 : 1.0)
                        .padding(.top, Spacing.sm)
                        .animation(.easeInOut(duration: 0.2), value: isLoading)
                    }
                    .padding(.horizontal, Spacing.xl)
                    
                    Spacer()
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
        .onAppear {
            // Auto-focus email field on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .email
            }
        }
    }
    
    private func signIn() {
        // Trim email before validation (match SignUpView behavior)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate email format
        if !isValidEmail(trimmedEmail) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                emailError = "Please enter a valid email address"
            }
            return
        }
        
        // Validate password not empty
        guard !password.isEmpty else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                errorMessage = "Please enter your password"
            }
            return
        }
        
        // Clear previous errors
        errorMessage = nil
        emailError = nil
        isLoading = true
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        Task {
            do {
                // Normalize email: trim whitespace and lowercase (match SignUpView behavior)
                let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                
                // IMPORTANT: Password passed exactly as entered
                try await sessionManager.login(email: cleanEmail, password: password)
                
                // Success haptic
                let successGenerator = UINotificationFeedbackGenerator()
                successGenerator.notificationOccurred(.success)
                
                // Small delay to show success state
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                
                // Update UI on main actor
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch let error as AuthError {
                // Error haptic
                let errorGenerator = UINotificationFeedbackGenerator()
                errorGenerator.notificationOccurred(.error)
                
                // Update UI on main actor
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        errorMessage = error.userFriendlyMessage
                    }
                    isLoading = false
                }
            } catch {
                // Error haptic
                let errorGenerator = UINotificationFeedbackGenerator()
                errorGenerator.notificationOccurred(.error)
                
                // Map non-AuthError failures to a useful message
                let message: String
                if let apiError = error as? APIError {
                    message = apiError.userFriendlyMessage
                } else {
                    let nsError = error as NSError
                    switch nsError.code {
                    case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                        message = "No internet connection. Please check your network and try again."
                    case NSURLErrorTimedOut:
                        message = "The request timed out. Please try again."
                    case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
                        message = "Unable to reach the server. Please try again later."
                    default:
                        message = "Unable to sign in right now. Please try again."
                    }
                }
                
                // Update UI on main actor
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        errorMessage = message
                    }
                    isLoading = false
                }
            }
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
}
