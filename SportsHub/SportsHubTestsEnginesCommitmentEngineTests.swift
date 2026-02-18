//
//  CommitmentEngineTests.swift
//  SportsHubTests
//
//  Created by Aarush Khanna on 2/17/26.
//
//  TDD — defines required behaviour of CommitmentEngine.
//  The engine does not exist yet. All tests will fail until it is implemented.
//
//  Rules under test (from PenaltyPolicy):
//    0 strikes → .clear
//    1 strike  → .warned  (no restriction)
//    2 strikes → .cooldown(until: strikeDate + 24h)
//    3 strikes → .cooldown(until: strikeDate + 72h)
//
//  Cooldown is computed state — no real timer.
//  CommitmentEngine.penaltyState(for:at:) is called with a reference date.

import Testing
import Foundation
@testable import SportsHubCore

// ---------------------------------------------------------------------------
// MARK: - Suite: Penalty State Resolution
// ---------------------------------------------------------------------------

@Suite("Commitment — Penalty State Resolution")
struct CommitmentPenaltyStateTests {

    private let playerID = UUID()
    private let sport: Sport = .basketball

    // A player with 0 strikes is clear.
    @Test("0 strikes → .clear")
    func zeroStrikesIsClear() throws {
        let record = CommitmentRecord(
            playerID: playerID,
            sport: sport,
            strikeCount: 0,
            lastStrikeDate: nil
        )
        let state = CommitmentEngine.penaltyState(for: record, at: Date())
        #expect(state == .clear)
    }

    // A player with exactly 1 strike is warned — no cooldown.
    @Test("1 strike → .warned")
    func oneStrikeIsWarned() throws {
        let record = CommitmentRecord(
            playerID: playerID,
            sport: sport,
            strikeCount: 1,
            lastStrikeDate: Date()
        )
        let state = CommitmentEngine.penaltyState(for: record, at: Date())
        #expect(state == .warned)
    }

    // 2 strikes within 24 hours → active cooldown.
    @Test("2 strikes, 12 hours elapsed → active 24-hour cooldown")
    func twoStrikesActiveCooldown() throws {
        let strikeDate = Date(timeIntervalSinceNow: -12 * 3600)  // 12 hours ago
        let record = CommitmentRecord(
            playerID: playerID,
            sport: sport,
            strikeCount: 2,
            lastStrikeDate: strikeDate
        )
        let now = Date()
        let state = CommitmentEngine.penaltyState(for: record, at: now)

        if case .cooldown(let until) = state {
            let expectedUntil = strikeDate.addingTimeInterval(PenaltyPolicy.shortCooldownDuration)
            #expect(abs(until.timeIntervalSince(expectedUntil)) < 1.0)
        } else {
            Issue.record("Expected .cooldown but got \(state)")
        }
    }

    // 2 strikes but 24+ hours have elapsed → cooldown has expired → .warned.
    // (Still has 2 strikes on record, but the cooldown window has passed.)
    @Test("2 strikes, 25 hours elapsed → cooldown expired → .warned")
    func twoStrikesExpiredCooldown() throws {
        let strikeDate = Date(timeIntervalSinceNow: -25 * 3600)  // 25 hours ago
        let record = CommitmentRecord(
            playerID: playerID,
            sport: sport,
            strikeCount: 2,
            lastStrikeDate: strikeDate
        )
        let state = CommitmentEngine.penaltyState(for: record, at: Date())
        #expect(state == .warned)
    }

    // 3 strikes within 72 hours → active 72-hour cooldown.
    @Test("3 strikes, 24 hours elapsed → active 72-hour cooldown")
    func threeStrikesActiveCooldown() throws {
        let strikeDate = Date(timeIntervalSinceNow: -24 * 3600)  // 24 hours ago
        let record = CommitmentRecord(
            playerID: playerID,
            sport: sport,
            strikeCount: 3,
            lastStrikeDate: strikeDate
        )
        let now = Date()
        let state = CommitmentEngine.penaltyState(for: record, at: now)

        if case .cooldown(let until) = state {
            let expectedUntil = strikeDate.addingTimeInterval(PenaltyPolicy.longCooldownDuration)
            #expect(abs(until.timeIntervalSince(expectedUntil)) < 1.0)
        } else {
            Issue.record("Expected .cooldown but got \(state)")
        }
    }

