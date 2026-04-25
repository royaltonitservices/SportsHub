// CoachingPhilosophy.swift
// SportsHub — Phase 11
//
// Single source of truth for coaching identity, sport constraints,
// safety detection, and feedback persistence. Both the iOS local pipeline
// and the backend GPT path must reflect these rules.

import Foundation

// MARK: - Coaching Philosophy

/// Shared coaching identity text injected into the GPT system prompt.
/// The backend reads an equivalent Python constant (COACHING_PHILOSOPHY in ai_orchestrator.py).
/// Both must stay in sync.
enum CoachingPhilosophyConstants {
    static let systemPromptSection = """
    COACHING PHILOSOPHY (NON-NEGOTIABLE — applies to every response):
    1. ATHLETE-FIRST: Long-term development and safety above all short-term performance goals.
    2. SPECIFICITY: Named drills with exact sets, reps, and durations — never generic categories.
    3. PROGRESSIVE OVERLOAD: Every session escalates from the last; reference prior training history.
    4. SPORT-SPECIFIC MASTERY: Every drill and skill reference MUST belong to the active sport. Zero exceptions.
    5. HONESTY-FIRST: Don't pad responses with hollow encouragement. Acknowledge strengths only when the athlete has shared a specific success; otherwise go directly to the plan.
    6. NO DEAD ENDS: Every response closes with a clear next action the athlete can take today.
    7. SAFETY ABOVE ALL: Injury or overtraining signals override ALL other coaching directives immediately.
    """
}

// MARK: - Sport Constraints

/// Per-sport coaching constraints injected into the GPT system prompt and used as
/// guardrail text in the local iOS coaching pipeline.
struct SportConstraint {
    let sport: Sport
    /// Whether solo (individual, non-team-dependent) drills are appropriate for this sport.
    let allowsSoloDrills: Bool
    /// Whether 1-on-1 match-play framing ("you vs one opponent") is valid for this sport.
    let allowsOneOnOneMatchFraming: Bool
    /// Whether every drill must reference a team context element (routes, formations, etc.).
    let teamContextRequired: Bool
    /// Text block appended to the GPT system prompt for this sport.
    let systemPromptEnforcement: String
    /// Text block injected into the local coaching brief as a guardrail.
    let localPipelineGuardrail: String

    static let basketball = SportConstraint(
        sport: .basketball,
        allowsSoloDrills: true,
        allowsOneOnOneMatchFraming: true,
        teamContextRequired: false,
        systemPromptEnforcement: "Basketball: solo skill work and 1v1 drills are fully appropriate. Connect individual skills to team application (pick-and-roll, help defense, spacing) where relevant.",
        localPipelineGuardrail: "Basketball: solo and 1v1 drills are appropriate."
    )

    static let football = SportConstraint(
        sport: .football,
        allowsSoloDrills: false,
        allowsOneOnOneMatchFraming: false,
        teamContextRequired: true,
        systemPromptEnforcement: """
        FOOTBALL CONSTRAINT — CRITICAL ZERO TOLERANCE:
        Football is a TEAM sport. NEVER generate solo 1-on-1 match drills or frame any training as individual competition.
        EVERY drill must include a team context element: route running with QB timing, formation reads, blocking assignments, coverage recognition, or scout team roles.
        FORBIDDEN: "you vs one other player in a match" framing, isolation drills borrowed from individual sports.
        REQUIRED: Name the team role, formation, or scheme for every drill. A "route running" drill must specify the route, the coverage to read, and the team timing context.
        """,
        localPipelineGuardrail: "Football: TEAM CONTEXT REQUIRED. No 1v1 match framing. All drills must reference team elements — routes, formations, blocking schemes, coverage reads, or scout team roles."
    )

    static let soccer = SportConstraint(
        sport: .soccer,
        allowsSoloDrills: true,
        allowsOneOnOneMatchFraming: true,
        teamContextRequired: false,
        systemPromptEnforcement: "Soccer: solo ball work and 1v1 dribbling drills are appropriate. Connect individual skills to team patterns (combinations, pressing shape, transition) where relevant.",
        localPipelineGuardrail: "Soccer: solo and 1v1 drills are appropriate."
    )

