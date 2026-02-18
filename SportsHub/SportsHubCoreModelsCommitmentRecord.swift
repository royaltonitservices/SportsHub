//
//  CommitmentRecord.swift
//  SportsHubCore
//
//  Created by Aarush Khanna on 2/17/26.
//

import Foundation

/// Tracks a player's commitment history for one sport.
///
/// Strikes accumulate per sport independently.
/// Cooldown is a **computed state** — there is no real timer.
/// `CommitmentEngine` derives the current penalty state from
/// `strikeCount` and `lastStrikeDate` on demand.
public struct CommitmentRecord: Sendable, Codable, Equatable {

    public let playerID: UUID
    public let sport: Sport

    /// Number of no-show strikes accumulated.
    public var strikeCount: Int

    /// When the most recent strike was recorded.
    /// `nil` if the player has no strikes.
    public var lastStrikeDate: Date?

    public init(
        playerID: UUID,
        sport: Sport,
        strikeCount: Int = 0,
        lastStrikeDate: Date? = nil
    ) {
        self.playerID = playerID
        self.sport = sport
        self.strikeCount = strikeCount
        self.lastStrikeDate = lastStrikeDate
    }
}

/// The penalty state derived from a `CommitmentRecord` at a given moment.
public enum PenaltyState: Sendable, Equatable {
    /// No restriction. Player may participate freely.
    case clear

    /// Player has one strike. Warning issued, no restriction.
    case warned

    /// Player is in a cooldown period. `until` is when it expires.
    case cooldown(until: Date)
}
