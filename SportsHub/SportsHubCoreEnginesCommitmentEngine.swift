//
//  CommitmentEngine.swift
//  SportsHubCore
//
//  Created by Aarush Khanna on 2/17/26.
//
//  Pure functions. No stored state. No side effects.
//  All policy values read from PenaltyPolicy — never hardcoded here.
//
//  Rules:
//    0 strikes              → .clear
//    1 strike               → .warned
//    2 strikes, within 24h  → .cooldown(until: lastStrikeDate + 24h)
//    2 strikes, after 24h   → .warned  (cooldown expired; strike count does not decay)
//    3+ strikes, within 72h → .cooldown(until: lastStrikeDate + 72h)
//    3+ strikes, after 72h  → .warned  (cooldown expired; strike count does not decay)
//
//  Date is always injected by the caller — no internal Date() calls.

import Foundation

/// Pure commitment and penalty state engine.
///
/// Use as a namespace — all functions are static, no instances are created.
/// All policy constants come from `PenaltyPolicy`. Nothing is hardcoded here.
public enum CommitmentEngine {

    // MARK: - Penalty State Resolution

    /// Returns the current `PenaltyState` for a player given their
    /// `CommitmentRecord` and a reference date.
    ///
    /// The reference date is always provided by the caller so this
    /// function remains pure and fully testable without real time passing.
    ///
    /// Strike count never decays — an expired cooldown downgrades to
    /// `.warned`, not `.clear`.
    ///
    /// - Parameters:
    ///   - record: The player's commitment record for one sport.
    ///   - date: The point in time at which to evaluate penalty state.
    /// - Returns: The resolved `PenaltyState`.
    public static func penaltyState(for record: CommitmentRecord, at date: Date) -> PenaltyState {
        switch record.strikeCount {

        case 0:
            return .clear

        case PenaltyPolicy.warningStrikeCount:
            // 1 strike — warning only, no cooldown restriction.
            return .warned

        case PenaltyPolicy.shortCooldownStrikeCount:
            // 2 strikes — 24-hour cooldown if still within window.
            guard let lastStrikeDate = record.lastStrikeDate else {
                return .warned
            }
            let expiry = lastStrikeDate.addingTimeInterval(PenaltyPolicy.shortCooldownDuration)
            return date < expiry ? .cooldown(until: expiry) : .warned

        default:
            // 3+ strikes — 72-hour cooldown if still within window.
            guard let lastStrikeDate = record.lastStrikeDate else {
                return .warned
            }
            let expiry = lastStrikeDate.addingTimeInterval(PenaltyPolicy.longCooldownDuration)
            return date < expiry ? .cooldown(until: expiry) : .warned
        }
    }

    // MARK: - Applying a Strike

    /// Returns a new `CommitmentRecord` with one additional strike recorded
    /// at the given date.
    ///
    /// Value semantics — the original record is never mutated.
    /// `playerID` and `sport` are preserved unchanged.
    /// Strike count never decreases — this function only increments.
    ///
    /// - Parameters:
    ///   - record: The player's current commitment record for one sport.
    ///   - date: The date on which the strike is being recorded.
    /// - Returns: A new `CommitmentRecord` with `strikeCount + 1` and
    ///   `lastStrikeDate` set to `date`.
    public static func applyStrike(to record: CommitmentRecord, at date: Date) -> CommitmentRecord {
        CommitmentRecord(
            playerID: record.playerID,
            sport: record.sport,
            strikeCount: record.strikeCount + 1,
            lastStrikeDate: date
        )
    }
}
