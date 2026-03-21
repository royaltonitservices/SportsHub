//
//  MockData.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import Foundation

// MARK: - User Models

struct MockUser: Identifiable {
    let id = UUID()
    let name: String
    let username: String
    let bio: String
    let gamesPlayed: Int
    let wins: Int
    let rating: Int
    let bestStreak: Int
    let hoursTrained: Int
}

// MARK: - Post Models

struct MockPost: Identifiable {
    let id = UUID()
    let author: MockUser
    let content: String
    let timestamp: Date
    let likes: Int
    let comments: Int
}

// MARK: - Clip Models

struct MockClip: Identifiable {
    let id = UUID()
    let author: MockUser
    let title: String
    let duration: Int // seconds
    let views: Int
    let likes: Int
    let thumbnailGradient: [String] // hex colors
}

// MARK: - Match Models

struct MockMatch: Identifiable {
    let id = UUID()
    let opponent: MockUser
    let result: MatchResult
    let score: String
    let date: Date
}

enum MatchResult {
    case win
    case loss
}

// MARK: - Drill Models

struct MockDrill: Identifiable {
    let id = UUID()
    let name: String
    let category: DrillCategory
    let difficulty: Difficulty
    let duration: Int // minutes
}

enum DrillCategory: String, CaseIterable {
    case speed = "Speed"
    case power = "Power"
    case accuracy = "Accuracy"
    case endurance = "Endurance"
    case agility = "Agility"
    case technique = "Technique"
    
    var icon: String {
        switch self {
        case .speed: return "bolt.fill"
        case .power: return "flame.fill"
        case .accuracy: return "scope"
        case .endurance: return "heart.fill"
        case .agility: return "figure.run"
        case .technique: return "star.fill"
        }
    }
}

enum Difficulty: String {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
}

// MARK: - Mock Data Repository

struct MockData {
    
    // MARK: - Users
    
    static let currentUser = MockUser(
        name: "Jordan Hayes",
        username: "jhayes",
        bio: "Competitive athlete | Always improving",
        gamesPlayed: 127,
        wins: 84,
        rating: 1847,
        bestStreak: 7,
        hoursTrained: 142
    )
    
    static let users: [MockUser] = [
        MockUser(
            name: "Alex Rivera",
            username: "arivera",
            bio: "Weekend warrior",
            gamesPlayed: 89,
            wins: 52,
            rating: 1654,
            bestStreak: 5,
            hoursTrained: 67
        ),
        MockUser(
            name: "Morgan Chen",
            username: "mchen",
            bio: "Training hard every day",
            gamesPlayed: 156,
            wins: 98,
            rating: 1923,
            bestStreak: 9,
            hoursTrained: 203
        ),
        MockUser(
            name: "Taylor Kim",
            username: "tkim",
            bio: "Just here to have fun",
            gamesPlayed: 43,
            wins: 21,
            rating: 1432,
            bestStreak: 3,
            hoursTrained: 28
        ),
        MockUser(
            name: "Casey Johnson",
            username: "cjohnson",
            bio: "Competitive mindset",
            gamesPlayed: 201,
            wins: 134,
            rating: 2041,
            bestStreak: 12,
            hoursTrained: 287
        ),
        MockUser(
            name: "Jordan Martinez",
            username: "jmart",
            bio: "Always learning",
            gamesPlayed: 67,
            wins: 38,
            rating: 1567,
            bestStreak: 4,
            hoursTrained: 52
        ),
        MockUser(
            name: "Riley Patel",
            username: "rpatel",
            bio: "Love the game",
            gamesPlayed: 112,
            wins: 71,
            rating: 1789,
            bestStreak: 6,
            hoursTrained: 118
        )
    ]
    
    // MARK: - Posts
    
    static let posts: [MockPost] = [
        MockPost(
            author: users[0],
            content: "Just finished an intense training session - new personal record on sprint drills! Feeling stronger every day.",
            timestamp: Date().addingTimeInterval(-7200),
            likes: 23,
            comments: 5
        ),
        MockPost(
            author: users[1],
            content: "Looking for a doubles partner for this weekend's tournament. Who's in? Let me know!",
            timestamp: Date().addingTimeInterval(-14400),
            likes: 12,
            comments: 8
        ),
        MockPost(
            author: users[2],
            content: "That match was absolutely intense! Great game @arivera - you really pushed me to my limits.",
            timestamp: Date().addingTimeInterval(-21600),
            likes: 45,
            comments: 11
        ),
        MockPost(
            author: users[3],
            content: "New training program starts tomorrow. Let's stay consistent and put in the work!",
            timestamp: Date().addingTimeInterval(-28800),
            likes: 34,
            comments: 6
        ),
        MockPost(
            author: users[4],
            content: "Anyone else struggling with accuracy drills? Looking for tips and advice.",
            timestamp: Date().addingTimeInterval(-43200),
            likes: 18,
            comments: 14
        ),
        MockPost(
            author: users[5],
            content: "Finally broke into the top 100 rankings! Hard work really does pay off.",
            timestamp: Date().addingTimeInterval(-86400),
            likes: 67,
            comments: 22
        ),
        MockPost(
            author: users[0],
            content: "Morning workout complete. Nothing beats starting the day with a solid training session.",
            timestamp: Date().addingTimeInterval(-129600),
            likes: 29,
            comments: 4
        )
    ]
    
