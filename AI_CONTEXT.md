# SportsHub — Unified AI Context
Last Updated: 2026-03-27
Commit: 6263607

This file is the canonical context file for any LLM, coding assistant, code generator, or product collaborator working on SportsHub.

Use this file as the source of truth for:
- product intent
- architectural direction
- current implementation state
- repo / branch / checkpoint context
- critical product rules
- what is already built vs what still needs refinement

Do NOT treat SportsHub as a toy project.
Do NOT treat this as a generic social app.
Do NOT assume this is still an empty-state prototype.
Do NOT regress the product into a demo-only shell.

============================================================
1. PROJECT OVERVIEW
============================================================

SportsHub is a **production-quality, multi-sport, account-based platform** for teenagers and young athletes.

It combines:
- pickup and competitive sports matchmaking
- sport-specific progression and Elo/rating systems
- training and AI coaching
- social graph / friends / messaging
- short-form clips and posts
- trust, evidence, dispute, and moderation systems
- notifications
- profile identity and sport-specific reputation
- premium subscriptions (StoreKit 2)
- smartwatch/fitness tracker integration
- tournaments
- admin moderation dashboard

**Current Scale:**
- 32 Swift files (iOS frontend)
- 14,343 lines of Python backend code (FastAPI)
- 70+ API endpoints implemented
- Real authentication with session persistence
- Working premium subscription system
- Functional AI coaching system
- Comprehensive trust & dispute resolution

SportsHub is intended to feel:
- alive
- responsive
- social
- competitive
- safe
- youth-friendly
- modern
- trustworthy
- never empty
- never confusing

SportsHub is NOT:
- a toy prototype
- a single-user demo
- a single-sport utility
- an unmoderated social network
- a static UI shell

============================================================
2. CURRENT GIT / REPO STATE
============================================================

Repository:
- GitHub remote: `royaltonitservices/SportsHub`

Current checkpoint state:
- Current branch: `checkpoint/state-of-union-2026-03-21`
- Latest commit: `6263607` - "Checkpoint: major SportsHub integration pass before restart handoff 03272026"
- Working tree: clean

Important commits:
- `6263607` — Checkpoint: major SportsHub integration pass before restart handoff 03272026
- `7e8d185` — Docs: refresh AI context to current product and repo state
- `394503e` — Docs: add state of the union note for 2026-03-21
- `4831a74` — Checkpoint: SportsHub state of the union 2026-03-21

Remote baseline branches that already exist:
- `main`
- `demo-architecture-freeze`
- `phase-1-domain-engine`

Important repo notes:
- The earlier remote repo represents an older, smaller baseline.
- The current local/project state is much larger and more advanced than the older remote baseline.
- The current checkpoint was intentionally pushed to a NEW BRANCH instead of overwriting remote `main`.
- `.gitignore` was added during checkpointing.
- Sensitive/local files such as `backend/.env` and local DB files were intentionally kept out of git.

When working in this repo:
- prefer new feature/fix branches
- do not casually push to remote `main`
- preserve the checkpoint branch as a recovery/safety point
- respect `.gitignore`

Suggested branch naming:
- `feature/ai-coach-chat`
- `feature/username-editing`
- `feature/available-now-notifications`
- `fix/auth-error-mapping`
- `fix/login-ui-polish`
- `checkpoint/YYYY-MM-DD-description`

============================================================
3. CORE PRODUCT MODEL
============================================================

SportsHub is a multi-sport athlete operating system with:
- one global user identity
- sport-specific progression
- sport-specific ratings
- sport-specific experiences
- social connections
- safety and moderation
- training and competition loops

Launch sports:
1. Basketball
2. Football
3. Soccer
4. Tennis

Users have:
- one account
- one global profile / identity
- separate ratings / stats / rank context per sport

The app must never feel dead.
Every important screen must provide a next action.

============================================================
4. NON-NEGOTIABLE APP STRUCTURE
============================================================

The authenticated app shell has EXACTLY 6 tabs:

1. Home
2. Play
3. Train
4. Posts
5. Clips
6. Profile

Do not reduce or rename these tabs.

