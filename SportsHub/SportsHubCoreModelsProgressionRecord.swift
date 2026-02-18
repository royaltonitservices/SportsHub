//
//  ProgressionRecord.swift
//  SportsHubCore
//
//  Created by Aarush Khanna on 2/17/26.
//

import Foundation

/// A player's current rank tier and unlock state for one sport.
///
/// `RankTier` is computed by `ProgressionEngine` from the player's
/// current ELO rating. This struct holds the resolved result so
/// ViewModels and UI do not need to repeat the calculation.
public struct ProgressionRecord: Sendable, Codable, Equatable {

    public let playerID: UUID
    public let sport: Sport
    public let tier: RankTier
    public let currentRating: Double

    public init(
        playerID: UUID,
        sport: Sport,
        tier: RankTier,
        currentRating: Double
    ) {
        self.playerID = playerID
        self.sport = sport
        self.tier = tier
        self.currentRating = currentRating
    }
}

/// Rank tiers awarded based on ELO rating thresholds.
///
/// Thresholds (same across all sports):
/// - Rookie:   < 900
/// - Bronze:   900 – 1099
/// - Silver:   1100 – 1299
/// - Gold:     1300 – 1499
/// - Platinum: 1500 – 1699
/// - Elite:    1700+
public enum RankTier: String, CaseIterable, Sendable, Codable, Comparable {
    case rookie
    case bronze
    case silver
    case gold
    case platinum
    case elite

    // Comparable conformance — higher ordinal = higher tier.
    public static func < (lhs: RankTier, rhs: RankTier) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    private var ordinal: Int {
        switch self {
        case .rookie:   return 0
        case .bronze:   return 1
        case .silver:   return 2
        case .gold:     return 3
        case .platinum: return 4
        case .elite:    return 5
        }
    }
}
