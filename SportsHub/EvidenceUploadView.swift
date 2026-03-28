//
//  EvidenceUploadView.swift
//  SportsHub
//
//  Phase 4: Evidence upload for match verification
//

import SwiftUI
import PhotosUI

struct EvidenceUploadView: View {
    @Environment(\.dismiss) private var dismiss
    let challenge: ChallengeResponse
    let requirement: EvidenceRequirementResponse
    let onUploadComplete: () async -> Void

    @State private var evidenceType: String = "image"
    @State private var description: String = ""
    @State private var isUploading = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var selectedMedia: PhotosPickerItem?
    @State private var hasSelectedMedia = false
    @State private var selectedMediaFileName: String?
    @State private var showPhotoPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Requirement Explanation
                    requirementCard

                    // Evidence Type Selector
                    evidenceTypeSelector

                    // Upload Options
                    uploadOptions

                    // Description Field
                    descriptionField

                    // Upload Button
                    uploadButton

                    // Skip Option (if not required)
                    if requirement.requirement != "required" {
                        skipButton
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("Submit Evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if showSuccess {
                    successOverlay
                }
            }
            .alert("Upload Error", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
                Button("Try Again", role: .cancel) {
                    errorMessage = nil
                }
            } message: { error in
                Text(error)
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedMedia,
                matching: evidenceType == "video" ? .videos : .images
            )
            .onChange(of: selectedMedia) { _, newValue in
                if newValue != nil {
                    handleMediaSelection()
                }
            }
        }
    }

    private var requirementCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: requirementIcon)
                    .font(.title2)
                    .foregroundStyle(requirementColor)

                Text(requirementTitle)
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)

                Spacer()
            }

            Text(requirement.reason)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Trust tier indicators (if relevant)
            if requirement.requirement != "optional" {
                HStack(spacing: Spacing.sm) {
                    trustTierBadge(tier: requirement.userTrustTier, label: "You")
                    trustTierBadge(tier: requirement.opponentTrustTier, label: "Opponent")
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .strokeBorder(requirementColor.opacity(0.3), lineWidth: 2)
        )
    }

    private var evidenceTypeSelector: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Evidence Type")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)

            HStack(spacing: Spacing.sm) {
                typeButton(type: "image", icon: "photo.fill", label: "Photo")
                typeButton(type: "screenshot", icon: "camera.viewfinder", label: "Screenshot")
                typeButton(type: "video", icon: "video.fill", label: "Video")
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    private func typeButton(type: String, icon: String, label: String) -> some View {
        Button(action: {
            // Clear selected media when changing type
            if evidenceType != type {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    evidenceType = type
                    hasSelectedMedia = false
                    selectedMedia = nil
                    selectedMediaFileName = nil
                }
            }
        }) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(evidenceType == type ? .white : Color.appTextPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(evidenceType == type ? Color.appPrimary : Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.small)
                    .strokeBorder(evidenceType == type ? Color.appPrimary : Color.clear, lineWidth: 2)
            )
        }
    }

    private var uploadOptions: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Text(hasSelectedMedia ? "Selected Media" : "Upload Evidence")
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)
                
                Spacer()
                
                if hasSelectedMedia {
                    Button("Change") {
                        showPhotoPicker = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.appPrimary)
                }
            }

            if hasSelectedMedia {
                // Selected state - show what was picked
                HStack(spacing: Spacing.md) {
                    Image(systemName: evidenceType == "video" ? "video.fill" : "photo.fill")
                        .font(.title)
                        .foregroundStyle(Color.green)
                        .frame(width: 60, height: 60)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.green)
                            Text("Ready to upload")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appTextPrimary)
                        }
                        
                        Text(selectedMediaFileName ?? "\(evidenceType == "video" ? "Video" : "Photo") selected")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            hasSelectedMedia = false
                            selectedMedia = nil
                            selectedMediaFileName = nil
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
                .padding(Spacing.md)
                .background(Color.green.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .strokeBorder(Color.green.opacity(0.3), lineWidth: 1.5)
                )
                .transition(.scale.combined(with: .opacity))
            } else {
                // Empty state - prompt to select
                Button(action: {
                    showPhotoPicker = true
                }) {
                    HStack {
                        Image(systemName: evidenceType == "video" ? "video.badge.plus" : "photo.badge.plus")
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Choose from Library")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(evidenceType == "video" ? "Select game clip or recording" : "Select scoreboard photo or screenshot")
                                .font(.caption)
                                .opacity(0.8)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.appPrimary)
                    .padding(Spacing.md)
                    .background(Color.appPrimary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .strokeBorder(Color.appPrimary.opacity(0.3), lineWidth: 1.5)
                    )
                }
                .transition(.scale.combined(with: .opacity))
            }

            // Improved guidance based on evidence type
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption2)
                    Text("What to submit:")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.appTextSecondary)
                
                Group {
                    if evidenceType == "video" {
                        Text("• Game clips showing the final score\n• Recording of the match scoreboard\n• Video proof of match completion")
                    } else if evidenceType == "screenshot" {
                        Text("• Screenshot of final scoreboard\n• In-game score screen capture\n• Match result confirmation screen")
                    } else {
                        Text("• Photo of scoreboard showing final score\n• Picture of match result display\n• Clear image of score confirmation")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Description (Optional)")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)

            TextField(descriptionPlaceholder, text: $description, axis: .vertical)
                .lineLimit(3...6)
                .padding(Spacing.md)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.small)
                        .strokeBorder(Color.appTextSecondary.opacity(0.2), lineWidth: 1)
                )
            
            Text("Add any relevant details about the match or score")
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private var descriptionPlaceholder: String {
        switch requirement.requirement {
        case "required":
            return "Explain the match context (helpful for review)"
        case "recommended":
            return "Add notes about the match if helpful"
        default:
            return "Optional: Add context or notes"
        }
    }

    private var uploadButton: some View {
        Button(action: {
            Task {
                await submitEvidence()
            }
        }) {
            HStack(spacing: Spacing.sm) {
                if isUploading {
                    ProgressView()
                        .tint(.white)
                    Text("Uploading...")
                        .fontWeight(.semibold)
                } else {
                    Image(systemName: canSubmit ? "arrow.up.circle.fill" : "arrow.up.circle")
                    Text(submitButtonText)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(canSubmit ? .white : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)
            .background(canSubmit ? Color.appPrimary : Color.appTextSecondary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
        .disabled(!canSubmit || isUploading)
        .padding(.horizontal, Spacing.md)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSubmit)
    }
    
    private var canSubmit: Bool {
        // Required evidence must have media selected
        if requirement.requirement == "required" {
            return hasSelectedMedia
        }
        // Optional/recommended can submit without media
        return true
    }
    
    private var submitButtonText: String {
        if !hasSelectedMedia && requirement.requirement == "required" {
            return "Select Media to Continue"
        }
        
        switch requirement.requirement {
        case "required":
            return "Submit Required Evidence"
        case "recommended":
            return hasSelectedMedia ? "Submit Evidence" : "Submit Without Evidence"
        default:
            return hasSelectedMedia ? "Submit Evidence" : "Continue Without Evidence"
        }
    }

    private var skipButton: some View {
        Button(action: {
            dismiss()
        }) {
            Text(requirement.requirement == "recommended" ? "I'll Submit Later" : "Skip for Now")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
        }
        .padding(.horizontal, Spacing.md)
    }

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {} // Prevent dismissal by tap

            VStack(spacing: Spacing.lg) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.green)
                    .symbolEffect(.bounce, value: showSuccess)

                VStack(spacing: Spacing.sm) {
                    Text(hasSelectedMedia ? "Evidence Submitted!" : "Submission Recorded")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text(successMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Spacing.sm)
                }
            }
            .padding(Spacing.xl)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            .padding(Spacing.xl)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    private var successMessage: String {
        if !hasSelectedMedia {
            return "You can submit evidence later if needed"
        }
        
        switch requirement.requirement {
        case "required":
            return "Your evidence will help verify this match. Both players' submissions will be reviewed if needed."
        case "recommended":
            return "Thank you for submitting evidence. This helps protect both players in case of disputes."
        default:
            return "Evidence saved. This will speed up any future dispute resolution."
        }
    }

    private func trustTierBadge(tier: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: trustTierIcon(tier))
                .font(.caption2)
            Text("\(label): \(tier.capitalized)")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(trustTierColor(tier))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(trustTierColor(tier).opacity(0.15))
        .clipShape(Capsule())
    }

    private var requirementIcon: String {
        switch requirement.requirement {
        case "required": return "exclamationmark.shield.fill"
        case "recommended": return "checkmark.shield.fill"
        default: return "info.circle.fill"
        }
    }

    private var requirementColor: Color {
        switch requirement.requirement {
        case "required": return .red
        case "recommended": return .orange
        default: return .blue
        }
    }

    private var requirementTitle: String {
        switch requirement.requirement {
        case "required": return "Evidence Required"
        case "recommended": return "Evidence Recommended"
        default: return "Evidence Optional"
        }
    }

    private func trustTierIcon(_ tier: String) -> String {
        switch tier {
        case "trusted": return "checkmark.seal.fill"
        case "caution": return "exclamationmark.triangle.fill"
        case "restricted": return "xmark.shield.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private func trustTierColor(_ tier: String) -> Color {
        switch tier {
        case "trusted": return .green
        case "caution": return .orange
        case "restricted": return .red
        default: return .blue
        }
    }

    private func handleMediaSelection() {
        Task {
            guard let selectedMedia else { return }
            
            // Extract filename if possible
            if let identifier = selectedMedia.itemIdentifier {
                selectedMediaFileName = String(identifier.split(separator: "/").last ?? "Selected media")
            } else {
                selectedMediaFileName = nil
            }
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                hasSelectedMedia = true
            }
        }
    }
    
    private func submitEvidence() async {
        isUploading = true
        errorMessage = nil

        do {
            // Only upload if media was selected
            if hasSelectedMedia {
                // In production, would upload actual image/video to CDN first
                // Simulate realistic upload delay
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                let fileExtension = evidenceType == "video" ? "mp4" : "jpg"
                let fileUrl = "https://cdn.sportshub.com/evidence/\(challenge.id)/\(evidenceType)_\(Date().timeIntervalSince1970).\(fileExtension)"

                _ = try await APIClient.shared.uploadEvidence(
                    challengeId: challenge.id,
                    evidenceType: evidenceType,
                    fileUrl: fileUrl,
                    description: description.isEmpty ? nil : description
                )
            }

            // Show success
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showSuccess = true
            }

            // Dismiss after delay
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
            await onUploadComplete()
            dismiss()
        } catch {
            errorMessage = "We couldn't upload your evidence. Check your connection and try again."
        }

        isUploading = false
    }
}

#Preview {
    EvidenceUploadView(
        challenge: ChallengeResponse(
            id: "test-id",
            challengerId: "challenger-id",
            opponentId: "opponent-id",
            sport: "basketball",
            matchType: "ranked",
            status: "accepted",
            createdAt: "2026-03-19T12:00:00Z",
            challengerSubmittedScore: nil,
            opponentSubmittedScore: nil,
            acceptedAt: "2026-03-19T12:05:00Z",
            completedAt: nil,
            winnerUserId: nil
        ),
        requirement: EvidenceRequirementResponse(
            challengeId: "test-id",
            requirement: "recommended",
            reason: "Opponent has elevated trust requirements - evidence recommended for protection",
            isDisputed: false,
            userTrustTier: "standard",
            opponentTrustTier: "caution"
        ),
        onUploadComplete: {}
    )
}
