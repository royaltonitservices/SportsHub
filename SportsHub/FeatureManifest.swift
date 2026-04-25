
//
//  FeatureManifest.swift
//  SportsHub
//
//  Single source of truth for feature implementation completeness.
//  Each feature records presence across 4 layers:
//    UI         — a SwiftUI view / affordance exists
//    ViewModel  — a ViewModel, ObservableObject, or state manager owns business logic
//    APIClient  — an APIClient method calls the backend
//    Backend    — a FastAPI router endpoint handles the request
//
//  Status reflects actual code state after Phases 1-5.
//  Update entries here when layers are added or removed.
//  Do NOT mark features complete optimistically.
//

import Foundation

// MARK: - Feature Status

enum FeatureStatus {
    /// All four layers are present and the feature functions end-to-end.
    case complete
    /// One or more layers are present but the feature cannot function end-to-end.
    case partial
    /// No meaningful implementation exists in any layer.
    case absent
}

// MARK: - Feature Layer Presence

struct FeatureLayerPresence {
    /// A user-facing SwiftUI view or UI affordance exists.
    let hasUI: Bool
    /// A ViewModel, ObservableObject, or state manager owns business logic.
    let hasViewModel: Bool
    /// An APIClient method exists to call the backend.
    let hasAPIClient: Bool
    /// A FastAPI router endpoint exists in the backend.
    let hasBackend: Bool

    /// All layers present.
    static let allPresent = FeatureLayerPresence(hasUI: true,  hasViewModel: true,  hasAPIClient: true,  hasBackend: true)
    /// No layers present.
    static let allAbsent  = FeatureLayerPresence(hasUI: false, hasViewModel: false, hasAPIClient: false, hasBackend: false)

    /// True when every layer has an implementation — a necessary (not sufficient) condition for `.complete` status.
    var isFullyImplemented: Bool {
        hasUI && hasViewModel && hasAPIClient && hasBackend
    }
}

// MARK: - Feature Definition

struct FeatureDefinition {
    let id: String
    let name: String
    let status: FeatureStatus
    let layers: FeatureLayerPresence
    /// Brief explanation of current state and any known gaps.
    let notes: String?

    init(id: String, name: String, status: FeatureStatus, layers: FeatureLayerPresence, notes: String? = nil) {
        #if DEBUG
        if status == .complete && !layers.isFullyImplemented {
            assertionFailure(
                "'\(name)' is marked .complete but is missing at least one layer. " +
                "Fix the layer presence or downgrade status to .partial."
            )
        }
        #endif
        self.id = id
        self.name = name
        self.status = status
        self.layers = layers
        self.notes = notes
    }
}

// MARK: - Feature Manifest

enum FeatureManifest {

    // -----------------------------------------------------------------------
    // COMPLETE — all 4 layers present; feature functions end-to-end
    // -----------------------------------------------------------------------

    static let evidenceUpload = FeatureDefinition(
        id: "evidence_upload",
        name: "Evidence Upload",
        status: .complete,
        layers: .allPresent,
        notes: "Phase 4a/4b: real multipart POST /evidence/upload; UploadRecord DB model; upload_id returned to iOS; /cdn/evidence CDN mount. No fake URL path remains."
    )

    static let homeActivityFeed = FeatureDefinition(
        id: "home_activity_feed",
        name: "Home Activity Feed",
        status: .complete,
        layers: .allPresent,
        notes: "Phase 5: HomeView fetches GET /activity/feed; typed ActivityLoadState enum (idle/loading/loaded/failed); sport-filtered client-side; static placeholder removed."
    )

    static let tournamentRegisteredState = FeatureDefinition(
        id: "tournament_registered_state",
        name: "Tournament isRegistered State",
        status: .complete,
        layers: .allPresent,
        notes: "Phase 3: TournamentDetailViewModel.isRegistered seeded from tournament.isRegistered ?? false at init; eliminates first-render false-negative. Backend batch-queries participant table."
    )

