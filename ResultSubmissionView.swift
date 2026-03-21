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
                    Text("Player 1")
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
                    Text("Player 2")
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
                winnerButton(id: challenge.challengerId, label: "I Won", icon: "checkmark.circle.fill")
                winnerButton(id: challenge.opponentId, label: "Opponent Won", icon: "xmark.circle.fill")
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
            
            try await APIClient.shared.submitMatchResult(
                challengeId: challenge.id,
                winnerId: selectedWinner,
                scoreData: scoreData
            )
            
            await onSubmit()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
