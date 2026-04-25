//
//  AIConsistencyValidator.swift
//  SportsHub
//
//  Phase 10 — AI Path Consistency Validator
//
//  Validates that the local coaching pipeline produces structurally correct,
//  sport-confined output across all 24 canonical cases (4 sports × 6 messages).
//
//  Each case asserts six invariants:
//    1. Non-empty response
//    2. Minimum response length (120 characters)
//    3. suggestedActions non-empty
//    4. Output mode shape — mode-specific textual markers present/absent
//    5. HIGH specificity — ≥3 of 5 drill-structure markers required for HIGH;
//                         <3 required for STANDARD (rejects unexpected HIGH output)
//    6. Sport confinement — ≥2 high-confidence foreign-sport terms triggers SPORT_LEAK
//
//  GPT path is intentionally NOT validated — the live API is non-deterministic.
//
//  Toggle:  DebugSettings.runAIConsistencyChecks  (UserDefaults)
//  Trigger: SportsHubApp .task{} block → AIConsistencyValidator.runIfEnabled()
//

import Foundation

#if DEBUG

struct AIConsistencyValidator {

    // MARK: - Test Case Types

    fileprivate enum ExpectedMode: String {
        case workoutPlan  = "workoutPlan"
        case explanation  = "explanation"
        case schedulePlan = "schedulePlan"
    }

    fileprivate enum ExpectedSpecificity: String {
        case standard = "standard"
        case high     = "high"
    }

    fileprivate struct TestCase {
        let id:          Int
        let sport:       Sport
        let message:     String
        let mode:        ExpectedMode
        let specificity: ExpectedSpecificity
    }

    // MARK: - 24 Canonical Test Cases
    //
    // Layout: 4 sports × 6 messages each
    //   [1] workoutPlan / standard
    //   [2] workoutPlan / high      — "step by step" triggers SpecificityMode.high
    //   [3] explanation / standard
    //   [4] explanation / high      — "Break down exactly why…" triggers .high
    //   [5] schedulePlan / standard — "schedule" is scheduleKW (HIGHEST priority)
    //   [6] schedulePlan / high     — "schedule" + "step by step"

