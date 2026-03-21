# SportsHub - AI Context & Architecture Documentation

## Project Overview

SportsHub is a **multi-sport competitive platform** with integrated social features, training systems, and content sharing. It is designed as a real, account-based application with authentication, backend services, and AI-powered features.

---

## Product Philosophy

### What SportsHub Is:
- Multi-sport athlete operating system
- Competitive identity platform
- Social sports network with safety-first messaging
- Training and progression platform
- Community content platform

### What SportsHub Is NOT:
- Single-sport utility
- Single-user demo
- Toy prototype
- Unmoderated social platform

---

## Core Product Requirements

### 1. Multi-Sport System (CRITICAL)

**Users compete across multiple sports, not just one.**

#### Supported Sports (Launch):
1. Basketball
2. Football
3. Soccer
4. Tennis

#### Sport Context Rules:
- Each user has **separate stats per sport**
- Each user has **separate rating per sport**
- Each user has **separate rank per sport**
- Users maintain **one global identity** across all sports
- Sports must be **structured types** (enum), not strings

#### Global Sport Selector (REQUIRED UI):
- **Always visible** across app
- Allows instant sport switching
- Appears on: Home, Play, Train, Clips, Profile, Leaderboard
- Style: Segmented control or horizontal chips
- User must always know: "Which sport am I viewing?"

#### What Changes When Sport Switches:
- Player rating (sport-specific Elo)
- Rank tier
- Leaderboards (filtered by sport)
- Match history
- Win/loss stats
- Training drills
- Matchmaking pool
- Clips feed (sport-filtered)
- Posts feed (sport-aware)
- AI recommendations

**Switch must feel instant. No reload screens.**

---

### 2. Social System - Friend Graph

**Communication is restricted for safety.**

#### Friend System Rules:
- Users **CANNOT** message strangers
- Messaging **ONLY** allowed between friends
- Friend requests must be sent and accepted
- No unsolicited messages

#### Friend States:
1. **Not Connected** - Default state
2. **Request Sent** - Pending friend request
3. **Request Received** - User has pending request from other user
4. **Friends** - Mutual connection, messaging unlocked

#### Friend Actions:
- Send friend request
- Accept friend request
- Decline friend request
- Remove friend
- Block user

---

### 3. Direct Messaging (DM) Feature

#### Access Rules:
- **Friends-only messaging**
- No stranger DMs
- No group chats (launch MVP)
- Text-only initially (no media sharing at MVP)

#### DM Capabilities:
- Text messages
- Emojis
- Basic reactions (like, heart, etc.)
- Timestamps
- Read receipts
- Message history

#### DM Access Points:
- Profile → Message button (if friends)
- Friends list → Message
- Dedicated "Messages" tab in main app

#### DM Safety:
- Encrypted in transit
- Stored securely
- Block functionality
- Report abuse option
- Content moderation on all messages

---

### 4. Content Moderation AI (MANDATORY)

**All user-generated text is filtered.**

#### Applies To:
- Posts
- Comments
- Direct messages
- Usernames
- Bios
- Clip captions

#### AI Moderation Capabilities:
- Profanity detection
- Slur detection
- Harassment detection
- Bullying language detection
- Contextual toxicity analysis

#### Actions on Violation:
1. **Soft block** - Message not sent
2. **Warn user** - Show warning message
3. **Log incident** - Store for moderation review
4. **Escalate repeat abuse** - Flag account for review

---

### 5. Authentication System (REQUIRED FIRST)

#### User Flow:
1. Welcome/landing screen
2. Sign up OR log in
3. Age verification (13+ check)
4. Account creation
5. Goals survey (optional onboarding)
6. Enter app shell

#### Session Management:
- **Login once, stay logged in**
- Persistent session storage (Keychain)
- Session token validation
- Explicit logout from Profile/Settings
- Auto-logout on session expiry

#### Age Verification (13+ Gate):
- Required during signup
- Date of birth collection
- Age calculation on client + server
- AI age verification checker (detect inconsistencies)
- Block account creation if under 13

---

### 6. Six-Tab App Shell (NON-NEGOTIABLE)

Once authenticated, user enters app with **exactly 6 tabs:**

