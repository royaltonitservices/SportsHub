# SportsHub API Guide

**Version:** 1.0
**Base URL:** `http://localhost:8000` (development)
**Authentication:** JWT Bearer Token

---

## Table of Contents

1. [Authentication](#authentication)
2. [Users](#users)
3. [Sports & Profiles](#sports--profiles)
4. [Matchmaking](#matchmaking)
5. [Teams](#teams)
6. [Friends](#friends)
7. [Messaging](#messaging)
8. [Posts & Clips](#posts--clips)
9. [Comments](#comments)
10. [Search](#search)
11. [Badges](#badges)
12. [Activity Feed](#activity-feed)
13. [Disputes](#disputes)
14. [Blocking](#blocking)
15. [Admin](#admin)

---

## Authentication

### Sign Up
```http
POST /auth/signup
Content-Type: application/json

{
  "email": "user@example.com",
  "username": "player123",
  "password": "securepass",
  "display_name": "Player Name",
  "date_of_birth": "2008-01-15T00:00:00Z"
}
```

**Response:**
```json
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "token_type": "bearer"
}
```

### Login
```http
POST /auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepass"
}
```

### Get Current User
```http
GET /users/me
Authorization: Bearer <token>
```

---

## Users

### Get User Profile
```http
GET /users/{user_id}
Authorization: Bearer <token>
```

### Update Athletic Level
```http
PUT /users/update-athletic-level
Authorization: Bearer <token>
Content-Type: application/json

{
  "sport": "basketball",
  "athletic_level": "varsity"
}
```

**Athletic Levels:** `varsity`, `jv`, `club`, `recreational`, `beginner`

### Update Pronouns
```http
PUT /users/update-pronouns?pronouns=he/him
Authorization: Bearer <token>
```

---

## Sports & Profiles

### Get Sport Profile
```http
GET /sports/profile/{sport}
Authorization: Bearer <token>
```

**Sports:** `basketball`, `football`, `soccer`, `tennis`

**Response:**
```json
{
  "id": "uuid",
  "sport": "basketball",
  "rating": 1547,
  "provisional_games": 8,
  "is_provisional": true,
  "rank_tier": "gold",
  "athletic_level": "varsity",
  "games_played": 23,
  "ranked_games_played": 15,
  "wins": 14,
  "losses": 9,
  "best_streak": 5,
  "current_streak": 2
}
```

---

## Matchmaking

### Find Opponents
```http
POST /matchmaking/find-opponents
Authorization: Bearer <token>
Content-Type: application/json

{
  "sport": "basketball",
  "match_type": "ranked"
}
```

**Match Types:** `ranked`, `unranked`

### Create Challenge
```http
POST /matchmaking/create-challenge
Authorization: Bearer <token>
Content-Type: application/json

{
  "sport": "basketball",
  "match_type": "ranked",
  "opponent_id": "uuid"
}
```

### Accept Challenge
```http
POST /matchmaking/accept-challenge/{challenge_id}
Authorization: Bearer <token>
```

### Submit Match Result
```http
POST /matchmaking/submit-result
Authorization: Bearer <token>
Content-Type: application/json

{
  "challenge_id": "uuid",
  "winner_id": "uuid",
  "score_data": {
    "team1_score": 21,
    "team2_score": 18
  }
}
```

**Note:** Both players must confirm the result

### Get Leaderboard
```http
GET /matchmaking/leaderboard/{sport}?limit=100
Authorization: Bearer <token>
```

### Get My Challenges
```http
GET /matchmaking/my-challenges
Authorization: Bearer <token>
```

---

## Teams

### Create Team
```http
POST /teams/create?name=Team%20Name&sport=basketball
Authorization: Bearer <token>
```

### Add Team Member
```http
POST /teams/{team_id}/add-member
Authorization: Bearer <token>
Content-Type: application/json

{
  "user_id": "uuid"
}
```

**Note:** Only team captain can add members. Max 3 members per team.

### Get My Teams
```http
GET /teams/my-teams
Authorization: Bearer <token>
```

### Get Team Members
```http
GET /teams/{team_id}/members
```

### Create Team Challenge
```http
POST /teams/challenge
Authorization: Bearer <token>
Content-Type: application/json

{
  "team1_id": "uuid",
  "team2_id": "uuid",
  "sport": "basketball",
  "match_type": "ranked"
}
```

### Complete Team Challenge
```http
POST /teams/challenge/{challenge_id}/complete
Authorization: Bearer <token>
Content-Type: application/json

{
  "winner_team_id": "uuid"
}
```

---

## Friends

### Send Friend Request
```http
POST /friends/request
Authorization: Bearer <token>
Content-Type: application/json

{
  "target_user_id": "uuid"
}
```

### Accept Friend Request
```http
POST /friends/accept/{friendship_id}
Authorization: Bearer <token>
```

### Decline Friend Request
```http
POST /friends/decline/{friendship_id}
Authorization: Bearer <token>
```

### Get Friends List
```http
GET /friends/list
Authorization: Bearer <token>
```

### Get Friend Requests
```http
GET /friends/requests
Authorization: Bearer <token>
```

---

## Messaging

### Send Message
```http
POST /messages/send
Authorization: Bearer <token>
Content-Type: application/json

{
  "receiver_id": "uuid",
  "content": "Hey, want to play basketball later?"
}
```

**Note:** Can only message friends

### Get Conversations
```http
GET /messages/conversations
Authorization: Bearer <token>
```

### Get Messages with User
```http
GET /messages/with/{user_id}
Authorization: Bearer <token>
```

---

## Posts & Clips

### Create Post
```http
POST /posts/create
Authorization: Bearer <token>
Content-Type: application/json

{
  "content": "Just hit a new personal record!",
  "sport": "basketball"
}
```

### Get Feed
```http
GET /posts/feed?sport=basketball&limit=20
Authorization: Bearer <token>
```

### Like Post
```http
POST /posts/{post_id}/like
Authorization: Bearer <token>
```

### Create Clip
```http
POST /clips/create
Authorization: Bearer <token>
Content-Type: application/json

{
  "sport": "basketball",
  "title": "Amazing buzzer beater",
  "duration": 15,
  "video_url": "https://..."
}
```

---

## Comments

### Create Comment
```http
POST /comments/create
Authorization: Bearer <token>
Content-Type: application/json

{
  "post_id": "uuid",
  "content": "Great job!",
  "parent_comment_id": null
}
```

**Note:** Set `parent_comment_id` for nested replies

### Get Post Comments
```http
GET /comments/post/{post_id}
```

### Like Comment
```http
POST /comments/like/{comment_id}
Authorization: Bearer <token>
```

### Delete Comment
```http
DELETE /comments/{comment_id}
Authorization: Bearer <token>
```

---

## Search

### Global Search
```http
GET /search/?query=john&search_type=all&limit=20
Authorization: Bearer <token>
```

**Search Types:** `all`, `users`, `posts`, `clips`

**Response:**
```json
{
  "users": [...],
  "posts": [...],
  "clips": [...]
}
```

### Search User by Username
```http
GET /search/users/{username}
Authorization: Bearer <token>
```

---

## Badges

### Get Available Badges
```http
GET /badges/available/{sport}
Authorization: Bearer <token>
```

**Response:**
```json
[
  {
    "id": "bb_first_win",
    "name": "First Victory",
    "description": "Win your first basketball match",
    "category": "achievement",
    "rarity": "common",
    "icon": "trophy.fill",
    "requirement": {"type": "wins", "value": 1},
    "earned": true,
    "earned_at": "2026-03-01T10:30:00Z"
  }
]
```

### Get My Badges
```http
GET /badges/my-badges?sport=basketball
Authorization: Bearer <token>
```

### Get Badge Statistics
```http
GET /badges/stats
Authorization: Bearer <token>
```

**Response:**
```json
{
  "basketball": {
    "total": 100,
    "earned": 15,
    "percentage": 15.0
  },
  "football": {
    "total": 100,
    "earned": 0,
    "percentage": 0.0
  }
}
```

---

## Activity Feed

### Get Personalized Feed
```http
GET /activity/feed?limit=50
Authorization: Bearer <token>
```

**Response:**
```json
[
  {
    "type": "match_completed",
    "timestamp": "2026-03-09T14:30:00Z",
    "challenge_id": "uuid",
    "sport": "basketball",
    "match_type": "ranked",
    "challenger": {
      "id": "uuid",
      "username": "player1",
      "display_name": "Player One"
    },
    "opponent": {
      "id": "uuid",
      "username": "player2",
      "display_name": "Player Two"
    },
    "winner": {...},
    "rating_change": {
      "challenger": 15,
      "opponent": -15
    }
  }
]
```

### Get Recent Matches
```http
GET /activity/recent-matches?sport=basketball&limit=20
Authorization: Bearer <token>
```

---

## Disputes

### Create Dispute
```http
POST /disputes/create
Authorization: Bearer <token>
Content-Type: application/json

{
  "challenge_id": "uuid",
  "reason": "Opponent reported wrong score",
  "evidence": {
    "screenshot_url": "https://...",
    "description": "Screenshot showing actual score"
  }
}
```

### Get My Disputes
```http
GET /disputes/my-disputes
Authorization: Bearer <token>
```

### Resolve Dispute (Admin Only)
```http
POST /disputes/resolve/{dispute_id}
Authorization: Bearer <admin-token>
Content-Type: application/json

{
  "resolution": "reverse",
  "admin_notes": "Evidence clearly shows different outcome"
}
```

**Resolution Types:** `uphold`, `reverse`

### Reject Dispute (Admin Only)
```http
POST /disputes/reject/{dispute_id}
Authorization: Bearer <admin-token>
Content-Type: application/json

{
  "admin_notes": "Insufficient evidence"
}
```

---

## Blocking

### Block User
```http
POST /blocking/block
Authorization: Bearer <token>
Content-Type: application/json

{
  "blocked_user_id": "uuid"
}
```

### Unblock User
```http
POST /blocking/unblock/{blocked_user_id}
Authorization: Bearer <token>
```

### Get Blocked Users
```http
GET /blocking/my-blocked-users
Authorization: Bearer <token>
```

---

## Admin

### Get All Users (Admin Only)
```http
GET /admin/users?limit=50
Authorization: Bearer <admin-token>
```

### Suspend User (Admin Only)
```http
POST /admin/suspend/{user_id}
Authorization: Bearer <admin-token>
Content-Type: application/json

{
  "reason": "Violation of terms of service"
}
```

### Get Moderation Flags (Admin Only)
```http
GET /moderation/flags?status=pending
Authorization: Bearer <admin-token>
```

---

## Response Codes

| Code | Description |
|------|-------------|
| 200 | Success |
| 201 | Created |
| 400 | Bad Request |
| 401 | Unauthorized (invalid/missing token) |
| 403 | Forbidden (insufficient permissions) |
| 404 | Not Found |
| 409 | Conflict (duplicate entry) |
| 422 | Validation Error |
| 500 | Internal Server Error |

---

## Error Response Format

```json
{
  "detail": "Error message description"
}
```

---

## Rate Limiting

**Note:** Rate limiting is not yet implemented but recommended for production:
- Authentication endpoints: 5 requests/minute
- General endpoints: 100 requests/minute
- Search endpoints: 20 requests/minute

---

## Webhooks (Future Feature)

Webhook support for real-time events:
- `match.completed`
- `friend.request`
- `message.received`
- `badge.earned`

---

## SDK Examples

### JavaScript/TypeScript
```typescript
const API_BASE = 'http://localhost:8000';
const token = localStorage.getItem('auth_token');

async function getLeaderboard(sport: string) {
  const response = await fetch(`${API_BASE}/matchmaking/leaderboard/${sport}`, {
    headers: {
      'Authorization': `Bearer ${token}`
    }
  });
  return response.json();
}
```

### Swift/iOS
```swift
func getLeaderboard(sport: String) async throws -> [LeaderboardEntry] {
    guard let token = UserDefaults.standard.string(forKey: "auth_token") else {
        throw APIError.noToken
    }

    var request = URLRequest(url: URL(string: "\(apiBase)/matchmaking/leaderboard/\(sport)")!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode([LeaderboardEntry].self, from: data)
}
```

---

## Testing

Run backend tests:
```bash
cd backend
pytest
```

Interactive API documentation:
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

---

## Support

For issues, feature requests, or questions:
- GitHub: [repository URL]
- Email: support@sportshub.com
- Discord: [invite link]

---

**Last Updated:** March 9, 2026
