//
//  ForgotPasswordView.swift
//  SportsHub
//
//  Two-step password reset: enter email → receive 6-digit code → set new password.
//

import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Field?

    enum Field { case email, code, password, confirm }
    enum Step { case enterEmail, enterCode }

    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showNewPassword = false

    @State private var step: Step = .enterEmail
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    /// Delivery mode reported by the backend after requesting a code
    /// ("dev_log" / "sent" / "unavailable"). Drives honest step-2 copy.
    @State private var deliveryMode: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.xl) {
                        // Header
                        VStack(spacing: Spacing.sm) {
                            Image(systemName: "lock.rotation")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.appPrimary)
                                .padding(.top, 40)

                            Text(step == .enterEmail ? "Reset Password" : stepTwoTitle)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.appTextPrimary)

                            Text(step == .enterEmail
                                 ? "Enter your email address to get a 6-digit reset code."
                                 : stepTwoSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Spacing.lg)
                        }

                        // Form
                        VStack(spacing: Spacing.lg) {
                            if step == .enterEmail {
                                emailStep
                            } else {
                                codeStep
                            }

                            // Error
                            if let err = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                    Text(err)
                                        .font(.subheadline)
                                }
                                .foregroundStyle(.red)
                                .padding(Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                            }

                            // Success
                            if let msg = successMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text(msg)
                                        .font(.subheadline)
                                }
                                .foregroundStyle(.green)
                                .padding(Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.green.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                            }

                            // Primary CTA
                            Button(action: primaryAction) {
                                HStack(spacing: Spacing.sm) {
                                    if isLoading {
                                        ProgressView().tint(.white)
                                    }
                                    Text(step == .enterEmail ? "Send Reset Code" : "Reset Password")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                            }
                            .primaryButton()
                            .disabled(isLoading || primaryDisabled)
                            .opacity((isLoading || primaryDisabled) ? 0.7 : 1)

                            // Back link for code step
                            if step == .enterCode {
                                Button("Didn't receive a code? Send again") {
                                    withAnimation { step = .enterEmail }
                                }
                                .font(.subheadline)
                                .foregroundStyle(Color.appPrimary)
                            }
                        }
                        .padding(.horizontal, Spacing.xl)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.appPrimary)
                }
            }
        }
    }

    // MARK: - Email Step

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Email")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appTextPrimary)

            TextField("your@email.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .focused($focused, equals: .email)
                .padding(Spacing.md)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                .foregroundStyle(Color.appTextPrimary)
                .onChange(of: email) { _, _ in errorMessage = nil }
                .onSubmit { primaryAction() }
        }
    }

    // MARK: - Code + New Password Step

    private var codeStep: some View {
        VStack(spacing: Spacing.md) {
            // Code field
            VStack(alignment: .leading, spacing: 8) {
                Text("Reset Code")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appTextPrimary)

                TextField("6-digit code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .submitLabel(.next)
                    .focused($focused, equals: .code)
                    .padding(Spacing.md)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .foregroundStyle(Color.appTextPrimary)
                    .onChange(of: code) { _, _ in errorMessage = nil }
                    .onSubmit { focused = .password }
            }

            // New password
            VStack(alignment: .leading, spacing: 8) {
                Text("New Password")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appTextPrimary)

                HStack(spacing: 0) {
                    Group {
                        if showNewPassword {
                            TextField("At least 6 characters", text: $newPassword)
                        } else {
                            SecureField("At least 6 characters", text: $newPassword)
                        }
                    }
                    .textContentType(.newPassword)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .submitLabel(.next)
                    .focused($focused, equals: .password)
                    .onChange(of: newPassword) { _, _ in errorMessage = nil }
                    .onSubmit { focused = .confirm }

                    Button(action: { showNewPassword.toggle() }) {
                        Image(systemName: showNewPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.leading, Spacing.md)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                .foregroundStyle(Color.appTextPrimary)
            }

            // Confirm password
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appTextPrimary)

                SecureField("Repeat new password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .submitLabel(.go)
                    .focused($focused, equals: .confirm)
                    .padding(Spacing.md)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .foregroundStyle(Color.appTextPrimary)
                    .onChange(of: confirmPassword) { _, _ in errorMessage = nil }
                    .onSubmit { primaryAction() }
            }
        }
    }

    // MARK: - Actions

    // MARK: - Honest step-2 copy (driven by backend delivery mode)

    private var stepTwoTitle: String {
        switch deliveryMode {
        case "dev_log":     return "Check the Backend Logs"
        case "unavailable": return "Enter Your Reset Code"
        default:            return "Check Your Email"   // "sent" or unknown
        }
    }

    private var stepTwoSubtitle: String {
        switch deliveryMode {
        case "dev_log":
            return "This is a development build, so no email was sent. Your 6-digit reset code was printed to the local backend logs. Enter it below and choose a new password."
        case "unavailable":
            return "Email delivery isn't set up yet. If an account exists for \(email), enter the 6-digit reset code and choose a new password."
        default:
            return "If an account exists for \(email), we've sent a 6-digit reset code. Enter it below and choose a new password."
        }
    }

    private var primaryDisabled: Bool {
        if step == .enterEmail { return email.trimmingCharacters(in: .whitespaces).isEmpty }
        return code.count < 6 || newPassword.count < 6 || confirmPassword.isEmpty
    }

    private func primaryAction() {
        errorMessage = nil
        successMessage = nil
        if step == .enterEmail {
            sendCode()
        } else {
            submitReset()
        }
    }

    private func sendCode() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter your email address."
            return
        }
        isLoading = true
        Task {
            do {
                let delivery = try await APIClient.shared.forgotPassword(email: trimmed)
                await MainActor.run {
                    isLoading = false
                    deliveryMode = delivery
                    withAnimation { step = .enterCode }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    // Advance regardless to prevent email enumeration. Delivery mode
                    // is unknown here, so step-2 copy falls back to the neutral text.
                    deliveryMode = nil
                    withAnimation { step = .enterCode }
                }
            }
        }
    }

    private func submitReset() {
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords don't match."
            return
        }
        guard newPassword.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }
        isLoading = true
        Task {
            do {
                try await APIClient.shared.resetPassword(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    code: code.trimmingCharacters(in: .whitespaces),
                    newPassword: newPassword
                )
                await MainActor.run {
                    isLoading = false
                    successMessage = "Password updated! You can now sign in."
                    // Dismiss after brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch let apiError as APIError {
                await MainActor.run {
                    isLoading = false
                    // The reset endpoint returns a specific, user-safe 400 detail
                    // ("Invalid or expired reset code.") which the generic
                    // userFriendlyMessage would otherwise mask — surface it directly.
                    if case .serverError(let detail) = apiError {
                        errorMessage = detail
                    } else {
                        errorMessage = apiError.userFriendlyMessage
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Invalid or expired reset code. Please try again."
                }
            }
        }
    }
}

#Preview {
    ForgotPasswordView()
}
