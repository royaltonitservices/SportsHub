//
//  RatingRecord.swift
//  SportsHubCore
//
//  Created by Aarush Khanna on 2/17/26.
//

import Foundation

/// A snapshot of a player's ELO rating for one sport at a point in time.
///
/// The ELO engine returns a `RatingDelta` (not this type directly).
/// `RatingRecord` is used when storing historical snapshots or
/// initialising player state.
public struct RatingRecord: Sendable, Codable, Equatable {

    public let playerID: UUID
    public let sport: Sport
    public let rating: Double
    public let matchCount: Int
    public let recordedAt: Date

    public init(
        playerID: UUID,
        sport: Sport,
        rating: Double,
        matchCount: Int,
        recordedAt: Date = Date()
    ) {
        self.playerID = playerID
        self.sport = sport
        self.rating = rating
        self.matchCount = matchCount
        self.recordedAt = recordedAt
    }
}
