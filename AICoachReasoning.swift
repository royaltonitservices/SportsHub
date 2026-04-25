//
//  AICoachReasoning.swift
//  SportsHub
//
//  Core reasoning engine for the AI Coach.
//  Internal access so it is testable via @testable import SportsHub.
//  No SwiftUI/UIKit imports — pure logic only.
//

import Foundation

// MARK: - Weakness Classification

/// Root type of athletic limitation. Each maps to a distinct training methodology.
enum WeaknessType: String {
    case endurance       = "endurance"
    case lateGameFatigue = "late game fatigue"
    case explosiveness   = "explosiveness"
    case speed           = "speed"
    case strength        = "strength"
    case coordination    = "coordination"
    case technique       = "technique"
    case mental          = "mental"
}

// MARK: - Progression Stage

/// Where the athlete is in their development arc for a given focus area.
/// Determines HOW the session is designed, not just what drills are selected.
enum ProgressionStage {
    case foundation   // 1–2 mentions: fix the movement pattern, form before intensity
    case development  // 3–4 mentions: pattern is there — add load, reduce rest, add constraint
    case stressTest   // 5+ mentions: game-like conditions, decision-making under fatigue

    init(mentionCount: Int) {
        switch mentionCount {
        case ..<3:  self = .foundation
        case 3..<5: self = .development
        default:    self = .stressTest
        }
    }

    var stageNumber: Int {
        switch self {
        case .foundation:  return 1
        case .development: return 2
        case .stressTest:  return 3
        }
    }

    var displayName: String {
        switch self {
        case .foundation:  return "Foundation"
        case .development: return "Development"
        case .stressTest:  return "Stress-Test"
        }
    }

    /// Describes how the coach should design the session structure.
    var sessionDesignPrinciple: String {
        switch self {
        case .foundation:
            return "Build the pattern first — form before intensity. Slow, deliberate reps with no competitive pressure yet."
        case .development:
            return "Athlete has the pattern — add load, reduce rest, introduce a constraint (time pressure, defender, smaller target)."
        case .stressTest:
            return "Pattern is proven — test it under fire. Game-like conditions, fatigue-state reps, scored competition format."
        }
    }

    /// Direct instruction to GPT-4 on how to apply this stage.
    var progressionDirective: String {
        switch self {
        case .foundation:
            return "Correct mechanics before adding speed or load. Run each drill at 60–70% pace. Prioritise movement quality over volume."
        case .development:
            return "Athlete is past basics — increase intensity 15–20%, add a constraint (defender, reduced rest, time pressure). Push the last set."
        case .stressTest:
            return "Apply game conditions — random starting positions, fatigue-state execution, scored competition format. No safety net."
        }
    }
}

// MARK: - Analysis Structs

struct WeaknessAnalysis {
    let type: WeaknessType
    let manifestation: String     // When and how the limitation shows up in play
    let sportImpact: String       // Performance cost specific to this sport
    let trainingFocus: String     // What aspect of training addresses this root cause
    let sessionStructure: String  // Concrete time-templated prescription
    let drillCategory: String     // Used in COACHING DIRECTIVE
    let intensityMultiplier: Double
}

struct CoachPrioritization {
    let primaryFocus: String       // The #1 thing to address today
    let primaryReason: String      // Why — scoring rationale for GPT-4 context
    let secondaryFocus: String?    // Lower-priority area; deprioritise today
    let progressionStage: ProgressionStage
    let whyToday: String           // Concise 1-line rationale (shown in UI and brief)
}

/// Compact version surfaced in the UI — kept separate from CoachPrioritization
/// so the view layer never imports heavy types.
struct CoachSessionInsight: Equatable {
    let primaryFocus: String   // e.g. "late game conditioning"
    let stageLabel: String     // e.g. "Stage 2 · Development"
    let whyToday: String       // e.g. "Mentioned 4× + expressed again today"
    let secondaryFocus: String?
}

// MARK: - Reasoning Engine