1. **Home** - Personal dashboard, stats, quick actions
2. **Play** - Competition, challenges, matchmaking, leaderboard
3. **Train** - Drills, programs, progress tracking
4. **Posts** - Community text/photo feed
5. **Clips** - Short-form video content
6. **Profile** - User identity, stats, settings, logout

**All tabs require authentication to access.**

---

## Data Architecture

### User Model

```swift
struct User {
    let id: UUID
    let email: String
    let username: String
    let displayName: String
    let dateOfBirth: Date
    let avatarSeed: String
    let bio: String
    let accountStatus: AccountStatus
    let createdAt: Date

    // Multi-sport profiles
    let sportProfiles: [Sport: SportProfile]

    // Social graph
    let friendsCount: Int
    let pendingRequestsCount: Int
}

enum AccountStatus: String {
    case active
    case suspended
    case banned
}
```

### Sport Enum

```swift
enum Sport: String, CaseIterable {
    case basketball = "Basketball"
    case football = "Football"
    case soccer = "Soccer"
    case tennis = "Tennis"

    var icon: String {
        switch self {
        case .basketball: return "basketball.fill"
        case .football: return "football.fill"
        case .soccer: return "soccerball"
        case .tennis: return "tennisball.fill"
        }
    }
}
```

### SportProfile Model

```swift
struct SportProfile {
    let sport: Sport
    let rating: Int // Elo rating
    let rankTier: RankTier
    let gamesPlayed: Int
    let wins: Int
    let losses: Int
    let bestStreak: Int
    let currentStreak: Int
    let progressionLevel: Int
    let lastPlayed: Date?
}

enum RankTier: String {
    case bronze
    case silver
    case gold
    case platinum
    case diamond
    case master
}
```

### Friendship Model

```swift
struct Friendship {
    let id: UUID
    let userA: UUID
    let userB: UUID
    let status: FriendshipStatus
    let initiatedBy: UUID
    let createdAt: Date
    let acceptedAt: Date?
}

enum FriendshipStatus: String {
    case pending
    case accepted
    case blocked
    case declined
}
```

### Message Model

```swift
struct Message {
    let id: UUID
    let senderId: UUID
    let receiverId: UUID
    let content: String
    let isSafetyChecked: Bool
    let moderationStatus: ModerationStatus
    let sentAt: Date
    let readAt: Date?
    let deletedBySender: Bool
    let deletedByReceiver: Bool
}

enum ModerationStatus: String {
    case safe
    case flagged
    case blocked
}
```

### Challenge Model

```swift
struct Challenge {
    let id: UUID
    let sport: Sport // CRITICAL: Sport-specific
    let challengerId: UUID
    let opponentId: UUID
    let status: ChallengeStatus
    let scoreData: ScoreData?
    let impactWeight: Double // AI-calculated
    let createdAt: Date
    let completedAt: Date?
    let winnerId: UUID?
}

enum ChallengeStatus: String {
    case pending
    case accepted
    case declined
    case completed
    case disputed
}
```

### Post Model

```swift
struct Post {
    let id: UUID
    let authorId: UUID
    let content: String
    let sport: Sport? // Optional sport tag
    let safetyChecked: Bool
    let moderationStatus: ModerationStatus
    let likesCount: Int
    let commentsCount: Int
    let createdAt: Date
}
```

### Clip Model

```swift
struct Clip {
    let id: UUID
    let authorId: UUID
    let sport: Sport // REQUIRED: Sport tag
    let title: String
    let videoUrl: String
    let thumbnailGradient: [String]
    let duration: Int
    let viewsCount: Int
    let likesCount: Int
    let safetyChecked: Bool
    let createdAt: Date
}
```

### Drill Model

```swift
struct Drill {
    let id: UUID
    let sport: Sport // REQUIRED: Sport-specific
    let name: String
    let category: DrillCategory
    let difficulty: Difficulty
    let duration: Int
    let instructions: String
    let generatedByAI: Bool
    let createdAt: Date
}

enum DrillCategory: String {
    case speed
    case power
    case accuracy
    case endurance
    case agility
    case technique
}
```

---

## Backend API Structure

### Base URL
```
https://api.sportshub.app
```

### Authentication Endpoints

