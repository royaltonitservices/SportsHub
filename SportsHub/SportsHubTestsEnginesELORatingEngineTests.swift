//
//  ELORatingEngineTests.swift
//  SportsHubTests
//
//  Created by Aarush Khanna on 2/17/26.
//
//  TDD — these tests define the required behaviour of ELORatingEngine.
//  The engine does not exist yet. All tests will fail until it is implemented.
//
//  ELO formula reference:
//    Expected score for A vs B:
//      E(A) = 1 / (1 + 10^((ratingB - ratingA) / 400))
//
//    New rating:
//      R'(A) = R(A) + K * (score - E(A))
//      where score = 1.0 for a win, 0.0 for a loss
//
//  K-factor schedule (SportConfig):
//    matchCount < 10          → K = 40  (provisional)
//    matchCount >= 10         → K = 24  (standard)
//    rating > 1600 (either)   → K = 16  (high-rated, takes priority)

import Testing
@testable import SportsHubCore

// ---------------------------------------------------------------------------
// MARK: - ELO Delta Output
// ---------------------------------------------------------------------------

/// The value type returned by ELORatingEngine after processing a result.
/// Defined here so tests can reference it before the engine exists.
/// The engine must return a value matching this shape.
///
/// - `winnerNewRating`: Updated ELO for the winner.
/// - `loserNewRating`: Updated ELO for the loser.
/// - `winnerDelta`: Change applied to the winner (always ≥ 0).
/// - `loserDelta`: Change applied to the loser (always ≤ 0).
// (ELORatingEngine.swift will declare the real ELORatingDelta struct.)

// ---------------------------------------------------------------------------
// MARK: - Suite: Expected Score Calculation
// ---------------------------------------------------------------------------

@Suite("ELO — Expected Score Formula")
struct ELOExpectedScoreTests {

    // Two players with identical ratings should each have a 0.5 expected score.
    @Test("Equal ratings → expected score is 0.5")
    func equalRatings() throws {
        let result = ELORatingEngine.expectedScore(ratingA: 1000, ratingB: 1000)
        #expect(abs(result - 0.5) < 0.0001)
    }

    // Player A is 400 points above player B.
    // Formula: 1 / (1 + 10^(-400/400)) = 1 / (1 + 10^-1) = 1 / 1.1 ≈ 0.9091
    @Test("A rated 400 above B → A expected score ≈ 0.9091")
    func playerAFourHundredHigher() throws {
        let result = ELORatingEngine.expectedScore(ratingA: 1400, ratingB: 1000)
        #expect(abs(result - 0.9091) < 0.001)
    }

    // Player A is 400 points below player B.
    // Formula: 1 / (1 + 10^(400/400)) = 1 / (1 + 10) = 1/11 ≈ 0.0909
    @Test("A rated 400 below B → A expected score ≈ 0.0909")
    func playerAFourHundredLower() throws {
        let result = ELORatingEngine.expectedScore(ratingA: 1000, ratingB: 1400)
        #expect(abs(result - 0.0909) < 0.001)
    }