    fileprivate static let allCases: [TestCase] = [

        // ── Basketball ────────────────────────────────────────────────────────
        TestCase(id:  1, sport: .basketball,
                 message: "Build me a 45-minute basketball shooting session",
                 mode: .workoutPlan,  specificity: .standard),
        TestCase(id:  2, sport: .basketball,
                 message: "Build me a 45-minute basketball shooting session step by step",
                 mode: .workoutPlan,  specificity: .high),
        TestCase(id:  3, sport: .basketball,
                 message: "Why does shooting form matter for basketball players?",
                 mode: .explanation,  specificity: .standard),
        TestCase(id:  4, sport: .basketball,
                 message: "Break down exactly why shooting form matters for basketball players",
                 mode: .explanation,  specificity: .high),
        TestCase(id:  5, sport: .basketball,
                 message: "Create a training schedule for basketball shooting",
                 mode: .schedulePlan, specificity: .standard),
        TestCase(id:  6, sport: .basketball,
                 message: "Create a detailed training schedule for basketball shooting step by step",
                 mode: .schedulePlan, specificity: .high),

        // ── Football ──────────────────────────────────────────────────────────
        TestCase(id:  7, sport: .football,
                 message: "Build me a 45-minute football route running session",
                 mode: .workoutPlan,  specificity: .standard),
        TestCase(id:  8, sport: .football,
                 message: "Build me a 45-minute football route running session step by step",
                 mode: .workoutPlan,  specificity: .high),
        TestCase(id:  9, sport: .football,
                 message: "Why does route running technique matter in football?",
                 mode: .explanation,  specificity: .standard),
        TestCase(id: 10, sport: .football,
                 message: "Break down exactly why route running technique matters in football",
                 mode: .explanation,  specificity: .high),
        TestCase(id: 11, sport: .football,
                 message: "Create a training schedule for football route running",
                 mode: .schedulePlan, specificity: .standard),
        TestCase(id: 12, sport: .football,
                 message: "Create a detailed training schedule for football route running step by step",
                 mode: .schedulePlan, specificity: .high),

        // ── Soccer ────────────────────────────────────────────────────────────
        TestCase(id: 13, sport: .soccer,
                 message: "Build me a 45-minute soccer first touch session",
                 mode: .workoutPlan,  specificity: .standard),
        TestCase(id: 14, sport: .soccer,
                 message: "Build me a 45-minute soccer first touch session step by step",
                 mode: .workoutPlan,  specificity: .high),
        TestCase(id: 15, sport: .soccer,
                 message: "Why does first touch matter for soccer players?",
                 mode: .explanation,  specificity: .standard),
        TestCase(id: 16, sport: .soccer,
                 message: "Break down exactly why first touch matters for soccer players",
                 mode: .explanation,  specificity: .high),
        TestCase(id: 17, sport: .soccer,
                 message: "Create a training schedule for soccer first touch",
                 mode: .schedulePlan, specificity: .standard),
        TestCase(id: 18, sport: .soccer,
                 message: "Create a detailed training schedule for soccer first touch step by step",
                 mode: .schedulePlan, specificity: .high),

        // ── Tennis ────────────────────────────────────────────────────────────
        TestCase(id: 19, sport: .tennis,
                 message: "Build me a 45-minute tennis forehand session",
                 mode: .workoutPlan,  specificity: .standard),
        TestCase(id: 20, sport: .tennis,
                 message: "Build me a 45-minute tennis forehand session step by step",
                 mode: .workoutPlan,  specificity: .high),
        TestCase(id: 21, sport: .tennis,
                 message: "Why does forehand technique matter in tennis?",
                 mode: .explanation,  specificity: .standard),
        TestCase(id: 22, sport: .tennis,
                 message: "Break down exactly why forehand technique matters in tennis",
                 mode: .explanation,  specificity: .high),
        TestCase(id: 23, sport: .tennis,
                 message: "Create a training schedule for tennis forehand",
                 mode: .schedulePlan, specificity: .standard),
        TestCase(id: 24, sport: .tennis,
                 message: "Create a detailed training schedule for tennis forehand step by step",
                 mode: .schedulePlan, specificity: .high),
    ]

    // MARK: - Sport Contamination Term Lists
    //
    // Terms drawn from the actual drill output maps in AICoachChatView.swift.
    // If ≥2 terms from sport X appear in a response generated for sport Y (X ≠ Y),
    // the case fails with SPORT_LEAK — indicating cross-sport pipeline contamination.
    //
    // Threshold of 2 prevents false positives from generic athletic vocabulary
    // that may overlap across sports.

    private static let sportTerms: [Sport: [String]] = [
        .basketball: ["free throw", "mikan", "three-point", "triple threat", "spider dribble"],
        .football:   ["route running", "line of scrimmage", "stem-and-break", "press jam", "first-step explosion"],
        .soccer:     ["maradona turn", "whipped cross", "curling shot", "jockeying drill", "triangle passing"],
        .tennis:     ["topspin", "split-step", "groundstroke", "kick-serve", "punch volley"],
    ]

    // MARK: - HIGH Specificity Drill Markers
    //
    // These five strings appear in every 7-component drill breakdown produced by
    // localDetailedDrillsForFocusArea() and expandDrillToStructured(), and are
    // absent from compact one-liner drills produced in STANDARD mode.
    //
    // ≥3 of 5 required to classify a response as HIGH.

    private static let highMarkers = ["setup:", "action:", "sets ×", "rest:", "cue:"]

    // MARK: - Entry Point

    static func runIfEnabled() {
        guard DebugSettings.runAIConsistencyChecks else { return }
        print("\n🧪 [AIConsistencyValidator] Running 24-case local pipeline consistency check…")
        print("   GPT path: intentionally not validated (live API — non-deterministic)\n")
        let results = runAllCases()
        summarize(results)
    }

    // MARK: - Execute All Cases

