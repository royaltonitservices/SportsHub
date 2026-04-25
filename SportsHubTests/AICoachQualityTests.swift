//
//  AICoachQualityTests.swift
//  SportsHubTests
//
//  Regression test harness for the AI Coach reasoning layer.
//
//  Structure:
//  - Section A: WeaknessAnalysis classification tests (pure logic, no GPT-4 call)
//  - Section B: Prioritization and progression stage tests
//  - Section C: Constraint + recovery helper tests
//  - Section D: Quality rubric (documents expected vs bad GPT-4 behaviour per scenario)
//    — these are not executable assertions, but they define what "good" means so
//      regressions can be caught during manual review or future eval automation.
//

import Testing
@testable import SportsHub

// MARK: - A: Weakness Classification

struct WeaknessClassificationTests {

    @Test("Conditioning concepts → endurance")
    func testEnduranceClassification() {
        let result = AICoachReasoning.analyze(
            concepts: ["conditioning", "stamina"],
            message: "I run out of energy during practice",
            intent: "athletic_development",
            sport: .basketball
        )
        #expect(result?.type == .endurance)
        #expect(result?.drillCategory == "aerobic_base")
        #expect(result?.intensityMultiplier ?? 1.0 < 1.0)  // endurance = lower multiplier
    }

    @Test("Conditioning + late-game phrasing → lateGameFatigue (higher priority)")
    func testLateGameFatigueWinsOverEndurance() {
        let result = AICoachReasoning.analyze(
            concepts: ["conditioning", "endurance"],
            message: "I always die in the last quarter",
            intent: "athletic_development",
            sport: .basketball
        )
        #expect(result?.type == .lateGameFatigue)
        #expect(result?.drillCategory == "aerobic_intervals")
    }

    @Test("Speed concepts → speed classification")
    func testSpeedClassification() {
        let result = AICoachReasoning.analyze(
            concepts: ["speed", "agility"],
            message: "I feel slow on defence",
            intent: "weakness_help",
            sport: .soccer
        )
        #expect(result?.type == .speed)
        #expect(result?.intensityMultiplier ?? 0 > 1.0)  // speed = higher multiplier
    }

    @Test("Explosiveness concepts → explosiveness")
    func testExplosivenessClassification() {
        let result = AICoachReasoning.analyze(
            concepts: ["explosiveness", "power"],
            message: "I'm not explosive enough off the line",
            intent: "athletic_development",
            sport: .football
        )
        #expect(result?.type == .explosiveness)
        #expect(result?.drillCategory == "plyometric_power")
    }

    @Test("Footwork/balance concepts → coordination")
    func testCoordinationClassification() {
        let result = AICoachReasoning.analyze(
            concepts: ["footwork", "balance"],
            message: "My footwork is off",
            intent: "weakness_help",
            sport: .tennis
        )
        #expect(result?.type == .coordination)
    }

    @Test("Confidence/mental concepts → mental")
    func testMentalClassification() {
        let result = AICoachReasoning.analyze(
            concepts: ["confidence", "composure"],
            message: "I choke under pressure in big matches",
            intent: "weakness_help",
            sport: .tennis
        )
        #expect(result?.type == .mental)
    }

    @Test("Strength/physicality concepts → strength")
    func testStrengthClassification() {
        let result = AICoachReasoning.analyze(
            concepts: ["strength", "physicality"],
            message: "I get pushed around in the post",
            intent: "weakness_help",
            sport: .basketball
        )
        #expect(result?.type == .strength)
    }

    @Test("Explosiveness beats speed in priority order")
    func testExplosivenessBeatsSingleSpeed() {
        let result = AICoachReasoning.analyze(
            concepts: ["explosiveness", "speed"],
            message: "I need more power and burst",
            intent: "athletic_development",
            sport: .basketball
        )
        #expect(result?.type == .explosiveness)
    }

    @Test("Empty concepts returns nil")
    func testEmptyConceptsReturnsNil() {
        let result = AICoachReasoning.analyze(
            concepts: [],
            message: "what should I do",
            intent: "general",
            sport: .basketball
        )
        #expect(result == nil)
    }

