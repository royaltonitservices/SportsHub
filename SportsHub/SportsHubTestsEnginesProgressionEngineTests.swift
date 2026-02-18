//
//  ProgressionEngineTests.swift
//  SportsHubTests
//
//  Created by Aarush Khanna on 2/17/26.
//
//  TDD — defines required behaviour of ProgressionEngine.
//  The engine does not exist yet. All tests will fail until it is implemented.
//
//  Tier thresholds (ProgressionPolicy):
//    Rookie:    rating < 900
//    Bronze:    900  ≤ rating < 1100
//    Silver:    1100 ≤ rating < 1300
//    Gold:      1300 ≤ rating < 1500
//    Platinum:  1500 ≤ rating < 1700
//    Elite:     rating ≥ 1700

import Testing
@testable import SportsHubCore

// ---------------------------------------------------------------------------
// MARK: - Suite: Tier From Rating (Interior Values)
// ---------------------------------------------------------------------------

@Suite("Progression — Tier From Rating (Interior Values)")
struct ProgressionInteriorTests {

    @Test("Rating 500 → Rookie")
    func rating500IsRookie() throws {
        let tier = ProgressionEngine.tier(for: 500)
        #expect(tier == .rookie)
    }

    @Test("Rating 850 → Rookie")
    func rating850IsRookie() throws {
        let tier = ProgressionEngine.tier(for: 850)
        #expect(tier == .rookie)
    }

    @Test("Rating 1000 → Bronze")
    func rating1000IsBronze() throws {
        let tier = ProgressionEngine.tier(for: 1000)
        #expect(tier == .bronze)
    }

    @Test("Rating 1200 → Silver")
    func rating1200IsSilver() throws {
        let tier = ProgressionEngine.tier(for: 1200)
        #expect(tier == .silver)
    }

    @Test("Rating 1400 → Gold")
    func rating1400IsGold() throws {
        let tier = ProgressionEngine.tier(for: 1400)
        #expect(tier == .gold)
    }

    @Test("Rating 1600 → Platinum")
    func rating1600IsPlatinum() throws {
        let tier = ProgressionEngine.tier(for: 1600)
        #expect(tier == .platinum)
    }

    @Test("Rating 1800 → Elite")
    func rating1800IsElite() throws {
        let tier = ProgressionEngine.tier(for: 1800)
        #expect(tier == .elite)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Suite: Tier Boundary Values (Exact Thresholds)
// ---------------------------------------------------------------------------

@Suite("Progression — Tier Boundary Values")
struct ProgressionBoundaryTests {

    // Lower boundary of each tier (inclusive floor).

    @Test("Rating 899.9 → Rookie (just below Bronze floor)")
    func justBelowBronzeFloor() throws {
        let tier = ProgressionEngine.tier(for: 899.9)
        #expect(tier == .rookie)
    }

    @Test("Rating 900 → Bronze (exact floor)")
    func exactBronzeFloor() throws {
        let tier = ProgressionEngine.tier(for: 900)
        #expect(tier == .bronze)
    }

    @Test("Rating 1099.9 → Bronze (just below Silver floor)")
    func justBelowSilverFloor() throws {
        let tier = ProgressionEngine.tier(for: 1099.9)
        #expect(tier == .bronze)
    }

    @Test("Rating 1100 → Silver (exact floor)")
    func exactSilverFloor() throws {
        let tier = ProgressionEngine.tier(for: 1100)
        #expect(tier == .silver)
    }

    @Test("Rating 1299.9 → Silver (just below Gold floor)")
    func justBelowGoldFloor() throws {
        let tier = ProgressionEngine.tier(for: 1299.9)
        #expect(tier == .silver)
    }

    @Test("Rating 1300 → Gold (exact floor)")
    func exactGoldFloor() throws {
        let tier = ProgressionEngine.tier(for: 1300)
        #expect(tier == .gold)
    }

    @Test("Rating 1499.9 → Gold (just below Platinum floor)")
    func justBelowPlatinumFloor() throws {
        let tier = ProgressionEngine.tier(for: 1499.9)
        #expect(tier == .gold)
    }

    @Test("Rating 1500 → Platinum (exact floor)")
    func exactPlatinumFloor() throws {
        let tier = ProgressionEngine.tier(for: 1500)
        #expect(tier == .platinum)
    }

    @Test("Rating 1699.9 → Platinum (just below Elite floor)")
    func justBelowEliteFloor() throws {
        let tier = ProgressionEngine.tier(for: 1699.9)
        #expect(tier == .platinum)
    }

    @Test("Rating 1700 → Elite (exact floor)")
    func exactEliteFloor() throws {
        let tier = ProgressionEngine.tier(for: 1700)
        #expect(tier == .elite)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Suite: Initial Rating Tier
// ---------------------------------------------------------------------------

@Suite("Progression — Initial Rating Tier")
struct ProgressionInitialRatingTests {

    // A brand-new player starts at 1000 → Bronze.
    @Test("Initial rating (1000) → Bronze")
    func initialRatingIsBronze() throws {
        let tier = ProgressionEngine.tier(for: SportConfig.initialRating)
        #expect(tier == .bronze)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Suite: Tier Ordering
// ---------------------------------------------------------------------------

@Suite("Progression — Tier Ordering")
struct ProgressionTierOrderingTests {

    // Comparable conformance on RankTier must produce correct ordering.
    @Test("Rookie < Bronze < Silver < Gold < Platinum < Elite")
    func tierOrdering() throws {
        #expect(RankTier.rookie   < RankTier.bronze)
        #expect(RankTier.bronze   < RankTier.silver)
        #expect(RankTier.silver   < RankTier.gold)
        #expect(RankTier.gold     < RankTier.platinum)
        #expect(RankTier.platinum < RankTier.elite)
    }

    @Test("Elite is not less than Platinum")
    func eliteNotLessThanPlatinum() throws {
        #expect(!(RankTier.elite < RankTier.platinum))
    }

    @Test("Same tier is not less than itself")
    func sameTierIsNotLess() throws {
        #expect(!(RankTier.gold < RankTier.gold))
    }
}

// ---------------------------------------------------------------------------
// MARK: - Suite: ProgressionRecord Construction
// ---------------------------------------------------------------------------

@Suite("Progression — ProgressionRecord Construction")
struct ProgressionRecordTests {

    private let playerID = UUID()

    @Test("ProgressionEngine builds correct ProgressionRecord")
    func buildsCorrectRecord() throws {
        let rating: Double = 1350   // Gold tier
        let record = ProgressionEngine.progressionRecord(
            playerID: playerID,
            sport: .basketball,
            rating: rating
        )
        #expect(record.playerID == playerID)
        #expect(record.sport == .basketball)
        #expect(record.tier == .gold)
        #expect(abs(record.currentRating - rating) < 0.001)
    }
}
