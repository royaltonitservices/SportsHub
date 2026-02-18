//
//  PenaltyPolicy.swift
//  SportsHubCore
//
//  Created by Aarush Khanna on 2/17/26.
//

import Foundation

/// Constants governing how no-show strikes accumulate and
/// how long cooldown periods last.
///
/// Strikes are tracked per player per sport.
/// Cooldowns are computed state — no real timers involved.
public struct PenaltyPolicy: Sendable {

    // MARK: - Strike Thresholds

    /// A player with exactly this many strikes receives a warning.
    /// No participation restriction is applied.
    public static let warningStrikeCount: Int = 1

    /// A player with this many strikes enters a 24-hour cooldown.
    public static let shortCooldownStrikeCount: Int = 2

    /// A player with this many strikes enters a 72-hour cooldown.
    public static let longCooldownStrikeCount: Int = 3

    // MARK: - Cooldown Durations

    /// Duration of the cooldown triggered at `shortCooldownStrikeCount`.
    public static let shortCooldownDuration: TimeInterval = 24 * 60 * 60   // 24 hours

    /// Duration of the cooldown triggered at `longCooldownStrikeCount`.
    public static let longCooldownDuration: TimeInterval = 72 * 60 * 60    // 72 hours
}