    static let tennis = SportConstraint(
        sport: .tennis,
        allowsSoloDrills: true,
        allowsOneOnOneMatchFraming: true,
        teamContextRequired: false,
        systemPromptEnforcement: "Tennis is an individual sport. Both solo drilling (shadow swings, ball machine, feeding drills) and 1v1 match-play scenarios are fully appropriate and expected.",
        localPipelineGuardrail: "Tennis: solo and 1v1 scenarios are appropriate and expected."
    )

    static func constraint(for sport: Sport) -> SportConstraint {
        switch sport {
        case .basketball: return .basketball
        case .football:   return .football
        case .soccer:     return .soccer
        case .tennis:     return .tennis
        }
    }
}

// MARK: - Safety Detector

/// Detects injury and overtraining risk from user messages and local session history.
/// Safety constraint blocks are appended to the coaching brief and injected into
/// both the GPT system prompt path (via coachingBrief in CoachContext) and the local pipeline.
enum SafetyDetector {

    // MARK: Injury Detection

    private static let injuryKeywords: [String] = [
        "hurt", "hurts", "pain", "painful", "sore", "soreness",
        "injury", "injured", "ache", "aching",
        "sprain", "sprained", "strain", "strained", "pulled", "pull",
        "tear", "torn", "swollen", "swelling", "bruised", "bruise",
        "fracture", "fractured", "knee", "ankle", "shoulder", "wrist",
        "elbow", "hip", "lower back", "back pain", "neck pain",
        "hamstring", "quad", "quadricep", "calf", "shin splint",
        "plantar", "tendon", "ligament", "tendinitis",
        "tweak", "tweaked", "popped", "snap", "snapped",
        "can't run", "can't play", "limping"
    ]

    /// Returns true if the message contains injury-related language.
    static func detectsInjury(in message: String) -> Bool {
        let lowered = message.lowercased()
        return injuryKeywords.contains { lowered.contains($0) }
    }

    // MARK: Overtraining Detection

    /// Counts saved training sessions within the last 7 days for a given sport.
    static func weeklySessionCount(for sport: Sport) -> Int {
        let sessionsKey = "recent_sessions_\(sport.rawValue)"
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let sessions = try? JSONDecoder().decode([SavedSessionData].self, from: data) else {
            return 0
        }
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return sessions.filter { $0.date >= sevenDaysAgo }.count
    }

    /// Returns true if 5 or more sessions were logged in the last 7 days (overtraining risk threshold).
    static func detectsOvertraining(sessionCount: Int) -> Bool {
        return sessionCount >= 5
    }

    // MARK: Safety Brief Blocks

    /// Appended to the coaching brief when injury language is detected.
    /// GPT reads this before generating any training prescription.
    static let injuryConstraintBlock: String = """

    ⚠️ SAFETY ALERT — INJURY LANGUAGE DETECTED:
    The athlete mentioned pain, soreness, or an injury. MANDATORY RESPONSE RULES:
    1. Acknowledge the pain with empathy BEFORE any training content.
    2. Do NOT prescribe high-intensity drills involving the affected body part.
    3. Offer a modified low-impact alternative: mobility work, upper/lower body split, or light technical work.
    4. Recommend consulting a sports medicine professional before returning to full training.
    5. If pain sounds acute, recommend stopping training today.
    SAFETY TAKES ABSOLUTE PRIORITY OVER ANY TRAINING GOAL.
    """

    /// Appended to the coaching brief when overtraining is detected.
    static func overtainingConstraintBlock(sessionCount: Int) -> String {
        return """

        ⚠️ OVERTRAINING RISK — HIGH TRAINING LOAD:
        This athlete has logged \(sessionCount) sessions in the last 7 days (threshold: 5).
        MANDATORY RESPONSE RULES:
        1. Acknowledge the high training load before any prescription.
        2. Reduce today's session intensity by at least 40%: cut volume, add rest, lower intensity.
        3. Prioritize recovery: mobility, light technical review, or active rest.
        4. If generating a multi-day schedule, include at least one explicit Recovery Day.
        5. Remind the athlete: adaptation happens during rest — training without recovery is counterproductive.
        """
    }
}

// MARK: - Coach Feedback

/// Records whether an athlete found a coaching response helpful or not.
struct CoachFeedbackEntry: Codable {
    let messageId: String
    let helpful: Bool
    let sport: String
    let focusArea: String?
    let timestamp: Date

    init(messageId: String, helpful: Bool, sport: Sport, focusArea: String? = nil) {
        self.messageId = messageId
        self.helpful   = helpful
        self.sport     = sport.rawValue
        self.focusArea = focusArea
        self.timestamp = Date()
    }
}