    static let skillProgressionDisclosure = FeatureDefinition(
        id: "skill_progression_disclosure",
        name: "Skill Progression Disclosure Accuracy",
        status: .complete,
        layers: .allPresent,
        notes: "Phase 2: disclosure label now derived from StorageStrategy.hybrid (confirmed SkillProgressionEngine calls syncSkillSnapshot / getSkillSnapshot). Label previously said 'local only' — incorrect."
    )

    static let matchResultSubmit = FeatureDefinition(
        id: "match_result_submit",
        name: "Match Result Submit",
        status: .complete,
        layers: .allPresent,
        notes: "ResultSubmissionView → submitResult(). POST /challenges/{id}/result. Pre-existing and confirmed working."
    )

    static let directMessaging = FeatureDefinition(
        id: "direct_messaging",
        name: "Direct Messaging (1:1)",
        status: .complete,
        layers: .allPresent,
        notes: "Friends-only gate enforced. Message send, conversation list, read receipts all wired. Pre-existing."
    )

    static let friendSystem = FeatureDefinition(
        id: "friend_system",
        name: "Friend System",
        status: .complete,
        layers: .allPresent,
        notes: "9+ endpoints: send / accept / decline requests, list friends, block/unblock, search, status check. Pre-existing."
    )

    static let tournaments = FeatureDefinition(
        id: "tournaments",
        name: "Tournaments (List / Create / Register / Bracket)",
        status: .complete,
        layers: .allPresent,
        notes: "PremiumAPIClient: 10+ methods. Backend: routers/tournaments.py. Premium-gated creation; free users can join. is_registered computed via batch query (Phase 5 session fix)."
    )

    static let passwordReset = FeatureDefinition(
        id: "password_reset",
        name: "Password Reset",
        status: .complete,
        layers: .allPresent,
        notes: "POST /auth/forgot-password + /auth/reset-password. 6-digit code, salted SHA-256, 10-min TTL, single-use enforcement. ForgotPasswordView 2-step flow."
    )

    static let profilePictureUpload = FeatureDefinition(
        id: "profile_picture_upload",
        name: "Profile Picture Upload",
        status: .complete,
        layers: .allPresent,
        notes: "PUT /users/me/avatar multipart endpoint. /cdn/avatars/ StaticFiles CDN. PhotosPicker in ProfileView uploads JPEG on selection."
    )

    // -----------------------------------------------------------------------
    // PARTIAL — layers exist but feature cannot function end-to-end
    // -----------------------------------------------------------------------

    static let aiCoachChat = FeatureDefinition(
        id: "ai_coach_chat",
        name: "AI Coach Chat",
        status: .partial,
        layers: .allPresent,
        notes: "~82% complete. Chat, voice input, proactive insights, survey intelligence, and conversation persistence all wired. Local coaching engine is fallback. Gap: team-challenge coaching and full drill-catalog integration not wired."
    )

    static let googleSignIn = FeatureDefinition(
        id: "google_sign_in",
        name: "Google Sign-In",
        status: .partial,
        layers: FeatureLayerPresence(hasUI: true, hasViewModel: true, hasAPIClient: true, hasBackend: true),
        notes: "UI button exists in code but hidden via CapabilityRegistry (.unavailableHidden, Phase 1). OAuthManager.signInWithGoogle() throws immediately — no Google SDK integrated. Cannot produce a real ID token. Backend handler exists (tokeninfo validation when GOOGLE_OAUTH_CLIENT_ID set) but untestable without SDK."
    )

    static let generalSearch = FeatureDefinition(
        id: "general_search",
        name: "General Athlete / Content Search",
        status: .partial,
        layers: FeatureLayerPresence(hasUI: true, hasViewModel: false, hasAPIClient: false, hasBackend: false),
        notes: "HomeView search bar exists. Phase 1: scoped to friend search (opens AddFriendView). Capability gated (.unavailableHidden). No general search ViewModel, no APIClient method, no backend search route beyond GET /users/search (user lookup by username only)."
    )

