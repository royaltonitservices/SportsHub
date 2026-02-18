//
//  MatchRules.swift
//  SportsHubCore
//
//  Created by Aarush Khanna on 2/17/26.
//

/// Rules governing what constitutes a valid reported match result,
/// and shared mathematical constants used by the matchmaking system.
///
/// Phase 1 scope: result validity + fairness scale factor.
/// Score range validation and dispute resolution are stubbed here
/// for future phases.
public struct MatchRules: Sendable {

    /// A match result requires exactly two distinct players.
    public static let requiredPlayerCount: Int = 2

    /// A player cannot be both winner and loser of the same match.
    /// `ELORatingEngine` enforces this at the point of calculation.
    public static let winnerAndLoserMustDiffer: Bool = true

    /// Scale factor used in the matchmaking fairness formula:
    ///
    ///   fairness = 1 / (1 + (abs(ratingA - ratingB) / fairnessScaleFactor))
    ///
    /// Locked at 400 to align with ELO semantics:
    /// a 400-point rating gap represents a major mismatch (~91% expected win
    /// for the higher-rated player), so fairness decays proportionally
    /// on the same scale the ELO engine already uses.
    ///
    /// `MatchmakingEngine` must read this constant — never hardcode 400.
    public static let fairnessScaleFactor: Double = 400
}
