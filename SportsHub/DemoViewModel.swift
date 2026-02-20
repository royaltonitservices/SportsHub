//
//  DemoViewModel.swift
//  SportsHub
//
//  Created by Aarush Khanna  on 2/19/26.
//

//
//  DemoViewModel.swift
//  SportsHub
//
import SwiftUI
import SportsHubCore
import Observation
//import SportsHubCore

// MARK: - Demo Player (UI projection)

struct DemoPlayer: Identifiable {
    let id: UUID
    var name: String
    var rating: Double
    var matchCount: Int
    
    var rankLabel: String {
        switch rating {
        case ..<1000: return "Rookie"
        case 1000..<1200: return "Amateur"
        case 1200..<1400: return "Pro"
        default: return "Elite"
        }
    }
}

// MARK: - Match Log Entry

struct MatchLogEntry: Identifiable {
    let id = UUID()
    let winnerName: String
    let loserName: String
    let ratingChange: Double
}

// MARK: - ViewModel

@Observable
@MainActor
final class DemoViewModel {

    private(set) var gameState: DemoAuthority.GameState = DemoAuthority.GameState()

    var matchLog: [MatchLogEntry] = []
    
    // MARK: - Player Identity (Demo Only)
    
    var currentPlayerID: UUID?
    
    var selectedSport: Sport = .basketball
    
    var currentPlayerName: String {
        players.first(where: { $0.id == currentPlayerID })?.name ?? "Select Player"
    }
    
    var currentPlayer: DemoPlayer? {
        guard let id = currentPlayerID else { return nil }
        return players.first(where: { $0.id == id })
    }
    
    var sportDisplayName: String {
        switch selectedSport {
        case .basketball: return "Basketball"
        case .football: return "Football"
        case .soccer: return "Soccer"
        case .tennis: return "Tennis"
        @unknown default:
            return "Sport"
        }
    }

    var players: [DemoPlayer] {
        gameState.players.map {
            DemoPlayer(
                id: $0.id,
                name: $0.name,
                rating: $0.rating(for: selectedSport),
                matchCount: $0.matchCount(for: selectedSport)
            )
        }
    }

    // MARK: Authority subscription

    func startListening() async {

        if gameState.players.isEmpty {
            await DemoAuthority.shared.seedPlayers()
        }

        let stream = await DemoAuthority.shared.subscribe()

        for await state in stream {
            gameState = state
        }
    }

    // MARK: Simulate Match

    func simulateMatch() {

        let current = gameState.players
        guard current.count >= 2 else { return }

        let first = Int.random(in: 0..<current.count)
        var second = Int.random(in: 0..<current.count - 1)
        if second >= first { second += 1 }

        let winner = Bool.random() ? current[first] : current[second]
        let loser  = winner.id == current[first].id ? current[second] : current[first]

        let delta = ELORatingEngine.calculateDelta(
            winnerRating: winner.rating(for: selectedSport),
            winnerMatchCount: winner.matchCount(for: selectedSport),
            loserRating: loser.rating(for: selectedSport),
            loserMatchCount: loser.matchCount(for: selectedSport)
        )

        matchLog.insert(
            MatchLogEntry(
                winnerName: winner.name,
                loserName: loser.name,
                ratingChange: delta.winnerDelta
            ),
            at: 0
        )

        if matchLog.count > 5 {
            matchLog.removeLast()
        }

        Task {
            await DemoAuthority.shared.applyMatchResult(
                winnerID: winner.id,
                loserID: loser.id,
                sport: selectedSport,
                delta: delta
            )
        }
    }
}
