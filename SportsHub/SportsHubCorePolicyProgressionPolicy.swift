//
//  ProgressionPolicy.swift
//  SportsHubCore
//
//  Created by Aarush Khanna on 2/17/26.
//

/// ELO rating thresholds that determine a player's `RankTier`.
///
/// Thresholds are identical across all sports.
/// `ProgressionEngine` uses these constants to map a raw rating
/// to the correct `RankTier` case.
///
/// Tier boundaries (inclusive lower bound, exclusive upper bound):
/// - Rookie:   rating < 900
/// - Bronze:   900  ≤ rating < 1100
/// - Silver:   1100 ≤ rating < 1300
/// - Gold:     1300 ≤ rating < 1500
/// - Platinum: 1500 ≤ rating < 1700
/// - Elite:    rating ≥ 1700
public struct ProgressionPolicy: Sendable {

    public static let rookieCeiling: Double    = 900
    public static let bronzeFloor: Double      = 900
    public static let bronzeCeiling: Double    = 1100
    public static let silverFloor: Double      = 1100
    public static let silverCeiling: Double    = 1300
    public static let goldFloor: Double        = 1300
    public static let goldCeiling: Double      = 1500
    public static let platinumFloor: Double    = 1500
    public static let platinumCeiling: Double  = 1700
    public static let eliteFloor: Double       = 1700
}
