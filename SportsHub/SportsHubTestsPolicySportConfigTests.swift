//
//  SportConfigTests.swift
//  SportsHubTests
//
//  Created by Aarush Khanna on 2/17/26.
//
//  Validates that SportConfig constants are internally self-consistent.
//  These tests do not test engine logic — they guard the policy values
//  themselves so a future accidental edit is caught immediately.

import Testing
@testable import SportsHubCore

@Suite("Policy — SportConfig Consistency")
struct SportConfigTests {

    @Test("Initial rating is 1000")
    func initialRatingIs1000() {
        #expect(SportConfig.initialRating == 1000)
    }

    @Test("Provisional K-factor is 40")
    func provisionalKIs40() {
        #expect(SportConfig.kFactorProvisional == 40)
    }

    @Test("Standard K-factor is 24")
    func standardKIs24() {
        #expect(SportConfig.kFactorStandard == 24)
    }

    @Test("High-rated K-factor is 16")
    func highRatedKIs16() {
        #expect(SportConfig.kFactorHighRated == 16)
    }

    @Test("K-factors are in descending order: provisional > standard > high-rated")
    func kFactorsDescendingOrder() {
        #expect(SportConfig.kFactorProvisional > SportConfig.kFactorStandard)
        #expect(SportConfig.kFactorStandard > SportConfig.kFactorHighRated)
    }

    @Test("Provisional match threshold is 10")
    func provisionalThresholdIs10() {
        #expect(SportConfig.provisionalMatchThreshold == 10)
    }

    @Test("High-rated threshold is 1600")
    func highRatedThresholdIs1600() {
        #expect(SportConfig.highRatedThreshold == 1600)
    }

    @Test("High-rated threshold is above initial rating")
    func highRatedThresholdAboveInitial() {
        #expect(SportConfig.highRatedThreshold > SportConfig.initialRating)
    }

    @Test("All K-factors are positive")
    func allKFactorsPositive() {
        #expect(SportConfig.kFactorProvisional > 0)
        #expect(SportConfig.kFactorStandard > 0)
        #expect(SportConfig.kFactorHighRated > 0)
    }
}