    // 3 strikes but 73+ hours have elapsed → cooldown expired → .warned.
    @Test("3 strikes, 73 hours elapsed → cooldown expired → .warned")
    func threeStrikesExpiredCooldown() throws {
        let strikeDate = Date(timeIntervalSinceNow: -73 * 3600)
        let record = CommitmentRecord(
            playerID: playerID,
            sport: sport,
            strikeCount: 3,
            lastStrikeDate: strikeDate
        )
        let state = CommitmentEngine.penaltyState(for: record, at: Date())
        #expect(state == .warned)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Suite: Applying a Strike
// ---------------------------------------------------------------------------

@Suite("Commitment — Applying a Strike")
struct CommitmentApplyStrikeTests {

    private let playerID = UUID()
    private let sport: Sport = .basketball

    // Applying a strike to a clean record produces strikeCount = 1.
    @Test("First strike increments count from 0 to 1")
    func firstStrikeIncrementsCount() throws {
        let record = CommitmentRecord(
            playerID: playerID,
            sport: sport,
            strikeCount: 0,
            lastStrikeDate: nil
        )
        let strikeDate = Date()
        let updated = CommitmentEngine.applyStrike(to: record, at: strikeDate)
        #expect(updated.strikeCount == 1)
    }

    // Applying a strike updates `lastStrikeDate` to the given date.
    @Test("Applying a strike sets lastStrikeDate")
    func applyStrikeSetsDate() throws {
        let record = CommitmentRecord(
            playerID: playerID,
            sport: sport,
            strikeCount: 0,
            lastStrikeDate: nil
        )
        let strikeDate = Date()
        let updated = CommitmentEngine.applyStrike(to: record, at: strikeDate)
        let lastDate = try #require(updated.lastStrikeDate)
        #expect(abs(lastDate.timeIntervalSince(strikeDate)) < 0.001)
    }

    // Applying a second strike increments count from 1 to 2.
    @Test("Second strike increments count from 1 to 2")
    func secondStrikeIncrementsCount() throws {
        let record = CommitmentRecord(
            playerID: playerID,
            sport: sport,
            strikeCount: 1,
            lastStrikeDate: Date(timeIntervalSinceNow: -3600)
        )
        let updated = CommitmentEngine.applyStrike(to: record, at: Date())
        #expect(updated.strikeCount == 2)
    }

    // Applying a third strike increments count from 2 to 3.
    @Test("Third strike increments count from 2 to 3")
    func thirdStrikeIncrementsCount() throws {
        let record = CommitmentRecord(
            playerID: playerID,
            sport: sport,
            strikeCount: 2,
            lastStrikeDate: Date(timeIntervalSinceNow: -3600)
        )
        let updated = CommitmentEngine.applyStrike(to: record, at: Date())
        #expect(updated.strikeCount == 3)
    }

    // Applying a strike must not change playerID or sport.
    @Test("Strike preserves playerID and sport")
    func strikePreservesIdentity() throws {
        let record = CommitmentRecord(
            playerID: playerID,
            sport: sport,
            strikeCount: 0,
            lastStrikeDate: nil
        )
        let updated = CommitmentEngine.applyStrike(to: record, at: Date())
        #expect(updated.playerID == playerID)
        #expect(updated.sport == sport)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Suite: Strike Independence Across Sports
// ---------------------------------------------------------------------------

@Suite("Commitment — Strikes Are Per-Sport")
struct CommitmentPerSportTests {

    private let playerID = UUID()

    // A basketball strike must not affect the football record.
    @Test("Basketball strikes do not affect football record")
    func strikesArePerSport() throws {
        let basketball = CommitmentRecord(
            playerID: playerID,
            sport: .basketball,
            strikeCount: 3,
            lastStrikeDate: Date()
        )
        let football = CommitmentRecord(
            playerID: playerID,
            sport: .football,
            strikeCount: 0,
            lastStrikeDate: nil
        )

        let bState = CommitmentEngine.penaltyState(for: basketball, at: Date())
        let fState = CommitmentEngine.penaltyState(for: football, at: Date())

        if case .cooldown = bState { } else {
            Issue.record("Basketball should be in cooldown")
        }
        #expect(fState == .clear)
    }
}