/// All methods are static and pure (no side effects). Shared between the ViewModel and tests.
enum AICoachReasoning {

    // MARK: - Weakness Analysis

    /// Maps semantic concepts + message text to a structured WeaknessAnalysis.
    ///
    /// Priority order (highest → lowest):
    ///   1. direct_skill  — user named a specific skill, stroke, body part, or move
    ///   2. technique     — general skill/fundamentals signals
    ///   3. late-game fatigue
    ///   4. endurance
    ///   5. explosiveness
    ///   6. speed
    ///   7. strength
    ///   8. coordination
    ///   9. mental
    ///
    /// RULE: Skill and technique signals ALWAYS outrank physical/conditioning categories.
    /// Conditioning history must never hijack explicit skill requests.
    static func analyze(concepts: [String], message: String, intent: String, sport: Sport) -> WeaknessAnalysis? {
        let c = concepts.map { $0.lowercased() }
        let msg = message.lowercased()
        guard !c.isEmpty else { return nil }

        // ── Priority 1: Direct skill signal ──────────────────────────────────────────
        // Injected by semanticMap() when the user names a specific skill, stroke, body
        // part, or move (e.g. "left hand", "shooting", "serve", "first touch").
        // Absolute highest priority — nothing overrides this.
        if c.contains("direct_skill") {
            return directSkillAnalysis(message: message, sport: sport)
        }

        let hasEndurance = c.contains { ["conditioning", "stamina", "endurance", "cardio", "fitness"].contains($0) }
        let hasLateGame  = msg.contains("late") || msg.contains("end of") || msg.contains("second half") ||
                           msg.contains("last quarter") || msg.contains("fourth quarter") || msg.contains("last set")
        let hasExplosive = c.contains { ["explosiveness", "power", "explosive"].contains($0) }
        let hasSpeed     = c.contains { ["speed", "quickness", "acceleration", "agility"].contains($0) }
        let hasStrength  = c.contains { ["strength", "physicality"].contains($0) }
        let hasCoord     = c.contains { ["footwork", "balance", "timing", "coordination", "stability", "core"].contains($0) }
        let hasMental    = c.contains { ["confidence", "mental", "composure", "clutch"].contains($0) }
        // "technique" is injected by semanticMap() for sport-specific skill terms (shooting, serve, etc.)
        let hasTechnique = c.contains { ["consistency", "fundamentals", "technique"].contains($0) }

        // ── Priority 2: Technique / sport-specific skill ──────────────────────────────
        // Outranks all physical/conditioning categories (endurance, speed, strength, etc.).
        if hasTechnique {
            return WeaknessAnalysis(
                type: .technique,
                manifestation: "Technique is inconsistent — execution varies significantly between reps under the same conditions",
                sportImpact: techniqueImpact(sport),
                trainingFocus: "Deliberate practice: slow-to-fast reps with embedded feedback loop",
                sessionStructure: "5min warm-up → Slow-motion: 3×10 reps at 50% (feel the pattern) → Build-up: 3×10 at 75% → Full: 3×10 at 100% with self-assessment → Consistency block: 20 consecutive quality reps",
                drillCategory: "deliberate_technique",
                intensityMultiplier: 0.85)
        }

        // ── Priorities 3–9: Physical / athletic attributes ────────────────────────────
        if hasEndurance && hasLateGame {
            return WeaknessAnalysis(
                type: .lateGameFatigue,
                manifestation: "Performance drops sharply in the final stage — energy reserves are depleted when the outcome is decided",
                sportImpact: lateGameImpact(sport),
                trainingFocus: "Aerobic base expansion + race-pace intervals to extend high-output duration into late-game situations",
                sessionStructure: "5min warm-up → 3×4min sustained intervals at 75–80% max effort (90s recovery each) → 2×90s race-pace burst at 90% → 3min cool-down",
                drillCategory: "aerobic_intervals",
                intensityMultiplier: 1.0)
        }
        if hasEndurance {
            return WeaknessAnalysis(
                type: .endurance,
                manifestation: "Gets winded during extended sequences; cardiovascular ceiling limits sustained performance output",
                sportImpact: enduranceImpact(sport),
                trainingFocus: "Aerobic base building + active recovery efficiency between high-intensity bursts",
                sessionStructure: "5min warm-up → 15–20min steady-state aerobic work at 65–70% max HR → 3×45s sport-specific conditioning bursts (30s rest) → 3min cool-down",
                drillCategory: "aerobic_base",
                intensityMultiplier: 0.85)
        }
        if hasExplosive {
            return WeaknessAnalysis(
                type: .explosiveness,
                manifestation: "Lacks reactive burst — first-step drive and change-of-direction acceleration are both limited",
                sportImpact: explosivenessImpact(sport),
                trainingFocus: "Neuromuscular power training: plyometrics + contrast loading + reactive acceleration",
                sessionStructure: "5min dynamic warm-up → Plyometrics: 4×8 squat jumps, 3×6 depth drops → Contrast: 3×4 broad jumps immediately into 3×20m sprint → 3min full rest between contrast sets",
                drillCategory: "plyometric_power",
                intensityMultiplier: 1.1)
        }
        if hasSpeed {
            return WeaknessAnalysis(
                type: .speed,
                manifestation: "Slower repositioning and change of direction; arrives late to balls and defensive positions",
                sportImpact: speedImpact(sport),
                trainingFocus: "Acceleration mechanics + agility patterns + sport-specific speed sequences",
                sessionStructure: "5min warm-up → Acceleration: 6×20m sprints at 95% (full recovery) → Agility: 4×5-10-5 shuttle + 4×ladder pattern → Sport-pattern speed: 3×game-speed sequence at full intensity",
                drillCategory: "speed_mechanics",
                intensityMultiplier: 1.15)
        }
        if hasStrength {
            return WeaknessAnalysis(
                type: .strength,
                manifestation: "Gets displaced from position during physical contact; struggles to win 50/50 situations",
                sportImpact: strengthImpact(sport),
                trainingFocus: "Functional strength + sport-specific contact conditioning",
                sessionStructure: "5min activation → Lower: 3×12 bodyweight squats progressing to jump squats → Upper: 3×15 push-up variations → Core: 3×30s plank + 3×15 anti-rotation presses → Sport contact: 3×5 reps",
                drillCategory: "functional_strength",
                intensityMultiplier: 1.0)
        }
        if hasCoord {
            return WeaknessAnalysis(
                type: .coordination,
                manifestation: "Movement efficiency and timing are desynchronised — footwork disconnected from skill execution",
                sportImpact: coordinationImpact(sport),
                trainingFocus: "Footwork patterns + timing synchronisation + deliberate technical rep-volume at controlled pace",
                sessionStructure: "5min warm-up → Footwork: 3×2min ladder sequences at build-up pace → Timing: 4×10 rhythm coordination reps → Technical: 3×8 coordinated skill reps at 75% speed (quality over speed)",
                drillCategory: "footwork_coordination",
                intensityMultiplier: 0.9)
        }
        if hasMental {
            return WeaknessAnalysis(
                type: .mental,
                manifestation: "Confidence wavers under pressure; execution quality degrades in high-stakes moments",
                sportImpact: mentalImpact(sport),
                trainingFocus: "Pressure simulation + process-focus routines + pre-performance ritual establishment",
                sessionStructure: "5min warm-up → Pressure sim: skill drills with a consequence (made/missed) → Routine: 5×breathing sequence + skill rep → Competition sim: 3×game-scenario reps at full intensity",
                drillCategory: "mental_performance",
                intensityMultiplier: 0.95)
        }
        return nil
    }

