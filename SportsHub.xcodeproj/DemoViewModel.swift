//
//  DemoViewModel.swift
//  SportsHub
//
//  Created by Aarush Khanna on 2/18/26.
//
//  Holds demo players, simulates matches, calls ELORatingEngine,
//  publishes rating updates, and maintains a match log.
//
//  Uses @Observable (Observation framework) — not ObservableObject.
//  Uses Swift Concurrency — no Combine, no DispatchQueue.

import Observation
import SportsHubCore

// ---------------------------------------------------------------------------
// MARK: - Demo Player
// ---------------------------------------------------------------------------

/// A lightweight in-memory player record for the Friday demo.
struct DemoPlayer: Identifiable {
    let id: UUID = UUID()
    var name: String
    var rating: Double
    var matchCount: Int = 0
}

// ---------------------------------------------------------------------------
// MARK: - Match Log Entry
// ---------------------------------------------------------------------------

/// One line in the on-screen match history.
struct MatchLogEntry: Identifiable {
    let id: UUID = UUID()
    let winnerName: String
    let loserName: String
    let ratingChange: Double   // points the winner gained (always > 0)
}

// ---------------------------------------------------------------------------
// MARK: - ViewModel
// ---------------------------------------------------------------------------

@Observable
@MainActor
final class DemoViewModel {

    // MARK: - State (observed by ContentView)

    /// The three demo players. Published automatically via @Observable.
    var players: [DemoPlayer] = [
        DemoPlayer(name: "Aarush", rating: SportConfig.initialRating),
        DemoPlayer(name: "Arnav",  rating: SportConfig.initialRating),
        DemoPlayer(name: "Player C", rating: SportConfig.initialRating)
    ]

    /// Last 5 match results, newest first.
    var matchLog: [MatchLogEntry] = []

    // MARK: - Match Simulation

    /// Randomly picks a winner and loser from `players`,
    /// runs the ELO engine, updates ratings, and appends to the log.
    func simulateMatch() {
        // Need at least 2 players.
        guard players.count >= 2 else { return }

        // Pick two distinct random indices.
        let firstIndex  = Int.random(in: 0..<players.count)
        var secondIndex = Int.random(in: 0..<players.count - 1)
        if secondIndex >= firstIndex { secondIndex += 1 }

        // Randomly assign winner / loser roles.
        let (winnerIndex, loserIndex): (Int, Int) = Bool.random()
            ? (firstIndex, secondIndex)
            : (secondIndex, firstIndex)

        let winner = players[winnerIndex]
        let loser  = players[loserIndex]

        // Ask the pure ELO engine for the rating delta.
        let delta = ELORatingEngine.calculateDelta(
            winnerRating:     winner.rating,
            winnerMatchCount: winner.matchCount,
            loserRating:      loser.rating,
            loserMatchCount:  loser.matchCount
        )

        // Apply results back to the players array.
        players[winnerIndex].rating      = delta.winnerNewRating
        players[winnerIndex].matchCount += 1
        players[loserIndex].rating       = delta.loserNewRating
        players[loserIndex].matchCount  += 1

        // Prepend log entry; keep only the 5 most recent.
        let entry = MatchLogEntry(
            winnerName:   winner.name,
            loserName:    loser.name,
            ratingChange: delta.winnerDelta
        )
        matchLog.insert(entry, at: 0)
        if matchLog.count > 5 { matchLog.removeLast() }
    }
}