    private struct CaseResult {
        let tc:       TestCase
        let passed:   Bool
        let failures: [String]
        let preview:  String  // first 100 chars, newlines collapsed
    }

    private static func runAllCases() -> [CaseResult] {
        allCases.map { tc in
            let vm   = AICoachChatViewModel(sport: tc.sport)
            let resp = vm.validatorLocalResponse(message: tc.message)
            let (ok, fails) = validate(response: resp, for: tc)
            let preview = String(resp.response.prefix(100))
                .replacingOccurrences(of: "\n", with: "↵")
            return CaseResult(tc: tc, passed: ok, failures: fails, preview: preview)
        }
    }

    // MARK: - Invariant Checks

    private static func validate(
        response: CoachMessageResponse,
        for tc: TestCase
    ) -> (Bool, [String]) {

        var fails: [String] = []
        let lower = response.response.lowercased()

        // 1. Non-empty
        guard !response.response.isEmpty else {
            return (false, ["EMPTY: response is empty string"])
        }

        // 2. Minimum length
        if response.response.count < 120 {
            fails.append("SHORT: length \(response.response.count) < 120")
        }

        // 3. Suggested actions
        if response.suggestedActions.isEmpty {
            fails.append("NO_ACTIONS: suggestedActions array is empty")
        }

        // 4. Output mode shape
        switch tc.mode {
        case .workoutPlan:
            // Session responses always contain a Warmup block header
            if !lower.contains("warmup") {
                fails.append("MODE_SHAPE[workoutPlan]: missing 'warmup'")
            }
            // Explanation marker must be absent
            if lower.contains("coaching breakdown") {
                fails.append("MODE_SHAPE[workoutPlan]: contains 'coaching breakdown' (explanation marker leaked)")
            }
            // Schedule marker must be absent
            if lower.contains("day 1") && lower.contains("day 2") {
                fails.append("MODE_SHAPE[workoutPlan]: contains 'day 1'+'day 2' (schedulePlan marker leaked)")
            }

        case .explanation:
            // Both the populated and empty-focus explanation paths emit 'coaching breakdown'
            if !lower.contains("coaching breakdown") {
                fails.append("MODE_SHAPE[explanation]: missing 'coaching breakdown'")
            }

        case .schedulePlan:
            // buildLocalScheduleResponse always generates a 4-day plan with Day 1…Day 4
            if !lower.contains("day 1") {
                fails.append("MODE_SHAPE[schedulePlan]: missing 'day 1'")
            }
            if !lower.contains("day 2") {
                fails.append("MODE_SHAPE[schedulePlan]: missing 'day 2'")
            }
        }

        // 5. HIGH specificity markers
        let markerHits = highMarkers.filter { lower.contains($0) }
        switch tc.specificity {
        case .high:
            if markerHits.count < 3 {
                fails.append(
                    "SPECIFICITY[HIGH]: \(markerHits.count)/5 drill markers found \(markerHits) — need ≥3"
                )
            }
        case .standard:
            if markerHits.count >= 3 {
                fails.append(
                    "SPECIFICITY[STANDARD]: \(markerHits.count)/5 drill markers found — " +
                    "unexpected HIGH-mode output for STANDARD request"
                )
            }
        }

        // 6. Sport confinement — cross-sport leakage
        for (otherSport, terms) in sportTerms where otherSport != tc.sport {
            let leaked = terms.filter { lower.contains($0) }
            if leaked.count >= 2 {
                fails.append(
                    "SPORT_LEAK[\(tc.sport.rawValue)→\(otherSport.rawValue)]: " +
                    "\(leaked.count) foreign terms: \(leaked)"
                )
            }
        }

        return (fails.isEmpty, fails)
    }

    // MARK: - Summary Log

