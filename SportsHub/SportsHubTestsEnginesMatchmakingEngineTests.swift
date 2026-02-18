//
//  MatchmakingEngineTests.swift
//  SportsHubTests
//
//  Created by Aarush Khanna on 2/17/26.
//
//  TDD — defines required behaviour of MatchmakingEngine.
//  The engine does not exist yet. All tests will fail until it is implemented.
//
//  MatchmakingEngine computes a "fairness score" between two players
//  for a given sport. The fairness score represents how evenly matched
//  the two players are.
//
//  Fairness score definition (to be confirmed):
//    - Range: 0.0 (completely mismatched) to 1.0 (perfectly matched)
//    - Two players with identical ratings → 1.0
//    - Larger rating difference → lower fairness score
//    - The score is symmetric: fair(A, B) == fair(B, A)
//
//  NOTE: The exact decay curve is not yet locked.
//  These tests define the structural/invariant properties.
//  Specific numeric thresholds are left flexible until the curve is chosen.

import Testing
@testable import SportsHubCore

// ---------------------------------------------------------------------------
// MARK: - Suite: Fairness Score Invariants
// ---------------------------------------------------------------------------

@Suite("Matchmaking — Fairness Score Invariants")
struct MatchmakingFairnessInvariantTests {

    // Two identical players → perfectly fair match → score == 1.0.
    @Test("Identical ratings → fairness score = 1.0")
    func identicalRatingsArePerfectlyFair() throws {
        let score = MatchmakingEngine.fairnessScore(
            ratingA: 1000,
            ratingB: 1000,
            sport: .basketball
        )
        #expect(abs(score - 1.0) < 0.0001)
    }

    // Fairness score must always be in [0.0, 1.0].
    @Test("Fairness score is always in range [0, 1] — small gap")
    func fairnessScoreInRangeSmallGap() throws {
        let score = MatchmakingEngine.fairnessScore(
            ratingA: 1000,
            ratingB: 1050,
            sport: .basketball
        )
        #expect(score >= 0.0)
        #expect(score <= 1.0)
    }

    @Test("Fairness score is always in range [0, 1] — large gap")
    func fairnessScoreInRangeLargeGap() throws {
        let score = MatchmakingEngine.fairnessScore(
            ratingA: 800,
            ratingB: 2000,
            sport: .basketball
        )
        #expect(score >= 0.0)
        #expect(score <= 1.0)
    }

    // The fairness score must be symmetric: fair(A, B) == fair(B, A).
    @Test("Fairness score is symmetric")
    func fairnessScoreIsSymmetric() throws {
        let scoreAB = MatchmakingEngine.fairnessScore(
            ratingA: 1100,
            ratingB: 1300,
            sport: .basketball
        )
        let scoreBA = MatchmakingEngine.fairnessScore(
            ratingA: 1300,
            ratingB: 1100,
            sport: .basketball
        )
        #expect(abs(scoreAB - scoreBA) < 0.0001)
    }

    // A larger rating gap must produce a lower or equal fairness score
    // than a smaller rating gap (monotonically decreasing with gap size).
    @Test("Larger rating gap → lower fairness score")
    func largerGapProducesLowerFairness() throws {
        let smallGapScore = MatchmakingEngine.fairnessScore(
            ratingA: 1000,
            ratingB: 1100,
            sport: .basketball
        )
        let largeGapScore = MatchmakingEngine.fairnessScore(
            ratingA: 1000,
            ratingB: 1500,
            sport: .basketball
        )
        #expect(largeGapScore < smallGapScore)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Suite: Fairness Across Sports
// ---------------------------------------------------------------------------

@Suite("Matchmaking — Fairness Is Sport-Aware")
struct MatchmakingCrossSportTests {

    // The same two ratings must produce the same fairness score regardless
    // of sport — because all sports share the same K-factor and thresholds.
    // This test will need revisiting if sport-specific config diverges.
    @Test("Same ratings, different sports → same fairness score (shared config)")
    func sameFairnessAcrossSports() throws {
        let basketball = MatchmakingEngine.fairnessScore(
            ratingA: 1100,
            ratingB: 1250,
            sport: .basketball
        )
        let football = MatchmakingEngine.fairnessScore(
            ratingA: 1100,
            ratingB: 1250,
            sport: .football
        )
        #expect(abs(basketball - football) < 0.0001)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Suite: Recommended Match Threshold
// ---------------------------------------------------------------------------

@Suite("Matchmaking — Recommended Match Threshold")
struct MatchmakingRecommendationTests {

    // MatchmakingEngine must expose a minimum fairness score below which
    // a match is not recommended. The exact value is TBD but must exist
    // and be in (0, 1).
    @Test("Minimum recommended fairness threshold is defined and in (0, 1)")
    func minimumThresholdIsDefined() throws {
        let threshold = MatchmakingEngine.minimumRecommendedFairness
        #expect(threshold > 0.0)
        #expect(threshold < 1.0)
    }

    // Two closely rated players should be recommended.
    @Test("Close ratings produce a recommended match")
    func closeRatingsAreRecommended() throws {
        let score = MatchmakingEngine.fairnessScore(
            ratingA: 1000,
            ratingB: 1020,
            sport: .basketball
        )
        #expect(score >= MatchmakingEngine.minimumRecommendedFairness)
    }

    // A 600-point gap should NOT be a recommended match.
    @Test("600-point gap produces a non-recommended match")
    func largeGapIsNotRecommended() throws {
        let score = MatchmakingEngine.fairnessScore(
            ratingA: 800,
            ratingB: 1400,
            sport: .basketball
        )
        #expect(score < MatchmakingEngine.minimumRecommendedFairness)
    }
}