```
POST   /api/auth/signup
POST   /api/auth/login
POST   /api/auth/logout
GET    /api/auth/validate
POST   /api/auth/refresh-token
```

### User Endpoints

```
GET    /api/users/me
PUT    /api/users/me
GET    /api/users/:id
GET    /api/users/:id/sport-profile/:sport
PUT    /api/users/me/sport-profile/:sport
```

### Friend Endpoints

```
GET    /api/friends
GET    /api/friends/requests
POST   /api/friends/request/:userId
PUT    /api/friends/accept/:requestId
PUT    /api/friends/decline/:requestId
DELETE /api/friends/:userId
POST   /api/friends/block/:userId
```

### Message Endpoints

```
GET    /api/messages/conversations
GET    /api/messages/conversation/:userId
POST   /api/messages/send
PUT    /api/messages/:id/read
DELETE /api/messages/:id
```

### Challenge Endpoints

```
POST   /api/challenges/create
GET    /api/challenges/active
GET    /api/challenges/history
PUT    /api/challenges/:id/accept
PUT    /api/challenges/:id/decline
POST   /api/challenges/:id/submit-result
GET    /api/challenges/leaderboard/:sport
```

### Training Endpoints

```
POST   /api/training/goals-survey
GET    /api/training/drills/:sport
POST   /api/training/log-session
GET    /api/training/progress/:sport
```

### Posts Endpoints

```
POST   /api/posts
GET    /api/posts/feed
GET    /api/posts/feed/:sport
POST   /api/posts/:id/like
POST   /api/posts/:id/report
DELETE /api/posts/:id
```

### Clips Endpoints

```
POST   /api/clips/upload
GET    /api/clips/feed/:sport
GET    /api/clips/:id
POST   /api/clips/:id/like
POST   /api/clips/:id/report
DELETE /api/clips/:id
```

### Moderation Endpoints

```
POST   /api/moderation/check-content
POST   /api/moderation/report
GET    /api/moderation/flags (admin only)
```

---

## AI Services

### 1. Age Verification AI

**Purpose:** Detect inconsistent age entries and flag suspicious accounts.

**Inputs:**
- Date of birth
- Account creation patterns
- User behavior signals

**Outputs:**
- Age verification score
- Flagged accounts for review

### 2. Content Safety AI

**Purpose:** Detect profanity, harassment, bullying, and unsafe content.

**Inputs:**
- Text content (posts, messages, usernames)
- User history
- Context signals

**Outputs:**
- Safety score
- Violation flags
- Recommended action (allow/warn/block)

**Applied to:**
- All posts
- All direct messages
- All comments
- All usernames/bios
- All clip captions

### 3. Challenge Impact AI

**Purpose:** Weight challenge results based on context for fair leaderboard impact.

**Inputs:**
- Opponent rating difference
- Sport type
- Challenge frequency
- Recent performance
- Time of day
- Challenge type (casual vs tournament)

**Outputs:**
- Impact weight multiplier (0.5 - 2.0)
- Applied to Elo rating change

**Example:**
```
Base Elo change: +25
Opponent much stronger: 1.5x weight
Spam prevention (10+ games today): 0.7x weight
Final impact: +25 * 1.5 * 0.7 = +26 points
```

### 4. AI Drill Generator

**Purpose:** Generate personalized training drills based on goals survey.

**Inputs:**
- Sport selection
- Skill level
- Improvement goals
- Time commitment
- Weaknesses identified
- Current rating

**Outputs:**
- Personalized drill recommendations
- Difficulty-appropriate exercises
- Sport-specific training programs

---

## Database Schema (PostgreSQL)

