
//
//  AppCapability.swift
//  SportsHub
//
//  Single source of truth for every feature with a UI affordance.
//  Add a case here when a new interactive feature is introduced.
//  Update CapabilityRegistry when the backing implementation is ready.
//

import Foundation

/// One case per feature that has a visible UI affordance.
/// Never add a case here for a feature that is fully implemented and available to all users.
enum AppCapability: CaseIterable {
    /// Google Sign-In — OAuthManager.signInWithGoogle() always throws; no Google SDK integrated.
    case googleSignIn

    /// Delete a direct-message conversation — no backend DELETE /conversations endpoint; empty closure in UI.
    case conversationDelete

    /// General athlete/content search from HomeView search bar — currently opens AddFriendView (friend search only).
    case generalSearch

    /// Structured training programs — no programs infrastructure exists; placeholder "coming soon" section.
    case trainingPrograms

    /// Evidence file upload — real multipart upload pipeline implemented (Phase 4b).
    case evidenceFileUpload

    /// The `id` of the corresponding `FeatureDefinition` in `FeatureManifest.allFeatures`.
    /// Used by `CoherenceValidator` to assert that every `.available` capability is backed
    /// by a `.complete` feature. Must be kept in sync when new cases are added.
    var featureManifestId: String? {
        switch self {
        case .googleSignIn:       return "google_sign_in"
        case .conversationDelete: return "conversation_delete"
        case .generalSearch:      return "general_search"
        case .trainingPrograms:   return "training_programs"
        case .evidenceFileUpload: return "evidence_upload"
        }
    }
}

/// Describes how an unavailable capability should be presented.
enum CapabilityStatus {
    /// Fully implemented; render normally.
    case available

    /// Not implemented; remove the affordance from the view hierarchy entirely.
    /// Users never see a broken or misleading UI element.
    case unavailableHidden

    /// Not yet implemented but committed to the roadmap; render the affordance
    /// with a "Coming Soon" overlay so users understand it is intentional.
    case unavailableComingSoon

    /// Only shown in DEBUG builds (e.g., internal testing tools).
    case debugOnly
}

/// Maps every AppCapability to its current CapabilityStatus.
/// This is the only place that should be updated when an implementation becomes ready.
enum CapabilityRegistry {
    static let statuses: [AppCapability: CapabilityStatus] = [
        // Phase 1 — identified as fake/dead/misleading in audit
        .googleSignIn:        .unavailableHidden,   // no SDK; always throws after 2s delay
        .conversationDelete:  .unavailableHidden,   // no backend endpoint; empty action closure
        .generalSearch:       .unavailableHidden,   // opens friend search, not general search
        .trainingPrograms:    .unavailableHidden,   // no infrastructure; "coming soon" placeholder
        .evidenceFileUpload:  .available,            // real multipart upload (Phase 4b complete)
    ]

    /// Returns the status for a capability, defaulting to .unavailableHidden for safety.
    /// An unknown capability is never silently treated as available.
    static func status(for capability: AppCapability) -> CapabilityStatus {
        statuses[capability] ?? .unavailableHidden
    }
}