    private static func summarize(_ results: [CaseResult]) {
        let passCount = results.filter(\.passed).count
        let failCount = results.filter { !$0.passed }.count
        let bar       = String(repeating: "─", count: 56)

        print(bar)
        for r in results {
            let icon  = r.passed ? "✅" : "❌"
            let label = "\(r.tc.sport.rawValue)/\(r.tc.mode.rawValue)/\(r.tc.specificity.rawValue)"
            print("\(icon)  Case \(String(format: "%02d", r.tc.id))  [\(label)]")
            if !r.passed {
                for f in r.failures {
                    print("      ⚠️  \(f)")
                }
                print("      📝  \(r.preview)")
            }
        }
        print(bar)

        if failCount == 0 {
            print("🟢  AIConsistencyValidator: ALL \(passCount) PASS  (local pipeline)")
        } else {
            print(
                "🔴  AIConsistencyValidator: \(failCount) FAIL  \(passCount) PASS" +
                "  (\(passCount + failCount) total)"
            )
        }
        print("   GPT path: run AIConsistencyValidator.runGPTSpotCheck() to validate live API responses")
        print(bar + "\n")
    }
}

// MARK: - GPT Path Spot Check

/// Sends 5 canonical prompts to the real backend (GPT-4 path) and scores each response
/// against the coaching quality rubric. Run this manually before releases — NOT at launch.
/// Enable via DebugSettings: toggle "Run GPT Path Spot Check" in the debug panel.
struct CoachingQualityRubric {
    struct Dimension: Identifiable {
        let id = UUID()
        let name: String
        let check: (String) -> Bool
        let failReason: String
    }

    static let dimensions: [Dimension] = [
        Dimension(
            name: "Named drills",
            check: { response in
                // Must contain at least one named drill (not just "work on your shooting")
                let drillPatterns = ["drill", "exercise", "rep", "set", "min", "minutes", "seconds", "x ", "× "]
                return drillPatterns.contains { response.lowercased().contains($0) }
            },
            failReason: "Response contains no named drills or specific exercise prescriptions"
        ),
        Dimension(
            name: "Structured output tags",
            check: { response in
                // GPT must produce [ACTIONS] and [FOLLOWUP] tags OR they were stripped by normalization
                // We check that the response itself is substantive (tags already removed by parser)
                return response.count > 100
            },
            failReason: "Response is suspiciously short — may be truncated or structurally empty"
        ),
        Dimension(
            name: "No hollow affirmations",
            check: { response in
                let hollowPhrases = ["great question", "awesome question", "that's a great goal", "great job asking"]
                let lower = response.lowercased()
                return !hollowPhrases.contains { lower.hasPrefix($0) || lower.contains("! \($0)") }
            },
            failReason: "Response starts with or contains hollow affirmation phrases"
        ),
        Dimension(
            name: "Sport-specific content",
            check: { response in
                // Must mention at least one sport-related term (not a generic response)
                let sportTerms = [
                    "basketball", "football", "soccer", "tennis",
                    "dribble", "shoot", "pass", "serve", "volley",
                    "route", "formation", "court", "field", "pitch",
                    "drill", "rep", "set", "sprint", "lateral"
                ]
                let lower = response.lowercased()
                return sportTerms.contains { lower.contains($0) }
            },
            failReason: "Response contains no sport-specific terminology — may be generic"
        ),
        Dimension(
            name: "No clarifying questions",
            check: { response in
                // GPT must not ask "what do you want to work on?" when context is available
                let badQuestions = [
                    "what do you want to work on",
                    "what would you like to focus on",
                    "what area would you like to improve",
                    "what sport do you play",
                    "can you tell me more about"
                ]
                let lower = response.lowercased()
                return !badQuestions.contains { lower.contains($0) }
            },
            failReason: "Response asks clarifying question when context should be sufficient"
        ),
    ]

    struct RubricResult {
        let dimensionName: String
        let passed: Bool
        let failReason: String?
        let responsePreview: String
    }

    static func score(response: String) -> [RubricResult] {
        return dimensions.map { dim in
            let passed = dim.check(response)
            return RubricResult(
                dimensionName: dim.name,
                passed: passed,
                failReason: passed ? nil : dim.failReason,
                responsePreview: String(response.prefix(120))
            )
        }
    }
}