    @Test("Sport impact strings are sport-specific")
    func testSportImpactsAreDifferent() {
        let basketball = AICoachReasoning.lateGameImpact(.basketball)
        let tennis     = AICoachReasoning.lateGameImpact(.tennis)
        let soccer     = AICoachReasoning.lateGameImpact(.soccer)
        let football   = AICoachReasoning.lateGameImpact(.football)
        // All four should be different strings
        let unique = Set([basketball, tennis, soccer, football])
        #expect(unique.count == 4)
    }
}

// MARK: - B: Prioritization and Progression Stage

struct PrioritizationTests {

    @Test("Progression stage: 1 mention → foundation")
    func testFoundationStage() {
        let stage = ProgressionStage(mentionCount: 1)
        #expect(stage == .foundation)
        #expect(stage.stageNumber == 1)
    }

    @Test("Progression stage: 2 mentions → foundation")
    func testFoundationStage2() {
        #expect(ProgressionStage(mentionCount: 2) == .foundation)
    }

    @Test("Progression stage: 3 mentions → development")
    func testDevelopmentStage() {
        let stage = ProgressionStage(mentionCount: 3)
        #expect(stage == .development)
        #expect(stage.stageNumber == 2)
    }

    @Test("Progression stage: 4 mentions → development")
    func testDevelopmentStage4() {
        #expect(ProgressionStage(mentionCount: 4) == .development)
    }

    @Test("Progression stage: 5 mentions → stress-test")
    func testStressTestStage() {
        let stage = ProgressionStage(mentionCount: 5)
        #expect(stage == .stressTest)
        #expect(stage.stageNumber == 3)
    }

    @Test("Progression stage: 10 mentions → stress-test")
    func testStressTestStageHighCount() {
        #expect(ProgressionStage(mentionCount: 10) == .stressTest)
    }

    @Test("Prioritize: highest-frequency concept becomes primary")
    func testHighFrequencyConceptIsPrimary() throws {
        let analysis = try #require(AICoachReasoning.analyze(
            concepts: ["conditioning"],
            message: "I gas out",
            intent: "athletic_development",
            sport: .basketball
        ))
        let result = AICoachReasoning.prioritize(
            recurringWeaknesses: ["conditioning": 5, "footwork": 1],
            latestConcern: nil,
            surveyWeaknesses: [],
            analysis: analysis
        )
        #expect(result.primaryFocus == "conditioning")
        #expect(result.secondaryFocus == "footwork")
    }

    @Test("Prioritize: recency bonus elevates lesser-mentioned concept")
    func testRecencyBonusElevatesConcept() throws {
        let analysis = try #require(AICoachReasoning.analyze(
            concepts: ["speed"],
            message: "I feel slow today",
            intent: "weakness_help",
            sport: .basketball
        ))
        let result = AICoachReasoning.prioritize(
            recurringWeaknesses: ["conditioning": 2, "speed": 1],
            latestConcern: "speed",  // recency bonus = +3
            surveyWeaknesses: [],
            analysis: analysis
        )
        // conditioning score = 2×2=4, speed score = 1×2=2 + 3=5 → speed wins
        #expect(result.primaryFocus == "speed")
    }

    @Test("Prioritize: survey weakness adds score bonus")
    func testSurveyWeaknessAddsBonus() throws {
        let analysis = try #require(AICoachReasoning.analyze(
            concepts: ["conditioning"],
            message: "I need better conditioning",
            intent: "athletic_development",
            sport: .soccer
        ))
        let result = AICoachReasoning.prioritize(
            recurringWeaknesses: ["conditioning": 1],
            latestConcern: nil,
            surveyWeaknesses: ["conditioning"],  // +1 bonus
            analysis: analysis
        )
        #expect(result.primaryFocus == "conditioning")
        #expect(result.whyToday.contains("flagged in your goals survey"))
    }

    @Test("Prioritize: whyToday includes mention count when >= 2")
    func testWhyTodayIncludesMentionCount() throws {
        let analysis = try #require(AICoachReasoning.analyze(
            concepts: ["conditioning"],
            message: "I gas out",
            intent: "athletic_development",
            sport: .basketball
        ))
        let result = AICoachReasoning.prioritize(
            recurringWeaknesses: ["conditioning": 3],
            latestConcern: nil,
            surveyWeaknesses: [],
            analysis: analysis
        )
        #expect(result.whyToday.contains("3×"))
    }

    @Test("Prioritize: progression stage reflects recurring mention count")
    func testProgressionStageFromRecurringCount() throws {
        let analysis = try #require(AICoachReasoning.analyze(
            concepts: ["conditioning"],
            message: "conditioning again",
            intent: "athletic_development",
            sport: .basketball
        ))
        let result = AICoachReasoning.prioritize(
            recurringWeaknesses: ["conditioning": 4],
            latestConcern: "conditioning",
            surveyWeaknesses: [],
            analysis: analysis
        )
        #expect(result.progressionStage == .development)
    }
}

