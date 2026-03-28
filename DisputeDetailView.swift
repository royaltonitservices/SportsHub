//
//  DisputeDetailView.swift
//  SportsHub
//
//  Phase 3: Trust + Match Lifecycle
//  Dispute resolution interface
//

import SwiftUI

struct DisputeDetailView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    let challenge: ChallengeResponse
    let onResolved: () async -> Void

    @State private var showCreateDispute = false
    @State private var disputeReason = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Status indicator
                    statusCard

                    // Match info
                    matchInfoCard

                    // Submission details
                    submissionDetailsCard

                    // Actions
                    if challenge.status == "disputed" {
                        waitingForAdminCard
                    } else if shouldShowDisputeButton {
                        createDisputeButton
                    }

                    // Error/success messages
                    if let error = errorMessage {
                        errorCard(error)
                    }

                    if let success = successMessage {
                        successCard(success)
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("Match Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCreateDispute) {
                createDisputeSheet
            }
        }
    }

    // MARK: - Status Card
    private var statusCard: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: statusIcon)
                .font(.system(size: 48))
                .foregroundStyle(statusColor)

            Text(statusText)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(Color.appTextPrimary)

            Text(statusDescription)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .cardBackground()
    }

    private var statusIcon: String {
        switch challenge.status {
        case "disputed": return "exclamationmark.triangle.fill"
        case "completed": return "checkmark.circle.fill"
        default: return "clock.fill"
        }
    }

    private var statusColor: Color {
        switch challenge.status {
        case "disputed": return .red
        case "completed": return .green
        default: return .orange
        }
    }

    private var statusText: String {
        switch challenge.status {
        case "disputed": return "Match Disputed"
        case "completed": return "Match Confirmed"
        default: return "Waiting for Confirmation"
        }
    }

    private var statusDescription: String {
        switch challenge.status {
        case "disputed":
            return "Results don't match. Admin will review and resolve."
        case "completed":
            return "Both players confirmed the same result"
        default:
            return "Waiting for opponent to submit result"
        }
    }

    // MARK: - Match Info Card
    private var matchInfoCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "sportscourt.fill")
                    .foregroundStyle(Color.appPrimary)
                Text("Match Information")
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)
            }

            Divider()

            VStack(spacing: Spacing.sm) {
                infoRow(label: "Sport", value: challenge.sport.capitalized)
                infoRow(label: "Match Type", value: challenge.matchType.capitalized)
                infoRow(label: "Date", value: formatDate(challenge.createdAt))
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.appTextPrimary)
        }
    }

    // MARK: - Submission Details Card
    private var submissionDetailsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(Color.appPrimary)
                Text("Submitted Results")
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)
            }

            Divider()

            VStack(spacing: Spacing.md) {
                submissionRow(
                    player: "You",
                    score: isChallenger ? challenge.challengerSubmittedScore : challenge.opponentSubmittedScore,
                    isUser: true
                )

                submissionRow(
                    player: "Opponent",
                    score: isChallenger ? challenge.opponentSubmittedScore : challenge.challengerSubmittedScore,
                    isUser: false
                )
            }

            if challenge.challengerSubmittedScore != nil && challenge.opponentSubmittedScore != nil {
                Divider()

                HStack(spacing: Spacing.xs) {
                    Image(systemName: scoresMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(scoresMatch ? Color.green : Color.red)
                    Text(scoresMatch ? "Results match" : "Results don't match")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(scoresMatch ? Color.green : Color.red)
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    private func submissionRow(player: String, score: String?, isUser: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(player)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appTextPrimary)

                if let score = score {
                    Text("Score: \(score)")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                } else {
                    Text("Not submitted")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            }

            Spacer()

            if score != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
            } else {
                Image(systemName: "clock.fill")
                    .foregroundStyle(Color.gray)
            }
        }
    }

    // MARK: - Waiting for Admin Card
    private var waitingForAdminCard: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "person.badge.shield.checkmark")
                .font(.system(size: 40))
                .foregroundStyle(Color.blue)

            Text("Under Review")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)

            Text("An admin will review the submitted results and make a decision. Both players will be notified of the outcome.")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    // MARK: - Create Dispute Button
    private var createDisputeButton: some View {
        Button(action: {
            showCreateDispute = true
        }) {
            HStack {
                Image(systemName: "exclamationmark.bubble.fill")
                Text("Report Incorrect Result")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)
            .foregroundStyle(.white)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
    }

    // MARK: - Create Dispute Sheet
    private var createDisputeSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Why are you disputing this result?")
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)

                    Text("Explain what happened. An admin will review your case.")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary)

                    TextEditor(text: $disputeReason)
                        .frame(height: 150)
                        .padding(Spacing.sm)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.small)
                                .strokeBorder(Color.appTextSecondary.opacity(0.2), lineWidth: 1)
                        )
                }

                Button(action: {
                    Task {
                        await submitDispute()
                    }
                }) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Submit Dispute")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.md)
                .foregroundStyle(.white)
                .background(disputeReason.isEmpty ? Color.gray : Color.red)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                .disabled(isSubmitting || disputeReason.isEmpty)

                Spacer()
            }
            .padding(Spacing.md)
            .navigationTitle("Report Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showCreateDispute = false
                    }
                }
            }
        }
    }

    // MARK: - Helper Views
    private func errorCard(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.appTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private func successCard(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.appTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    // MARK: - Computed Properties
    private var isChallenger: Bool {
        sessionManager.currentUser?.id.uuidString == challenge.challengerId
    }

    private var scoresMatch: Bool {
        guard let challengerScore = challenge.challengerSubmittedScore,
              let opponentScore = challenge.opponentSubmittedScore else {
            return false
        }
        return challengerScore == opponentScore
    }

    private var shouldShowDisputeButton: Bool {
        // Show button if both submitted but don't match, and not already disputed
        return challenge.challengerSubmittedScore != nil &&
               challenge.opponentSubmittedScore != nil &&
               !scoresMatch &&
               challenge.status != "disputed"
    }

    // MARK: - Actions
    private func submitDispute() async {
        isSubmitting = true
        errorMessage = nil

        do {
            _ = try await APIClient.shared.createDispute(
                challengeId: challenge.id,
                reason: disputeReason
            )

            successMessage = "Dispute submitted successfully"
            showCreateDispute = false

            // Wait a moment then dismiss and refresh
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await onResolved()
            dismiss()
        } catch {
            errorMessage = "We couldn't submit your dispute. Please try again."
        }

        isSubmitting = false
    }

    // MARK: - Helpers
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

#Preview {
    DisputeDetailView(
        challenge: ChallengeResponse(
            id: "1",
            challengerId: "user1",
            opponentId: "user2",
            sport: "basketball",
            matchType: "ranked",
            status: "disputed",
            createdAt: "2026-03-19T10:00:00Z",
            challengerSubmittedScore: "21-18",
            opponentSubmittedScore: "18-21",
            acceptedAt: "2026-03-19T10:01:00Z",
            completedAt: nil,
            winnerUserId: nil
        ),
        onResolved: {}
    )
    .environmentObject(SessionManager.shared)
}
