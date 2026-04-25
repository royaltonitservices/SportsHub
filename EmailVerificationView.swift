//
//  EmailVerificationView.swift
//  SportsHub
//
//  6-digit email verification screen shown after signup.
//  Features: individual digit boxes, auto-advance, paste support,
//  60-second resend countdown, clear error states.
//

import SwiftUI

struct EmailVerificationView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    // The masked email shown to the user (e.g. jo***@gmail.com)
    let maskedEmail: String

    @State private var digits: [String] = Array(repeating: "", count: 6)
    @State private var focusedIndex: Int? = 0
    @State private var isVerifying = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var resendCountdown = 0
    @State private var countdownTimer: Timer?

    @FocusState private var focusedField: Int?

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.xl) {
                    headerSection
                    codeInputSection
                    actionSection
                    resendSection
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, 48)
                .padding(.bottom, Spacing.xl)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // Auto-send code on appear (backend already sent one at signup,
            // but if this view appears from login-resume, trigger a fresh send)
            startResendCountdown(seconds: 60)
        }
        .onDisappear {
            countdownTimer?.invalidate()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Spacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.appPrimary)
            }

            Text("Check your email")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.appTextPrimary)

            VStack(spacing: 4) {
                Text("We sent a 6-digit code to")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                Text(maskedEmail)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appTextPrimary)
            }
        }
    }

    // MARK: - Code Input

    private var codeInputSection: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    digitBox(index: index)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.appError)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            if let success = successMessage {
                Text(success)
                    .font(.caption)
                    .foregroundStyle(Color.appSuccess)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
        .animation(.easeInOut(duration: 0.2), value: successMessage)
    }

    private func digitBox(index: Int) -> some View {
        TextField("", text: $digits[index])
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.title2)
            .fontWeight(.bold)
            .foregroundStyle(Color.appTextPrimary)
            .frame(width: 46, height: 56)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .fill(Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .strokeBorder(
                                focusedField == index ? Color.appPrimary : Color.clear,
                                lineWidth: 2
                            )
                    )
            )
            .focused($focusedField, equals: index)
            .onChange(of: digits[index]) { _, newValue in
                handleDigitChange(index: index, newValue: newValue)
            }
            .onTapGesture {
                focusedField = index
            }
    }

    // MARK: - Action

    private var actionSection: some View {
        Button(action: submitCode) {
            ZStack {
                if isVerifying {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Verify Email")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .fill(isFormFilled ? Color.appPrimary : Color.appSurface)
            )
        }
        .disabled(!isFormFilled || isVerifying)
    }

    // MARK: - Resend

    private var resendSection: some View {
        VStack(spacing: Spacing.sm) {
            if resendCountdown > 0 {
                Text("Resend code in \(resendCountdown)s")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
            } else {
                Button(action: resendCode) {
                    if isSending {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.appPrimary))
                    } else {
                        Text("Resend code")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.appPrimary)
                    }
                }
                .disabled(isSending)
            }

            Button(action: signOut) {
                Text("Use a different account")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
    }

    // MARK: - Computed

    private var isFormFilled: Bool {
        digits.allSatisfy { $0.count == 1 }
    }

    private var fullCode: String {
        digits.joined()
    }

    // MARK: - Logic

    private func handleDigitChange(index: Int, newValue: String) {
        errorMessage = nil

        // Handle paste: if a 6-char string lands in one field, distribute it
        if newValue.count == 6 && newValue.allSatisfy({ $0.isNumber }) {
            let chars = Array(newValue)
            for i in 0..<6 { digits[i] = String(chars[i]) }
            focusedField = nil
            return
        }

        // Keep only last digit if multiple entered
        if newValue.count > 1 {
            digits[index] = String(newValue.suffix(1))
        }

        // Filter non-digits
        digits[index] = digits[index].filter { $0.isNumber }

        // Auto-advance
        if digits[index].count == 1 && index < 5 {
            focusedField = index + 1
        }

        // Auto-backspace to previous field on delete
        if digits[index].isEmpty && index > 0 {
            focusedField = index - 1
        }
    }

    private func submitCode() {
        guard isFormFilled else { return }
        isVerifying = true
        errorMessage = nil

        Task {
            do {
                let tokenResponse = try await APIClient.shared.verifyCode(fullCode)
                await sessionManager.handleVerificationSuccess(token: tokenResponse.accessToken)
            } catch let error as APIError {
                await MainActor.run {
                    errorMessage = self.errorMessage(from: error)
                    isVerifying = false
                    // Clear digits on wrong/expired code so user retries cleanly
                    if case .serverError = error {
                        digits = Array(repeating: "", count: 6)
                        focusedField = 0
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Something went wrong. Please try again."
                    isVerifying = false
                }
            }
        }
    }

    private func resendCode() {
        isSending = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                _ = try await APIClient.shared.resendVerificationCode()
                await MainActor.run {
                    isSending = false
                    successMessage = "New code sent!"
                    startResendCountdown(seconds: 60)
                    // Clear old digits
                    digits = Array(repeating: "", count: 6)
                    focusedField = 0
                }
            } catch let error as APIError {
                await MainActor.run {
                    isSending = false
                    errorMessage = errorMessage(from: error)
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Couldn't send code. Please try again."
                }
            }
        }
    }

    private func startResendCountdown(seconds: Int) {
        countdownTimer?.invalidate()
        resendCountdown = seconds
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if self.resendCountdown > 0 {
                    self.resendCountdown -= 1
                } else {
                    self.countdownTimer?.invalidate()
                    self.countdownTimer = nil
                }
            }
        }
    }

    private func signOut() {
        countdownTimer?.invalidate()
        sessionManager.logout()
    }

    private func errorMessage(from error: APIError) -> String {
        switch error {
        case .serverError(let msg):
            // Server sends specific messages for bad code / rate limits
            return msg
        case .unauthorized, .forbidden:
            return "Session expired. Please sign in again."
        default:
            return "Something went wrong. Please try again."
        }
    }
}

#Preview {
    EmailVerificationView(maskedEmail: "jo***@gmail.com")
        .environmentObject(SessionManager.shared)
        .preferredColorScheme(.dark)
}
