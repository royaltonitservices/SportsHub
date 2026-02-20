//
//  DemoAuthority.swift
//  SportsHub
//
//  Created by Aarush Khanna  on 2/19/26.
//

import Foundation

public actor DemoAuthority {

    // MARK: - Singleton

    public static let shared = DemoAuthority()
    private init() {}

    // MARK: - Game State

    public struct GameState: Sendable, Codable {
        public var players: [Player] = []
        public var matches: [MatchResult] = []
        // empty initializer
        public init() {
            self.players = []
            self.matches = []
        }

        // initializer used by currentState()
        public init(players: [Player], matches: [MatchResult]) {
            self.players = players
            self.matches = matches
        }
    }

    private var players: [Player] = []
    private var matches: [MatchResult] = []

    // MARK: - Subscriptions

    private var continuations:
        [UUID: AsyncStream<GameState>.Continuation] = [:]

    public func subscribe() -> AsyncStream<GameState> {
        let id = UUID()

        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(currentState())

            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func publish() {
        let state = currentState()
        continuations.values.forEach { $0.yield(state) }
    }

    private func currentState() -> GameState {
        GameState(players: players, matches: matches)
    }

    // MARK: - Seed Players

    public func seedPlayers() {
        guard players.isEmpty else { return }

        players = [
            Player(name: "Aarush Khanna"),
            Player(name: "Manav Sundar"),
            //Player(name: "Player C")
        ]

        publish()
    }

    // MARK: - Apply Match

    public func applyMatchResult(
        winnerID: UUID,
        loserID: UUID,
        sport: Sport,
        delta: ELORatingDelta
    ) {
        guard
            let wi = players.firstIndex(where: { $0.id == winnerID }),
            let li = players.firstIndex(where: { $0.id == loserID })
        else { return }

        players[wi].ratings[sport] = delta.winnerNewRating
        players[wi].matchCounts[sport, default: 0] += 1

        players[li].ratings[sport] = delta.loserNewRating
        players[li].matchCounts[sport, default: 0] += 1

        matches.append(
            MatchResult(
                winnerID: winnerID,
                loserID: loserID,
                sport: sport
            )
        )

        publish()
    }
}
