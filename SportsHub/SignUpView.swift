//
//  SignUpView.swift
//  SportsHub
//
//  Production-quality sign-up experience for SportsHub
//  Age-gated (13+), validated, polished, youth-friendly
//

import SwiftUI

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var dateOfBirth = Date()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false
    @State private var showConfirmPassword = false

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case email, username, password, confirmPassword
    }

    // MARK: - Validation

    private var isAtLeast13: Bool {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dateOfBirth, to: Date())
        return (ageComponents.year ?? 0) >= 13
    }

    private var isEmailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Basic email validation: has @ and . after @
        let components = trimmed.split(separator: "@")
        guard components.count == 2,
              !components[0].isEmpty,
              components[1].contains("."),
              components[1].count > 2 else {
            return false
        }
        return true
    }

    private var isUsernameValid: Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count >= 3 else { return false }

        // Username must be alphanumeric, underscores, and hyphens only
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return trimmed.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }

    private var isPasswordValid: Bool {
        password.count >= 8
    }

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    private var isFormValid: Bool {
        isEmailValid &&
        isUsernameValid &&
        isPasswordValid &&
        passwordsMatch &&
        isAtLeast13
    }

    private var ageWarningMessage: String? {
        guard !isAtLeast13 else { return nil }
        return "You must be at least 13 years old to create an account"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.xl) {
                        // Header
                        VStack(spacing: Spacing.sm) {
                            Text("Create Account")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.appTextPrimary)

                            Text("Join the SportsHub community")
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        .padding(.top, Spacing.xl)

                        // Form
                        VStack(spacing: Spacing.md) {
                            // Email
                            FormField(
                                label: "Email",
                                text: $email,
                                placeholder: "you@example.com",
                                submitLabel: .next
                            )
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = .username }
                            .onChange(of: email) { _, _ in clearErrorIfNeeded() }

                            if !email.isEmpty && !isEmailValid {
                                ValidationMessage(text: "Enter a valid email address")
                            }

                            // Username
                            FormField(
                                label: "Username",
                                text: $username,
                                placeholder: "athlete123",
                                submitLabel: .next
                            )
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .username)
                            .onSubmit { focusedField = .password }
                            .onChange(of: username) { _, _ in clearErrorIfNeeded() }

                            if !username.isEmpty && !isUsernameValid {
                                ValidationMessage(text: "Username must be at least 3 characters (letters, numbers, _ or - only)")
                            }

                            // Password
                            SecureFormField(
                                label: "Password",
                                text: $password,
                                placeholder: "At least 8 characters",
                                showPassword: $showPassword,
                                submitLabel: .next
                            )
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .password)
                            .onSubmit { focusedField = .confirmPassword }
                            .onChange(of: password) { _, _ in clearErrorIfNeeded() }

                            if !password.isEmpty && !isPasswordValid {
                                ValidationMessage(text: "Password must be at least 8 characters")
                            }

                            // Confirm Password
                            SecureFormField(
                                label: "Confirm Password",
                                text: $confirmPassword,
                                placeholder: "Re-enter password",
                                showPassword: $showConfirmPassword,
                                submitLabel: .done
                            )
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .confirmPassword)
                            .onSubmit { signUp() }
                            .onChange(of: confirmPassword) { _, _ in clearErrorIfNeeded() }

                            if !confirmPassword.isEmpty && !passwordsMatch {
                                ValidationMessage(text: "Passwords do not match")
                            }

                            // Date of Birth
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Date of Birth")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.appTextPrimary)

                                DatePicker(
                                    "",
                                    selection: $dateOfBirth,
                                    in: ...Date(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .padding(Spacing.md)
                                .background(Color.appSurface)
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                                .onChange(of: dateOfBirth) { _, _ in clearErrorIfNeeded() }

                                if let ageWarning = ageWarningMessage {
                                    ValidationMessage(text: ageWarning)
                                } else {
                                    Text("You must be 13 or older to create an account")
                                        .font(.caption)
                                        .foregroundStyle(Color.appTextSecondary)
                                }
                            }

                            // Error Message
                            if let errorMessage {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                    Text(errorMessage)
                                        .font(.caption)
                                }
                                .foregroundStyle(Color.appError)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Spacing.xs)
                            }

                            // Sign Up Button
                            Button(action: signUp) {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text("Create Account")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .primaryButton()
                            .disabled(isLoading || !isFormValid)
                            .opacity((isLoading || !isFormValid) ? 0.6 : 1.0)
                            .padding(.top, Spacing.sm)
                        }
                        .padding(.horizontal, Spacing.xl)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.appTextSecondary)
                    .disabled(isLoading)
                }

                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func clearErrorIfNeeded() {
        if errorMessage != nil {
            errorMessage = nil
        }
    }

    private func signUp() {
        // Dismiss keyboard
        focusedField = nil

        // Clear previous errors
        errorMessage = nil

        // Validate age requirement
        guard isAtLeast13 else {
            errorMessage = "You must be at least 13 years old to create an account"
            return
        }

        // Validate email
        guard isEmailValid else {
            errorMessage = "Please enter a valid email address"
            return
        }

        // Validate username
        guard isUsernameValid else {
            errorMessage = "Username must be at least 3 characters and contain only letters, numbers, underscores, or hyphens"
            return
        }

        // Validate password
        guard isPasswordValid else {
            errorMessage = "Password must be at least 8 characters"
            return
        }

        // Validate password match
        guard passwordsMatch else {
            errorMessage = "Passwords do not match"
            return
        }

        isLoading = true

        Task {
            do {
                // Trim email and username, preserve password exactly
                let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

                try await sessionManager.signUp(
                    email: cleanEmail,
                    username: cleanUsername,
                    password: password, // Preserve exactly as entered
                    dateOfBirth: dateOfBirth
                )

                // Success - dismiss on main actor
                await MainActor.run {
                    dismiss()
                }
            } catch let error as AuthError {
                // Map auth errors to user-friendly messages
                await MainActor.run {
                    errorMessage = mapAuthError(error)
                    isLoading = false
                }
            } catch {
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
                        message = "We couldn't create your account right now. Please try again."
                    }
                }
                await MainActor.run {
                    errorMessage = message
                    isLoading = false
                }
            }
        }
    }

    private func mapAuthError(_ error: AuthError) -> String {
        switch error {
        case .underAge:
            return "You must be at least 13 years old to create an account"
        case .invalidCredentials:
            return "Invalid email or password format"
        case .usernameTaken:
            return "That username is already taken"
        case .networkError:
            return "No internet connection. Please check your network and try again."
        case .serverUnavailable:
            return "Our servers are temporarily unavailable. Please try again in a moment."
        case .serviceUnavailable:
            return "Service is temporarily unavailable. Please try again in a moment."
        case .timeout:
            return "Request timed out. Please try again."
        case .noConnection:
            return "No internet connection. Please check your network and try again."
        case .serverError(let message):
            // Check for common backend messages
            if message.contains("username") && message.contains("exists") || message.contains("already taken") {
                return "That username is already taken"
            } else if message.contains("email") && message.contains("exists") || message.contains("already registered") {
                return "An account with this email already exists"
            } else if message.contains("age") || message.contains("13") {
                return "You must be at least 13 years old to create an account"
            } else if message.contains("password") && (message.contains("weak") || message.contains("short")) {
                return "Password must be at least 8 characters"
            } else if message.contains("email") && message.contains("invalid") {
                return "Please enter a valid email address"
            }
            return "We couldn't create your account right now. Please try again."
        }
    }
}

// MARK: - Validation Message Component

struct ValidationMessage: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle.fill")
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(Color.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Enhanced Form Field Components

struct FormField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var submitLabel: SubmitLabel = .done

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.appTextPrimary)

            TextField(placeholder, text: $text)
                .submitLabel(submitLabel)
                .padding(Spacing.md)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                .foregroundStyle(Color.appTextPrimary)
        }
    }
}

struct SecureFormField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    @Binding var showPassword: Bool
    var submitLabel: SubmitLabel = .done

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.appTextPrimary)

            HStack {
                Group {
                    if showPassword {
                        TextField(placeholder, text: $text)
                            .submitLabel(submitLabel)
                    } else {
                        SecureField(placeholder, text: $text)
                            .submitLabel(submitLabel)
                    }
                }
                .textContentType(.password)

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(Color.appTextSecondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .padding(.trailing, Spacing.xs)
            }
            .padding(Spacing.md)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .foregroundStyle(Color.appTextPrimary)
        }
    }
}

#Preview {
    SignUpView()
        .environmentObject(SessionManager.shared)
}