/// Persists coach feedback entries in UserDefaults and generates coaching brief injections
/// from negative signals so future sessions can adapt their approach.
enum CoachFeedbackStore {
    private static let storageKey = "coach_feedback_entries_v1"

    /// Records a feedback entry, deduplicating by messageId.
    /// Keeps only the most recent 100 entries to bound storage size.
    static func record(_ entry: CoachFeedbackEntry) {
        var existing = load()
        existing.removeAll { $0.messageId == entry.messageId }
        existing.append(entry)
        if existing.count > 100 {
            existing = Array(existing.suffix(100))
        }
        if let data = try? JSONEncoder().encode(existing) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Loads all stored feedback entries.
    static func load() -> [CoachFeedbackEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([CoachFeedbackEntry].self, from: data) else {
            return []
        }
        return entries
    }

    /// Returns (helpful, notHelpful) counts for the last 30 days for a sport.
    /// Used by `OutcomeAwareProgressionStage` to adjust the coaching stage based on feedback quality.
    static func feedbackCounts(for sport: Sport) -> (helpful: Int, notHelpful: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recent = load().filter { $0.sport == sport.rawValue && $0.timestamp >= cutoff }
        let helpful    = recent.filter { $0.helpful }.count
        let notHelpful = recent.filter { !$0.helpful }.count
        return (helpful, notHelpful)
    }

    /// Returns a brief injection string summarizing recent negative feedback for a sport,
    /// or nil if there is no significant negative signal in the last 14 days.
    /// This text is appended to the coaching brief so GPT adapts its approach.
    static func negativeSignalSummary(for sport: Sport) -> String? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recent = load().filter {
            $0.sport == sport.rawValue && !$0.helpful && $0.timestamp >= cutoff
        }
        guard !recent.isEmpty else { return nil }

        let focusAreas = recent.compactMap(\.focusArea)
        let unique = Array(Set(focusAreas)).prefix(3)

        if unique.isEmpty {
            return "FEEDBACK SIGNAL: Athlete marked \(recent.count) recent response(s) as not helpful. Try a different approach — vary drill types, adjust depth, or simplify language."
        } else {
            return "FEEDBACK SIGNAL: Recent responses on [\(unique.joined(separator: ", "))] were marked not helpful. Adjust approach — try different drill types, clearer cues, or more actionable next steps."
        }
    }
}

// MARK: - Safety Coaching Modes

/// Explicit coaching modes triggered by safety signals. Modes override normal coaching output —
/// they are NOT optional adjustments. Both the local pipeline and GPT path must apply the active mode.
///
/// Hierarchy (highest priority first):
///   stopAndDefer > injuryCaution > recoveryBiased > normal
enum SafetyCoachingMode: Equatable {
    case normal
    case recoveryBiased(sessionCount: Int)
    case injuryCaution(matchedKeyword: String)
    case stopAndDefer(reason: String)

    var modeName: String {
        switch self {
        case .normal:             return "normal"
        case .recoveryBiased:     return "recovery_biased"
        case .injuryCaution:      return "injury_caution"
        case .stopAndDefer:       return "stop_and_defer"
        }
    }

    /// True if any high-intensity prescription (sprints, max-effort, heavy plyometrics) must be removed.
    var forbidsHighIntensity: Bool {
        switch self {
        case .normal:             return false
        case .recoveryBiased:     return true
        case .injuryCaution:      return true
        case .stopAndDefer:       return true
        }
    }

    /// True if ALL training content must be replaced with safety/rest guidance.
    var forbidsAllTraining: Bool {
        if case .stopAndDefer = self { return true }
        return false
    }