High-level role of each:
- Home: personal dashboard, quick actions, relevant activity
- Play: competition, matchmaking, challenges, leaderboards
- Train: drills, plans, AI coaching, progress
- Posts: sport-aware social feed
- Clips: short-form sports video
- Profile: identity, stats, settings, account management

**AI Coach Overlay:**
- AICoachFloatingView appears on all tabs (z-index 999)
- Premium badge shown to free users
- Full chat access for premium users

============================================================
5. CORE PRODUCT RULES
============================================================

### 5.1 Multi-sport is real, not cosmetic
- sports must be structured types, not random strings
- each sport has separate stats / ratings / rank context
- user maintains one global account identity

### 5.2 Sport context must feel immediate
Switching sports should change:
- ratings
- leaderboards
- feeds
- training recommendations
- matchmaking pools
- sport-specific stats

The switch should feel instant.

### 5.3 Messaging is safety-gated
- users cannot DM strangers
- messaging is friends-only
- friend request / acceptance flow is required

### 5.4 Content moderation is mandatory
Applies to:
- usernames
- bios
- posts
- comments
- direct messages
- clip captions

### 5.5 Authentication is production-quality
- login once, stay logged in via Keychain
- signup includes 13+ age gate
- date of birth matters
- session persistence via Keychain + UserDefaults
- logout completely clears session
- auth should feel production-quality
- password encoding handles special characters correctly

**Recent verification (March 27, 2026):**
- Backend import errors fixed (Enum → SQLEnum, added Index)
- Backend now runs successfully on http://localhost:8000
- Login tested end-to-end with special characters in password - WORKS

### 5.6 No dead states
SportsHub should not leave users at blank endpoints like:
- no match and no suggestion
- no coach insights and no next step
- unknown status with no action
- empty feed with no path forward

Always offer a next action.

============================================================
6. REALISM RULES BY SPORT
============================================================

Not all sports should be modeled identically.

### Tennis (strictest venue realism)
Tennis requires real tennis-court-aware behavior.
Do NOT treat tennis like generic open-space pickup.

Tennis requirements:
- match/location flow should reference real courts where possible
- users should be told that some courts may require reservation, rental, paid booking, or membership
- tennis match suggestions should not assume free, open access
- TennisCourtPickerView integrated into matchmaking
- Backend endpoints: `/tennis-courts/nearby`, `/tennis-courts/search/by-city`, `/tennis-courts/{courtId}`

### Basketball
- prefer real court-aware context where possible
- lighter venue strictness than tennis
- mention possible gym/court access constraints when relevant

### Soccer / Football
- can use more flexible field/open-space logic
- do not force tennis-level venue strictness
- venue constraints can be contextual rather than mandatory

Important rule:
SportsHub should be a shared sports platform with sport-specific rules where needed, not one oversimplified sport model applied everywhere.

============================================================
7. PREMIUM SYSTEM RULES
============================================================

**Premium is dual-source:**
1. **Client-side (StoreKit 2):** Local purchase history via StoreManager
2. **Server-side (Backend):** Admin-granted premium via `/users/me/subscription`

**Premium Products:**
- Monthly: $8.99 (`com.sportshub.premium.monthly`)
- Yearly: $100/year (~7% savings, `com.sportshub.premium.yearly`)

**Premium Features:**
1. AI Coach Chat (unlimited)
2. AI Weekly Drills
3. Daily Readiness
4. Skill Progression Tracking
5. Advanced Analytics
6. Wearable Sync
7. Tournament Creation

**Gating Philosophy:**
- AI Coach is premium-only for **actual use** - but visible to all users on TrainView
- Free users see premium features with "PREMIUM" badge
- Premium upgrade sheet shown when tapped by non-premium
- Non-premium users CAN join tournaments (only creation is premium-gated)
- No degraded experiences - free users get full access to core matchmaking

**Implementation:**
```swift
@EnvironmentObject var storeManager: StoreManager

if storeManager.isPremium {
    // Show premium feature
} else {
    // Show upgrade sheet
}
```

============================================================
8. AI COACH RULES
============================================================

The AI Coach is a major feature area.