    static let trainingProfileEditing = FeatureDefinition(
        id: "training_profile_editing",
        name: "Training Profile Editing (Settings)",
        status: .complete,
        layers: .allPresent,
        notes: "Phase 13: Goals field added to backend OnboardingSurveyRequest/Response (models.py goals column, schemas.py goals field, onboarding_survey.py persistence). iOS: OnboardingSurveyRequest/Response updated, SettingsView TrainingProfileSettingsView has Goals section with sport-specific toggles, loads from cache, saves and refreshes cache. Full round-trip: POST /onboarding/survey (with goals) → GET /onboarding/survey → UserDefaults cache update. Migration: migrate_auth_onboarding.py Step 2b adds goals column idempotently."
    )

    static let aiCoachSafetyModes = FeatureDefinition(
        id: "ai_coach_safety_modes",
        name: "AI Coach Safety Modes",
        status: .complete,
        layers: .allPresent,
        notes: "Phase 11-12: 4 explicit modes (normal, recoveryBiased, injuryCaution, stopAndDefer) with override hierarchy. SafetyModeClassifier accepts wearable recovery score (<30 → recoveryBiased). stopAndDefer short-circuits the entire coaching brief. Applied to both GPT and local paths. Backend COACHING_PHILOSOPHY safety rule #7 mirrors this."
    )

    static let aiCoachGPTContractValidation = FeatureDefinition(
        id: "ai_coach_gpt_validation",
        name: "AI Coach GPT Post-Response Validation",
        status: .partial,
        layers: FeatureLayerPresence(hasUI: false, hasViewModel: true, hasAPIClient: false, hasBackend: true),
        notes: "Phase 13: Constrained retry added. Flow: first GPT response fails → recordConstrainedRetryStarted → second GPT call with constrainedMode=true in CoachContext → backend injects strict per-sport contract block into system prompt → if second response passes validation → show response; if second fails or network error → recordConstrainedRetryFailed → handleWithLocalCoaching (guaranteed no loop). Backend football hard-stop also added: _normalize_gpt_response() on repair failure now replaces with safe team-context fallback and returns immediately — never returns unrepaired 1v1 response to client."
    )

    static let coachTelemetry = FeatureDefinition(
        id: "coach_telemetry",
        name: "AI Coach Telemetry",
        status: .partial,
        layers: FeatureLayerPresence(hasUI: false, hasViewModel: true, hasAPIClient: true, hasBackend: true),
        notes: "Phase 13: External path added. CoachTelemetry.record() now calls fireAndForget() after local write — POST /telemetry/event to backend (5s timeout, errors silently discarded). Backend: backend/routers/telemetry.py stores events as JSONL at uploads/telemetry/events.jsonl. No auth required. 3 new constrained_retry events added. Event types now 20+. Remaining gap: JSONL file is local to the server — dashboarding requires a log-aggregation tool (jq, Grafana, etc.) pointed at the file. No external SaaS analytics SDK."
    )

    static let drillLibraryView = FeatureDefinition(
        id: "drill_library",
        name: "Drill Library",
        status: .partial,
        layers: .allPresent,
        notes: "Phase 13 verification: DrillLibraryView DOES call the backend via getTrainingDrills(sport:) in loadDrillsFromAPI(). Overlay pattern: filteredDrills uses apiDrills when non-empty, falls back to ~2000 lines of hardcoded TrainingDrill definitions when empty or backend unavailable. Filter/search/category logic unchanged. Backend GET /training/drills wired. Remaining: hardcoded drill bank still present as fallback (~2000 lines); full replacement with API-only is a future dedicated refactor."
    )

    static let teamLobbyView = FeatureDefinition(
        id: "team_lobby",
        name: "Team Lobby",
        status: .partial,
        layers: .allPresent,
        notes: "Phase 3: getMyTeams, createTeam, getOpenTeams all wired to real API. Create and browse-open tabs functional. 'Challenge' button shows honest message directing to Play tab (no team-vs-team matchmaking exists). Full team challenge flow is absent."
    )

