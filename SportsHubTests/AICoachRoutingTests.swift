//
//  AICoachRoutingTests.swift
//  SportsHubTests
//
//  Routing/intake regression suite — Phases 1, 2, 3, and 4.
//
//  Purpose: Verify that PrePipelineClassifier, OutputModeDetector,
//  RefinementClassifier, AppHelpClassifier, and AnalyticsClassifier
//  route every message to the correct bucket.
//
//  Phase 1 Categories (PrePipelineClassifier):
//    1.  Pure greetings (bucket: greetingSocial)
//    2.  Single-word social acknowledgements (bucket: greetingSocial)
//    3.  Positive-feedback / thank-you messages (bucket: greetingSocial)
//    4.  Laughter / emoji social signals (bucket: greetingSocial)
//    5.  Simple arithmetic — pass (bucket: arithmeticFactual)
//    6.  Arithmetic with coaching vocabulary — blocked (bucket: coachingLikely)
//    7.  Off-topic factual redirects (bucket: offTopicRedirect)
//    8.  Unclear / ambiguous messages (bucket: unclear)
//    9.  Coaching-likely — sport names trigger (bucket: coachingLikely)
//    10. Coaching-likely — training vocabulary (bucket: coachingLikely)
//    11. Edge cases: coaching action verbs override social signal (bucket: coachingLikely)
//    12. Coaching-adjacent expressions (bucket: coachingLikely)
//
//  Phase 2 Categories (OutputModeDetector):
//    13. Guidance mode
//    14. CoachingConversational mode
//    15. WorkoutPlan mode
//    16. Explanation mode
//    17. SchedulePlan mode
//    18. "plan" word edge cases
//
//  Phase 3 Categories (RefinementClassifier):
//    19. Constraint modifiers — time
//    20. Constraint modifiers — intensity
//    21. Constraint modifiers — equipment & recovery
//    22. Guidance → session conversion
//    23. CoachingConversational completion
//    24. Fresh topic override
//    25. hasPriorAIResponse = false → always freshRequest
//    26. Explicit duration extraction
//
//  Phase 4 Categories (AppHelpClassifier + AnalyticsClassifier):
//    27. App-help detection — navigation, features, settings questions
//    28. App-help non-detection — coaching skill questions excluded
//    29. Analytics detection — training progress / data summary queries
//    30. Analytics non-detection — skill vocab → falls through to coaching
//    31. Post-plan collision resolution — Phase 4 fires before Phase 3
//
//  Phase 5 Categories (DirectSkillDetector, AmbiguityClassifier, SafetyInterruptClassifier):
//    32. Direct-skill detection — sport-specific phrases trigger survey suppression
//    33. Direct-skill non-detection — generic/cross-sport phrases pass through
//    34. Ambiguity classifier detection — underspecified coaching gets clarifying question
//    35. Ambiguity classifier non-detection — specific requests pass through to pipeline
//    36. Safety interrupt detection — injury + coaching mixed inputs → safety wins
//    37. Safety interrupt non-detection — pure coaching requests pass through
//

import Testing
@testable import SportsHub

// MARK: - Helpers

private func route(_ message: String, sport: Sport = .basketball) -> PrePipelineIntent {
    PrePipelineClassifier.classify(message, sport: sport)
}

private func isGreetingSocial(_ message: String, sport: Sport = .basketball) -> Bool {
    if case .greetingSocial = route(message, sport: sport) { return true }
    return false
}

private func isCoachingLikely(_ message: String, sport: Sport = .basketball) -> Bool {
    if case .coachingLikely = route(message, sport: sport) { return true }
    return false
}

private func isOffTopicRedirect(_ message: String, sport: Sport = .basketball) -> Bool {
    if case .offTopicRedirect = route(message, sport: sport) { return true }
    return false
}

private func isUnclear(_ message: String, sport: Sport = .basketball) -> Bool {
    if case .unclear = route(message, sport: sport) { return true }
    return false
}

private func arithmeticAnswer(for message: String) -> String? {
    if case .arithmeticFactual(let answer) = route(message) { return answer }
    return nil
}

// MARK: - 1. Pure Greetings

struct PureGreetingTests {