    /// Text block prepended to the coaching brief (highest priority — GPT reads it first).
    var localBriefPrefix: String {
        switch self {
        case .normal:
            return ""
        case .recoveryBiased(let count):
            return """
            🔴 COACHING MODE: RECOVERY-BIASED
            Athlete has logged \(count) sessions in the last 7 days — above sustainable threshold.
            RULE: Today's session must be low-intensity recovery work only. No high-effort drills,
            no max-speed work, no plyometrics. Prioritize mobility, active recovery, and light technical review.
            Acknowledge the training load before any prescription.
            """
        case .injuryCaution(let keyword):
            return """
            🔴 COACHING MODE: INJURY-CAUTION
            Athlete mentioned injury-related language: "\(keyword)".
            RULE 1: Acknowledge the discomfort with empathy — this comes before any training content.
            RULE 2: Do NOT prescribe drills that load the affected area.
            RULE 3: Offer a modified session that avoids the injury site entirely.
            RULE 4: Recommend consulting a sports medicine professional before returning to full training.
            """
        case .stopAndDefer(let reason):
            return """
            🛑 COACHING MODE: STOP AND DEFER
            Reason: \(reason)
            RULE: Do NOT generate any training prescription today. The athlete must rest.
            Response MUST: (1) empathize, (2) recommend stopping training today, (3) advise seeing a
            sports medicine professional or doctor, (4) offer a single recovery-only suggestion
            (ice, elevation, rest) if appropriate. No drills. No "light" alternatives. Stop.
            """
        }
    }

    static func == (lhs: SafetyCoachingMode, rhs: SafetyCoachingMode) -> Bool {
        lhs.modeName == rhs.modeName
    }
}

// MARK: - Safety Mode Classifier

/// Classifies the active safety coaching mode from the current message + session history.
/// Classification is deterministic and runs before the coaching brief is built.
enum SafetyModeClassifier {

    /// Phrases that escalate to stopAndDefer (acute injury / severe pain signals).
    private static let acuteInjuryPhrases: [String] = [
        "can't walk", "can't move", "severe pain", "excruciating", "snapped",
        "popped", "heard a pop", "bone", "fracture", "broke", "torn", "tore",
        "emergency", "hospital", "went to the doctor", "seeing a doctor"
    ]

    /// Classify the appropriate coaching mode given a user message, weekly training load,
    /// and optional wearable recovery score (0–100, where <30 = heavily fatigued).
    ///
    /// - Parameters:
    ///   - message: The raw user message text.
    ///   - weeklySessionCount: Sessions in the past 7 days from `SafetyDetector.weeklySessionCount()`.
    ///   - recoveryScore: Optional wearable recovery score (0–100). Nil if no wearable data.
    static func classify(
        message: String,
        weeklySessionCount: Int,
        recoveryScore: Int? = nil
    ) -> SafetyCoachingMode {
        let lower = message.lowercased()

        // Highest priority: acute injury signals → stop all training
        if acuteInjuryPhrases.contains(where: { lower.contains($0) }) {
            return .stopAndDefer(reason: "Acute injury or severe pain language detected")
        }

        // Overtraining threshold: ≥6 sessions/7 days with injury mention → stop and defer
        if weeklySessionCount >= 6 && SafetyDetector.detectsInjury(in: message) {
            return .stopAndDefer(reason: "High training load (\(weeklySessionCount) sessions) combined with injury language")
        }

        // Injury language → injury-caution mode
        if SafetyDetector.detectsInjury(in: message) {
            let matched = SafetyDetector.firstMatchedKeyword(in: message) ?? "pain/injury"
            return .injuryCaution(matchedKeyword: matched)
        }

        // High session count → recovery-biased mode
        if SafetyDetector.detectsOvertraining(sessionCount: weeklySessionCount) {
            return .recoveryBiased(sessionCount: weeklySessionCount)
        }

        // Wearable-driven recovery bias: very low recovery score even without overtraining count
        // (threshold <30 = heavily fatigued per HRV/HR/sleep composite)
        if let score = recoveryScore, score < 30 {
            return .recoveryBiased(sessionCount: weeklySessionCount)
        }

        return .normal
    }
}

// MARK: - SafetyDetector Extension

extension SafetyDetector {
    /// Returns the first matched injury keyword for use in mode descriptions.
    static func firstMatchedKeyword(in message: String) -> String? {
        let lower = message.lowercased()
        // Check the full list from the existing injuryKeywords (private)
        let quickList = [
            "pain", "hurt", "sore", "injury", "injured", "sprain", "strain",
            "knee", "ankle", "shoulder", "back", "hamstring", "tendon"
        ]
        return quickList.first { lower.contains($0) }
    }
}

// MARK: - Football Constraint Validator

/// Hard enforcement for the American football team-context rule.
/// Football coaching must NEVER frame training as solo 1v1 match play.
/// This validator runs as a post-response check and can repair or flag GPT output.
enum FootballConstraintValidator {

    /// Phrases that indicate 1v1 or solo match framing — prohibited in football context.
    private static let oneOnOnePatterns: [String] = [
        "1v1", "1-on-1", "one on one", "one-on-one",
        "vs opponent", "against an opponent", "beat your man",
        "solo match", "1 vs 1", "one versus one"
    ]