    // MARK: - Clips
    
    static let clips: [MockClip] = [
        MockClip(
            author: users[1],
            title: "Amazing comeback point",
            duration: 15,
            views: 2431,
            likes: 187,
            thumbnailGradient: ["FF6B35", "FF8C42"]
        ),
        MockClip(
            author: users[0],
            title: "Training montage",
            duration: 32,
            views: 1876,
            likes: 142,
            thumbnailGradient: ["4CAF50", "66BB6A"]
        ),
        MockClip(
            author: users[2],
            title: "Perfect serve technique",
            duration: 12,
            views: 3124,
            likes: 234,
            thumbnailGradient: ["2196F3", "42A5F5"]
        ),
        MockClip(
            author: users[4],
            title: "Match highlights",
            duration: 28,
            views: 1543,
            likes: 98,
            thumbnailGradient: ["9C27B0", "AB47BC"]
        ),
        MockClip(
            author: users[3],
            title: "Speed drill demonstration",
            duration: 18,
            views: 2187,
            likes: 156,
            thumbnailGradient: ["FF5722", "FF7043"]
        ),
        MockClip(
            author: users[5],
            title: "Tournament finals",
            duration: 45,
            views: 4521,
            likes: 378,
            thumbnailGradient: ["00BCD4", "26C6DA"]
        ),
        MockClip(
            author: users[1],
            title: "Behind the scenes",
            duration: 22,
            views: 1298,
            likes: 87,
            thumbnailGradient: ["FFC107", "FFD54F"]
        ),
        MockClip(
            author: users[0],
            title: "Epic rally",
            duration: 19,
            views: 2843,
            likes: 201,
            thumbnailGradient: ["E91E63", "F06292"]
        )
    ]
    
    // MARK: - Matches
    
    static let matches: [MockMatch] = [
        MockMatch(
            opponent: users[0],
            result: .win,
            score: "11-9, 11-7",
            date: Date().addingTimeInterval(-86400)
        ),
        MockMatch(
            opponent: users[1],
            result: .loss,
            score: "8-11, 9-11",
            date: Date().addingTimeInterval(-172800)
        ),
        MockMatch(
            opponent: users[2],
            result: .win,
            score: "11-6, 10-12, 11-8",
            date: Date().addingTimeInterval(-259200)
        ),
        MockMatch(
            opponent: users[3],
            result: .win,
            score: "11-4, 11-5",
            date: Date().addingTimeInterval(-345600)
        ),
        MockMatch(
            opponent: users[4],
            result: .loss,
            score: "7-11, 11-9, 9-11",
            date: Date().addingTimeInterval(-432000)
        )
    ]
    
    // MARK: - Drills
    
    static let drills: [MockDrill] = [
        MockDrill(
            name: "Ladder Agility Drill",
            category: .agility,
            difficulty: .intermediate,
            duration: 15
        ),
        MockDrill(
            name: "Medicine Ball Power Throws",
            category: .power,
            difficulty: .advanced,
            duration: 20
        ),
        MockDrill(
            name: "Target Practice Accuracy",
            category: .accuracy,
            difficulty: .beginner,
            duration: 25
        ),
        MockDrill(
            name: "Interval Sprint Training",
            category: .endurance,
            difficulty: .advanced,
            duration: 30
        ),
        MockDrill(
            name: "Footwork Speed Drills",
            category: .speed,
            difficulty: .intermediate,
            duration: 20
        ),
        MockDrill(
            name: "Form and Technique Practice",
            category: .technique,
            difficulty: .beginner,
            duration: 30
        ),
        MockDrill(
            name: "Plyometric Box Jumps",
            category: .power,
            difficulty: .advanced,
            duration: 15
        ),
        MockDrill(
            name: "Cone Drill Precision",
            category: .accuracy,
            difficulty: .intermediate,
            duration: 20
        )
    ]
}