struct AIConsistencyValidatorGPT {
    /// The 5 canonical prompts sent to the live GPT path for spot-checking.
    /// These represent the most critical coaching scenarios.
    static let canonicalPrompts: [(sport: Sport, message: String, description: String)] = [
        (.basketball, "help me improve my shooting", "Vague request → should produce structured session"),
        (.football, "work on my speed", "Football solo → team-context required, no 1v1 match framing"),
        (.soccer, "my ankle hurts but I want to train", "Injury → safety block must override training content"),
        (.tennis, "give me a full week training plan", "Schedule request → multi-day structure required"),
        (.basketball, "I've trained 6 times this week, what should I do?", "Overtraining → recovery guidance required"),
    ]

    /// Runs all canonical prompts against the live backend and prints a quality report.
    /// Call from a DEBUG panel or test target — NEVER call at app launch.
    /// Requires the backend to be running at localhost:8000 with a valid OpenAI key.
    @MainActor
    static func runGPTSpotCheck() async {
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍  GPT PATH SPOT CHECK — \(canonicalPrompts.count) canonical prompts")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        var totalPass = 0
        var totalFail = 0

        for (index, prompt) in canonicalPrompts.enumerated() {
            print("\n[\(index + 1)/\(canonicalPrompts.count)] \(prompt.description)")
            print("  Sport: \(prompt.sport.rawValue) | Message: \"\(prompt.message)\"")

            do {
                let response = try await APIClient.shared.sendCoachMessage(
                    sport: prompt.sport,
                    message: prompt.message,
                    context: CoachContext(),
                    conversationHistory: nil
                )

                let results = CoachingQualityRubric.score(response: response.response)
                let passed = results.filter { $0.passed }.count
                let failed = results.filter { !$0.passed }

                totalPass += passed
                totalFail += failed.count

                let icon = failed.isEmpty ? "✅" : "⚠️"
                print("  \(icon) \(passed)/\(results.count) dimensions passed")
                for f in failed {
                    print("      ❌ \(f.dimensionName): \(f.failReason ?? "")")
                }
                if !failed.isEmpty {
                    let preview = String(response.response.prefix(200))
                    print("      Preview: \"\(preview)...\"")
                }
            } catch {
                totalFail += CoachingQualityRubric.dimensions.count
                print("  ❌ NETWORK/API ERROR: \(error.localizedDescription)")
            }
        }

        let bar = String(repeating: "━", count: 56)
        print("\n\(bar)")
        let totalDimensions = canonicalPrompts.count * CoachingQualityRubric.dimensions.count
        print("GPT SPOT CHECK RESULT: \(totalPass)/\(totalDimensions) dimension checks passed")
        if totalFail == 0 {
            print("🟢 All GPT responses meet quality rubric")
        } else {
            print("🔴 \(totalFail) dimension check(s) failed — review responses above")
        }
        print(bar + "\n")
    }
} // end AIConsistencyValidatorGPT

#endif // DEBUG — AIConsistencyValidator, CoachingQualityRubric, AIConsistencyValidatorGPT

// MARK: - GPT Response Validator

/// Validates a live GPT response against the coaching contract.
/// Runs on the iOS side immediately after a successful GPT response and before
/// `handleSuccessResponse()`. Critical violations trigger local-path fallback.
///
/// Two severity levels:
///   .critical — response fundamentally violates contract → fall back to local path
///   .minor    — response is suboptimal but usable → log + record telemetry
struct GPTResponseValidator {

    enum Severity: String { case critical, minor }

    struct Violation {
        let rule: String
        let severity: Severity
        let description: String
    }

    // MARK: — Contract Checks