    /// Phrases that indicate solo sport framing borrowed from other sports.
    private static let soloMatchPatterns: [String] = [
        "play against one player", "challenge one player",
        "dribble around", "isolate your defender",
        "individual competition", "singular match"
    ]

    /// Returns true if the response contains prohibited 1v1 or solo match framing for football.
    static func detectsViolation(in response: String) -> Bool {
        let lower = response.lowercased()
        return oneOnOnePatterns.contains(where: { lower.contains($0) }) ||
               soloMatchPatterns.contains(where: { lower.contains($0) })
    }

    /// Attempts an inline repair: replaces known violation phrases with team-context equivalents.
    /// Returns the repaired response. If the response can't be reliably repaired, returns nil.
    static func repairResponse(_ response: String) -> String? {
        var repaired = response

        // Replace each 1v1 phrase with a team-context equivalent
        let repairs: [(pattern: String, replacement: String)] = [
            ("1v1 drill", "route-running drill against simulated coverage"),
            ("1-on-1 drill", "positional drill in team context"),
            ("1v1", "positional rep (team context)"),
            ("1-on-1", "positional rep (team context)"),
            ("one on one", "team positional rep"),
            ("one-on-one", "team positional rep"),
            ("beat your man", "beat your assigned coverage"),
            ("vs opponent", "vs the defense alignment"),
            ("against an opponent", "against your coverage assignment"),
        ]

        for (pattern, replacement) in repairs {
            repaired = repaired.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.caseInsensitive]
            )
        }

        // If the repaired response still contains violations, don't use it — fall back
        return detectsViolation(in: repaired) ? nil : repaired
    }
}

// MARK: - Drill Realism Prompt Block

/// Generates a realism guardrail block appended to the coaching brief.
/// Prevents GPT from prescribing drills that require unavailable equipment,
/// unrealistic time allocations, or inappropriate solo setups for a team sport.
struct DrillRealistPromptBlock {

    /// Generates the realism constraint text for injection into the coaching brief.
    static func generate(for sport: Sport, timeMinutes: Int?) -> String {
        let timeConstraint: String
        if let mins = timeMinutes, mins > 0 {
            timeConstraint = "Total session time is \(mins) minutes — drill sets + rest MUST sum to this."
        } else {
            timeConstraint = "Assume a 45-minute solo or small-group session."
        }

        let equipmentNote: String
        switch sport {
        case .basketball:
            equipmentNote = "Assume: basketball, standard court or driveway hoop. No gym machines, weight rooms, or team equipment unless explicitly mentioned."
        case .football:
            equipmentNote = "Assume: cones, agility ladder, a football. Do NOT require a full team or game-speed contact unless specified. All reps must be executable with 1-2 people."
        case .soccer:
            equipmentNote = "Assume: soccer ball, open outdoor space (grass or turf), cones. No specialized rebounder equipment unless specified."
        case .tennis:
            equipmentNote = "Assume: tennis racket, balls, a court (or wall for solo shadow work). Do not require a ball machine unless specified."
        }

        return """
        DRILL REALISM (REQUIRED):
        \(timeConstraint)
        \(equipmentNote)
        Age context: young/developing athlete (13-22). Avoid adult-elite-only recovery tech (cryotherapy, altitude training).
        Solo feasibility: every drill must be executable by the athlete alone OR with one training partner. Label drills requiring a partner.
        """
    }
}

// MARK: - Drill Realism Post-Validator

/// Post-response validator that checks generated coaching content for feasibility issues
/// that a prompt constraint alone cannot reliably prevent.
///
/// Returns an array of `DrillRealismViolation` — all violations are advisory (minor severity).
/// They are logged via telemetry but do not trigger local-path fallback on their own.
enum DrillRealismValidator {

    struct Violation {
        let rule: String
        let description: String
    }

    /// Prohibited equipment terms — adult-elite-only or unavailable to typical young athletes.
    private static let prohibitedEquipment: [String] = [
        "cryotherapy", "ice bath chamber", "altitude training",
        "hypoxic tent", "blood flow restriction bands", "force plate",
        "velocity-based training device", "gps tracker vest"
    ]

    /// Terms that indicate a full team is required (only prohibited for football solo drills).
    private static let fullTeamTerms: [String] = [
        "full team", "11-on-11", "11v11", "full squad",
        "entire offense", "entire defense", "team practice"
    ]