### Required coach behavior
The coach must:
- answer direct user questions
- ask smart coaching questions
- remain useful even without smartwatch data
- never end in a dead "All Caught Up" state with nothing helpful to do

### User-led prompts the coach should support:
- "What should I train today?"
- "How do I improve my left hand?"
- "Should I recover or train hard today?"
- "Give me a 20-minute workout."

### Coach-initiated questions:
- "What do you think are your weak points?"
- "What sport are you focused on right now?"
- "How much time do you have?"
- "How is your body feeling today?"
- "Are you training for a game, improvement, or recovery?"

### Critical rule:
The AI Coach should be **wearable-enhanced, not wearable-dependent**.

If smartwatch/recovery data is missing, the coach should still be useful via:
- user questions
- self-reported readiness
- weak-point input
- sport context
- time available
- training goals

### Voice Input:
- VoiceInputManager.swift handles recording
- iOS Speech framework for transcription
- Live preview while recording
- Sends transcribed text to chat

### Backend Integration:
- `POST /ai/coach/message` - send message to coach
- `GET /ai/coach/checkin` - proactive check-in
- `DELETE /ai/coach/history` - clear conversation
- `POST /ai/coach/drill/generate` - generate workout drill (available to all)
- `POST /ai/coach/challenge/generate` - generate challenge (available to all)
- `POST /ai/coach/analyze` - analyze training session (premium)

Bad behavior to avoid:
- dead-end "No insights"
- passive refresh-only behavior
- raw "Internal Server Error" shown to user
- inability to ask the coach questions

============================================================
9. FITNESS TRACKER / SMARTWATCH RULES
============================================================

**Current Status:** Partially implemented (65% complete)

**Integration Loop:**
Smartwatch Sync → AI Coach → Train → Session Logging → Progress

**Features:**
- HealthKit authorization flow
- Connection status display
- Recovery status scoring
- Recent biometric data display
- Apple Watch/Health integration
- Premium-gated feature

**Data Types:**
- Heart rate
- Recovery metrics
- Sleep data
- Training load
- HRV (heart rate variability)

**Fallback Behavior (works now):**
- AI Coach works without wearable data
- Self-reported readiness available
- Training recommendations via conversation

**Known Gap:**
- Backend sync endpoints need verification
- Real-time data flow from Apple Watch needs testing

============================================================
10. PLAY / MATCHMAKING RULES
============================================================

Play is one of the most important parts of the product.

Requirements:
- users can find matches
- users can challenge others
- system should support 1v1, 2v2, 3v3 where applicable
- trust and reliability matter
- users should not hit dead-end empty states

### Matchmaking Features (90% complete):
- Match type selector (ranked, unranked)
- Tennis court picker (tennis-specific)
- Rating range controls with presets and manual editor
- Distance/radius control (10 mile default)
- Availability status toggle ("Available Now")
- Friend invite CTA
- Opponent list with comprehensive trust warnings
- Rating info card

### Trust System:
- Trust score (0-100)
- Trust tier badges ("trusted", "standard", "caution", "restricted")
- Dispute rate tracking
- Completion rate metrics
- Warning alerts before challenging low-trust players