    // MARK: - Direct Skill Analysis

    /// Creates a targeted WeaknessAnalysis when the user names a specific skill,
    /// body part, or technique (e.g. "left hand", "shooting", "serve").
    ///
    /// The message text is embedded in the brief so GPT-4 generates drills that are
    /// specific to the named skill — not a generic "technique" response.
    static func directSkillAnalysis(message: String, sport: Sport) -> WeaknessAnalysis {
        let msg = message.lowercased()

        // Extract the most meaningful skill label from the message text
        let knownSkills: [String] = [
            "left hand", "weak hand", "off hand", "non-dominant", "right hand",
            "shooting", "free throw", "three point", "mid range", "pull up", "step back",
            "layup", "euro step", "floater", "post move", "post up",
            "dribbling", "ball handling", "crossover", "ball control",
            "finishing", "passing", "first touch", "heading", "crossing",
            "serve", "forehand", "backhand", "volley", "topspin", "overhead",
            "route running", "catching", "blocking",
            "footwork", "pivot", "drop shot", "return"
        ]
        let skillLabel = knownSkills.first(where: { msg.contains($0) })
            ?? msg.trimmingCharacters(in: .whitespacesAndNewlines)

        return WeaknessAnalysis(
            type: .technique,
            manifestation: "Athlete has specifically identified \"\(skillLabel)\" — targeted isolated skill reps required",
            sportImpact: "A gap in \(skillLabel) directly limits \(sport.rawValue) execution in game situations where that skill is required",
            trainingFocus: "Deliberate skill isolation: build the correct movement pattern for \(skillLabel) before adding speed or pressure",
            sessionStructure: "5min warm-up → Isolation: 3×12 \(skillLabel) reps at 60% (feel the correct pattern) → Build-up: 3×10 at 80% → Game-speed: 3×8 at full pace, self-assess each rep → Volume block: 20 consecutive quality reps",
            drillCategory: "direct_skill_work",
            intensityMultiplier: 0.85
        )
    }

