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

/// A lightweight view-facing projection of a Player from GameState.
struct DemoPlayer: Identifiable {
    let id: UUID          // stable — mirrors Player.id from authority
    var name: String
    var rating: Double
    var matchCount: Int
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

    /// Latest authoritative snapshot from DemoAuthority.
    /// Updated on every publish — never mutated directly.
    private(set) var gameState: GameState = GameState()

    /// Last 5 match results, newest first.
    /// Maintained locally — GameState carries raw MatchResults,
    /// this is the display-ready projection for the match log section.
    var matchLog: [MatchLogEntry] = []

    /// View-facing player list derived from the latest GameState.
    /// Uses basketball rating as the primary display value.
    var players: [DemoPlayer] {
        gameState.players.map { player in
            DemoPlayer(
                id:         player.id,
                name:       player.name,
                rating:     player.rating(for: .basketball),
                matchCount: player.matchCount(for: .basketball)
            )
        }
    }

    // MARK: - Authority Subscription

    /// Seeds DemoAuthority (only if empty), then subscribes and listens
    /// for all state changes. Call once from ContentView's .task modifier
    /// — runs for the view's lifetime. Safe to re-enter after SwiftUI
    /// task restarts because seeding is skipped when players already exist.
    func startListening() async {
        let initialState = await DemoAuthority.shared.subscribe()

        // Seed only when the authority has no players yet.
        // Prevents reseeding if SwiftUI restarts the task.
        if gameState.players.isEmpty {
            await DemoAuthority.shared.seedPlayers()
        }

        for await state in initialState {
            gameState = state
        }
    }

    // MARK: - Match Simulation

    /// Picks a random winner and loser from GameState players,
    /// computes ELO delta, and pushes the result to DemoAuthority.
    /// Never mutates local state — authority publishes the update back.
    func simulateMatch() {
        let current = gameState.players
        guard current.count >= 2 else { return }

        let firstIndex  = Int.random(in: 0..<current.count)
        var secondIndex = Int.random(in: 0..<current.count - 1)
        if secondIndex >= firstIndex { secondIndex += 1 }

        let (winnerIndex, loserIndex): (Int, Int) = Bool.random()
            ? (firstIndex, secondIndex)
            : (secondIndex, firstIndex)

        let winner = current[winnerIndex]
        let loser  = current[loserIndex]

        let delta = ELORatingEngine.calculateDelta(
            winnerRating:     winner.rating(for: .basketball),
            winnerMatchCount: winner.matchCount(for: .basketball),
            loserRating:      loser.rating(for: .basketball),
            loserMatchCount:  loser.matchCount(for: .basketball)
        )

        let entry = MatchLogEntry(
            winnerName:   winner.name,
            loserName:    loser.name,
            ratingChange: delta.winnerDelta
        )
        matchLog.insert(entry, at: 0)
        if matchLog.count > 5 { matchLog.removeLast() }

        Task {
            await DemoAuthority.shared.applyMatchResult(
                winnerID: winner.id,
                loserID:  loser.id,
                sport:    .basketball,
                delta:    delta
            )
        }
    }
}