### Challenge Lifecycle:
- Pending (awaiting response)
- Accepted (match ready)
- Completed (both submitted, scores match)
- Disputed (both submitted, scores differ)
- Waiting for Opponent (user submitted, opponent hasn't)

### Backend Integration (all working):
- `POST /matchmaking/find-opponents`
- `POST /challenges/create`
- `GET /challenges/pending`
- `POST /challenges/{id}/accept`
- `POST /challenges/{id}/result`

**Known Gap:**
- Decline challenge endpoint marked TODO

The difference between:
- discovering people
and
- discovering a realistically playable match
matters.

============================================================
11. TRAIN / DRILL RULES
============================================================

### Sport-Specific Drill Taxonomy:

**Basketball:**
- Form Shooting, Ball Handling, Free Throws, Defense, Conditioning

**Tennis:**
- Serve Practice, Groundstrokes, Footwork, Volleys, Match Play

**Soccer:**
- Dribbling, Passing, Shooting, Defending, Fitness

**Football:**
- Route Running, Catching, Throwing, Agility, Strength

### Train View Structure (85% complete):
- Sport selector with auto-refresh
- **Premium Gated:**
  - AI Weekly Drills
  - Daily Readiness Card
  - AI Coach Chat access
  - Skill Progression
- **Always Available:**
  - Log Session
  - Drill Library
  - Find Partner
  - Recommended Drills (10-20 min, sport-specific)
  - Recent Sessions
  - Challenge Creation

### Training Programs:
- Placeholder exists ("Coming Soon")
- Not yet implemented
- Should use AI coach drill generation for multi-week programs

============================================================
12. SOCIAL / CONTENT RULES
============================================================

### Posts (80% complete):
- Sport selector with auto-refresh
- Create post button
- Posts feed with sport filtering
- Like/unlike functionality
- Delete post option (for own posts)
- Comments support
- Empty state messaging

**Working endpoints:**
- `GET /posts/feed` (sport-filtered)
- `POST /posts/create`
- `POST /posts/{id}/like`, `DELETE /posts/{id}/like`
- `DELETE /posts/{id}`
- Comments API complete

**Known gap:**
- Image/video attachments not yet implemented

### Clips (80% complete):
- Sport selector
- Upload button (navigates to VideoUploadView)
- Clips feed with error handling
- Video display (ClipCard component)
- Empty state

**Working endpoints:**
- `GET /clips/` (sport-filtered)
- `POST /clips/create`
- `POST /clips/upload` (multipart form data)

**Known gap:**
- Full video player with controls needs implementation

### Friends & Messaging:
- Friends-only messaging (safety-gated)
- Friend request/accept flow required
- Comprehensive friends API implemented:
  - Send/accept/decline friend requests
  - Block/unblock users
  - Get friends list, pending requests, blocked users
  - Check friendship status

============================================================
13. PROFILE / IDENTITY RULES
============================================================

Profile identity matters a lot in SportsHub.

### Profile Features (75% complete):
- Profile header with gradient avatar (based on name hash)
- Display name and username (@handle)
- Bio section (add/edit with modal)
- Sport selector with detailed stats per sport:
  - Rating (numerical with tier badge)
  - Rank tier (Bronze, Silver, Gold, Platinum, Diamond, Master, Grandmaster)
  - Games played / Win rate percentage
  - Leaderboard rank (#)
  - Badges earned (count)

### Edit Capabilities:
- ✅ Change display name (modal input) - backend integrated
- ✅ Change username (with real-time availability check) - backend integrated
- ✅ Change bio (multi-line editor) - local only, backend sync TODO
- ⚠️ Profile picture upload - UI present, backend integration missing

### Username Editing Requirements:
- Real-time availability checking via `/users/check-username/{username}`
- Slug validation (lowercase, alphanumeric + underscores)
- Uniqueness enforcement
- Update propagation across profile surfaces
- Protection against malformed/offensive usernames

Do NOT assume username is permanently fixed.

**Known gaps:**
- Bio backend sync needs wiring
- Profile picture upload needs multipart form data endpoint (similar to video clips)

============================================================
14. TRUST / SAFETY / DISPUTE SYSTEMS
============================================================

SportsHub includes comprehensive trust and safety systems (85% complete).

### Trust Features:
- Trust score (0-100)
- Trust tier: "trusted", "standard", "caution", "restricted"
- Dispute rate (percentage)
- Completion rate
- Matches completed count
- Trust warnings before challenging low-tier players
- OpponentResponse includes all trust fields

### Dispute Flow:
- Disputed matches show "Under Review" status
- DisputeDetailView available for disputed matches
- Evidence upload workflow with type selection
- Evidence requirement checking
- Match evidence retrieval
- Dispute history tracking

### Backend Integration (all working):
- `GET /disputes/my-disputes`
- `POST /disputes/create`
- `GET /evidence/required/{challengeId}`
- `POST /evidence/upload/{challengeId}`
- `GET /evidence/match/{challengeId}`

### Content Moderation:
- Admin moderation dashboard (AdminDashboardView)
- Content moderation queue (ContentModerationView)
- Flag management (pending flags list)
- Moderation actions: approve, remove, ban
- Appeal handling
- User suspension controls

Important product rule:
Trust systems should feel protective, not hostile.

They should help answer:
- is this player reliable?
- is this content safe?
- can this match result be trusted?
- what happens if players disagree?

Users should not see raw backend/admin language.

============================================================
15. TOURNAMENT RULES
============================================================

**Current Status:** 60% complete (UI done, backend needs verification)

### Tournament Features:
- Sport selector (basketball, football, soccer, tennis)
- Filter tabs: Upcoming, In Progress, Completed, My Tournaments
- Tournament cards with details:
  - Name, date range, participant count
  - Prize pool (if any), entry fee
  - Status badge
- Tournament detail view navigation
- Create tournament button (premium-gated)
- Tournament creation form

### Non-Premium Tournament Access:
- **Non-premium users CAN join tournaments**
- Only tournament **creation** is premium-gated
- Viewing and joining tournaments is free for all

**Known gap:**
- Tournament endpoints not explicitly wired to APIClient.swift
- Need to add: `/tournaments/list`, `/tournaments/create`, `/tournaments/{id}`, `/tournaments/{id}/join`

============================================================
16. NOTIFICATIONS
============================================================

**Current Status:** 60% complete (framework ready, push service needs verification)

### Available Now Feature:
- Users can mark themselves as "Available Now"
- MatchmakingView has availableNow toggle
- Relevant users can be notified based on:
  - Same sport
  - Similar skill/rating
  - Same city/zone
  - Friend relationship
  - Recent opponent/rival
  - Team format interest
  - Notification preferences

### Critical Rule:
Do NOT blast everyone.
This should feel alive, timely, and high-signal.

Tennis-specific notification behavior should preserve court realism where possible.

**Known gap:**
- Push notification service needs end-to-end testing
- Notification preferences storage needs verification

============================================================
17. ADMIN / MODERATION RULES
============================================================

**Current Status:** 75% complete

### Role-Based Access:
- Admin users see AdminDashboardView instead of MainTabView
- Check: `sessionManager.isAdmin` (derived from `currentUser?.role == "admin"`)
- Routing logic in SportsHubApp.swift

### Admin Dashboard Sections:

**1. Overview Tab:**
- Platform statistics cards (total users, active users, suspended accounts, pending reports)
- Recent admin actions log

**2. Users Tab (UserManagementView):**
- User list with pagination and search
- User details modal with account status
- Suspend/unsuspend user actions

**3. Moderation Tab (ContentModerationView):**
- Content moderation queue
- Flag management (posts, comments, clips)
- Moderation actions (approve, remove, ban)
- Appeal handling

**4. Settings Tab:**
- Placeholder (needs implementation)

**Known gaps:**
- Admin settings page implementation
- Bulk moderation actions
- Admin activity audit log export

============================================================
18. CURRENT IMPLEMENTATION REALITY
============================================================

This project is far beyond the earlier "UI shell only" stage.

**Frontend Scale:**
- 32 Swift files
- Comprehensive view coverage
- Real API integration via APIClient.swift (970+ lines)
- Production-quality authentication (SessionManager.swift)
- StoreKit 2 premium subscriptions
- DesignSystem.swift with adaptive colors and reusable components

**Backend Scale:**
- 14,343 lines of Python code
- FastAPI application with 24 routers
- Comprehensive database models (SQLAlchemy)
- AI coaching logic (ai_coach.py, ai_orchestrator.py)
- ELO ranking service
- Push notifications service
- Video CDN integration
- JWT authentication

**Notable Frontend Files:**
- SessionManager.swift - central auth state management
- APIClient.swift - all networking, 70+ endpoints
- PlayView.swift - matchmaking and challenges
- TrainView.swift - drills, AI coach, session logging
- AICoachChatView.swift - conversational AI interface
- ProfileView.swift - user profile and stats
- MatchmakingView.swift - opponent finding with trust warnings
- AdminDashboardView.swift - moderation console

**Notable Backend Files:**
- main.py - FastAPI app with 24 routers
- models.py - core database models (1200+ lines)
- models_premium.py - premium features models
- routers/ - 24 API routers covering all features
- ai_coach.py - AI coaching logic
- elo_service.py - ranking calculations

**Documentation Files:**
- AI_CONTEXT.md (this file)
- STATE_OF_THE_UNION_2026_03_21.md
- API_GUIDE.md
- IMPLEMENTATION_STATUS.md
- QUICKSTART.md

Important implication:
Do NOT plan as though backend/API/auth/social/AI are still hypothetical.
Work from the real codebase and refine current implementation rather than rebuilding imagined architecture from scratch.

============================================================
19. CRITICAL ARCHITECTURE PATTERNS
============================================================

### 19.1 Session Management Pattern
**SessionManager as EnvironmentObject:**
```swift
// In SportsHubApp.swift:
ContentView()
    .environmentObject(sessionManager)

// In any view:
@EnvironmentObject var sessionManager: SessionManager
```

**Session Persistence:**
- Token: Keychain (key: "sportshub_auth_token")
- User: UserDefaults (key: "sportshub_cached_user")
- Auto-restoration on every app launch via `restoreSession()`

**Auth Flow:**
1. App Launch → check Keychain → restore session if token exists
2. Login → save token to Keychain → fetch user → update @Published state
3. Logout → clear Keychain + UserDefaults → reset API token → show AuthenticationView

### 19.2 Sport Context Pattern
```swift
// Each major view has:
@State private var selectedSport: String = "basketball"

// Sport picker updates state → triggers view refresh via .onChange()
```

### 19.3 Premium Gating Pattern
```swift
@EnvironmentObject var storeManager: StoreManager

if storeManager.isPremium {
    // Show premium feature
} else {
    // Show premium upgrade sheet
}
```

### 19.4 API Client Pattern
- Generic HTTP methods (GET, POST, PUT, DELETE)
- Bearer token authorization on all requests
- Comprehensive error handling and mapping
- Safe credential logging (no passwords in logs)
- Network resilience (timeout, no connection, DNS failure)

### 19.5 Design System Pattern
- Adaptive colors (light/dark mode)
- Spacing constants (Spacing.xs, .sm, .md, .lg, .xl)
- Corner radius constants (CornerRadius.sm, .md, .lg)
- Reusable modifiers: .cardBackground(), .primaryButton(), .secondaryButton()
- AvatarView with gradient generation based on name hash

============================================================
20. KNOWN BUG PATTERNS TO WATCH FOR
============================================================

### Bug Pattern 1: Backend Not Running
**Symptom:** Generic "Something went wrong" error on login
**Root Cause:** Backend server not started, connection refused
**Fix:** Start backend with `uvicorn main:app --host 0.0.0.0 --port 8000 --reload`
**Recent:** Fixed import errors (Enum → SQLEnum, added Index import) on March 27, 2026

### Bug Pattern 2: Missing Keychain Entitlements
**Symptom:** Token not persisting, logout on app restart
**Root Cause:** Keychain access group not configured
**Fix:** Check SportsHub.entitlements for keychain-access-groups

### Bug Pattern 3: Sport Context Mismatch
**Symptom:** Seeing wrong sport data after switching
**Root Cause:** API calls not using updated `selectedSport` state
**Fix:** Ensure `.onChange(of: selectedSport)` triggers loadData()

### Bug Pattern 4: Premium Check Race Condition
**Symptom:** Premium features briefly locked on app launch
**Root Cause:** StoreManager.isPremium not loaded yet
**Fix:** Check `storeManager.isLoading` before gating

### Bug Pattern 5: Password Encoding Issues
**Symptom:** Login fails with special characters in password
**Root Cause:** Improper URL encoding
**Fix:** Use URLComponents.percentEncodedQuery (already implemented correctly)
**Verified:** March 27, 2026 - passwords with `$` and other special characters work correctly

============================================================
21. KNOWN GAPS & TECHNICAL DEBT
============================================================

### High Priority:
1. **Profile Picture Upload** - UI present, backend integration missing
2. **Decline Challenge Endpoint** - TODO marked in PlayView
3. **Training Programs** - "Coming Soon" placeholder, no implementation
4. **Smartwatch Sync Backend** - UI works, actual data sync needs verification
5. **Tournament Endpoints** - Not in APIClient, needs wiring

### Medium Priority:
6. **Search Functionality** - Search bar exists, backend endpoint needs verification
7. **Team Matchmaking** - "Coming Soon" button, no backend support
8. **Notifications Push Service** - Framework ready, needs end-to-end testing
9. **Admin Settings Page** - Placeholder only
10. **Bio Update Backend Sync** - Local only, server sync TODO

### Lower Priority:
11. **Video Player in Clips** - Placeholder, full controls missing
12. **Upload Progress Tracking** - No progress bar for video/image uploads
13. **Performance Predictions** - Premium feature, not implemented
14. **Goals System UI** - Backend models exist, no frontend views
15. **Highlights Generation** - UI shell exists, curation logic unclear

### Code Quality:
16. **ContentView.swift Legacy File** - Unused, should be deleted
17. **Error Handling Inconsistency** - Some views robust, others just print
18. **No Offline Support** - All features require network, no local caching

============================================================
22. WHAT IS OUTDATED FROM EARLIER CONTEXT
============================================================

The following earlier assumptions are no longer reliable:
- "pre-backend"
- "empty-state shell only"
- "auth not implemented"
- "backend API not implemented"
- "database not implemented"
- "network layer not implemented"
- "files to create" for many files that already exist
- "next immediate step = build backend API"
- "Current App State (as of 2026-03-06)" as a representation of today's reality

Do not use those assumptions when generating code or plans.

============================================================
23. HOW AN LLM SHOULD BEHAVE WHEN HELPING THIS PROJECT
============================================================

When helping with SportsHub:
- treat it as a real, production-quality product
- use the actual codebase state, not stale assumptions
- avoid generic startup fluff
- avoid toy-prototype simplifications
- respect the six-tab structure
- respect sport-specific realism (especially tennis court requirements)
- preserve safety-first messaging rules (friends-only DMs)
- preserve premium gating philosophy (visible but gated on use)
- preserve AI Coach conversational requirements (useful without wearables)
- preserve notification anti-spam realism (high-signal only)
- preserve trust / evidence / moderation direction
- build with current repo/checkpoint awareness

If something is already implemented, refine it.
Do not casually propose recreating the whole app.

**Verification before changes:**
- Read existing files before modifying
- Understand current patterns before suggesting new ones
- Test APIs before claiming they work
- Be honest about what's implemented vs what's TODO

**When debugging:**
1. Check if backend is running
2. Verify endpoint exists in APIClient
3. Check SessionManager state
4. Verify premium status if feature is gated
5. Test with actual data, not assumptions

============================================================
24. RECOMMENDED PRIORITIES FOR CONTINUATION
============================================================

### Priority 1: Complete Core Flows (High Value)
1. Wire tournament endpoints to APIClient
2. Implement decline challenge endpoint
3. Complete profile picture upload
4. Fix bio backend sync

### Priority 2: Verify & Polish (Medium Value)
5. Test smartwatch sync end-to-end
6. Test push notifications
7. Verify premium sync (StoreKit → backend)
8. Polish search functionality

### Priority 3: Implement Missing Features (Lower Value)
9. Training programs system
10. Video player in clips
11. Goals system UI
12. Team matchmaking

### Priority 4: Quality & Polish (Ongoing)
13. Consistent error handling
14. Offline support
15. Performance optimization
16. Admin tools polish

============================================================
25. SHORT STATE OF THE UNION
============================================================

**As of March 27, 2026:**

SportsHub is a production-quality multi-sport platform at **~85% completion**. It has real authentication (working end-to-end), comprehensive API integration (70+ endpoints), premium subscriptions via StoreKit 2, functional AI coaching, trust & dispute systems, admin moderation, and comprehensive matchmaking.

Recent work fixed critical backend import errors, verified authentication works correctly (including special characters in passwords), and confirmed the backend runs successfully.

Top priorities: Wire tournament endpoints, add decline challenge, complete profile picture upload, verify smartwatch sync, test push notifications.

This is NOT a prototype. Treat it as a real product with real users, real data, and real backend infrastructure. Refine what exists rather than rebuilding from scratch.
