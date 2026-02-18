//
//  PenaltyPolicyTests.swift
//  SportsHubTests
//
//  Created by Aarush Khanna on 2/17/26.
//
//  Validates that PenaltyPolicy constants are internally self-consistent.
//  Guards against accidental future edits to penalty constants.

import Testing
@testable import SportsHubCore

@Suite("Policy — PenaltyPolicy Consistency")
struct PenaltyPolicyTests {

    @Test("Warning strike count is 1")
    func warningStrikeCountIs1() {
        #expect(PenaltyPolicy.warningStrikeCount == 1)
    }

    @Test("Short cooldown strike count is 2")
    func shortCooldownStrikeCountIs2() {
        #expect(PenaltyPolicy.shortCooldownStrikeCount == 2)
    }

    @Test("Long cooldown strike count is 3")
    func longCooldownStrikeCountIs3() {
        #expect(PenaltyPolicy.longCooldownStrikeCount == 3)
    }

    @Test("Strike counts are in ascending order: warning < short < long")
    func strikeCountsAscending() {
        #expect(PenaltyPolicy.warningStrikeCount < PenaltyPolicy.shortCooldownStrikeCount)
        #expect(PenaltyPolicy.shortCooldownStrikeCount < PenaltyPolicy.longCooldownStrikeCount)
    }

    @Test("Short cooldown duration is 24 hours")
    func shortCooldownIs24Hours() {
        let expectedSeconds: Double = 24 * 60 * 60
        #expect(PenaltyPolicy.shortCooldownDuration == expectedSeconds)
    }

    @Test("Long cooldown duration is 72 hours")
    func longCooldownIs72Hours() {
        let expectedSeconds: Double = 72 * 60 * 60
        #expect(PenaltyPolicy.longCooldownDuration == expectedSeconds)
    }

    @Test("Long cooldown is longer than short cooldown")
    func longCooldownIsLonger() {
        #expect(PenaltyPolicy.longCooldownDuration > PenaltyPolicy.shortCooldownDuration)
    }

    @Test("Both cooldown durations are positive")
    func cooldownDurationsPositive() {
        #expect(PenaltyPolicy.shortCooldownDuration > 0)
        #expect(PenaltyPolicy.longCooldownDuration > 0)
    }
}