// MARK: - C: Constraint and Recovery Helpers

struct ConstraintHelperTests {

    @Test("Time < 15 min → single drill instruction")
    func testUnder15Min() {
        let analysis = AICoachReasoning.analyze(concepts: ["conditioning"], message: "", intent: "", sport: .basketball)!
        let result = AICoachReasoning.compressForTime(analysis: analysis, minutes: 10)
        #expect(result.contains("1 focused drill"))
    }

    @Test("Time 15–25 min → 2 exercise structure")
    func test15To25Min() {
        let analysis = AICoachReasoning.analyze(concepts: ["conditioning"], message: "", intent: "", sport: .basketball)!
        let result = AICoachReasoning.compressForTime(analysis: analysis, minutes: 20)
        #expect(result.contains("2 exercises"))
    }

    @Test("Time 25–35 min → short structured session")
    func test25To35Min() {
        let analysis = AICoachReasoning.analyze(concepts: ["conditioning"], message: "", intent: "", sport: .basketball)!
        let result = AICoachReasoning.compressForTime(analysis: analysis, minutes: 30)
        #expect(result.contains("Short session"))
    }

    @Test("Time 50+ min → full session with optional extra set")
    func testFullSession() {
        let analysis = AICoachReasoning.analyze(concepts: ["conditioning"], message: "", intent: "", sport: .basketball)!
        let result = AICoachReasoning.compressForTime(analysis: analysis, minutes: 60)
        #expect(result.contains("Full session as structured"))
    }

    @Test("Low readiness → reduce intensity 30%")
    func testLowReadinessNote() {
        let result = AICoachReasoning.readinessNote("low", multiplier: 1.0)
        #expect(result.contains("30%"))
    }

    @Test("Moderate readiness → reduce volume 1 set")
    func testModerateReadinessNote() {
        let result = AICoachReasoning.readinessNote("medium", multiplier: 1.0)
        #expect(result.contains("1 set"))
    }

    @Test("Good readiness → full session")
    func testGoodReadinessNote() {
        let result = AICoachReasoning.readinessNote("great", multiplier: 1.0)
        #expect(result.contains("full session"))
    }
}

