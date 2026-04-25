// AIEndToEndValidation.swift
// SportsHub — Phase 12
//
// Structured end-to-end validation spec for 8 critical user journeys.
// Each flow defines: setup, steps, success criteria, and failure criteria.
//
// Usage: Read in debugging sessions or before releases.
//        In DEBUG builds, call AIEndToEndValidation.printAll() to log all flows.
//

import Foundation

#if DEBUG

// MARK: - E2E Validation Framework

struct E2EFlow {
    let id: Int
    let name: String
    let setup: [String]
    let steps: [String]
    let passCriteria: [String]
    let failCriteria: [String]
}

enum AIEndToEndValidation {

    static let flows: [E2EFlow] = [

        // ── Flow 1: Onboarding → First AI Session ────────────────────────────────
        E2EFlow(
            id: 1,
            name: "Onboarding → First AI Session",
            setup: [
                "Fresh install or cleared UserDefaults",
                "Backend running at localhost:8000 with valid OpenAI key",
                "New account with no prior survey data"
            ],
            steps: [
                "1. Sign up with a new email",
                "2. Receive and enter 6-digit verification code",
                "3. Complete OnboardingSurveyView — select Basketball, rate Shooting 3/10, Dribbling 5/10",
                "4. Navigate to Train tab → open AI Coach",
                "5. Send: 'Help me improve my game'"
            ],
            passCriteria: [
                "OnboardingSurveyView advances through all 4 steps without crash",
                "POST /onboarding/survey returns 200",
                "AI Coach response mentions 'shooting' as a focus area (survey-seeded weakness)",
                "Response contains at least one named drill with a duration",
                "Session insight banner shows a primary focus and stage label",
                "No 'what do you want to work on?' clarifying question in response"
            ],
            failCriteria: [
                "Survey submission silently fails (no confirmation, no error)",
                "AI Coach response is generic with no reference to rated skills",
                "Response starts with 'Great question!' or similar hollow affirmation",
                "Response is under 100 characters",
                "App crashes during any step"
            ]
        ),

        // ── Flow 2: Survey Update → Coaching Recalibration ───────────────────────
        E2EFlow(
            id: 2,
            name: "Survey Update → Coaching Recalibration",
            setup: [
                "Logged-in account with existing survey (Shooting rated 2/10)",
                "AI Coach has prior conversation history for Basketball",
                "Backend running"
            ],
            steps: [
                "1. Navigate to Profile → Settings → Training Profile",
                "2. Change Shooting rating from 2/10 to 7/10 (material improvement)",
                "3. Tap 'Save Training Profile'",
                "4. Return to AI Coach and start a new conversation",
                "5. Send: 'What should I focus on today?'"
            ],
            passCriteria: [
                "Save shows success confirmation",
                "POST /onboarding/survey returns 200",
                "GET /onboarding/survey called after save to refresh cache",
                "AI Coach no longer flags Shooting as the top critical gap",
                "AI Coach focuses on next-lowest-rated skill or general development",
                "Telemetry records 'survey_updated' with changed_skills=1"
            ],
            failCriteria: [
                "AI Coach still prescribes Shooting as the top focus after the update",
                "Save fails silently with no error message shown",
                "The old stale weakness cache was not cleared (Shooting still in recurringWeaknesses)"
            ]
        ),

        // ── Flow 3: Challenge Lifecycle ───────────────────────────────────────────
        E2EFlow(
            id: 3,
            name: "Challenge Lifecycle",
            setup: [
                "Two accounts: challenger and challenged",
                "Both accounts are friends (required for messaging)",
                "Backend running"
            ],
            steps: [
                "1. As challenger: navigate to Play tab → Find Players → select a player",
                "2. Send a basketball challenge",
                "3. As challenged: open Play tab → see pending challenge notification (or pull to refresh)",
                "4. Accept the challenge",
                "5. As challenger: submit a result (Win)",
                "6. As challenged: confirm or dispute the result"
            ],
            passCriteria: [
                "Challenge appears in challenged user's pending list after acceptance",
                "Result submission returns 200",
                "Both users' records update (gamesPlayed +1, wins +1 for winner)",
                "Elo ratings update for both users after result confirmation",
                "No raw error message shown to either user at any step"
            ],
            failCriteria: [
                "Challenge never appears for challenged user",
                "Result submission fails with a visible error",
                "Stats remain at 0 after confirmed result",
                "App shows a backend error message instead of a user-friendly message"
            ]
        ),

        // ── Flow 4: Clip Upload → Playback ────────────────────────────────────────
        E2EFlow(
            id: 4,
            name: "Clip Upload → Playback",
            setup: [
                "Logged-in premium account (clips upload is open to all users per current setup)",
                "Backend running with /cdn/videos StaticFiles mount active",
                "A short video file (< 50MB) available in Photos"
            ],
            steps: [
                "1. Navigate to Clips tab",
                "2. Tap upload button → select a video from Photos",
                "3. Wait for upload to complete",
                "4. Pull to refresh the clips feed",
                "5. Find the newly uploaded clip and tap to play"
            ],
            passCriteria: [
                "Upload progress indicator shows during upload",
                "POST /clips/upload returns a clip_url",
                "Clip appears in the feed after refresh",
                "AVPlayer renders the video without a gray rectangle",
                "Video plays to completion without error"
            ],
            failCriteria: [
                "Upload silently fails with no error shown",
                "Clip appears but shows a gray rectangle instead of video",
                "AVPlayer shows 'The operation could not be completed' error",
                "Clip URL returns 404 (StaticFiles not mounted)"
            ]
        ),

        // ── Flow 5: Smartwatch Sync → AI Adaptation ───────────────────────────────
        E2EFlow(
            id: 5,
            name: "Smartwatch Sync → AI Coaching Adaptation",
            setup: [
                "Premium account",
                "Apple Watch paired, HealthKit permissions granted",
                "Backend running"
            ],
            steps: [
                "1. Navigate to Train → Smartwatch Sync",
                "2. Tap 'Sync Now'",
                "3. Verify HRV, resting HR, sleep hours appear in the sync view",
                "4. Navigate to AI Coach",
                "5. Send: 'I want to train today'"
            ],
            passCriteria: [
                "HealthKit data displays (HRV, HR, sleep, steps)",
                "Sync records data to UserDefaults keys (smartwatch_hrv, smartwatch_resting_hr, etc.)",
                "AI Coach response mentions recovery status or adjusts intensity based on HRV/HR",
                "If recovery score < 30: SafetyModeClassifier returns recoveryBiased and response is low-intensity",
                "CoachContext.wearableData is non-nil in the coaching brief"
            ],
            failCriteria: [
                "HealthKit returns no data (permissions denied or simulator)",
                "AI Coach response ignores wearable data entirely",
                "Recovery-biased mode not triggered despite very low recovery score"
            ]
        ),

        // ── Flow 6: Degraded Network AI Session ───────────────────────────────────
        E2EFlow(
            id: 6,
            name: "Degraded Network — AI Fallback",
            setup: [
                "Backend NOT running (or network disabled)",
                "App launched and logged in from cached session"
            ],
            steps: [
                "1. Navigate to AI Coach (backend unreachable)",
                "2. Send: 'Build me a 45-minute shooting session'"
            ],
            passCriteria: [
                "App does not crash or hang indefinitely",
                "After network timeout, local coaching engine produces a response",
                "Response contains named basketball drills (not generic advice)",
                "Session insight banner shows a focus area",
                "Telemetry records 'local_fallback' with reason 'network_error' or similar",
                "No raw URLError or server error shown to the user"
            ],
            failCriteria: [
                "App shows a raw error like 'URLSession task failed' or similar",
                "Infinite loading spinner with no fallback",
                "Response from local path is empty or under 100 characters"
            ]
        ),

        // ── Flow 7: Injury Context AI Session ────────────────────────────────────
        E2EFlow(
            id: 7,
            name: "Injury Context — Safety Mode Override",
            setup: [
                "Logged-in account",
                "Backend running or local fallback available"
            ],
            steps: [
                "1. Navigate to AI Coach",
                "2. Send: 'My knee hurts but I want to train basketball today'"
            ],
            passCriteria: [
                "SafetyModeClassifier returns injuryCaution (or stopAndDefer for severe language)",
                "Response begins with empathetic acknowledgment of the pain — no drill prescription first",
                "Response does NOT prescribe high-intensity drills (sprints, jumps, max-effort cuts)",
                "Response recommends consulting a medical professional before returning to full training",
                "Telemetry records 'injury_context' and 'safety_mode' with mode='injury_caution'",
                "GPT validator: no 'safety_override' critical violation in the response",
                "If backend GPT returns high-intensity drills despite injury: fallback to local path"
            ],
            failCriteria: [
                "Response contains 'sprint', 'jump', 'max effort', or similar high-load language",
                "Response ignores the injury mention and prescribes a normal session",
                "Response opens with a drill prescription before acknowledging the pain",
                "Safety mode not activated (telemetry shows 'normal' mode)"
            ]
        ),

        // ── Flow 8: High-Load Recovery Session ────────────────────────────────────
        E2EFlow(
            id: 8,
            name: "High Training Load — Recovery-Biased Mode",
            setup: [
                "Logged-in account",
                "5+ sessions logged in UserDefaults for basketball in the last 7 days",
                "Backend running or local fallback available"
            ],
            steps: [
                "1. Navigate to AI Coach",
                "2. Send: 'What should I do today?'"
            ],
            passCriteria: [
                "SafetyModeClassifier returns recoveryBiased (weeklyCount ≥ 5)",
                "Coaching brief includes the COACHING MODE: RECOVERY-BIASED prefix",
                "Response emphasizes recovery: mobility, light technical review, or rest",
                "Response does NOT prescribe high-intensity sprints, plyometrics, or max-effort sets",
                "Telemetry records 'overtraining' and 'safety_mode' with mode='recovery_biased'",
                "Session insight banner shows 'Recovery' or reduced-intensity recommendation"
            ],
            failCriteria: [
                "Response prescribes a high-intensity normal session despite 5+ sessions",
                "Safety mode not triggered (telemetry shows 'normal' mode)",
                "Response contains 'push through', 'max effort', or similar high-load language"
            ]
        ),
    ]

    // MARK: - Console Output

    /// Prints all 8 flows to the console in structured format.
    /// Call from the debug panel or before releases.
    static func printAll() {
        let divider = String(repeating: "═", count: 60)
        print("\n\(divider)")
        print("🧪  AI End-to-End Validation Spec — \(flows.count) flows")
        print(divider)

        for flow in flows {
            print("\n[\(flow.id)] \(flow.name)")
            print("  Setup:")
            flow.setup.forEach { print("    • \($0)") }
            print("  Steps:")
            flow.steps.forEach { print("    \($0)") }
            print("  ✅ Pass when:")
            flow.passCriteria.forEach { print("    • \($0)") }
            print("  ❌ Fail when:")
            flow.failCriteria.forEach { print("    • \($0)") }
        }

        print("\n\(divider)")
        print("Run these manually before each release. Automate flows 1, 6, 7, 8 first.")
        print("\(divider)\n")
    }
}

#endif