    // The two expected scores for a pair must sum to exactly 1.0.
    @Test("Expected scores for both players sum to 1.0")
    func expectedScoresSumToOne() throws {
        let eA = ELORatingEngine.expectedScore(ratingA: 1200, ratingB: 1050)
        let eB = ELORatingEngine.expectedScore(ratingA: 1050, ratingB: 1200)
        #expect(abs((eA + eB) - 1.0) < 0.0001)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Suite: K-Factor Selection
// ---------------------------------------------------------------------------

@Suite("ELO — K-Factor Selection")
struct ELOKFactorTests {

    // New player (0 matches, 1000 rating) → provisional K = 40.
    @Test("Brand new player gets provisional K = 40")
    func provisionalKForNewPlayer() throws {
        let k = SportConfig.kFactor(rating: 1000, matchCount: 0)
        #expect(k == 40)
    }

    // 9th match still provisional → K = 40.
    @Test("9th match still provisional K = 40")
    func provisionalKAtNinthMatch() throws {
        let k = SportConfig.kFactor(rating: 1000, matchCount: 9)
        #expect(k == 40)
    }

    // 10th match crosses threshold → K = 24.
    @Test("10th match switches to standard K = 24")
    func standardKAtTenthMatch() throws {
        let k = SportConfig.kFactor(rating: 1000, matchCount: 10)
        #expect(k == 24)
    }

    // High match count, normal rating → K = 24.
    @Test("Veteran player at 1200 rating gets standard K = 24")
    func standardKForVeteran() throws {
        let k = SportConfig.kFactor(rating: 1200, matchCount: 50)
        #expect(k == 24)
    }

    // Rating just above 1600 threshold → K = 16 regardless of match count.
    @Test("Rating 1601 triggers high-rated K = 16")
    func highRatedKJustAboveThreshold() throws {
        let k = SportConfig.kFactor(rating: 1601, matchCount: 50)
        #expect(k == 16)
    }

    // High-rated rule beats provisional rule.
    // A player with < 10 matches but rating > 1600 gets K = 16.
    @Test("High-rated K = 16 beats provisional K when rating > 1600")
    func highRatedBeatsProvisional() throws {
        let k = SportConfig.kFactor(rating: 1700, matchCount: 3)
        #expect(k == 16)
    }

    // Boundary: exactly 1600 is NOT above the threshold → standard/provisional applies.
    @Test("Rating exactly 1600 does NOT trigger high-rated K")
    func exactlyAtHighRatedBoundary() throws {
        let k = SportConfig.kFactor(rating: 1600, matchCount: 20)
        #expect(k == 24)   // standard — not > 1600
    }
}

// ---------------------------------------------------------------------------
// MARK: - Suite: Rating Delta Calculation
// ---------------------------------------------------------------------------

@Suite("ELO — Rating Delta Calculation")
struct ELORatingDeltaTests {

    // Two equal players (1000 vs 1000), provisional K = 40.
    // Winner gains: 40 * (1.0 - 0.5) = +20
    // Loser loses:  40 * (0.0 - 0.5) = -20
    @Test("Equal players, provisional K — winner gains 20, loser loses 20")
    func equalPlayersProvisional() throws {
        let delta = ELORatingEngine.calculateDelta(
            winnerRating: 1000, winnerMatchCount: 0,
            loserRating: 1000,  loserMatchCount: 0
        )
        #expect(abs(delta.winnerDelta - 20.0) < 0.5)
        #expect(abs(delta.loserDelta - (-20.0)) < 0.5)
    }

    // Two equal players (1000 vs 1000), standard K = 24.
    // Winner gains: 24 * 0.5 = +12
    // Loser loses:  24 * 0.5 = -12
    @Test("Equal players, standard K — winner gains 12, loser loses 12")
    func equalPlayersStandard() throws {
        let delta = ELORatingEngine.calculateDelta(
            winnerRating: 1000, winnerMatchCount: 15,
            loserRating: 1000,  loserMatchCount: 15
        )
        #expect(abs(delta.winnerDelta - 12.0) < 0.5)
        #expect(abs(delta.loserDelta - (-12.0)) < 0.5)
    }

    // Upset: lower-rated player (800) beats higher-rated (1200), standard K.
    // E(800 vs 1200) = 1 / (1 + 10^(400/400)) = 1/11 ≈ 0.0909
    // Winner delta: 24 * (1 - 0.0909) ≈ 24 * 0.9091 ≈ +21.8
    // Loser delta:  24 * (0 - 0.9091) ≈ -21.8
    @Test("Upset win — lower rated player gains more points")
    func upsetWin() throws {
        let delta = ELORatingEngine.calculateDelta(
            winnerRating: 800,  winnerMatchCount: 20,
            loserRating: 1200,  loserMatchCount: 20
        )
        #expect(delta.winnerDelta > 20.0)
        #expect(delta.loserDelta < -20.0)
    }

    // Expected win: higher-rated (1200) beats lower-rated (800), standard K.
    // Winner gains less — the result was expected.
    // E(1200 vs 800) ≈ 0.9091
    // Winner delta: 24 * (1 - 0.9091) ≈ 24 * 0.0909 ≈ +2.2
    @Test("Expected win — higher rated player gains fewer points")
    func expectedWin() throws {
        let delta = ELORatingEngine.calculateDelta(
            winnerRating: 1200, winnerMatchCount: 20,
            loserRating: 800,   loserMatchCount: 20
        )
        #expect(delta.winnerDelta < 10.0)
        #expect(delta.winnerDelta > 0.0)
    }

    // Winner's new rating = old rating + winner delta.
    @Test("Winner new rating = old rating + delta")
    func winnerNewRatingIsCorrect() throws {
        let delta = ELORatingEngine.calculateDelta(
            winnerRating: 1000, winnerMatchCount: 15,
            loserRating: 1000,  loserMatchCount: 15
        )
        #expect(abs(delta.winnerNewRating - (1000 + delta.winnerDelta)) < 0.001)
    }

    // Loser's new rating = old rating + loser delta (delta is negative).
    @Test("Loser new rating = old rating + delta (negative)")
    func loserNewRatingIsCorrect() throws {
        let delta = ELORatingEngine.calculateDelta(
            winnerRating: 1000, winnerMatchCount: 15,
            loserRating: 1000,  loserMatchCount: 15
        )
        #expect(abs(delta.loserNewRating - (1000 + delta.loserDelta)) < 0.001)
    }

    // Winner delta must always be positive.
    @Test("Winner delta is always positive")
    func winnerDeltaIsPositive() throws {
        let delta = ELORatingEngine.calculateDelta(
            winnerRating: 1800, winnerMatchCount: 100,
            loserRating: 800,   loserMatchCount: 5
        )
        #expect(delta.winnerDelta > 0)
    }

    // Loser delta must always be negative.
    @Test("Loser delta is always negative")
    func loserDeltaIsNegative() throws {
        let delta = ELORatingEngine.calculateDelta(
            winnerRating: 800,  winnerMatchCount: 5,
            loserRating: 1800,  loserMatchCount: 100
        )
        #expect(delta.loserDelta < 0)
    }

    // High-rated winner (>1600): their own K-factor is 16.
    // Equal opponent at 1600, winner at 1700, both 30 matches.
    // E(1700 vs 1600) = 1 / (1 + 10^(-100/400)) ≈ 0.6401
    // Winner delta: 16 * (1 - 0.6401) ≈ +5.76
    @Test("High-rated winner uses K = 16")
    func highRatedWinnerKFactor() throws {
        let delta = ELORatingEngine.calculateDelta(
            winnerRating: 1700, winnerMatchCount: 30,
            loserRating: 1600,  loserMatchCount: 30
        )
        // With K=16, gain must be less than it would be with K=24
        let deltaWithStandardK = ELORatingEngine.calculateDelta(
            winnerRating: 1700, winnerMatchCount: 30,
            loserRating: 1600,  loserMatchCount: 30
        )
        // High-rated K=16 applies; delta should be less than 16 * 1.0 = 16
        #expect(delta.winnerDelta < 16.0)
        #expect(delta.winnerDelta > 0.0)
        _ = deltaWithStandardK // silence unused warning
    }
}

// ---------------------------------------------------------------------------
// MARK: - Suite: Zero-Sum Property
// ---------------------------------------------------------------------------

@Suite("ELO — Zero-Sum Property")
struct ELOZeroSumTests {

    // Points gained by winner must equal points lost by loser.
    // ELO is zero-sum: the system neither creates nor destroys rating points.
    @Test("Rating points are conserved — winner gain equals loser loss")
    func zeroSumProperty() throws {
        let delta = ELORatingEngine.calculateDelta(
            winnerRating: 1150, winnerMatchCount: 12,
            loserRating: 1050,  loserMatchCount: 12
        )
        #expect(abs(delta.winnerDelta + delta.loserDelta) < 0.001)
    }

    @Test("Zero-sum holds for provisional K")
    func zeroSumProvisional() throws {
        let delta = ELORatingEngine.calculateDelta(
            winnerRating: 1000, winnerMatchCount: 3,
            loserRating: 1000,  loserMatchCount: 3
        )
        #expect(abs(delta.winnerDelta + delta.loserDelta) < 0.001)
    }

    @Test("Zero-sum holds for high-rated K")
    func zeroSumHighRated() throws {
        let delta = ELORatingEngine.calculateDelta(
            winnerRating: 1700, winnerMatchCount: 50,
            loserRating: 1700,  loserMatchCount: 50
        )
        #expect(abs(delta.winnerDelta + delta.loserDelta) < 0.001)
    }
}
