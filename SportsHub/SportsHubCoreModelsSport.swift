//
//  Sport.swift
//  SportsHubCore
//
//  Created by Aarush Khanna on 2/17/26.
//

/// The sports supported by SportsHub.
/// Each sport uses the same ELO algorithm and rank tier thresholds,
/// but carries its own configuration (K-factor schedule, rating floor)
/// via `SportConfig`.
public enum Sport: String, CaseIterable, Sendable, Codable {
    case basketball
    case football
    case soccer
    case tennis
}