    // -----------------------------------------------------------------------
    // ABSENT — no meaningful implementation in any layer
    // -----------------------------------------------------------------------

    static let pushNotificationsAPNs = FeatureDefinition(
        id: "push_notifications_apns",
        name: "Push Notifications (APNs)",
        status: .absent,
        layers: .allAbsent,
        notes: "Only local UNUserNotificationCenter notifications exist (fire when app is open). Zero APNs infrastructure: no device token registration, no provider certificate, no server-side push calls, no backend fanout."
    )

    static let conversationDelete = FeatureDefinition(
        id: "conversation_delete",
        name: "Conversation Delete",
        status: .absent,
        layers: FeatureLayerPresence(hasUI: false, hasViewModel: false, hasAPIClient: false, hasBackend: false),
        notes: "Phase 1: dead swipe-to-delete action removed from MessagesListView. No backend DELETE /conversations endpoint exists."
    )

    static let trainingPrograms = FeatureDefinition(
        id: "training_programs",
        name: "Training Programs",
        status: .absent,
        layers: .allAbsent,
        notes: "Phase 1: section gated via CapabilityRegistry (.unavailableHidden) and removed from layout. No programs data model, no backend route, no ViewModel infrastructure."
    )

    // -----------------------------------------------------------------------
    // Master list — iterate for reporting / enforcement
    // -----------------------------------------------------------------------

    static let allFeatures: [FeatureDefinition] = [
        // Complete
        evidenceUpload,
        homeActivityFeed,
        tournamentRegisteredState,
        skillProgressionDisclosure,
        matchResultSubmit,
        directMessaging,
        friendSystem,
        tournaments,
        passwordReset,
        profilePictureUpload,
        aiCoachSafetyModes,
        trainingProfileEditing,
        // Partial
        aiCoachChat,
        googleSignIn,
        generalSearch,
        aiCoachGPTContractValidation,
        coachTelemetry,
        drillLibraryView,
        teamLobbyView,
        // Absent
        pushNotificationsAPNs,
        conversationDelete,
        trainingPrograms,
    ]

    // -----------------------------------------------------------------------
    // DEBUG reporting
    // -----------------------------------------------------------------------

    #if DEBUG
    /// Prints a formatted feature completeness report to the console.
    /// Triggered automatically at app startup in DEBUG builds via SportsHubApp.
    static func printReport() {
        let divider = String(repeating: "─", count: 62)
        let complete = allFeatures.filter { $0.status == .complete }
        let partial  = allFeatures.filter { $0.status == .partial }
        let absent   = allFeatures.filter { $0.status == .absent }

        print("\n\(divider)")
        print("📋  FeatureManifest — Completeness Report")
        print(divider)
        print("  ✅ Complete : \(complete.count)  |  ⚠️  Partial : \(partial.count)  |  ❌ Absent : \(absent.count)  |  Total : \(allFeatures.count)")
        print(divider)

        let groups: [(label: String, icon: String, items: [FeatureDefinition])] = [
            ("COMPLETE",  "✅", complete),
            ("PARTIAL",   "⚠️ ", partial),
            ("ABSENT",    "❌", absent),
        ]

        for group in groups {
            if group.items.isEmpty { continue }
            print("\n  \(group.icon) \(group.label)")
            for f in group.items {
                let ui  = f.layers.hasUI        ? "[UI]" : "[  ]"
                let vm  = f.layers.hasViewModel  ? "[VM]" : "[  ]"
                let api = f.layers.hasAPIClient  ? "[API]" : "[   ]"
                let be  = f.layers.hasBackend    ? "[BE]" : "[  ]"
                print("    \(ui)\(vm)\(api)\(be)  \(f.name)")
                if let notes = f.notes {
                    print("              ↳ \(notes)")
                }
            }
        }

        print("\n\(divider)")
        print("  Layers: [UI]=SwiftUI View  [VM]=ViewModel/Manager  [API]=APIClient  [BE]=Backend Route")
        print("\(divider)\n")
    }
    #endif
}