    // MARK: - Prioritisation

    /// Scores every known concept and picks PRIMARY / SECONDARY focus with a progression stage.
    ///
    /// Score formula:
    ///   mention_count × 2         — conversation-inferred frequency
    ///   + recency bonus (3)        — something the user said right now
    ///   + skill rating bonus       — 1–2/10 → +3, 3/10 → +2, 4–6/10 → +1, 7–10 → 0
    ///   + survey weakness tag (+1) — user self-labelled this as a weakness
    ///
    /// Lower skill ratings receive higher bonuses so the coach automatically
    /// prioritises the athlete's declared weakest areas without them having to re-state it.
    static func prioritize(
        recurringWeaknesses: [String: Int],
        latestConcern: String?,
        surveyWeaknesses: [String],
        surveySkillRatings: [String: Int] = [:],
        analysis: WeaknessAnalysis
    ) -> CoachPrioritization {
        var scores: [String: Int] = [:]

        // Conversation memory
        for (concept, count) in recurringWeaknesses {
            scores[concept, default: 0] += count * 2
        }

        // Latest message is the highest-priority signal
        if let latest = latestConcern?.lowercased(), !latest.isEmpty {
            scores[latest, default: 0] += 3
        }

        // Survey skill ratings: lower rating = higher coaching priority
        for (skill, rating) in surveySkillRatings {
            let key = skill.lowercased()
            switch rating {
            case ...2:  scores[key, default: 0] += 3  // Severe gap — as urgent as latest concern
            case 3:     scores[key, default: 0] += 2  // Significant gap
            case 4...6: scores[key, default: 0] += 1  // Developing — worth addressing
            default:    break                          // 7–10: strong, no bonus
            }
        }

        // Survey weakness tags (separate from skill ratings — user explicitly flagged these)
        for w in surveyWeaknesses {
            scores[w.lowercased(), default: 0] += 1
        }

        // Always include the current analysis type so it appears in ranking
        scores[analysis.type.rawValue, default: 0] += 1

        let ranked = scores.sorted { $0.value > $1.value }
        let primaryKey = ranked.first?.key ?? analysis.type.rawValue
        let secondaryKey = ranked.dropFirst().first.map { $0.key != primaryKey ? $0.key : nil } ?? nil

        // Progression stage: sum all recurring mentions that partially match the primary concept
        var primaryCount = 0
        for (concept, count) in recurringWeaknesses {
            if concept.contains(primaryKey) || primaryKey.contains(concept) {
                primaryCount += count
            }
        }
        primaryCount = max(primaryCount, 1)
        let stage = ProgressionStage(mentionCount: primaryCount)

        // Build WHY TODAY rationale
        var whyParts: [String] = []
        var totalMentions = 0
        for (concept, count) in recurringWeaknesses {
            if concept.contains(primaryKey) || primaryKey.contains(concept) {
                totalMentions += count
            }
        }
        if totalMentions >= 2 { whyParts.append("mentioned \(totalMentions)× in this conversation") }

        let latestLower = latestConcern?.lowercased() ?? ""
        if !latestLower.isEmpty && (latestLower.contains(primaryKey) || primaryKey.contains(latestLower)) {
            whyParts.append("expressed again today")
        }

        // Check if this is a survey critical skill
        if let rating = surveySkillRatings.first(where: { $0.key.lowercased().contains(primaryKey) || primaryKey.contains($0.key.lowercased()) })?.value {
            if rating <= 3 {
                whyParts.append("rated \(rating)/10 in your baseline assessment")
            } else if surveyWeaknesses.map({ $0.lowercased() }).contains(where: { $0.contains(primaryKey) || primaryKey.contains($0) }) {
                whyParts.append("flagged in your goals survey")
            }
        } else if surveyWeaknesses.map({ $0.lowercased() }).contains(where: { $0.contains(primaryKey) || primaryKey.contains($0) }) {
            whyParts.append("flagged in your goals survey")
        }

        let whyToday = whyParts.isEmpty ? "highest-priority signal this session" : whyParts.joined(separator: " + ")

        return CoachPrioritization(
            primaryFocus: primaryKey,
            primaryReason: "Score \(ranked.first?.value ?? 1) — \(whyToday)",
            secondaryFocus: secondaryKey,
            progressionStage: stage,
            whyToday: whyToday
        )
    }

