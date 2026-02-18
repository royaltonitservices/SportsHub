//
//  ELORatingEngine.swift
//  SportsHubCore
//
//  Created by Aarush Khanna on 2/17/26.
//
//  Pure functions. No stored state. No side effects.
//  All policy values read from SportConfig — never hardcoded here.
//
//  ELO formula:
//    Expected score for player A:
//      E(A) = 1 / (1 + 10 ^ ((ratingB - ratingA) / SportConfig.eloScale))
//
//    New rating after result:
//      R'(player) = R(player) + K * (score - E(player))
//      where score = 1.0 (win) or 0.0 (loss)
//
//  K-factor is resolved independently per player via SportConfig.kFactor(rating:matchCount:).

import Foundation

// ---------------------------------------------------------------------------
// MARK: - Output Type
// ---------------------------------------------------------------------------

/// The result of processing one match through the ELO rating engine.
///
/// Both players' deltas and resulting ratings are returned together
/// so callers never need to call the engine twice for the same match.
public struct ELORatingDelta: Sendable, Equatable {

    /// Points added to the winner's rating. Always > 0.
    public let winnerDelta: Double

    /// Points added to the loser's rating. Always < 0.
    public let loserDelta: Double

    /// Winner's updated rating: `winnerRating + winnerDelta`.
    public let winnerNewRating: Double

    /// Loser's updated rating: `loserRating + loserDelta`.
    public let loserNewRating: Double
}

// ---------------------------------------------------------------------------
// MARK: - Engine
// ---------------------------------------------------------------------------

/// Pure ELO rating calculation engine.
///
/// Use as a namespace — all functions are static, no instances are created.
/// All policy constants come from `SportConfig`. Nothing is hardcoded here.
public enum ELORatingEngine {

    // MARK: - Expected Score

    /// Returns the expected score (probability of winning) for player A
    /// given the two players' current ratings.
    ///
    /// Formula: `E(A) = 1 / (1 + 10 ^ ((ratingB - ratingA) / eloScale))`
    /// Scale factor is read from `SportConfig.eloScale` (400).
    ///
    /// - Returns: A value in (0, 1). Equal ratings → 0.5.
    public static func expectedScore(ratingA: Double, ratingB: Double) -> Double {
        1.0 / (1.0 + pow(10.0, (ratingB - ratingA) / SportConfig.eloScale))
    }

    // MARK: - Delta Calculation

    /// Calculates the rating change for both players after a match result.
    ///
    /// Each player's K-factor is resolved independently from their own
    /// rating and match count via `SportConfig.kFactor(rating:matchCount:)`.
    ///
    /// - Parameters:
    ///   - winnerRating: The winner's current ELO rating.
    ///   - winnerMatchCount: Number of rated matches the winner has completed.
    ///   - loserRating: The loser's current ELO rating.
    ///   - loserMatchCount: Number of rated matches the loser has completed.
    /// - Returns: An `ELORatingDelta` containing each player's delta and new rating.
    public static func calculateDelta(
        winnerRating: Double,
        winnerMatchCount: Int,
        loserRating: Double,
        loserMatchCount: Int
    ) -> ELORatingDelta {

        // Resolve each player's K-factor independently.
        let kWinner = SportConfig.kFactor(rating: winnerRating, matchCount: winnerMatchCount)
        let kLoser  = SportConfig.kFactor(rating: loserRating,  matchCount: loserMatchCount)

        // Expected scores from each player's perspective.
        let expectedWinner = expectedScore(ratingA: winnerRating, ratingB: loserRating)
        let expectedLoser  = expectedScore(ratingA: loserRating,  ratingB: winnerRating)

        // Rating changes.
        // Winner score = 1.0, loser score = 0.0.
        let winnerDelta = kWinner * (1.0 - expectedWinner)
        let loserDelta  = kLoser  * (0.0 - expectedLoser)

        return ELORatingDelta(
            winnerDelta:    winnerDelta,
            loserDelta:     loserDelta,
            winnerNewRating: winnerRating + winnerDelta,
            loserNewRating:  loserRating  + loserDelta
        )
    }
}
