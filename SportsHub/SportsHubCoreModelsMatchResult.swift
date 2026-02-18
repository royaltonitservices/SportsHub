//
//  MatchResult.swift
//  SportsHubCore
//
//  Created by Aarush Khanna on 2/17/26.
//

import Foundation

/// The outcome of a completed match between two players.
///
/// `winnerID` and `loserID` identify which player won and lost.
/// `sport` determines which rating track is updated.
/// `playedAt` is set by the caller — demo uses a fixed or injected date.
public struct MatchResult: Sendable, Codable, Equatable {

    public let winnerID: UUID
    public let loserID: UUID
    public let sport: Sport
    public let playedAt: Date

    public init(
        winnerID: UUID,
        loserID: UUID,
        sport: Sport,
        playedAt: Date = Date()
    ) {
        self.winnerID = winnerID
        self.loserID = loserID
        self.sport = sport
        self.playedAt = playedAt
    }
}