    // MARK: - Constraint Helpers

    static func compressForTime(analysis: WeaknessAnalysis, minutes: Int) -> String {
        switch minutes {
        case ..<15:
            return "1 focused drill only — the single highest-impact exercise. No warm-up/cool-down. Maximum specificity."
        case 15..<25:
            return "2 exercises: 1 warm-up movement (2min) + 1 primary drill (rest of time). Full intensity on the primary."
        case 25..<35:
            return "Short session: warm-up (3min) + 2 primary drills + brief cool-down. Cut 1 set from standard structure."
        case 35..<50:
            return "Full session minus 1 set. Prioritise quality reps over volume."
        default:
            return "Full session as structured. Add an optional 4th set at 40min if athlete is responding well."
        }
    }

    static func readinessNote(_ readiness: String, multiplier: Double) -> String {
        let lower = readiness.lowercased()
        if lower.contains("low") || lower.contains("tired") || lower.contains("sore") || lower.contains("poor") {
            return "Low readiness — reduce intensity 30%, form-focus over conditioning load, stop if discomfort appears"
        }
        if lower.contains("medium") || lower.contains("ok") || lower.contains("moderate") {
            return "Moderate readiness — reduce volume by 1 set, maintain quality focus"
        }
        return "Good readiness — full session as planned, push the final set"
    }

    // MARK: - Sport-Specific Impact Strings

    static func lateGameImpact(_ sport: Sport) -> String {
        switch sport {
        case .basketball: return "4th-quarter decision-making slows, shot mechanics break down under fatigue, defensive rotations collapse in the final minutes"
        case .tennis:     return "3rd-set unforced errors spike, serve speed drops, shortened backswing under fatigue — momentum shifts to the fresher opponent"
        case .soccer:     return "Defensive shape breaks after 70 minutes, pressing intensity drops, recovery runs after overlaps stop happening"
        case .football:   return "Route precision degrades late, blocking leverage is lost in the 4th quarter, concentration catches start being dropped"
        }
    }

