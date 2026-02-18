//
//  Player.swift
//  SportsHubCore
//
//  Created by Aarush Khanna on 2/17/26.
//

import Foundation

/// A player participating in SportsHub.
///
/// `ratings` holds the player's current ELO rating for each sport.
/// `matchCounts` tracks how many rated matches the player has completed
/// per sport — used by the K-factor schedule.
public struct Player: Identifiable, Sendable, Codable, Equatable {

    public let id: UUID
    public var name: String

    /// Current ELO rating per sport. Defaults to `SportConfig.initialRating`
    /// (1000) when a player has not yet played a sport.
    public var ratings: [Sport: Double]

    /// Number of rated matches completed per sport.
    /// Used to determine which K-factor bracket applies.
    public var matchCounts: [Sport: Int]

    public init(
        id: UUID = UUID(),
        name: String,
        ratings: [Sport: Double] = [:],
        matchCounts: [Sport: Int] = [:]
    ) {
        self.id = id
        self.name = name
        self.ratings = ratings
        self.matchCounts = matchCounts
    }

    /// Returns the player's current ELO rating for the given sport,
    /// or the initial rating (1000) if they have not yet played.
    public func rating(for sport: Sport) -> Double {
        ratings[sport] ?? SportConfig.initialRating
    }

    /// Returns the number of rated matches completed for the given sport.
    public func matchCount(for sport: Sport) -> Int {
        matchCounts[sport] ?? 0
    }
}