    /// Validates a GPT coaching response for drill realism issues.
    ///
    /// - Parameters:
    ///   - response: The coaching response text.
    ///   - sport: The active sport for context-specific checks.
    ///   - sessionMinutes: Declared session length, or nil if unknown.
    static func validate(response: String, sport: Sport, sessionMinutes: Int?) -> [Violation] {
        var violations: [Violation] = []
        let lower = response.lowercased()

        // ── 1. Prohibited equipment ───────────────────────────────────────────────
        for item in prohibitedEquipment where lower.contains(item) {
            violations.append(Violation(
                rule: "prohibited_equipment",
                description: "Response mentions '\(item)' — not available to typical young athletes"
            ))
        }

        // ── 2. Football: full-team requirement (equipment block says ≤2 people) ──
        if sport == .football {
            for term in fullTeamTerms where lower.contains(term) {
                violations.append(Violation(
                    rule: "team_size_mismatch",
                    description: "Football response requires '\(term)' — solo or pair drills expected per equipment constraint"
                ))
            }
        }

        // ── 3. Time budget mismatch ───────────────────────────────────────────────
        // Parse explicit drill durations and check if total exceeds session budget by >50%.
        if let budget = sessionMinutes {
            let totalDrillMinutes = parseTotalDrillMinutes(from: response)
            if totalDrillMinutes > 0 && totalDrillMinutes > Int(Double(budget) * 1.5) {
                violations.append(Violation(
                    rule: "time_budget_exceeded",
                    description: "Total drill time ~\(totalDrillMinutes) min exceeds \(budget)-min session budget by >50%"
                ))
            }
        }

        return violations
    }

    /// Roughly estimates total drill time by summing explicit minute values in the response text.
    /// Looks for patterns like "10 minutes", "15 min", "×2 sets" × duration.
    private static func parseTotalDrillMinutes(from text: String) -> Int {
        var total = 0
        // Match patterns: "N minutes" / "N min" / "N-minute"
        let pattern = #"(\d+)\s*[-\s]?min(?:utes?)?"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            for match in matches {
                if let r = Range(match.range(at: 1), in: text), let val = Int(text[r]) {
                    // Ignore suspiciously large values (e.g. "60-minute session" header)
                    if val <= 45 { total += val }
                }
            }
        }
        return total
    }
}

// MARK: - Survey Skill Definitions

/// Shared sport skill taxonomy — used by both OnboardingSurveyView and TrainingProfileSettingsView.
/// This is the canonical source; OnboardingSurveyView's private SportSkills struct mirrors these values.
struct SurveySkillDefinitions {
    static let skills: [Sport: [String]] = [
        .basketball: ["Shooting", "Dribbling", "Defense", "Passing", "Athleticism", "IQ/Court Vision"],
        .football:   ["Speed", "Strength", "Route Running", "Catching", "Blocking", "Football IQ"],
        .soccer:     ["Dribbling", "Shooting", "Passing", "Defense", "Athleticism", "Vision"],
        .tennis:     ["Serve", "Forehand", "Backhand", "Volleys", "Footwork", "Mental Toughness"]
    ]

    static let strengths: [Sport: [String]] = [
        .basketball: ["Scoring", "Rebounding", "Defense", "Playmaking", "Athleticism", "Leadership", "Hustle"],
        .football:   ["Speed", "Power", "Route Running", "Ball Skills", "Blocking", "Instincts", "Toughness"],
        .soccer:     ["Pace", "Technique", "Vision", "Work Rate", "Defending", "Set Pieces", "Leadership"],
        .tennis:     ["Powerful Serve", "Baseline Play", "Net Play", "Consistency", "Mental Toughness", "Speed", "Touch"]
    ]

    static let weaknesses: [Sport: [String]] = [
        .basketball: ["Free Throws", "Left Hand", "Defense", "Three-Pointers", "Finishing", "Stamina", "Dribbling"],
        .football:   ["Speed", "Strength", "Hands", "Route Running", "Blocking", "Footwork", "Reading Defense"],
        .soccer:     ["Weak Foot", "Heading", "Defending", "Stamina", "Finishing", "Passing Accuracy", "Set Pieces"],
        .tennis:     ["Second Serve", "Backhand", "Net Play", "Return of Serve", "Consistency", "Footwork", "Mental Game"]
    ]
}