    static func enduranceImpact(_ sport: Sport) -> String {
        switch sport {
        case .basketball: return "Offensive transition slows, off-ball movement reduces, defensive closeouts arrive late"
        case .tennis:     return "Between-point recovery is insufficient, footwork efficiency drops mid-set, mental errors increase with fatigue"
        case .soccer:     return "Pressing triggers are missed, off-ball runs shorten, 50/50 challenges are avoided"
        case .football:   return "Route depth is cut short, pursuit angles widen on defence, snap execution slows in hurry-up"
        }
    }

    static func explosivenessImpact(_ sport: Sport) -> String {
        switch sport {
        case .basketball: return "First step to the rim is predictable — defenders stay on their heels knowing there is no burst; separation is impossible"
        case .tennis:     return "First-serve acceleration is limited, volley punch lacks penetration, overhead follow-through is weak"
        case .soccer:     return "Lost in 50/50 races to the ball, aerial duel acceleration is slow, can't beat defenders on the first touch"
        case .football:   return "Slow off the line after the snap, short-area burst routes are ineffective, unable to win jump-ball situations"
        }
    }

    static func speedImpact(_ sport: Sport) -> String {
        switch sport {
        case .basketball: return "Arrive late to defensive spots, trail on fast breaks, recovery after a drive requires stopping instead of continuing"
        case .tennis:     return "Wide balls become winners instead of retrievable; late arrival means a defensive pop-up instead of an offensive drive"
        case .soccer:     return "Beaten on recovery runs when defenders get in behind, slow to close on press triggers"
        case .football:   return "Get-off issues after the snap, slower to separate on deeper routes, can't outrun pursuit angles"
        }
    }

    static func strengthImpact(_ sport: Sport) -> String {
        switch sport {
        case .basketball: return "Get bodied off position on post plays and drives; struggle finishing through contact at the rim"
        case .tennis:     return "Reduced topspin generation, weaker penetrating drives, pushed around by heavy-ball opponents"
        case .soccer:     return "Long ball duels are lost, shielding the ball under pressure fails, physical opponents win contact exchanges"
        case .football:   return "Block is not sustained past initial contact, contested receptions are lost in traffic, coverage shedding is difficult"
        }
    }

    static func coordinationImpact(_ sport: Sport) -> String {
        switch sport {
        case .basketball: return "Ball handling breaks down under defensive pressure, footwork on pull-up jumpers is inconsistent"
        case .tennis:     return "Swing timing desynchronises from footwork, double faults increase, split-step timing is late"
        case .soccer:     return "First touch under pressure is miscontrolled, creating dangerous turnovers in advanced positions"
        case .football:   return "Route breaks are sloppy, footwork on drops is inconsistent, hands and feet don't sync on contested catches"
        }
    }

    static func mentalImpact(_ sport: Sport) -> String {
        switch sport {
        case .basketball: return "Free throw percentage drops in clutch moments, shot hesitation increases with the clock running out"
        case .tennis:     return "Break point conversion drops, double faults cluster on big points, unforced errors spike when serving for the set"
        case .soccer:     return "Simple passes are missed in the penalty area, shooting opportunities are hesitated on, communication breaks down under pressure"
        case .football:   return "Pre-snap reads are rushed, ball security loosens in contact, route timing breaks when the play clock is tight"
        }
    }

    static func techniqueImpact(_ sport: Sport) -> String {
        switch sport {
        case .basketball: return "Shot form varies between open and contested situations; dribbling pattern is readable under defensive pressure"
        case .tennis:     return "Rally consistency is unpredictable — the same shot produces different outcomes across successive reps"
        case .soccer:     return "Pass weight is inconsistent; shooting technique varies significantly between attempts"
        case .football:   return "Route stem and break are inconsistent, making timing routes difficult to execute reliably for the QB"
        }
    }
}