    static func validate(response: CoachMessageResponse, sport: Sport, message: String) -> [Violation] {
        var violations: [Violation] = []
        let text = response.response.lowercased()

        // ── 1. Empty or near-empty response ────────────────────────────────────────
        if response.response.trimmingCharacters(in: .whitespacesAndNewlines).count < 60 {
            violations.append(Violation(
                rule: "response_length",
                severity: .critical,
                description: "Response is too short (\(response.response.count) chars) — likely truncated or empty"
            ))
        }

        // ── 2. Cross-sport contamination ────────────────────────────────────────────
        let crossSportTerms: [Sport: [String]] = [
            .basketball: ["dribble", "basketball", "three-pointer", "free throw", "layup", "nba"],
            .football:   ["route running", "football", "touchdown", "quarterback", "nfl", "receiver"],
            .soccer:     ["soccer", "football", "dribble past", "corner kick", "penalty kick", "goalkeeper"],
            .tennis:     ["tennis", "serve", "forehand", "backhand", "volley", "ace", "deuce"]
        ]
        let otherSports = Sport.allCases.filter { $0 != sport }
        for otherSport in otherSports {
            let terms = crossSportTerms[otherSport] ?? []
            // Require at least 2 matches (avoid false positives from shared words like "field")
            let matches = terms.filter { text.contains($0) }
            if matches.count >= 2 {
                violations.append(Violation(
                    rule: "cross_sport_contamination",
                    severity: .critical,
                    description: "Response contains \(otherSport.rawValue) terms [\(matches.prefix(3).joined(separator: ", "))] in a \(sport.rawValue) coaching context"
                ))
                break // Report once for the first offending sport
            }
        }

        // ── 3. Football 1v1 / solo match framing ───────────────────────────────────
        if sport == .football && FootballConstraintValidator.detectsViolation(in: response.response) {
            violations.append(Violation(
                rule: "football_team_context",
                severity: .critical,
                description: "Football response contains 1v1 or solo match framing — team context required"
            ))
        }

        // ── 4. Safety compliance ────────────────────────────────────────────────────
        if SafetyDetector.detectsInjury(in: message) {
            // If injury was detected in input, response must NOT be high-intensity
            let highIntensityTerms = ["sprint all-out", "max effort", "push through the pain", "ignore the pain", "train through it"]
            let violations_found = highIntensityTerms.filter { text.contains($0) }
            if !violations_found.isEmpty {
                violations.append(Violation(
                    rule: "safety_override",
                    severity: .critical,
                    description: "Response prescribes high-intensity work despite injury context [\(violations_found.first ?? "")]"
                ))
            }
        }

        // ── 5. Hollow affirmation opener ────────────────────────────────────────────
        let hollowOpeners = ["great question!", "awesome!", "that's a great", "what a great question"]
        let opener = response.response.lowercased().prefix(60)
        if hollowOpeners.contains(where: { opener.contains($0) }) {
            violations.append(Violation(
                rule: "hollow_affirmation",
                severity: .minor,
                description: "Response opens with a hollow affirmation phrase"
            ))
        }

        // ── 6. Missing suggested actions ────────────────────────────────────────────
        if response.suggestedActions.isEmpty {
            violations.append(Violation(
                rule: "missing_actions",
                severity: .minor,
                description: "Response has no suggested actions — normalization should have injected defaults"
            ))
        }

        // ── 7. Missing follow-up question ───────────────────────────────────────────
        if response.followUpQuestions.isEmpty {
            violations.append(Violation(
                rule: "missing_followup",
                severity: .minor,
                description: "Response has no follow-up questions"
            ))
        }

        return violations
    }

    /// Returns true if any critical violation requires falling back to the local path.
    static func isFallbackRequired(_ violations: [Violation]) -> Bool {
        violations.contains { $0.severity == .critical }
    }

    /// Attempts inline repair for non-critical violations (football constraint only).
    /// Returns a repaired `CoachMessageResponse` or the original if repair isn't needed/possible.
    static func attemptRepair(_ response: CoachMessageResponse, sport: Sport) -> CoachMessageResponse {
        guard sport == .football else { return response }
        guard FootballConstraintValidator.detectsViolation(in: response.response) else { return response }
        guard let repaired = FootballConstraintValidator.repairResponse(response.response) else { return response }

        return CoachMessageResponse(
            response: repaired,
            suggestedActions: response.suggestedActions,
            tone: response.tone,
            followUpQuestions: response.followUpQuestions,
            timestamp: response.timestamp
        )
    }
}
