//
//  ResultSubmissionView.swift
//  SportsHub
//
//  Created for Phase 1: Chess-style Challenge Flow
//

import SwiftUI

struct ResultSubmissionView: View {
    let challenge: ChallengeResponse
    let onSubmit: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedWinner: String = ""
    @State private var myScore: String = ""
    @State private var opponentScore: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    // Phase 4: Evidence integration
    @State private var evidenceRequirement: EvidenceRequirementResponse?
    @State private var showEvidenceUpload = false
    @State private var isCheckingRequirement = true

    // This screen is reached by BOTH the challenger and the opponent, so "I Won"
    // must map to whoever is *currently* viewing — not always the challenger.
    // Role is resolved case-insensitively (Swift UUID.uuidString is uppercase;
    // backend IDs are lowercase).
    private var amChallenger: Bool {
        SessionManager.shared.isCurrentUser(challenge.challengerId)
    }
    private var myId: String { amChallenger ? challenge.challengerId : challenge.opponentId }
    private var theirId: String { amChallenger ? challenge.opponentId : challenge.challengerId }
    private var opponentName: String {
        let display = amChallenger ? challenge.opponentDisplayName : challenge.challengerDisplayName
        let username = amChallenger ? challenge.opponentUsername : challenge.challengerUsername
        if let d = display, !d.isEmpty { return d }
        if let u = username, !u.isEmpty { return u }
        return "Opponent"
    }
    private var myName: String {
        SessionManager.shared.currentUser?.displayName ?? "You"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Match Info Card
                    matchInfoCard
                    
                    // Winner Selection
                    winnerSection
                    
                    // Score Entry (Optional)
                    scoreSection

                    // Phase 4: Evidence recommendation card
                    if let requirement = evidenceRequirement, requirement.requirement != "optional" {
                        evidenceRecommendationCard
                    }

                    // Submit Button
                    submitButton

                    // Info Note
                    confirmationNote
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("Submit Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showEvidenceUpload) {
                if let requirement = evidenceRequirement {
                    EvidenceUploadView(
                        challenge: challenge,
                        requirement: requirement,
                        onUploadComplete: {
                            await loadEvidenceRequirement()
                        }
                    )
                }
            }
            .task {
                await loadEvidenceRequirement()
            }
        }
    }
    
    private var matchInfoCard: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: "sportscourt.fill")
                    .foregroundStyle(Color.appPrimary)
                Text(challenge.sport.capitalized)
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
                Text(challenge.matchType.capitalized)
                    .font(.caption)
                    .foregroundStyle(Color.appPrimary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.appPrimary.opacity(0.2)))
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    Text(myName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appTextPrimary)
                }

                Spacer()

                Text("vs")
                    .font(.headline)
                    .foregroundStyle(Color.appTextSecondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Opponent")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    Text(opponentName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appTextPrimary)
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private var winnerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Color.appPrimary)
                Text("Who won?")
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)
            }
            
            VStack(spacing: Spacing.sm) {
                winnerButton(id: myId, label: "I Won", icon: "checkmark.circle.fill")
                winnerButton(id: theirId, label: "Opponent Won", icon: "xmark.circle.fill")
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private func winnerButton(id: String, label: String, icon: String) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedWinner = id
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(selectedWinner == id ? .white : Color.appPrimary)
                
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(selectedWinner == id ? .white : Color.appTextPrimary)
                
                Spacer()
                
                if selectedWinner == id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.white)
                }
            }
            .padding(Spacing.md)
            .background(selectedWinner == id ? Color.appPrimary : Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        }
    }
    
    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "number.circle.fill")
                    .foregroundStyle(Color.appPrimary)
                Text("Score (Optional)")
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)
            }
            
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Score")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    TextField("0", text: $myScore)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }
                
                Text("-")
                    .font(.headline)
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, Spacing.md)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opponent Score")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    TextField("0", text: $opponentScore)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private var submitButton: some View {
        Button(action: {
            Task {
                await submitResult()
            }
        }) {
            HStack {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                }
                
                Text(isSubmitting ? "Submitting..." : "Submit Result")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)
            .background(selectedWinner.isEmpty ? Color.gray : Color.appPrimary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
        .disabled(selectedWinner.isEmpty || isSubmitting)
    }
    
    private var confirmationNote: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.appSecondary)
                Text("Opponent must confirm")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
            }

            Text("Both players must submit the same result before ratings are updated. If results don't match, a dispute will be created.")
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(Color.appSecondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
    }

    private var evidenceRecommendationCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: evidenceRequirement?.requirement == "required" ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .foregroundStyle(evidenceRequirement?.requirement == "required" ? Color.red : Color.orange)
                Text(evidenceRequirement?.requirement == "required" ? "Evidence Required" : "Evidence Recommended")
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
            }

            if let reason = evidenceRequirement?.reason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: {
                showEvidenceUpload = true
            }) {
                HStack {
                    Image(systemName: "arrow.up.doc.fill")
                    Text("Upload Evidence")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(Color.appPrimary)
                .padding(Spacing.sm)
                .background(Color.appPrimary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            }
        }
        .padding(Spacing.md)
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .strokeBorder((evidenceRequirement?.requirement == "required" ? Color.red : Color.orange).opacity(0.3), lineWidth: 2)
        )
    }

    private func loadEvidenceRequirement() async {
        isCheckingRequirement = true

        do {
            evidenceRequirement = try await APIClient.shared.checkEvidenceRequirement(challengeId: challenge.id)
        } catch {
            // Silently fail - evidence system is optional enhancement
            print("Failed to check evidence requirement: \(error)")
        }

        isCheckingRequirement = false
    }

    private func submitResult() async {
        guard !selectedWinner.isEmpty else { return }
        
        isSubmitting = true
        errorMessage = nil
        
        do {
            let scoreData = !myScore.isEmpty && !opponentScore.isEmpty
                ? "\(myScore)-\(opponentScore)"
                : nil

            let response = try await APIClient.shared.submitMatchResult(
                challengeId: challenge.id,
                winnerId: selectedWinner,
                scoreData: scoreData
            )

            // Only fire a result notification when the match actually closed
            // (status == "completed"). For first-submitter "waiting" and
            // "disputed" states, suppress the alert because no rating change
            // applies yet — surfacing a +15/-10 placeholder would be a lie.
            if response.status == "completed" {
                // selectedWinner and myId are both backend-style IDs, so this
                // comparison is casing-safe (unlike comparing against the
                // uppercase UUID.uuidString directly). Delta is chosen by role.
                let currentUserWon = (selectedWinner == myId)
                let myDelta = amChallenger
                    ? response.challengerRatingChange
                    : response.opponentRatingChange
                NotificationManager.shared.scheduleResultNotification(
                    opponentName: "",
                    won: currentUserWon,
                    ratingChange: myDelta
                )
            }

            await onSubmit()
            dismiss()
        } catch {
            errorMessage = "We couldn't submit your result. Please try again."
            isSubmitting = false
        }
    }
}

#Preview {
    ResultSubmissionView(
        challenge: ChallengeResponse(
            id: "1",
            challengerId: "user1",
            opponentId: "user2",
            sport: "basketball",
            matchType: "ranked",
            status: "accepted",
            createdAt: "2026-03-19T10:00:00Z",
            challengerSubmittedScore: nil,
            opponentSubmittedScore: nil,
            acceptedAt: "2026-03-19T10:01:00Z",
            completedAt: nil,
            winnerUserId: nil
        ),
        onSubmit: {}
    )
}