// MARK: - D: Quality Rubric (Manual Evaluation Reference)
//
// These are NOT executable assertions. They define what GOOD and BAD look like
// for each scenario so that human reviewers can spot regressions when testing
// the AI Coach against the live GPT-4 backend.
//
// Format per case:
//   User says   → what they typed
//   Expected    → what a good response does
//   Bad signs   → red flags that indicate regression
//
// ─────────────────────────────────────────────────────────────────────────────
//
// SCENARIO 1 — Vague athletic problem, basketball
//   User says:   "I feel slow"
//   Expected:    Coach identifies speed/agility as focus. Prescribes acceleration
//                mechanics + agility work with exact drills (5-10-5 shuttle,
//                ladder patterns, 20m sprints). Explains how slowness hurts
//                basketball performance specifically. Does NOT ask "what sport?"
//   Bad signs:   Generic motivational text. Lists drill categories without
//                specifics. Ignores basketball context. Asks clarifying questions
//                instead of acting on what is already known.
//
// SCENARIO 2 — Time-constrained basketball
//   User says:   "I only have 20 minutes, help me with my conditioning"
//   Expected:    Exactly 2 exercises prescribed (per compression rule). Named
//                drills, exact durations, full intensity note. Does not provide
//                a 40-minute session or ignore the constraint.
//   Bad signs:   Gives 5-drill session ignoring time limit. Says "try to fit in
//                as much as you can." No concrete drill names.
//
// SCENARIO 3 — Recovery-aware tennis
//   User says:   "I'm pretty tired today, what should I do for footwork"
//   Expected:    Identifies coordination as focus. Applies low-readiness modifier
//                (−30% intensity, form focus). Tennis-specific footwork drills
//                (split-step timing, recovery step sequences). Volume reduced.
//   Bad signs:   Gives full-intensity session. Ignores tiredness. Generic footwork
//                advice not specific to tennis.
//
// SCENARIO 4 — Recurring weakness, soccer (progression check)
//   Context:     User has mentioned conditioning 4× (Development stage)
//   User says:   "let's work on conditioning again"
//   Expected:    Coach acknowledges the pattern ("I see conditioning keeps coming
//                up"). Applies Development stage design — adds constraint or
//                reduced rest vs prior sessions. Increases complexity.
//   Bad signs:   Gives Foundation-level session (same as first session, 60–70%
//                intensity, form focus). Does not acknowledge recurring pattern.
//
// SCENARIO 5 — Match prep, football
//   User says:   "I have a game tomorrow, what should I do"
//   Expected:    Recognises match_prep intent. Light activation session only —
//                no heavy conditioning or strength work. Mental readiness focus.
//                Sport-specific cues for game-day execution.
//   Bad signs:   Heavy conditioning or strength work the day before a game.
//                Generic motivational message. Ignores match_prep context.
//
// SCENARIO 6 — Late-game fatigue, basketball, 25-minute session
//   Context:     User has mentioned conditioning 3× (Development stage)
//   User says:   "I always gas out in the 4th quarter and I only have 25 minutes"
//   Expected:    lateGameFatigue identified. 25-minute compression (3-section).
//                aerobic_intervals with race-pace work. Development stage
//                applied — reduced rest, push the last set. COACHING DIRECTIVE
//                followed. No generic suggestions.
//   Bad signs:   Gives general aerobic advice. Ignores 25-minute constraint.
//                Gives Foundation session despite 3× repetition. Lists categories
//                instead of exact drills.
//
// SCENARIO 7 — Elaboration follow-up
//   User says:   "can you make that shorter" (after receiving a full plan)
//   Expected:    Immediately compresses the prior response. No re-introduction,
//                no restating the problem. Just the tighter version.
//   Bad signs:   Restates context. Re-explains the weakness. Gives a new plan
//                instead of compressing the existing one.
//
// SCENARIO 8 — Mental game, tennis, Stress-Test stage
//   Context:     User has mentioned confidence/mental game 5× (Stress-Test stage)
//   User says:   "I need help with my mental game before big points"
//   Expected:    Competition simulation format (scored drills, consequence-based
//                reps, game-like pressure). Acknowledges depth of pattern.
//                No Foundation-level routine advice.
//   Bad signs:   Gives basic breathing exercises only. Ignores 5× recurrence.
//                Does not apply any competitive pressure format.
//
// SCENARIO 9 — Strength, soccer, wearable data present (high HR, low sleep)
//   Context:     Resting HR 75bpm, sleep 5.5h
//   User says:   "I keep getting pushed off the ball"
//   Expected:    Strength identified. Biometric flags applied (−20% intensity,
//                form over load). Soccer-specific strength drills adapted.
//                Recovery caveat explicitly included.
//   Bad signs:   Full-intensity strength session ignoring HR/sleep data. No
//                mention of recovery state. Generic push drills without soccer
//                context.
//
// ─────────────────────────────────────────────────────────────────────────────
// END QUALITY RUBRIC
