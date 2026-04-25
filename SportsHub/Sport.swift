// Sport.swift
// SportsHub
//
// Shared Sport model — used across all features: matchmaking, training, AI coach, leaderboards.
// Defined here so it isn't coupled to any specific view.

import Foundation

enum Sport: String, CaseIterable, Codable {
    case basketball = "Basketball"
    case football   = "Football"
    case soccer     = "Soccer"
    case tennis     = "Tennis"

    var icon: String {
        switch self {
        case .basketball: return "basketball.fill"
        case .football:   return "football.fill"
        case .soccer:     return "soccerball"
        case .tennis:     return "tennisball.fill"
        }
    }

    // Lowercase value for API calls (matches backend enum)
    var apiValue: String {
        return self.rawValue.lowercased()
    }
}
