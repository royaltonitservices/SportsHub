//
//  SportConfig.swift
//  SportsHubCore
//
//  Created by Aarush Khanna on 2/17/26.
//

/// Per-sport configuration constants consumed by the ELO engine.
///
/// All sports currently share the same values.
/// This struct exists so sport-specific tuning can be introduced
/// later without changing the engine's interface.
public struct SportConfig: Sendable {

    // MARK: - Initial Rating

    /// The ELO rating assigned to a brand-new player for any sport.
    public static let initialRating: Double = 1000

    // MARK: - K-Factor Schedule

    /// K-factor applied during a player's first 10 rated matches.
    /// High value — ratings move quickly while a player is unproven.
    public static let kFactorProvisional: Double = 40

    /// K-factor applied after a player has completed 10 rated matches.
    /// Standard value — ratings stabilise as sample size grows.
    public static let kFactorStandard: Double = 24

    /// K-factor applied when a player's rating exceeds 1600.
    /// Low value — top-rated players' ratings change slowly.
    public static let kFactorHighRated: Double = 16

    /// The match count threshold that ends the provisional K-factor period.
    public static let provisionalMatchThreshold: Int = 10

    /// The rating threshold above which the high-rated K-factor applies.
    public static let highRatedThreshold: Double = 1600

    // MARK: - ELO Formula Constants

    /// The denominator scale used in the ELO expected-score formula.
    ///
    /// Standard value is 400, meaning a player rated 400 points above
    /// their opponent has an expected score of approximately 0.909.
    ///
    /// Formula: `E(A) = 1 / (1 + 10 ^ ((ratingB - ratingA) / eloScale))`
    ///
    /// `ELORatingEngine` must read this constant — never hardcode 400.
    public static let eloScale: Double = 400

    // MARK: - K-Factor Resolution

    /// Returns the correct K-factor for a player given their current
    /// rating and number of completed rated matches.
    ///
    /// Priority order (highest wins):
    /// 1. Rating > 1600 → `kFactorHighRated` (16)
    /// 2. Match count < 10 → `kFactorProvisional` (40)
    /// 3. Otherwise → `kFactorStandard` (24)
    public static func kFactor(rating: Double, matchCount: Int) -> Double {
        if rating > highRatedThreshold {
            return kFactorHighRated
        } else if matchCount < provisionalMatchThreshold {
            return kFactorProvisional
        } else {
            return kFactorStandard
        }
    }
}