    @Test("'Hi' alone → greetingSocial")
    func testHi() { #expect(isGreetingSocial("Hi")) }

    @Test("'Hey' alone → greetingSocial")
    func testHey() { #expect(isGreetingSocial("Hey")) }

    @Test("'Hello' alone → greetingSocial")
    func testHello() { #expect(isGreetingSocial("Hello")) }

    @Test("'Hi there' → greetingSocial")
    func testHiThere() { #expect(isGreetingSocial("Hi there")) }

    @Test("'Hey coach' → greetingSocial (short greeting)")
    func testHeyCoach() { #expect(isGreetingSocial("Hey coach")) }

    @Test("'Good morning' → greetingSocial")
    func testGoodMorning() { #expect(isGreetingSocial("Good morning")) }

    @Test("'How are you' does NOT route social (ambiguous — maps unclear or coaching)")
    func testHowAreYou() {
        // "How are you" has no greeting prefix and no social phrase — maps to .unclear, not to pipeline
        let intent = route("How are you")
        if case .greetingSocial = intent { return }   // acceptable
        if case .unclear = intent { return }           // acceptable
        Issue.record("'How are you' routed to unexpected bucket")
    }

    // Greeting prefix + social question — must route .greetingSocial after fix
    @Test("'Hi, how are you' → greetingSocial")
    func testHiHowAreYou() { #expect(isGreetingSocial("Hi, how are you")) }

    @Test("'Hey, how are you' → greetingSocial")
    func testHeyHowAreYou() { #expect(isGreetingSocial("Hey, how are you")) }

    @Test("'Hello, how are you' → greetingSocial")
    func testHelloHowAreYou() { #expect(isGreetingSocial("Hello, how are you")) }
}

// MARK: - 2. Single-Word Social Acknowledgements

struct SingleWordAcknowledgementTests {

    @Test("'ok' alone → greetingSocial")
    func testOk() { #expect(isGreetingSocial("ok")) }

    @Test("'okay' → greetingSocial")
    func testOkay() { #expect(isGreetingSocial("okay")) }

    @Test("'cool' → greetingSocial")
    func testCool() { #expect(isGreetingSocial("cool")) }

    @Test("'great' → greetingSocial")
    func testGreat() { #expect(isGreetingSocial("great")) }

    @Test("'noted' → greetingSocial")
    func testNoted() { #expect(isGreetingSocial("noted")) }

    @Test("'👍' → greetingSocial")
    func testThumbsUp() { #expect(isGreetingSocial("👍")) }
}

// MARK: - 3. Positive Feedback / Thank-You

struct PositiveFeedbackTests {

    @Test("'thanks' → greetingSocial")
    func testThanks() { #expect(isGreetingSocial("thanks")) }

    @Test("'thank you' → greetingSocial")
    func testThankYou() { #expect(isGreetingSocial("thank you")) }

    @Test("'that was helpful' → greetingSocial")
    func testThatWasHelpful() { #expect(isGreetingSocial("that was helpful")) }

    @Test("'that was great' → greetingSocial")
    func testThatWasGreat() { #expect(isGreetingSocial("that was great")) }

    @Test("'sounds good' → greetingSocial")
    func testSoundsGood() { #expect(isGreetingSocial("sounds good")) }

    @Test("'got it' → greetingSocial")
    func testGotIt() { #expect(isGreetingSocial("got it")) }

    @Test("'that session was amazing' → greetingSocial (past positive, no future action)")
    func testSessionWasAmazing() { #expect(isGreetingSocial("that session was amazing")) }

    @Test("'the workout was perfect' → greetingSocial")
    func testWorkoutWasPerfect() { #expect(isGreetingSocial("the workout was perfect")) }
}

// MARK: - 4. Laughter / Emoji Social Signals

struct LaughterEmojiTests {

    @Test("'lol' → greetingSocial")
    func testLol() { #expect(isGreetingSocial("lol")) }

    @Test("'haha' → greetingSocial")
    func testHaha() { #expect(isGreetingSocial("haha")) }

    @Test("'that's funny haha' → greetingSocial")
    func testThatsFunnyHaha() { #expect(isGreetingSocial("that's funny haha")) }

    @Test("'😂' → greetingSocial")
    func testLaughEmoji() { #expect(isGreetingSocial("😂")) }
}

// MARK: - 5. Arithmetic — Pass

struct ArithmeticPassTests {

    @Test("'2 + 2' → arithmeticFactual(answer: '4')")
    func testTwoPlusTwo() { #expect(arithmeticAnswer(for: "2 + 2") == "4") }

    @Test("'10 - 3' → arithmeticFactual(answer: '7')")
    func testTenMinusThree() { #expect(arithmeticAnswer(for: "10 - 3") == "7") }

    @Test("'6 * 7' → arithmeticFactual(answer: '42')")
    func testSixTimesSeven() { #expect(arithmeticAnswer(for: "6 * 7") == "42") }

    @Test("'100 / 4' → arithmeticFactual(answer: '25')")
    func testHundredDividedFour() { #expect(arithmeticAnswer(for: "100 / 4") == "25") }

    @Test("'what is 9 + 1' → arithmeticFactual(answer: '10')")
    func testWhatIsNinePlusOne() { #expect(arithmeticAnswer(for: "what is 9 + 1") == "10") }

    @Test("'what's 3 times 8' → arithmeticFactual(answer: '24')")
    func testWhatIsThreeTimesEight() { #expect(arithmeticAnswer(for: "what's 3 times 8") == "24") }

    @Test("'calculate 50 / 2' → arithmeticFactual(answer: '25')")
    func testCalculate() { #expect(arithmeticAnswer(for: "calculate 50 / 2") == "25") }

    @Test("Division by zero → NOT arithmeticFactual (no answer)")
    func testDivisionByZero() { #expect(arithmeticAnswer(for: "5 / 0") == nil) }

    // Trailing punctuation variants — must work after cleanup fix
    @Test("'what's 40 times 5?' (trailing ?) → arithmeticFactual('200')")
    func testTrailingQuestion() { #expect(arithmeticAnswer(for: "what's 40 times 5?") == "200") }

    @Test("'what is 18 + 6?' → arithmeticFactual('24')")
    func testTrailingQuestionPlus() { #expect(arithmeticAnswer(for: "what is 18 + 6?") == "24") }

    @Test("'12*3?' → arithmeticFactual('36')")
    func testBareExpressionTrailingQuestion() { #expect(arithmeticAnswer(for: "12*3?") == "36") }

    @Test("'100 / 4.' (trailing period) → arithmeticFactual('25')")
    func testTrailingPeriod() { #expect(arithmeticAnswer(for: "100 / 4.") == "25") }
    // The trailing "." is stripped as punctuation before the regex runs, leaving "100 / 4".
}

// MARK: - 6. Arithmetic Blocked by Coaching Vocabulary

struct ArithmeticBlockedTests {

    @Test("'how many reps should I do' → NOT arithmeticFactual (contains 'reps')")
    func testRepsGuard() { #expect(arithmeticAnswer(for: "how many reps should I do") == nil) }

    @Test("'how many sets is 3 x 10' → NOT arithmeticFactual (contains 'sets')")
    func testSetsGuard() { #expect(arithmeticAnswer(for: "how many sets is 3 x 10") == nil) }

    @Test("'how many minutes of basketball' → NOT arithmeticFactual")
    func testMinutesOfBasketball() { #expect(arithmeticAnswer(for: "how many minutes of basketball") == nil) }

    @Test("'2 drills per session' → NOT arithmeticFactual (contains 'drill')")
    func testDrillGuard() { #expect(arithmeticAnswer(for: "2 drills per session") == nil) }
}

// MARK: - 7. Off-Topic Factual Redirects

struct OffTopicRedirectTests {

    @Test("'what's the weather today' → offTopicRedirect")
    func testWeather() { #expect(isOffTopicRedirect("what's the weather today")) }

    @Test("'tell me a joke' → offTopicRedirect")
    func testJoke() { #expect(isOffTopicRedirect("tell me a joke")) }

    @Test("'recipe for pasta' → offTopicRedirect")
    func testRecipe() { #expect(isOffTopicRedirect("recipe for pasta")) }

    @Test("'what's the news today' → offTopicRedirect")
    func testNews() { #expect(isOffTopicRedirect("what's the news today")) }

    @Test("'stock market price' → offTopicRedirect")
    func testStocks() { #expect(isOffTopicRedirect("stock market")) }
}

// MARK: - 8. Unclear / Ambiguous Messages

struct UnclearMessageTests {

    @Test("Empty string → unclear")
    func testEmpty() { #expect(isUnclear("")) }

    @Test("'help' alone → unclear (no sport/skill context)")
    func testHelpAlone() { #expect(isUnclear("help")) }

    @Test("'I don't know' → unclear")
    func testIDontKnow() { #expect(isUnclear("I don't know")) }

    @Test("'what do you think' → unclear")
    func testWhatDoYouThink() { #expect(isUnclear("what do you think")) }
}

// MARK: - 9. Coaching-Likely — Sport Names

struct CoachingLikelySportNameTests {

    @Test("'basketball' alone → coachingLikely")
    func testBasketball() { #expect(isCoachingLikely("basketball")) }

    @Test("'I love football' → coachingLikely")
    func testILoveFootball() { #expect(isCoachingLikely("I love football")) }

    @Test("'soccer drills' → coachingLikely")
    func testSoccerDrills() { #expect(isCoachingLikely("soccer drills")) }

    @Test("'tennis serve' → coachingLikely")
    func testTennisServe() { #expect(isCoachingLikely("tennis serve")) }
}

// MARK: - 10. Coaching-Likely — Training Vocabulary

struct CoachingLikelyTrainingVocabTests {

    @Test("'show me a drill' → coachingLikely")
    func testShowMeADrill() { #expect(isCoachingLikely("show me a drill")) }

    @Test("'what's a good warm up' → coachingLikely")
    func testWarmUp() { #expect(isCoachingLikely("what's a good warm up")) }

    @Test("'help me improve my shooting' → coachingLikely")
    func testImproveShooting() { #expect(isCoachingLikely("help me improve my shooting")) }

    @Test("'I want to get better' → coachingLikely")
    func testWantToGetBetter() { #expect(isCoachingLikely("I want to get better")) }

    @Test("'what should I work on' → coachingLikely")
    func testWhatShouldIWorkOn() { #expect(isCoachingLikely("what should I work on")) }

    @Test("'can you plan my training schedule' → coachingLikely")
    func testPlanSchedule() { #expect(isCoachingLikely("can you plan my training schedule")) }
}

// MARK: - 11. Edge Cases: Coaching Action Verbs Override Social Signal

struct ActionVerbOverrideTests {

    @Test("'ok, build me a session' → coachingLikely (coaching verb overrides 'ok')")
    func testOkBuildMe() { #expect(isCoachingLikely("ok, build me a session")) }

    @Test("'thanks, give me a workout' → coachingLikely (coaching verb overrides 'thanks')")
    func testThanksGiveMeWorkout() { #expect(isCoachingLikely("thanks, give me a workout")) }

    @Test("'cool, let's work on my footwork' → coachingLikely")
    func testCoolLetsWorkOn() { #expect(isCoachingLikely("cool, let's work on my footwork")) }

    @Test("'sounds good, help me improve my serve' → coachingLikely (tennis)")
    func testSoundsGoodHelp() { #expect(isCoachingLikely("sounds good, help me improve my serve", sport: .tennis)) }

    @Test("'alright, create a drill routine for me' → coachingLikely")
    func testAlrightCreate() { #expect(isCoachingLikely("alright, create a drill routine for me")) }

    @Test("The original failure: 'Hi, how are you' does NOT generate a workout (maps to social/unclear, not coachingLikely)")
    func testHiHowAreYouDoesNotRouteToCoaching() {
        let intent = route("Hi, how are you")
        switch intent {
        case .coachingLikely:
            Issue.record("'Hi, how are you' incorrectly routed to coachingLikely — the confirmed failure case")
        default:
            break  // Any non-coaching bucket is a success
        }
    }
}

// MARK: - 12. Phase 2 — Coaching-Adjacent Phase 1 Expressions

struct CoachingAdjacentExpressionTests {

    @Test("'I feel stuck' → coachingLikely (coaching-adjacent expression)")
    func testFeelStuck() { #expect(isCoachingLikely("I feel stuck")) }

    @Test("'I'm not improving' → coachingLikely")
    func testNotImproving() { #expect(isCoachingLikely("I'm not improving")) }

    @Test("'I'm not getting better' → coachingLikely")
    func testNotGettingBetter() { #expect(isCoachingLikely("I'm not getting better")) }
}

// MARK: - 13. Phase 2 — OutputModeDetector Routing

private func outputMode(_ message: String) -> AICoachChatViewModel.OutputMode {
    AICoachChatViewModel.OutputModeDetector.detect(from: message)
}

struct OutputModeGuidanceTests {

    @Test("'What should I focus on today?' → guidance")
    func testFocusToday() { #expect(outputMode("What should I focus on today?") == .guidance) }

    @Test("'What should I work on?' → guidance")
    func testWorkOn() { #expect(outputMode("What should I work on?") == .guidance) }

    @Test("'What's most important right now?' → guidance")
    func testMostImportant() { #expect(outputMode("What's most important right now?") == .guidance) }

    @Test("'Am I working on the right things?' → guidance")
    func testRightThings() { #expect(outputMode("Am I working on the right things?") == .guidance) }

    @Test("'What do you recommend I focus on?' → guidance")
    func testRecommend() { #expect(outputMode("What do you recommend I focus on?") == .guidance) }

    @Test("'What should I do today?' → guidance")
    func testDoToday() { #expect(outputMode("What should I do today?") == .guidance) }
}

struct OutputModeCoachingConversationalTests {

    @Test("'I want to get better' → coachingConversational")
    func testWantToGetBetter() { #expect(outputMode("I want to get better") == .coachingConversational) }

    @Test("'I feel stuck' → coachingConversational (reaches Phase 2 via coaching-adjacent)")
    func testFeelStuck() { #expect(outputMode("I feel stuck") == .coachingConversational) }

    @Test("'I'm not improving' → coachingConversational")
    func testNotImproving() { #expect(outputMode("I'm not improving") == .coachingConversational) }

    @Test("'Help me with my shooting' → coachingConversational (no explicit plan request)")
    func testHelpWithShooting() { #expect(outputMode("Help me with my shooting") == .coachingConversational) }
}

struct OutputModeWorkoutPlanTests {

    @Test("'Build me a 45-minute shooting session' → workoutPlan")
    func testExplicitWorkout() { #expect(outputMode("Build me a 45-minute shooting session") == .workoutPlan) }

    @Test("'Create a workout for my dribbling' → workoutPlan")
    func testCreateWorkout() { #expect(outputMode("Create a workout for my dribbling") == .workoutPlan) }

    @Test("'Give me a drill routine' → workoutPlan")
    func testGiveMeDrills() { #expect(outputMode("Give me a drill routine") == .workoutPlan) }

    @Test("'Show me a drill for my shooting' → workoutPlan")
    func testShowMeDrill() { #expect(outputMode("Show me a drill for my shooting") == .workoutPlan) }
}

struct OutputModeExplanationTests {

    @Test("'Why does shooting form matter?' → explanation")
    func testWhyShooting() { #expect(outputMode("Why does shooting form matter?") == .explanation) }

    @Test("'How does footwork affect my game?' → explanation")
    func testHowDoes() { #expect(outputMode("How does footwork affect my game?") == .explanation) }

    @Test("'Explain the importance of court vision' → explanation")
    func testExplain() { #expect(outputMode("Explain the importance of court vision") == .explanation) }
}

struct OutputModeSchedulePlanTests {

    @Test("'Create a training schedule for this week' → schedulePlan")
    func testThisWeek() { #expect(outputMode("Create a training schedule for this week") == .schedulePlan) }

    @Test("'Give me a weekly training plan' → schedulePlan")
    func testWeeklyPlan() { #expect(outputMode("Give me a weekly training plan") == .schedulePlan) }

    @Test("'Build me a 4-day program' → schedulePlan")
    func testProgram() { #expect(outputMode("Build me a 4-day program") == .schedulePlan) }
}

struct OutputModePlanWordEdgeCaseTests {

    @Test("'I have a plan to improve my dribbling' → coachingConversational (NOT workoutPlan)")
    func testPlanAloneNotWorkout() { #expect(outputMode("I have a plan to improve my dribbling") == .coachingConversational) }

    @Test("'I'm planning to work on my serve' → coachingConversational (NOT workoutPlan)")
    func testPlanningNotWorkout() { #expect(outputMode("I'm planning to work on my serve") == .coachingConversational) }

    @Test("'Make a plan for me' → schedulePlan (action verb + 'make a plan' keyword)")
    func testMakeAPlan() { #expect(outputMode("Make a plan for me") == .schedulePlan) }
}

// MARK: - Phase 3 Helpers

private func refine(_ message: String, priorMode: AICoachChatViewModel.OutputMode) -> RefinementIntent {
    RefinementClassifier.classify(message: message, hasPriorAIResponse: true, priorMode: priorMode)
}

private func isRefineModify(_ intent: RefinementIntent) -> Bool {
    if case .refine = intent { return true }
    return false
}

private func isConvertGuidance(_ intent: RefinementIntent) -> Bool {
    if case .convertGuidanceToSession = intent { return true }
    return false
}

private func isConvCompletion(_ intent: RefinementIntent) -> Bool {
    if case .conversationalCompletion = intent { return true }
    return false
}

private func isFreshRequest(_ intent: RefinementIntent) -> Bool {
    if case .freshRequest = intent { return true }
    return false
}

// MARK: - 19. Constraint Modifiers — Time

struct RefinementTimeModifierTests {

    @Test("'make it 20 minutes' → refine (explicit duration)")
    func testExplicit20Min() { #expect(isRefineModify(refine("make it 20 minutes", priorMode: .workoutPlan))) }

    @Test("'I only have 30 minutes' → refine (explicit duration)")
    func testOnly30Min() { #expect(isRefineModify(refine("I only have 30 minutes", priorMode: .workoutPlan))) }

    @Test("'make it shorter' → refine (relative shortening)")
    func testShorter() { #expect(isRefineModify(refine("make it shorter", priorMode: .workoutPlan))) }

    @Test("'make it longer' → refine (relative extension)")
    func testLonger() { #expect(isRefineModify(refine("make it longer", priorMode: .workoutPlan))) }

    @Test("explicit 45 min extraction from '45 min session'")
    func testExplicitMinutesExtraction() {
        let result = RefinementClassifier.extractExplicitMinutes(from: "give me a 45 min session")
        #expect(result == 45)
    }

    @Test("explicit 20 extraction from 'only 20 minutes today'")
    func testExplicitMinutes20() {
        let result = RefinementClassifier.extractExplicitMinutes(from: "only 20 minutes today")
        #expect(result == 20)
    }

    @Test("no extraction from 'I want to train' (no duration)")
    func testNoMinutesInGeneralMessage() {
        let result = RefinementClassifier.extractExplicitMinutes(from: "I want to train")
        #expect(result == nil)
    }
}

// MARK: - 20. Constraint Modifiers — Intensity

struct RefinementIntensityModifierTests {

    @Test("'harder' → refine")
    func testHarder() { #expect(isRefineModify(refine("harder", priorMode: .workoutPlan))) }

    @Test("'make it harder' → refine")
    func testMakeItHarder() { #expect(isRefineModify(refine("make it harder", priorMode: .workoutPlan))) }

    @Test("'easier' → refine")
    func testEasier() { #expect(isRefineModify(refine("easier", priorMode: .workoutPlan))) }

    @Test("'scale it down' → refine")
    func testScaleDown() { #expect(isRefineModify(refine("scale it down", priorMode: .workoutPlan))) }

    @Test("'too hard, dial it back' → refine")
    func testDialItBack() { #expect(isRefineModify(refine("too hard, dial it back", priorMode: .workoutPlan))) }
}

// MARK: - 21. Constraint Modifiers — Equipment & Recovery

struct RefinementEquipmentRecoveryTests {

    @Test("'no equipment' → refine")
    func testNoEquipment() { #expect(isRefineModify(refine("no equipment", priorMode: .workoutPlan))) }

    @Test("'at home, bodyweight only' → refine")
    func testAtHome() { #expect(isRefineModify(refine("at home, bodyweight only", priorMode: .workoutPlan))) }

    @Test("'adjust for recovery' → refine")
    func testRecovery() { #expect(isRefineModify(refine("adjust for recovery", priorMode: .workoutPlan))) }

    @Test("'active recovery mode' → refine")
    func testActiveRecovery() { #expect(isRefineModify(refine("active recovery mode", priorMode: .workoutPlan))) }

    @Test("'low intensity today' → refine")
    func testLowIntensity() { #expect(isRefineModify(refine("low intensity today", priorMode: .workoutPlan))) }
}

// MARK: - 22. Guidance → Session Conversion

struct RefinementGuidanceConversionTests {

    @Test("'okay, make that into a session' after guidance → convertGuidanceToSession")
    func testMakeThatIntoSession() { #expect(isConvertGuidance(refine("okay, make that into a session", priorMode: .guidance))) }

    @Test("'build me a session' after guidance → convertGuidanceToSession")
    func testBuildMeSession() { #expect(isConvertGuidance(refine("build me a session", priorMode: .guidance))) }

    @Test("'yes, build me a session' after guidance → convertGuidanceToSession")
    func testYesBuildMe() { #expect(isConvertGuidance(refine("yes, build me a session", priorMode: .guidance))) }

    @Test("'turn that into a plan' after guidance → convertGuidanceToSession")
    func testTurnIntoPlan() { #expect(isConvertGuidance(refine("turn that into a plan", priorMode: .guidance))) }

    @Test("'make it a workout' after guidance → convertGuidanceToSession")
    func testMakeItWorkout() { #expect(isConvertGuidance(refine("make it a workout", priorMode: .guidance))) }

    @Test("conversion phrase after workoutPlan → NOT convertGuidanceToSession (wrong prior mode)")
    func testConversionNotApplicableAfterWorkout() {
        let intent = refine("build me a session", priorMode: .workoutPlan)
        #expect(!isConvertGuidance(intent))
    }
}

// MARK: - 23. CoachingConversational Completion

struct RefinementConversationalCompletionTests {

    @Test("'ball handling' after coachingConversational → conversationalCompletion")
    func testBallHandling() { #expect(isConvCompletion(refine("ball handling", priorMode: .coachingConversational))) }

    @Test("'shooting' after coachingConversational → conversationalCompletion")
    func testShooting() { #expect(isConvCompletion(refine("shooting", priorMode: .coachingConversational))) }

    @Test("time answer after coachingConversational → refine (has modifier vocab), not completion")
    func testTimeAnswerNotCompletion() {
        #expect(!isConvCompletion(refine("about 30 minutes", priorMode: .coachingConversational)))
    }

    @Test("long answer after coachingConversational → freshRequest (too many words)")
    func testLongAnswerIsFresh() {
        let msg = "I want to work on my dribbling and shooting and also my footwork"
        #expect(isFreshRequest(refine(msg, priorMode: .coachingConversational)))
    }
}

// MARK: - 24. Fresh Topic Override

struct RefinementFreshTopicTests {

    @Test("'what about footwork?' after shooting plan → freshRequest")
    func testWhatAboutFootwork() { #expect(isFreshRequest(refine("what about footwork?", priorMode: .workoutPlan))) }

    @Test("'how about defense instead?' → freshRequest")
    func testHowAboutDefense() { #expect(isFreshRequest(refine("how about defense instead?", priorMode: .workoutPlan))) }

    @Test("'what about my serve?' after guidance → freshRequest (not conversion)")
    func testWhatAboutMyServe() { #expect(isFreshRequest(refine("what about my serve?", priorMode: .guidance))) }

    @Test("Unrelated message with no modifier signals → freshRequest")
    func testGenericUnrelated() {
        let intent = refine("I want to think about my training structure", priorMode: .workoutPlan)
        #expect(isFreshRequest(intent))
    }
}

// MARK: - 25. No Prior AI Response → Always Fresh

struct RefinementNoPriorResponseTests {

    @Test("'harder' with no prior AI response → freshRequest")
    func testHarderNoPrior() {
        let intent = RefinementClassifier.classify(message: "harder", hasPriorAIResponse: false, priorMode: .workoutPlan)
        #expect(isFreshRequest(intent))
    }

    @Test("'make it shorter' with no prior AI response → freshRequest")
    func testShorterNoPrior() {
        let intent = RefinementClassifier.classify(message: "make it shorter", hasPriorAIResponse: false, priorMode: nil)
        #expect(isFreshRequest(intent))
    }
}

// MARK: - Phase 4 Helpers

private func isAppHelp(_ message: String) -> Bool {
    AppHelpClassifier.isAppHelp(message)
}

private func isAnalytics(_ message: String) -> Bool {
    AnalyticsClassifier.isAnalytics(message)
}

// MARK: - 27. App-Help Detection

struct AppHelpDetectionTests {

    @Test("'how do I log a session?' → app-help")
    func testLogSession() { #expect(isAppHelp("how do I log a session?")) }

    @Test("'where is the train tab?' → app-help")
    func testWhereIsTrainTab() { #expect(isAppHelp("where is the train tab?")) }

    @Test("'how does the AI Coach work?' → app-help")
    func testAICoachWork() { #expect(isAppHelp("how does the AI Coach work?")) }

    @Test("'what is premium?' → app-help")
    func testWhatIsPremium() { #expect(isAppHelp("what is premium?")) }

    @Test("'how do I connect my Apple Watch?' → app-help")
    func testConnectAppleWatch() { #expect(isAppHelp("how do I connect my Apple Watch?")) }

    @Test("'how do I add friends?' → app-help")
    func testAddFriends() { #expect(isAppHelp("how do I add friends?")) }

    @Test("'how do I file a dispute?' → app-help")
    func testFileDispute() { #expect(isAppHelp("how do I file a dispute?")) }

    @Test("'where is the drill library?' → app-help")
    func testDrillLibrary() { #expect(isAppHelp("where is the drill library?")) }

    @Test("'how do I save my workout?' → app-help")
    func testSaveWorkout() { #expect(isAppHelp("how do I save my workout?")) }
}

// MARK: - 28. App-Help Non-Detection (Coaching Questions Excluded)

struct AppHelpNonDetectionTests {

    @Test("'how do I do a euro step?' → NOT app-help (sport skill)")
    func testEuroStepNotAppHelp() { #expect(!isAppHelp("how do I do a euro step?")) }

    @Test("'how do I improve my shooting?' → NOT app-help (skill improvement intent)")
    func testImproveShootingNotAppHelp() { #expect(!isAppHelp("how do I improve my shooting?")) }

    @Test("'teach me a crossover' → NOT app-help (teach me)")
    func testTeachMeCrossoverNotAppHelp() { #expect(!isAppHelp("teach me a crossover")) }

    @Test("'help me with my footwork' → NOT app-help (help me with)")
    func testHelpMeFootworkNotAppHelp() { #expect(!isAppHelp("help me with my footwork")) }

    @Test("'explain how to do a drop shot' → NOT app-help (explain how to)")
    func testExplainDropShotNotAppHelp() { #expect(!isAppHelp("explain how to do a drop shot")) }

    @Test("'show me how to dribble' → NOT app-help (show me how to)")
    func testShowMeDribbleNotAppHelp() { #expect(!isAppHelp("show me how to dribble")) }

    @Test("'give me a 45 min workout' → NOT app-help (coaching request)")
    func testWorkoutRequestNotAppHelp() { #expect(!isAppHelp("give me a 45 min workout")) }
}

// MARK: - 29. Analytics Detection

struct AnalyticsDetectionTests {

    @Test("'how am I doing?' → analytics")
    func testHowAmIDoing() { #expect(isAnalytics("how am I doing?")) }

    @Test("'am I improving?' → analytics")
    func testAmIImproving() { #expect(isAnalytics("am I improving?")) }

    @Test("'what's my streak?' → analytics")
    func testMyStreak() { #expect(isAnalytics("what's my streak?")) }

    @Test("'how many sessions this week?' → analytics")
    func testSessionsThisWeek() { #expect(isAnalytics("how many sessions this week?")) }

    @Test("'what have I been working on?' → analytics")
    func testWhatHaveIBeenWorkingOn() { #expect(isAnalytics("what have I been working on?")) }

    @Test("'training summary' → analytics")
    func testTrainingSummary() { #expect(isAnalytics("training summary")) }

    @Test("'what are my weak areas?' → analytics")
    func testWeakAreas() { #expect(isAnalytics("what are my weak areas?")) }

    @Test("'show my recent sessions' → analytics")
    func testRecentSessions() { #expect(isAnalytics("show my recent sessions")) }

    @Test("'have I been improving?' → analytics")
    func testHaveIBeenImproving() { #expect(isAnalytics("have I been improving?")) }
}

// MARK: - 30. Analytics Non-Detection (Skill Vocab → Falls Through to Coaching)

struct AnalyticsNonDetectionTests {

    @Test("'how am I doing with my shooting?' → NOT analytics (has sport skill vocab)")
    func testShootingNotAnalytics() { #expect(!isAnalytics("how am I doing with my shooting?")) }

    @Test("'how do I improve?' → NOT analytics (coaching-action intent)")
    func testHowDoIImproveNotAnalytics() { #expect(!isAnalytics("how do I improve?")) }

    @Test("'what should I work on?' → NOT analytics (coaching-action intent)")
    func testWhatShouldIWorkOnNotAnalytics() { #expect(!isAnalytics("what should I work on?")) }

    @Test("'give me a workout' → NOT analytics")
    func testGiveWorkoutNotAnalytics() { #expect(!isAnalytics("give me a workout")) }

    @Test("'help me get better at dribbling' → NOT analytics")
    func testDribblingNotAnalytics() { #expect(!isAnalytics("help me get better at dribbling")) }

    @Test("'how am I doing with my conditioning?' → NOT analytics (conditioning is skill vocab)")
    func testConditioningNotAnalytics() { #expect(!isAnalytics("how am I doing with my conditioning?")) }
}

// MARK: - 31. Post-Plan Collision Resolution
//
// Verifies that Phase 4 classifiers fire for messages that could be
// ambiguous between refinement (Phase 3) and their actual intent.
// If AppHelpClassifier/AnalyticsClassifier return true, the Phase 3
// gate is not reached (Phase 4 returns early in sendMessage()).

struct PostPlanCollisionTests {

    @Test("'how do I log that?' after a plan → app-help fires (not refinement)")
    func testLogThatIsAppHelp() {
        // Phase 4a fires because "how do i log" matches app-help patterns
        #expect(isAppHelp("how do I log that?"))
    }

    @Test("'how am I doing?' after a plan → analytics fires (not refinement)")
    func testHowAmIDoingIsAnalytics() {
        // Phase 4b fires before Phase 3 can treat this as a refinement
        #expect(isAnalytics("how am I doing?"))
    }

    @Test("'how am I doing with my shooting?' → analytics does NOT fire → reaches coaching pipeline")
    func testSkillQueryFallsThroughAnalytics() {
        // Phase 4b does NOT fire — this falls through to the coaching pipeline
        #expect(!isAnalytics("how am I doing with my shooting?"))
    }

    @Test("'make it shorter' → NOT app-help, NOT analytics → Phase 3 handles it")
    func testShorterNotCaughtByPhase4() {
        #expect(!isAppHelp("make it shorter"))
        #expect(!isAnalytics("make it shorter"))
    }
}

// MARK: - Phase 5 Helpers

private func hasDirectSkill(_ message: String, sport: Sport = .basketball) -> Bool {
    DirectSkillDetector.detect(from: message, sport: sport)
}

// MARK: - 32. Direct-Skill Detection (Phase 5A)
//
// Verifies that DirectSkillDetector.detect() returns true for sport-specific
// technical phrases.  When true, survey-derived weakPoints are suppressed in
// buildCoachContext() so they cannot override the user's explicit focus.

@Suite("DirectSkillDetector — Detection")
struct DirectSkillDetectorDetectionTests {

    // Basketball
    @Test("Basketball: 'I want to work on my left hand' → hasDirectSkill")
    func testBasketballLeftHand() {
        #expect(hasDirectSkill("I want to work on my left hand", sport: .basketball))
    }

    @Test("Basketball: 'help me with my crossover' → hasDirectSkill")
    func testBasketballCrossover() {
        #expect(hasDirectSkill("help me with my crossover", sport: .basketball))
    }

    @Test("Basketball: 'shooting drills please' → hasDirectSkill")
    func testBasketballShooting() {
        #expect(hasDirectSkill("shooting drills please", sport: .basketball))
    }

    @Test("Basketball: 'my footwork needs work' → hasDirectSkill")
    func testBasketballFootwork() {
        #expect(hasDirectSkill("my footwork needs work", sport: .basketball))
    }

    // Football
    @Test("Football: 'help with route running' → hasDirectSkill")
    func testFootballRouteRunning() {
        #expect(hasDirectSkill("help with route running", sport: .football))
    }

    @Test("Football: 'I need to work on my catching' → hasDirectSkill")
    func testFootballCatching() {
        #expect(hasDirectSkill("I need to work on my catching", sport: .football))
    }

    // Soccer
    @Test("Soccer: 'first touch session' → hasDirectSkill")
    func testSoccerFirstTouch() {
        #expect(hasDirectSkill("first touch session", sport: .soccer))
    }

    @Test("Soccer: 'help me with dribbling' → hasDirectSkill")
    func testSoccerDribbling() {
        #expect(hasDirectSkill("help me with dribbling", sport: .soccer))
    }

    // Tennis
    @Test("Tennis: 'my serve is inconsistent' → hasDirectSkill")
    func testTennisServe() {
        #expect(hasDirectSkill("my serve is inconsistent", sport: .tennis))
    }

    @Test("Tennis: 'work on my forehand topspin' → hasDirectSkill")
    func testTennisForehandTopspin() {
        #expect(hasDirectSkill("work on my forehand topspin", sport: .tennis))
    }
}

// MARK: - 33. Direct-Skill Non-Detection (Phase 5A)
//
// Verifies that DirectSkillDetector.detect() returns false for generic
// coaching messages and cross-sport phrase combinations.  When false,
// survey-derived weakPoints are included normally (no suppression).

@Suite("DirectSkillDetector — Non-Detection")
struct DirectSkillDetectorNonDetectionTests {

    @Test("'I want to get better' → NOT hasDirectSkill (no specific skill named)")
    func testGenericGetBetter() {
        #expect(!hasDirectSkill("I want to get better"))
    }

    @Test("'give me a 45-minute workout' → NOT hasDirectSkill")
    func testGenericWorkout() {
        #expect(!hasDirectSkill("give me a 45-minute workout"))
    }

    @Test("'what should I work on today?' → NOT hasDirectSkill")
    func testGenericWhatToWorkOn() {
        #expect(!hasDirectSkill("what should I work on today?"))
    }

    @Test("'build me something hard' → NOT hasDirectSkill")
    func testGenericHardWorkout() {
        #expect(!hasDirectSkill("build me something hard"))
    }

    // Cross-sport: "shooting" is a basketball/soccer phrase, not football
    @Test("Football: 'shooting practice' → NOT hasDirectSkill (shooting is not a football phrase)")
    func testCrossSportShootingFootball() {
        #expect(!hasDirectSkill("shooting practice", sport: .football))
    }

    // Cross-sport: "serve" is tennis, not basketball
    @Test("Basketball: 'help with my serve' → NOT hasDirectSkill (serve is not a basketball phrase)")
    func testCrossSportServeBball() {
        #expect(!hasDirectSkill("help with my serve", sport: .basketball))
    }

    @Test("'I need help' → NOT hasDirectSkill")
    func testGenericHelp() {
        #expect(!hasDirectSkill("I need help"))
    }
}

// MARK: - Phase 5B Helpers

private func isAmbiguous(_ message: String) -> Bool {
    CoachingAmbiguityClassifier.isAmbiguous(message)
}

// MARK: - 34. Ambiguity Classifier Detection (Phase 5B)
//
// Verifies that CoachingAmbiguityClassifier.isAmbiguous() returns true for
// underspecified coaching messages with no skill, duration, or constraint signal.
// When true (and no prior AI in session), the coach returns a clarifying question.

@Suite("CoachingAmbiguityClassifier — Detection")
struct AmbiguityClassifierDetectionTests {

    @Test("'something for today' → isAmbiguous")
    func testSomethingForToday() {
        #expect(isAmbiguous("something for today"))
    }

    @Test("'what now' → isAmbiguous")
    func testWhatNow() {
        #expect(isAmbiguous("what now"))
    }

    @Test("'not sure what to do' → isAmbiguous")
    func testNotSureWhatToDo() {
        #expect(isAmbiguous("not sure what to do"))
    }

    @Test("'just give me something' → isAmbiguous")
    func testJustGiveMeSomething() {
        #expect(isAmbiguous("just give me something"))
    }

    @Test("'surprise me' → isAmbiguous")
    func testSurpriseMe() {
        #expect(isAmbiguous("surprise me"))
    }

    @Test("'any ideas' → isAmbiguous")
    func testAnyIdeas() {
        #expect(isAmbiguous("any ideas"))
    }

    @Test("'what do you recommend' → isAmbiguous")
    func testWhatDoYouRecommend() {
        #expect(isAmbiguous("what do you recommend"))
    }

    @Test("'not sure where to start' → isAmbiguous")
    func testNotSureWhereToStart() {
        #expect(isAmbiguous("not sure where to start"))
    }
}

// MARK: - 35. Ambiguity Classifier Non-Detection (Phase 5B)
//
// Verifies that CoachingAmbiguityClassifier.isAmbiguous() returns false for messages
// that contain any specificity signal (skill, duration, intensity, equipment).
// These pass through to the normal pipeline.

@Suite("CoachingAmbiguityClassifier — Non-Detection")
struct AmbiguityClassifierNonDetectionTests {

    @Test("'give me a 45-minute workout' → NOT ambiguous (has duration hint)")
    func testHasDuration() {
        #expect(!isAmbiguous("give me a 45-minute workout"))
    }

    @Test("'crossover drills please' → NOT ambiguous (has skill signal)")
    func testHasSkill() {
        #expect(!isAmbiguous("crossover drills please"))
    }

    @Test("'something hard with no equipment' → NOT ambiguous (has intensity + equipment hint)")
    func testHasIntensityAndEquipment() {
        #expect(!isAmbiguous("something hard with no equipment"))
    }

    @Test("'help me with my shooting' → NOT ambiguous (has skill signal)")
    func testHelpWithShootingNotAmbiguous() {
        #expect(!isAmbiguous("help me with my shooting"))
    }

    @Test("'build me a recovery session' → NOT ambiguous (has session type hint)")
    func testRecoverySession() {
        #expect(!isAmbiguous("build me a recovery session"))
    }

    @Test("'give me a drill for ball handling' → NOT ambiguous (has skill + drill hint)")
    func testDrillForBallHandling() {
        #expect(!isAmbiguous("give me a drill for ball handling"))
    }
}

// MARK: - Phase 5C Helpers

private func isSafetyInterrupt(_ message: String) -> Bool {
    SafetyInterruptClassifier.isMixedInjuryCoachingRequest(message)
}

// MARK: - 36. Safety Interrupt Detection (Phase 5C)
//
// Verifies that SafetyInterruptClassifier fires when the user mixes injury language
// with a coaching request in the same message.  Safety wins — no drills generated.

@Suite("SafetyInterruptClassifier — Detection")
struct SafetyInterruptDetectionTests {

    @Test("'my knee hurts but build me a workout' → safety interrupt")
    func testKneeHurtsBuildWorkout() {
        #expect(isSafetyInterrupt("my knee hurts but build me a workout"))
    }

    @Test("'my shoulder is sore give me a drill' → safety interrupt")
    func testShoulderSoreGiveDrill() {
        #expect(isSafetyInterrupt("my shoulder is sore give me a drill"))
    }

    @Test("'I'm in pain but I want to train' → safety interrupt")
    func testPainWantToTrain() {
        #expect(isSafetyInterrupt("I'm in pain but I want to train"))
    }

    @Test("'my ankle is sprained can I train' → safety interrupt")
    func testAnkleSprainedCanITrain() {
        #expect(isSafetyInterrupt("my ankle is sprained can I train"))
    }

    @Test("'sore knee give me a drill session' → safety interrupt")
    func testSoreKneeDrillSession() {
        #expect(isSafetyInterrupt("sore knee give me a drill session"))
    }
}

// MARK: - 37. Safety Interrupt Non-Detection (Phase 5C)
//
// Verifies that the safety interrupt does NOT fire for pure coaching requests
// (no injury language) or pure injury-only messages (no coaching request).

@Suite("SafetyInterruptClassifier — Non-Detection")
struct SafetyInterruptNonDetectionTests {

    @Test("'give me a 45-minute workout' → NOT safety interrupt (no injury)")
    func testPureWorkoutNoInjury() {
        #expect(!isSafetyInterrupt("give me a 45-minute workout"))
    }

    @Test("'my knee hurts' alone → NOT safety interrupt (no coaching request)")
    func testPureInjuryNoCoachingRequest() {
        #expect(!isSafetyInterrupt("my knee hurts"))
    }

    @Test("'I hurt myself yesterday' → NOT safety interrupt (no coaching request)")
    func testHurtMyselfNoRequest() {
        #expect(!isSafetyInterrupt("I hurt myself yesterday"))
    }

    @Test("'my legs feel a bit tired' → NOT safety interrupt")
    func testTiredNoInjury() {
        #expect(!isSafetyInterrupt("my legs feel a bit tired"))
    }

    @Test("'crossover drills please' → NOT safety interrupt (no injury)")
    func testCrossoverDrillNoInjury() {
        #expect(!isSafetyInterrupt("crossover drills please"))
    }
}

// MARK: - 38. Survey Staleness Decay (Phase 5D)
//
// Verifies AICoachChatViewModel.surveyRecencyMultiplier(ageInWeeks:) returns the
// correct decay value at key breakpoints.
// Named constants: surveyRecencyDecayPerWeek = 0.10, surveyRecencyMinMultiplier = 0.10

// MARK: - 38. Survey Staleness Decay (Phase 5D)
//
// Verifies SurveyRecencyConfig.multiplier(ageInWeeks:) returns the correct decay
// value at key breakpoints.
// Named constants: SurveyRecencyConfig.decayPerWeek = 0.10, minMultiplier = 0.10

@Suite("Survey Staleness Decay")
struct SurveyStalenesDecayTests {

    @Test("Age 0 weeks → multiplier == 1.0 (fresh survey, full weight)")
    func testFreshSurvey() {
        let mult = SurveyRecencyConfig.multiplier(ageInWeeks: 0)
        #expect(mult == 1.0)
    }

    @Test("Age 1 week → multiplier == 0.90 (10% decay)")
    func testOneWeekOld() {
        let mult = SurveyRecencyConfig.multiplier(ageInWeeks: 1)
        #expect(abs(mult - 0.90) < 0.001)
    }

    @Test("Age 4 weeks → multiplier == 0.60 (40% decay)")
    func testFourWeeksOld() {
        let mult = SurveyRecencyConfig.multiplier(ageInWeeks: 4)
        #expect(abs(mult - 0.60) < 0.001)
    }

    @Test("Age 9 weeks → multiplier == 0.10 (floored at minimum)")
    func testNineWeeksOld() {
        let mult = SurveyRecencyConfig.multiplier(ageInWeeks: 9)
        #expect(abs(mult - 0.10) < 0.001)
    }

    @Test("Age 15 weeks → multiplier == 0.10 (clamped — never below minimum)")
    func testFifteenWeeksOld() {
        let mult = SurveyRecencyConfig.multiplier(ageInWeeks: 15)
        #expect(mult == 0.10)
    }

    @Test("Negative age → multiplier == 1.0 (guard against clock skew)")
    func testNegativeAge() {
        let mult = SurveyRecencyConfig.multiplier(ageInWeeks: -2)
        #expect(mult == 1.0)
    }
}

// MARK: - 39. Mention-Count Decay (Phase 5E)
//
// Verifies MentionCountDecayConfig.apply(to:) produces the correct decayed values.
// Named constants: MentionCountDecayConfig.decayFactor = 0.80, countFloor = 1

@Suite("Mention-Count Decay")
struct MentionCountDecayTests {

    @Test("Count 10 → decayed to 8 (10 * 0.80)")
    func testDecayHighCount() {
        let result = MentionCountDecayConfig.apply(to: ["shooting": 10])
        #expect(result["shooting"] == 8)
    }

    @Test("Count 5 → decayed to 4 (5 * 0.80)")
    func testDecayMidCount() {
        let result = MentionCountDecayConfig.apply(to: ["dribbling": 5])
        #expect(result["dribbling"] == 4)
    }

    @Test("Count 1 → floored at 1 (never goes to 0)")
    func testDecayFloor() {
        let result = MentionCountDecayConfig.apply(to: ["footwork": 1])
        #expect(result["footwork"] == 1)
    }

    @Test("Count 2 → decayed to 1 (floor(2 * 0.80) = 1)")
    func testDecayLowCount() {
        let result = MentionCountDecayConfig.apply(to: ["passing": 2])
        #expect(result["passing"] == 1)
    }

    @Test("Multiple concepts all decay independently")
    func testDecayMultipleConcepts() {
        let input = ["shooting": 10, "dribbling": 5, "footwork": 1]
        let result = MentionCountDecayConfig.apply(to: input)
        #expect(result["shooting"] == 8)
        #expect(result["dribbling"] == 4)
        #expect(result["footwork"] == 1)
    }

    @Test("Empty dictionary → empty result")
    func testDecayEmpty() {
        let result = MentionCountDecayConfig.apply(to: [:])
        #expect(result.isEmpty)
    }
}

// MARK: - 40. Refinement Depth Guard (Phase 5F)
//
// Verifies RefinementDepthGuard correctly tracks modifier accumulation and
// signals a reset when the cap (maxDepth = 3) is reached.

@Suite("Refinement Depth Guard")
struct RefinementDepthGuardTests {

    @Test("Depth 0 → NOT at cap (1st modifier accepted)")
    func testDepth0NotAtCap() {
        #expect(!RefinementDepthGuard.isAtCap(depth: 0))
    }

    @Test("Depth 1 → NOT at cap (2nd modifier accepted)")
    func testDepth1NotAtCap() {
        #expect(!RefinementDepthGuard.isAtCap(depth: 1))
    }

    @Test("Depth 2 → NOT at cap (3rd modifier accepted)")
    func testDepth2NotAtCap() {
        #expect(!RefinementDepthGuard.isAtCap(depth: 2))
    }

    @Test("Depth 3 → AT CAP (4th modifier would reset)")
    func testDepth3AtCap() {
        #expect(RefinementDepthGuard.isAtCap(depth: 3))
    }

    @Test("Depth 4 → AT CAP (past cap, definitely resets)")
    func testDepth4AtCap() {
        #expect(RefinementDepthGuard.isAtCap(depth: 4))
    }

    @Test("incrementedDepth(from: 0) == 1")
    func testIncrementFrom0() {
        #expect(RefinementDepthGuard.incrementedDepth(from: 0) == 1)
    }

    @Test("incrementedDepth(from: 2) == 3 (reaches cap on next check)")
    func testIncrementFrom2() {
        #expect(RefinementDepthGuard.incrementedDepth(from: 2) == 3)
    }

    @Test("maxDepth == 3 (named tunable constant)")
    func testMaxDepthConstant() {
        #expect(RefinementDepthGuard.maxDepth == 3)
    }
}