### users
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(100),
    date_of_birth DATE NOT NULL,
    avatar_seed VARCHAR(100),
    bio TEXT,
    account_status VARCHAR(20) DEFAULT 'active',
    age_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    last_login TIMESTAMP
);
```

### sessions
```sql
CREATE TABLE sessions (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(255) UNIQUE NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### sport_profiles
```sql
CREATE TABLE sport_profiles (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    sport VARCHAR(50) NOT NULL,
    rating INT DEFAULT 1500,
    rank_tier VARCHAR(20) DEFAULT 'bronze',
    games_played INT DEFAULT 0,
    wins INT DEFAULT 0,
    losses INT DEFAULT 0,
    best_streak INT DEFAULT 0,
    current_streak INT DEFAULT 0,
    progression_level INT DEFAULT 1,
    last_played TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, sport)
);
```

### friendships
```sql
CREATE TABLE friendships (
    id UUID PRIMARY KEY,
    user_a UUID REFERENCES users(id) ON DELETE CASCADE,
    user_b UUID REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL,
    initiated_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW(),
    accepted_at TIMESTAMP,
    UNIQUE(user_a, user_b)
);
```

### messages
```sql
CREATE TABLE messages (
    id UUID PRIMARY KEY,
    sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    safety_checked BOOLEAN DEFAULT FALSE,
    moderation_status VARCHAR(20) DEFAULT 'pending',
    sent_at TIMESTAMP DEFAULT NOW(),
    read_at TIMESTAMP,
    deleted_by_sender BOOLEAN DEFAULT FALSE,
    deleted_by_receiver BOOLEAN DEFAULT FALSE
);
```

### challenges
```sql
CREATE TABLE challenges (
    id UUID PRIMARY KEY,
    sport VARCHAR(50) NOT NULL,
    challenger_id UUID REFERENCES users(id) ON DELETE CASCADE,
    opponent_id UUID REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL,
    score_data JSONB,
    impact_weight FLOAT DEFAULT 1.0,
    winner_id UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP
);
```

### posts
```sql
CREATE TABLE posts (
    id UUID PRIMARY KEY,
    author_id UUID REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    sport VARCHAR(50),
    safety_checked BOOLEAN DEFAULT FALSE,
    moderation_status VARCHAR(20) DEFAULT 'pending',
    likes_count INT DEFAULT 0,
    comments_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### clips
```sql
CREATE TABLE clips (
    id UUID PRIMARY KEY,
    author_id UUID REFERENCES users(id) ON DELETE CASCADE,
    sport VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    video_url VARCHAR(500),
    thumbnail_gradient JSONB,
    duration INT,
    views_count INT DEFAULT 0,
    likes_count INT DEFAULT 0,
    safety_checked BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### drills
```sql
CREATE TABLE drills (
    id UUID PRIMARY KEY,
    sport VARCHAR(50) NOT NULL,
    name VARCHAR(200) NOT NULL,
    category VARCHAR(50) NOT NULL,
    difficulty VARCHAR(20) NOT NULL,
    duration INT,
    instructions TEXT,
    generated_by_ai BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### goals_surveys
```sql
CREATE TABLE goals_surveys (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    primary_sport VARCHAR(50),
    skill_level VARCHAR(20),
    improvement_goals JSONB,
    time_commitment VARCHAR(50),
    competition_goals TEXT,
    completed_at TIMESTAMP DEFAULT NOW()
);
```

### moderation_flags
```sql
CREATE TABLE moderation_flags (
    id UUID PRIMARY KEY,
    content_type VARCHAR(20),
    content_id UUID,
    reporter_id UUID REFERENCES users(id),
    reason VARCHAR(100),
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

## iOS App Structure

### Current File Organization

```
SportsHub/
├── SportsHubApp.swift - App entry point
├── MainTabView.swift - Custom 6-tab navigation
├── ContentView.swift - PRESERVED (unused, original template)
├── Item.swift - PRESERVED (unused SwiftData model)
├── DesignSystem.swift - Colors, typography, spacing
├── MockData.swift - Placeholder data (dev/preview only)
├── HomeView.swift - Empty state, auth prompt
├── PlayView.swift - Empty state, auth prompt
├── TrainView.swift - Empty state, auth prompt
├── PostsView.swift - Empty state, auth prompt
├── ClipsView.swift - Empty state, auth prompt
└── ProfileView.swift - Empty state, auth prompt
```

### Files to Create (iOS)

**Network Layer:**
- NetworkManager.swift
- APIEndpoints.swift
- APIModels.swift
- KeychainManager.swift

**Services:**
- AuthService.swift
- UserService.swift
- FriendService.swift
- MessageService.swift
- ChallengeService.swift
- TrainingService.swift
- PostService.swift
- ClipService.swift

**Authentication Flow:**
- SessionManager.swift
- AuthenticationView.swift
- LoginView.swift
- SignUpView.swift
- AgeVerificationView.swift
- GoalsSurveyView.swift

**Multi-Sport System:**
- SportSelector.swift (reusable component)
- SportContext.swift (app-wide sport state)

**Social Features:**
- FriendsListView.swift
- FriendRequestsView.swift
- MessagesListView.swift
- ChatView.swift

**Real Data Views (replace empty states):**
- HomeView.swift (replace with real stats)
- ProfileView.swift (replace with real profile)
- PlayView.swift (add leaderboard, challenges)
- TrainView.swift (add personalized drills)
- PostsView.swift (add real feed)
- ClipsView.swift (add real clips)

**Models:**
- User.swift
- Sport.swift
- SportProfile.swift
- Friendship.swift
- Message.swift
- Challenge.swift
- Post.swift
- Clip.swift
- Drill.swift

---

## Implementation Phases

### Phase 1: Backend Foundation ✅ NEXT
1. Set up PostgreSQL database
2. Create all tables
3. Implement authentication endpoints
4. Deploy to staging environment

### Phase 2: iOS Network Layer
1. Create NetworkManager
2. Create all service classes
3. Implement Keychain storage
4. Test API connectivity

### Phase 3: Authentication Flow
1. Build auth UI screens
2. Implement session management
3. Add age verification
4. Connect to backend auth

### Phase 4: Multi-Sport System
1. Create Sport enum
2. Build SportSelector component
3. Implement sport context state
4. Add sport switching logic

### Phase 5: Core Features Integration
1. Replace empty states with real data
2. Implement challenge system
3. Add leaderboard (sport-filtered)
4. Implement training/drills

### Phase 6: Social Features
1. Build friend system
2. Implement DM chat
3. Add safety moderation
4. Test friend-gated messaging

### Phase 7: Content Features
1. Posts feed (sport-aware)
2. Clips feed (sport-filtered)
3. Upload functionality
4. Content moderation integration

### Phase 8: AI Services
1. Content safety AI
2. Drill generator AI
3. Challenge impact AI
4. Age verification AI

---

## Design System

### Colors
- Background: `#0A0A0A` (near black)
- Surface: `#1A1A1A` (card background)
- Primary: `#FF6B35` (orange accent)
- Text Primary: `#FFFFFF`
- Text Secondary: `#A0A0A0`
- Success: `#4CAF50`
- Error: `#F44336`

### Typography
- Large Title: 28pt, bold
- Title 2: 22pt, semibold
- Headline: 17pt, semibold
- Body: 17pt, regular
- Subheadline: 15pt, regular
- Caption: 12pt, regular

### Spacing
- XS: 4pt
- SM: 8pt
- MD: 16pt
- LG: 24pt
- XL: 32pt

---

## Safety & Moderation

### Content Types Requiring Moderation:
- Posts (text content)
- Comments (when implemented)
- Direct messages
- Usernames
- Bio text
- Clip captions

### Moderation Actions:
1. **Auto-filter** - Profanity replaced with asterisks
2. **Soft block** - Message not sent, user warned
3. **Flag for review** - Human moderation queue
4. **Account suspension** - Repeat violations
5. **Permanent ban** - Severe violations

### User Reporting:
- Report post
- Report clip
- Report message
- Report user profile
- Block user

---

## Current App State (as of 2026-03-06)

### ✅ Completed:
- Custom 6-tab navigation (no "More" button)
- Dark theme design system
- All empty states with auth prompts
- Zero fake/mock data displayed
- Clean architecture ready for backend

### ❌ Not Yet Implemented:
- Authentication system
- Backend API
- Database
- Network layer
- Real user data
- Multi-sport system
- Friend/messaging system
- Content moderation
- AI services

---

## Next Immediate Step

**BUILD BACKEND API**

Stack recommendation:
- **Node.js + Express** OR **Python + FastAPI**
- PostgreSQL database
- JWT authentication
- RESTful API design
- AI service integration (OpenAI API / custom models)

---

Last Updated: 2026-03-06
Phase: Pre-Backend (iOS UI shell complete, awaiting server implementation)
