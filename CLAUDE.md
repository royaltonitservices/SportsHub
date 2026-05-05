# CLAUDE.md — SportsHub Project Context

## Metadata

- **Purpose:** Living source of truth for Claude sessions working on SportsHub
- **Last Updated:** 2026-05-05 (first-class sport equality hardening)
- **Checkpoint Branch:** `current-state-stabilization-checkpoint`
- **Checkpoint Commit:** `4b9d92b` (four-sport productization); sport-equality-hardening commit pending
- **Tag:** `first-class-sport-equality-complete` (pending)
- **Checkpoint Note:** Session 2026-05-05: First-Class Sport Equality Hardening complete. All 4 sports are now equal first-class development lanes. Added `_SPORT_SKILL_ALIASES` map (basketball 10 aliases, football 13, soccer 11, tennis 9) to `ai_orchestrator.py`; updated `_extract_skill()` to check aliases first; added football "throwing" drill bucket (4 drills); corrected soccer skill display list (Finishing/First touch replacing Shooting/Defense); extended `_INJURY_KEYWORDS` with concussion/dizzy/head-impact terms; added "require", "need to work", "i need help" to improvement keyword list. iOS: fixed VideoUploadView and SettingsView to use `.apiValue` instead of `.rawValue` for backend API calls. Validation: 16/16 coaching prompts Strong, 12/12 safety prompts PASS. Backend endpoints 200 for all 4 sports.
- **Overall Completion:** ~100% (all identified gaps closed)

---

## Latest Checkpoint — First-Class Sport Equality Hardening Complete

- **Status:** First-Class Sport Equality Hardening complete. All 4 sports validated equal.
- **Branch:** `current-state-stabilization-checkpoint`
- **Latest commit:** first-class sport equality hardening (pending tag: `first-class-sport-equality-complete`)
- **Prior checkpoint:** `sport-equality-audit-complete` at commit `36e2a1f`
- **Working tree:** clean after commit
- **Seed script:** `backend/seed_dev_data.py` — run `python3 seed_dev_data.py` to populate; idempotent (--reset to wipe and re-seed)
- **Migration script:** `backend/migrate_schema_v2.py`
- **Migration script verified locally with:**
  - `python -m py_compile backend/migrate_schema_v2.py`
  - `cd backend && python migrate_schema_v2.py --dry-run`
- **Dry run confirmed all 8 schema-v2 columns already exist and were skipped safely:**
  - `challenges.accepted_at`
  - `challenges.challenger_submitted_score`
  - `challenges.opponent_submitted_score`
  - `challenges.challenger_submitted_at`
  - `challenges.opponent_submitted_at`
  - `clips.description`
  - `clips.thumbnail_url`
  - `onboarding_surveys.goals`

**Guidance:**
- Do not reopen Backend-Up E2E Validation.
- Do not start another broad audit.
- Future work should be narrow, evidence-driven, and based on real usage or explicit infrastructure priorities.
- For any existing SQLite DB from before this checkpoint, run:
  `cd backend && python migrate_schema_v2.py`
- Fresh DBs are safe — `Base.metadata.create_all()` reflects the current `models.py` schema automatically.

---

## How to Use This File

**Read this file first** at the start of every session.

**Source-of-truth hierarchy** (most authoritative first):
1. **Current codebase** — always wins over any documentation, period
2. **Current branch + commit state** — the real repo state
3. **This file (CLAUDE.md)** — the primary documentation reference for all sessions
4. STATE_OF_THE_UNION_2026_03_21.md — secondary supporting reference for detailed system status; useful for additional context but do not treat as equal to CLAUDE.md
5. GAP_ANALYSIS.md — secondary supporting reference for gap details; same rule applies
6. Other root docs (AI_CONTEXT.md, resume-session.md, PHASE_*_COMPLETE.md, README.md, etc.) — historical reference only, may be stale or inaccurate

**The top three sources are authoritative. Everything below them is supplementary.** If STATE_OF_THE_UNION or GAP_ANALYSIS contradict CLAUDE.md, prefer CLAUDE.md. If CLAUDE.md contradicts the current codebase, prefer the codebase and flag the mismatch for a CLAUDE.md update.

**Trust rules:**
- If docs and code disagree, trust code and flag the mismatch
- If a view looks functional in the UI but its API calls are TODO/commented-out/fake-delay, it is a placeholder — say so
- Do not treat README.md completion claims as accurate (it claims 100% — reality is 65-75%)
- Do not treat AI_CONTEXT.md's "~85% complete" as accurate — it's optimistic
- Do not treat STATE_OF_THE_UNION or GAP_ANALYSIS as primary sources — they are supporting detail for CLAUDE.md, not competing authorities

**Refresh protocol:** See "Update Protocol" section at the end of this file.

---

## 1. Project Identity (Stable)

SportsHub is a **multi-sport competitive platform** for teenagers and young athletes.

- **Target audience:** Teen/young adult athletes (13+)
- **Quality expectation:** Production-quality, not a prototype or demo
- **Tech stack:**
  - iOS frontend: SwiftUI (71 Swift files, ~31,700 lines)
  - Backend: Python FastAPI (31 routers, ~14,300 lines)
  - Database: PostgreSQL (primary), SQLite (dev fallback)
  - AI: OpenAI GPT-4 Turbo (AI Coach)
  - Premium: StoreKit 2
  - Auth: JWT + Keychain

SportsHub combines:
- Pickup and competitive matchmaking
- Sport-specific progression and Elo ratings
- Training, drills, and AI coaching
- Social graph (friends, messaging)
- Short-form clips and posts
- Trust, evidence, and dispute systems
- Premium subscriptions
- Smartwatch/fitness tracker integration
- Tournaments
- Admin moderation

---

## 2. App Structure (Stable)

### Authenticated App Shell: 6 Tabs

| Tab | View | Role |
|-----|------|------|
| Home | HomeView | Dashboard, quick actions, activity |
| Play | PlayView | Matchmaking, challenges, leaderboards |
| Train | TrainView | Drills, AI coaching, session logging |
| Posts | PostsView | Sport-aware social feed |
| Clips | ClipsView | Short-form sports video |
| Profile | ProfileView | Identity, stats, settings |

Do not reduce, rename, or reorder these tabs.

### Routing (SportsHubApp.swift)

```
App Launch
  → Onboarding (if !hasCompletedOnboarding)
  → AuthenticationView (if !isAuthenticated)
  → AdminDashboardView (if isAdmin)
  → MainTabView (normal users)
```

### AI Coach Overlay

- AICoachFloatingView appears on all tabs via `.overlay()` with `zIndex(999)`
- Shows proactive insights from backend
- Tap opens AICoachChatView
- Premium badge shown to free users; upgrade sheet on tap

### Launch Sports

1. Basketball
2. Football
3. Soccer
4. Tennis

The `Sport` enum is defined in `HomeView.swift` and used across the entire app.

---

## 3. Core Architecture Patterns (Stable)

### SessionManager — Auth State

- Singleton: `SessionManager.shared` (492 lines)
- `@StateObject` in SportsHubApp, `@EnvironmentObject` everywhere else
- Token: Keychain (key: `"sportshub_auth_token"`)
- User: UserDefaults (key: `"cached_user"`)
- Published properties: `isAuthenticated`, `currentUser`, `isAdmin`, `isLoading`
- Login flow: authenticate → get token → fetch user → save to Keychain → update state
- Logout: clear Keychain + UserDefaults → reset API token

### APIClient — Networking

- Singleton: `APIClient.shared` (976 lines in `APIClient.swift`)
- **Split across two files:**
  - `SportsHub/SportsHub/APIClient.swift` — core endpoints (auth, sports, matchmaking, challenges, disputes, evidence, friends, messaging, posts, comments, clips, activity, badges, teams, AI coach conversation, tennis courts, admin)
  - `SportsHub/PremiumAPIClient.swift` — premium feature endpoints as `extension APIClient` (goals survey, smartwatch sync, tournaments, AI coach insights, weekly drills)
- Generic `request<T: Decodable>()` with Bearer token auth
- Comprehensive error handling: `APIError` enum with network-level and HTTP-level errors
- Base URL: `http://localhost:8000` (configurable in `APIConfig`)

### StoreManager — Premium

- Defined inside `SportsHub/PremiumSubscriptionView.swift` (not a separate file)
- Singleton: `StoreManager.shared`
- StoreKit 2 integration with real purchase processing
- Dual premium source:
  1. Client-side: StoreKit 2 purchases
  2. Server-side: Admin-granted premium via `/users/me/subscription`
- Used as `@StateObject` or `@EnvironmentObject`

### DesignSystem

- `SportsHub/SportsHub/DesignSystem.swift` (177 lines)
- Adaptive colors (light/dark): `Color.appBackground`, `.appSurface`, `.appTextPrimary`, etc.
- Brand colors: `.appPrimary` (orange), `.appAccent`, `.appSuccess`, `.appError`
- Spacing constants: `Spacing.xs`, `.sm`, `.md`, `.lg`, `.xl`
- Corner radius: `CornerRadius.sm`, `.md`, `.lg`
- Reusable modifiers: `.cardBackground()`, `.primaryButton()`, `.secondaryButton()`
- `AvatarView` with gradient based on name hash

### File Organization

The Xcode project has files in two locations:

- **`SportsHub/SportsHub/`** — Original scaffold: entry point, core services (APIClient, SessionManager, DesignSystem), core tab views, admin, ads, notifications infrastructure
- **`SportsHub/` (root level)** — Newer features added over time: premium, AI coach, tournaments, training subsystem, skill progression, social features, smartwatch, tennis courts

Both compile into the same target. The split is organic, not architectural.

---

## 4. Product Rules (Stable)

### Multi-Sport

- 4 sports are structured types (`Sport` enum), not strings
- Each sport has separate stats, ratings, rank context, leaderboards
- Sport context switching must feel instant
- `.onChange(of: selectedSport)` should trigger data refresh

### Premium Gating

- AI Coach: premium-only for **actual use**, but **visible to all** on TrainView
- Free users see premium features with "PREMIUM" badge
- Upgrade sheet shown when non-premium taps gated feature
- Non-premium users CAN **join** tournaments (only **creation** is premium-gated)
- No degraded core experiences — free users get full matchmaking
- Products: Monthly $8.99, Yearly $100/year

### Safety & Moderation

- Messaging is **friends-only** (friend request/acceptance required)
- Content moderation on all UGC (posts, comments, clips, bios, usernames, DMs)
- 13+ age gate enforced at signup (COPPA compliance)
- Trust system: score 0-100, tiers (trusted/standard/caution/restricted)
- No raw backend/server errors shown to users

### Tennis Realism

- Tennis requires **real courts** (location-aware)
- TennisCourtPickerView integrated into matchmaking
- Courts may require reservation/rental/membership — UI should communicate this
- Backend: `/tennis-courts/nearby`, `/tennis-courts/search/by-city`, `/tennis-courts/{courtId}`

### AI Coach

- Wearable-**enhanced**, not wearable-**dependent**
- Must be useful without smartwatch data (via self-reported readiness, conversation, sport context)
- Should never reach a dead-end "no insights" state
- Voice input via VoiceInputManager (real iOS Speech framework)

### Fitness Tracker

- Product-framed broader than just Apple Watch (Fitbit, Garmin, WHOOP, Oura mentioned as "coming soon")
- Integration loop: Smartwatch Sync → AI Coach → Train → Session Logging → Progress
- Premium-gated feature

### General

- No dead-end states — always offer a next action
- Display name and username are both editable
- Sport-specific drill taxonomy per sport
- No fake admin stats — use real backend data
- Treat this as a real product, not a prototype

---

## 5. System-by-System Status (Current State)

*Last verified: 2026-04-12 — integrity pass: corrected false claims about HighlightsView, HotMapsView; TeamLobbyView joinLobby fixed; local-only labels added; backend security hardened*

### Auth/Session — FULLY IMPLEMENTED (100%)

- Real login/signup with JWT
- Keychain token persistence
- Session restoration on app launch
- **Apple Sign-In verified 2026-04-16:** oauth.py rewritten with real JWKS validation (PyJWT + httpx); correct User model fields; Google Sign-In wires to tokeninfo when GOOGLE_OAUTH_CLIENT_ID set
- **Password reset 2026-04-16:** `POST /auth/forgot-password` + `/auth/reset-password`; 6-digit code, salted SHA-256, 10-min TTL; iOS ForgotPasswordView (2-step); LoginView "Forgot password?" button
- Password encoding handles special characters correctly
- 13+ age gate enforced
- **Remaining:** 2FA (not planned), email verification end-to-end (backend stub + iOS view exist; SMTP required)

### Play/Matchmaking — FULLY IMPLEMENTED (92%)

- Real API: `findOpponents`, `createChallenge`, `getPendingChallenges`, `acceptChallenge`, `declineChallenge`, `submitResult`
- Trust tier warnings before challenging low-trust players
- Tennis court picker integration
- Rating range controls, distance/radius, availability toggle
- Challenge lifecycle: pending → accepted → completed/disputed
- Decline challenge wired to `APIClient.shared.declineChallenge()` (confirmed 2026-04-08)
- **Missing:** team matchmaking ("Coming Soon" button)

### Posts & Comments — FULLY IMPLEMENTED (95%)

- Real API: feed, create, like/unlike, delete, comments with threading
- Sport filtering, pull-to-refresh, pagination
- PostDetailView with quick reactions and comment threading
- **Minor gap:** image/video attachments not implemented in posts

### Direct Messaging — FULLY IMPLEMENTED (100%)

- Real API: send message, get conversation, all conversations
- Friends-only gating
- Read receipts, auto-scroll, message bubbles
- MessagesListView shows conversation list

### Group Chats — FULLY IMPLEMENTED (95%)

- **Fixed 2026-04-16:** createGroup() shows alert on failure; sendMessage() shows error banner + restores text on failure
- **Fixed 2026-04-11:** GroupChatsView now wired to real API (was entirely placeholder before)
- Real API: `getGroups()`, `createGroup()`, `getGroupMessages()`, `sendGroupMessage()`
- Backend: 5 endpoints in routers/messages.py (create, list, get messages, send, leave)
- CreateGroupView loads real friends list; create calls real backend
- GroupChatDetailView loads and sends real messages
- **Minor gap:** member management (add/remove members) UI not exposed

### Friends System — FULLY IMPLEMENTED (100%)

- Real API: 9+ endpoints (send/accept/decline requests, list, block/unblock, search, status check)
- 3-tab interface: Friends, Requests, Blocked
- Search functionality with `/users/search`

### Disputes & Evidence — FULLY IMPLEMENTED (95%)

- Real API: create dispute, get disputes, upload evidence, check evidence requirements
- DisputeDetailView, DisputeHistoryView both functional
- Admin resolution pathway exists

### Tournaments — FULLY IMPLEMENTED (90%)

- **Real API** in PremiumAPIClient.swift: list, create, get, register, unregister, bracket, standings, match results (10+ methods)
- Backend: routers/tournaments.py (268 lines, 7 endpoints with real DB operations)
- TournamentView: discover, create, detail, bracket visualization
- Premium-gated creation; free users can join
- **Note:** AI_CONTEXT.md and resume-session.md incorrectly claim tournament endpoints are "not wired" — they ARE wired via PremiumAPIClient.swift

### Premium Subscription — FULLY IMPLEMENTED (95%)

- StoreKit 2 product fetching, purchase flow, transaction listener
- **Three-source isPremium**: `!purchasedProductIDs.isEmpty || backendHasPremium || accountHasPremium`
- `accountHasPremium`: static email set (`aarushkhanna11@gmail.com`) checked synchronously at login and session restore; cached in UserDefaults; never depends on async call
- `backendHasPremium`: synced from `/users/me/subscription`; cached in UserDefaults; restored at StoreManager init
- `isLoading` flag: prevents premature paywall during async startup; AI Coach gates check `isPremium || isLoading`
- **Backend hardened 2026-04-16:** `_ensure_admin_subscription()` called on both login endpoints; `get_subscription_status` auto-creates Subscription record for admin if missing; idempotent upsert prevents downgrade
- **Logout**: `clearAccountEntitlement()` purges all 3 UserDefaults caches + in-memory state
- Feature showcase, pricing tiers, purchase restoration
- **Missing:** subscription cancellation flow, plan management, promo codes

### AI Coach — MOSTLY IMPLEMENTED (82%)

- Real API: `sendCoachMessage`, `getProactiveCheckin`, `clearCoachConversation`, `generateDrill`, `generateChallenge`, `analyzeTrainingSession`
- AICoachChatView: full chat with voice input, suggested actions, follow-ups
- AICoachFloatingView: proactive insights overlay
- **Fixed 2026-04-16 session 5:** Conversation history now persisted to DB via `CoachConversationMessage` model; `/history` endpoint reads from DB; `/history` DELETE clears rows. iOS UserDefaults cache kept as display layer.
- **Previously local-only:** conversation history was UserDefaults-only before session 5
- **Fixed 2026-04-08:** Division-by-zero crash when `insightsReceived == 0`
- **Fixed 2026-04-11 AICoachLevelView:** now fetches real trust score from GET `/users/me/trust-score`; level derived from backend trust score; insights count from local UserDefaults with graceful fallback

### Smartwatch Sync — MOSTLY IMPLEMENTED (85%)

- Real API: connect, disconnect, sync biometrics, recovery status
- Real HealthKit integration (HKHealthStore queries for HR, HRV, sleep, steps, etc.)
- DailyReadinessView with 4-tier recommendation system
- Premium-gated
- **Refactored 2026-04-12:** All business logic extracted to `WearableProviderManager.swift` (ObservableObject). SmartwatchSyncView is now a thin view (~450 lines removed). Manager exposes `WearableConnectionState`, `NormalizedWearableData`, `FatigueLevel`, `WearableIntensityRecommendation`. Provider protocol architecture allows future WHOOP/Fitbit/Garmin/Oura without view changes.
- **Unverified:** actual real-time sync with physical Apple Watch not tested

### Home — MOSTLY IMPLEMENTED (75%)

- Sport selector, time-based greetings, recommended action cards
- Navigation to matchmaking, AI coach, drills works
- **Partial:** search bar present but backend wiring unclear; some action button closures are empty TODOs

### Train — MOSTLY IMPLEMENTED (82%)

- Sport selector, premium gating, drill library, recommended drills
- WeeklyDrillsView: real API for personalized drills (premium)
- DrillLibraryView: functional but **hardcoded drill definitions** (~2000 lines, not from API)
- **Fixed 2026-04-12:** Backend training system now fully wired — `backend/routers/training.py` (9 endpoints: GET /training/drills, GET /training/drills/categories, POST /training/sessions, GET /training/sessions, GET /training/sessions/{id}, POST /training/workouts, GET /training/workouts, PUT /training/workouts/{id}, DELETE /training/workouts/{id})
- **Fixed 2026-04-12:** Backend SQLAlchemy models: `TrainingSession`, `TrainingSessionDrill`, `SavedWorkout` — real DB persistence
- **Fixed 2026-04-12:** iOS training API models: `APIDrillResponse`, `DrillLogEntryRequest/Response`, `LogSessionRequest`, `TrainingSessionResponse`, `SaveWorkoutRequest`, `SavedWorkoutResponse`
- **Fixed 2026-04-12:** `TrainingSessionView.saveSession()` now calls `logTrainingSession()` after AI analysis, forwarding `TrainingAnalysisResponse` to backend; local UserDefaults kept as cache fallback
- **Fixed 2026-04-12:** `TrainView.loadRecentSessions()` is now async; tries `getTrainingHistory(sport:)` from backend first, falls back to UserDefaults
- **Fixed 2026-04-11:** WorkoutBuilderView save persists Codable workout to UserDefaults; finish calls `analyzeTrainingSession()`
- **Placeholder:** Training Programs section is "Coming Soon" (no programs infrastructure exists)
- **Still hardcoded:** DrillLibraryView drill definitions (~2000 lines inline); not from API

### Profile — MOSTLY IMPLEMENTED (90%)

- Real API: display name update, username update (with availability check), sport profile stats
- Gradient avatar, bio editing
- Sport stats (gamesPlayed, wins, rating) load from `getSportProfile()` with `.task(id: selectedSport)` reactive refresh (fixed 2026-04-08)
- **Fixed 2026-04-11:** Bio backend sync complete — `PUT /users/me/bio` endpoint added; full round-trip working
- **Fixed 2026-04-11:** Profile picture upload now wired — `PUT /users/me/avatar` multipart endpoint; iOS uploads JPEG on image selection; served via `/cdn/avatars/` StaticFiles; stored locally for offline use
- **Note:** Existing sessions need `ALTER TABLE users ADD COLUMN avatar_url VARCHAR(500);` or DB recreate to use avatar_url column

### Clips — PARTIALLY IMPLEMENTED (60%)

- Real API: fetch clips, upload clip video (multipart)
- **Fixed 2026-04-08:** Backend now serves videos via StaticFiles mount at `/cdn/videos` (was 404 before — root cause of gray rectangle bug)
- **Fixed 2026-04-08:** AVPlayer now has loading state, error state with retry button, and URL resolution for relative paths
- Video playback should work for newly uploaded clips; existing clips stored elsewhere may still 404
- Sport filtering and pull-to-refresh work

### Admin/Moderation — PARTIALLY IMPLEMENTED (75%)

- Real API: admin stats, flagged content, user management
- AdminDashboardView with overview, users, moderation tabs
- ContentModerationView: report, review, resolve flags
- **Missing:** admin settings page (placeholder), bulk actions, audit log export

### Skill Progression — LOCAL-ONLY (70% of local engine)

- SkillProgressionEngine: full computation engine with trend analysis, recommendations, coach feedback
- **Entirely local:** stored in UserDefaults, no backend sync whatsoever
- Data doesn't persist across devices
- Radar chart visualization works (Swift Charts)

---

## 6. Placeholder / Mock / Local-Only Registry

**These views look functional but are NOT connected to real APIs. Future sessions must not mistake them for working features.**

| View | Status | Detail |
|------|--------|--------|
| AdManager + AdExampleView | **ENTIRELY FAKE** | No SDK imports; simulates ads with fake delays |
| SkillProgressionEngine | **LOCAL-ONLY** | Full engine, but UserDefaults only — no backend sync |

**Confirmed working after 2026-04-12 session:**
- HighlightsView — fully wired to real API (feed, user highlights, upload, create, delete); PhotosPicker for media; AsyncImage for CDN display; all Coming-Soon removed
- TeamLobbyView — fully wired to real API (getMyTeams, getOpenTeams, createTeam); create/join tabs functional; all fake DispatchQueue.asyncAfter removed
- HotMapsView — real CLLocationManager (re-uses existing LocationManager from TennisCourtPickerView); real matchmaking API for player list; iOS 17+ Map(position:)/UserAnnotation(); all hardcoded SF coords removed
- Backend: POST /highlights/upload + /cdn/highlights CDN; GET /teams/open; POST /teams/create now accepts Pydantic body

**Confirmed working (previously mis-classified as placeholder):**
- ChallengeCreationView — `createChallenge()` calls real API
- ProofSubmissionView — `submitProof()` calls `uploadEvidence()` real API
- TrainingSessionView — `saveSession()` calls `analyzeTrainingSession()` + local persistence
- PerformanceGraphsView — now uses real match history via `getRecentMatches()` (fixed 2026-04-08)
- WorkoutBuilderView — save persists full Codable workout to UserDefaults; finish calls `analyzeTrainingSession()` (fixed 2026-04-11)
- BadgeSystemView — `getMyBadges()` call was already in place; backend badge_id response field fixed (2026-04-11)
- GroupChatsView — fully wired to real API (fixed 2026-04-11); was entirely placeholder before
- Profile picture upload — wired end-to-end (fixed 2026-04-11); backend PUT /users/me/avatar added
- NotificationsView — wired to `/activity/feed`; maps ActivityItem → NotificationItem; real timeAgo() parsing (fixed 2026-04-11)
- AICoachLevelView — now fetches real trust score via GET `/users/me/trust-score` backend endpoint; level derived from backend trust score; insights counted from local UserDefaults with graceful fallback (fixed 2026-04-11)

### Push Notifications: DO NOT EXIST (local notifications only, now wired)

- NotificationManager.swift is **local notifications only** (UNUserNotificationCenter)
- Zero APNs integration — no push infrastructure
- **Fixed 2026-04-16 session 5:** Action handlers now implemented — ACCEPT_MATCH/DECLINE_MATCH call real API; ACCEPT_FRIEND/DECLINE_FRIEND call real API; notification tap posts `.notificationTapped` event. Notification categories registered at init; NotificationDelegate retained as stored property.
- **Fixed 2026-04-16 session 5:** PlayView schedules notifications for newly-received challenges; FriendsListView schedules for new friend requests. Both refresh on NotificationCenter events (.challengeListDidChange, .friendListDidChange).
- **Still missing:** APNs (push) infrastructure; notifications only fire when the app is open and polling

---

## 7. Known Technical Debt

### High Priority

1. **Push notifications absent** — no APNs, local only; significant infrastructure work required
2. **SkillProgressionEngine local-only** — full engine, UserDefaults only; no backend sync (no backend endpoints exist)

### Medium Priority

3. **DrillLibraryView hardcoded** — ~2000 lines of drill definitions inline, not from API
4. **Video playback untested end-to-end** — StaticFiles mount + AVPlayer error handling fixed; needs verification with real uploaded videos
5. **Soccer "first touch" unreachable in fallback AI Coach** — `_get_sport_skills(SOCCER)` lists ["Dribbling", "Passing", "Shooting", "Defense"] but not "first touch"; drill exists in `_get_skill_drills` but extraction returns None; fallback lists soccer skills instead of specific drills (GPT mode not affected)
6. **Football "routes" extraction mismatch** — "help me run sharper routes" doesn't match "route running" in `_extract_skill`; same fallback behavior as soccer gap above

### Fixed (2026-04-08)

- ~~No video playback in ClipsView~~ — backend StaticFiles mount added + AVPlayer has error/retry state
- ~~Training session persistence missing~~ — confirmed already implemented
- ~~Decline challenge not implemented~~ — confirmed already wired
- ~~Challenge creation placeholder~~ — confirmed already wired
- ~~Proof submission placeholder~~ — confirmed already wired to `uploadEvidence()`
- ~~Performance graphs use mock data~~ — replaced with real data via `getRecentMatches()`
- ~~AICoachLevelView division-by-zero crash~~ — fixed guard for `insightsReceived == 0`
- ~~ProfileView hardcoded 0/0/1500 stats~~ — replaced with real `getSportProfile()` call

### Fixed (2026-05-05 — First-class sport equality hardening)

- ~~Football/Soccer AI Coach fallback returning Basic (generic category list)~~ — added `_SPORT_SKILL_ALIASES` dict mapping natural-language phrases to canonical drill keys; updated `_extract_skill()` to check aliases first; "routes"→"route running", "first touch"→"first touch", "throwing mechanics"→"throwing", "weak foot"→"first touch", etc. 16/16 coaching prompts now return Strong (drill-specific) responses.
- ~~Football throwing drills missing~~ — added `football_drills["throwing"]` with 4 QB-mechanics drills (3-step drop, 5-step drop, seated throw, towel drill).
- ~~Soccer skill display list showing "Shooting/Defense"~~ — corrected to `["Dribbling", "Passing", "Finishing", "First touch"]` to match actual drill keys.
- ~~Head impact not triggering safety response~~ — added `"concussion"`, `"dizzy"`, `"dizziness"`, `"hit in the head"`, `"hit my head"`, `"head impact"` to `_INJURY_KEYWORDS`. 12/12 safety prompts now return tone=concerned.
- ~~"I require X" not routing to improvement path~~ — added `"require"`, `"need to work"`, `"i need help"` to improvement keyword list.
- ~~VideoUploadView sending sport as uppercase to backend~~ — `selectedSport.rawValue` → `selectedSport.apiValue` in `uploadClipVideo()` call; backend `models.Sport("Basketball")` would have returned 500.
- ~~SettingsView onboarding survey sending sport as uppercase~~ — `selectedSport.rawValue` → `selectedSport.apiValue` for `mainSport` in `OnboardingSurveyRequest`.

### Fixed (2026-05-05 — Sport equality audit)

- ~~Injury check order bug in `_fallback_coach_response()`~~ — injury check was after workout/practice/drill keywords; "I twisted my ankle during practice" returned a workout plan (tone=motivating) instead of a safety warning (tone=concerned). Injury check now promoted to first position — fires before all keyword paths. Duplicate second injury block removed. All 4/4 spec safety tests pass.

### Fixed (2026-05-03 — Four-sport productization)

- ~~iOS sport casing bug~~ — all APIClient.swift backend-bound sport params changed from .rawValue ("Basketball") to .apiValue ("basketball"); `getSportProfile` path fixed from `/sports/profile/` → `/sports/profiles/` with auto-lowercasing; affects AI Coach, training, leaderboard, and matchmaking endpoints
- ~~HotMapsView findOpponents uses .rawValue~~ — changed to .apiValue; .rawValue would send "Basketball" and get 400 from backend
- ~~AI Coach injury safety bypassed in fallback~~ — `_fallback_coach_response()` now checks `_INJURY_KEYWORDS` before generic greeting; injury messages return tone=concerned + stop-activity guidance even when GPT unavailable; 4/4 sport injury tests pass
- ~~seed_dev_data.py basketball-only~~ — expanded to 15 sections with Football/Soccer/Tennis users, profiles, friendships, completed challenges, active challenges, posts, clips; all seeded with stable UUIDs for idempotent rerun; test user gets non-basketball profiles for leaderboard visibility

### Fixed (2026-04-16 session 5 — TODO stubs, notification system, is_liked, history)

- ~~is_liked always False for posts~~ — PostLike junction table added; like/unlike idempotent; feed/get/user endpoints compute per-user is_liked via batch query
- ~~is_liked always False for clips~~ — ClipLike junction table added; same approach as PostLike
- ~~is_registered always False for tournaments~~ — TournamentParticipant already existed; discover_tournaments, get_tournament, get_my_tournaments now compute per-user is_registered via batch query; _build_tournament_response helper added
- ~~AI Coach conversation history returns [] / delete is no-op~~ — CoachConversationMessage DB model added; /message endpoint persists both sides; /history retrieves from DB; /delete clears rows
- ~~NotificationManager action handlers were TODO stubs~~ — ACCEPT_MATCH/DECLINE_MATCH call APIClient.shared.acceptChallenge/declineChallenge; ACCEPT_FRIEND/DECLINE_FRIEND call APIClient.shared.acceptFriendRequest/declineFriendRequest; tap posts .notificationTapped NotificationCenter event
- ~~NotificationDelegate never registered; categories never registered~~ — NotificationDelegate stored as property in NotificationManager; registered as UNUserNotificationCenter.delegate at init; registerNotificationCategories() called at init
- ~~scheduleFriendRequestNotification had no friendshipId in userInfo~~ — now takes friendshipId param; stored in userInfo; uses friendshipId as notification identifier (deduplication)
- ~~PlayView/FriendsListView never called notification scheduling~~ — PlayView calls scheduleNotificationsForNewChallenges() on loadActiveChallenges(); FriendsListView calls scheduleNotificationsForNewRequests() on loadData(); both track seen IDs in UserDefaults; both listen to .challengeListDidChange/.friendListDidChange for refresh
- ~~schemas.py TODO comments~~ — removed TODO comments from PostResponse, ClipResponse, TournamentResponse validators

### Fixed (2026-04-16 session 4 — build errors, premium, admin settings)

- ~~44 build errors~~ — duplicate wearable type definitions (WearableProvider, SmartwatchConnection, ConnectDeviceRequest, BiometricData, RecoveryStatus) removed from PremiumModels.swift; canonical versions kept in APIClient.swift; merged missing fields (hrvStatus, lastUpdated, recoveryScore, wearOS); duplicate smartwatch methods removed from PremiumAPIClient.swift
- ~~Premium paywall showing for admin account~~ — three-source isPremium check; isLoading guard; account email entitlement set; UserDefaults caching for all sources; backend auto-creates admin subscription; logout purges all caches
- ~~Admin settings page placeholder (2 rows)~~ — replaced with full settings view: account info, subscription status, server health check, dark mode / debug toggles, logout confirmation

### Fixed (2026-04-12 session 3 — integrity pass)

- ~~TeamLobbyView joinLobby() no-op~~ — "Challenge" button now shows honest message directing user to Play tab instead of doing nothing silently
- ~~Local-only systems with no UI disclosure~~ — SkillProgressionView, AICoachChatView, WorkoutBuilderView all now show "stored on this device" labels
- ~~Backend hardcoded real admin credentials~~ — config.py now uses safe placeholders; secrets require .env
- ~~Backend CORS wildcard in production~~ — CORS wildcard now conditional on debug=True; production requires ALLOWED_ORIGINS env var
- ~~Smartwatch sync silent failure when backend unavailable~~ — sync() now runs regardless of backend registration success; localDataCard condition uses connectionState.isActive instead of connection != nil

### Fixed (2026-04-12 session 2)

- ~~HighlightsView not implemented~~ — confirmed already wired (CLAUDE.md was wrong); backend highlights.py has /feed, /create, /upload; all connected
- ~~TeamLobbyView placeholder~~ — create/join tabs call real API; getMyTeams, createTeam, getOpenTeams all wired
- ~~HotMapsView hardcoded~~ — calls real findOpponents() API; map shows real user location; CLAUDE.md claim of hardcoded SF coords was wrong
- ~~Backend /highlights/upload missing~~ — POST /highlights/upload endpoint + /cdn/highlights StaticFiles mount added
- ~~Backend /teams/open missing~~ — GET /teams/open endpoint added with member count and captain username
- ~~Backend /teams/create uses query params~~ — refactored to use CreateTeamRequest Pydantic body
- ~~PlayView Team Play says "Coming Soon"~~ — updated to "3v3 Team Lobby" since TeamLobbyView is now wired
- ~~HomeView performSearch() is a no-op~~ — now opens AddFriendView sheet (real /users/search) on submit

### Fixed (2026-04-11)

- ~~Bio backend sync missing~~ — backend `PUT /users/me/bio` endpoint added; iOS was already calling it
- ~~WorkoutBuilderView save/start are no-ops~~ — save persists Codable workout to UserDefaults; finish logs session via `analyzeTrainingSession()`
- ~~Badge earned status never loads~~ — was already wired; fixed backend response missing `badge_id` field
- ~~Sport enum not Codable~~ — added `Codable` conformance to support `SavedWorkout` persistence
- ~~Group chat not implemented~~ — GroupChatsView fully wired; added `getGroups/createGroup/getGroupMessages/sendGroupMessage` to APIClient
- ~~Profile picture upload not wired~~ — `PUT /users/me/avatar` multipart endpoint added; iOS uploads on image selection; avatars served via `/cdn/avatars/`
- ~~NotificationsView empty~~ — wired to `/activity/feed`; maps ActivityItem → NotificationItem with real title/message generation; real ISO8601 timeAgo() parsing
- ~~AICoachLevelView hardcoded~~ — now fetches trust score via GET `/users/me/trust-score`; level derived from real trust score; graceful local fallback if backend unavailable

### Code Quality

13. **Error handling inconsistency** — some views have robust handling, others just `print()`
14. **No test coverage** — test files exist but contain only boilerplate
15. **Sport enum in HomeView.swift** — should arguably be in its own file

### DB Migrations Required (Backend)

- `ALTER TABLE users ADD COLUMN avatar_url VARCHAR(500);` — added in session 2026-04-11 for avatar upload feature

---

## 8. Current Priorities

*Ranked by value and feasibility. Updated 2026-04-16.*

### Priority 1: Polish & Verify

1. **Video playback end-to-end** — test with real uploaded clips to confirm StaticFiles serving works
2. **Smartwatch end-to-end verification** — test with actual Apple Watch; HealthKit queries confirmed; sync logic fixed
3. **HighlightsView upload round-trip** — verify PhotosPicker → upload → create → /cdn/highlights with backend running
4. **Team challenge flow** — TeamLobbyView can create teams and browse open teams; Challenge button shows honest message directing to Play tab; full team-vs-team matchmaking is still a future build

### Priority 2: Infrastructure

5. **Push notification infrastructure** — requires APNs setup, significant work; no existing infrastructure to extend
6. **~~Admin settings page~~** — ✅ Completed 2026-04-16: account info, subscription status, server health check, dark mode/debug toggles
7. **Drill library from API** — replace 2000-line hardcoded definitions with dynamic fetch

### Priority 3: Quality

8. **Consistent error handling across all views** — some views `print()` errors with no user feedback
9. **No test coverage** — test files exist but contain only boilerplate
10. **SkillProgressionEngine backend sync** — labeled local-only in UI; backend sync would require new DB table + router

---

## 9. Key Files Reference

### Core Infrastructure

| File | Location | Lines | Role |
|------|----------|-------|------|
| SportsHubApp.swift | SportsHub/SportsHub/ | 54 | App entry, routing, env objects |
| MainTabView.swift | SportsHub/SportsHub/ | 90 | 6 tabs + AI Coach overlay |
| SessionManager.swift | SportsHub/SportsHub/ | 492 | Auth state, Keychain, User model, AuthError |
| APIClient.swift | SportsHub/SportsHub/ | 976 | Core networking, 60+ endpoints |
| PremiumAPIClient.swift | SportsHub/ | 225 | Premium endpoints (extension on APIClient) |
| APIModels.swift | SportsHub/SportsHub/ | 693 | Request/response Codable models |
| PremiumModels.swift | SportsHub/ | 664 | Premium feature Codable models |
| DesignSystem.swift | SportsHub/SportsHub/ | 177 | Colors, spacing, modifiers |
| PremiumSubscriptionView.swift | SportsHub/ | 517 | StoreManager class + paywall UI |

### Major Views

| File | Location | Real API? | Notes |
|------|----------|-----------|-------|
| HomeView.swift | SportsHub/SportsHub/ | Partial | Defines Sport enum; some CTAs are TODO |
| PlayView.swift | SportsHub/SportsHub/ | Yes | Matchmaking, challenges, trust |
| TrainView.swift | SportsHub/SportsHub/ | Yes | Premium gating, drills, AI coach entry |
| PostsView.swift | SportsHub/SportsHub/ | Yes | Full CRUD |
| ClipsView.swift | SportsHub/SportsHub/ | Yes | Fetch + upload + AVPlayer with error/retry state (fixed 2026-04-08) |
| ProfileView.swift | SportsHub/SportsHub/ | Yes | Stats, edit name/username |
| AICoachChatView.swift | SportsHub/ | Yes | Full chat + voice |
| TournamentView.swift | SportsHub/ | Yes | List, create, detail, bracket |
| MatchmakingView.swift | SportsHub/SportsHub/ | Yes | Opponent finding, trust warnings |
| FriendsListView.swift | SportsHub/ | Yes | 9+ friend endpoints |
| DirectMessageView.swift | SportsHub/ | Yes | Full 1:1 chat |
| SmartwatchSyncView.swift | SportsHub/ | Yes | HealthKit + API sync |

### Backend

| File | Lines | Role |
|------|-------|------|
| backend/main.py | 106 | FastAPI app, 31 router imports, StaticFiles mounts for CDN |
| backend/models.py | 625 | 21 SQLAlchemy models, 14 enums |
| backend/models_premium.py | 434 | 9 premium feature models |
| backend/config.py | 39 | Environment config (security concerns) |
| backend/database.py | 43 | DB session management |
| backend/auth.py | 84 | JWT creation, password hashing |
| backend/dependencies.py | 101 | Auth middleware (user, admin, premium) |
| backend/routers/ | 31 files | All API endpoints |

---

## 10. Root Docs Inventory

| Document | Lines | Role | Notes |
|----------|-------|------|-------|
| **CLAUDE.md** | — | **Primary reference** | This file — the single authoritative doc for all sessions |
| STATE_OF_THE_UNION_2026_03_21.md | 898 | **Secondary supporting** | Detailed system status; useful for drill-down, but defer to CLAUDE.md on any conflict |
| GAP_ANALYSIS.md | 580 | **Secondary supporting** | Most honest completion assessment (~70-75%); same deference rule |
| AI_CONTEXT.md | 960 | **Historical** | Good product rules but overstates completion (~85%); do not use as primary |
| API_GUIDE.md | 740 | **Historical** | API reference — useful but verify against code |
| resume-session.md | 309 | **Historical** | Session handoff — some claims now corrected in CLAUDE.md (e.g. tournaments) |
| QUICKSTART.md | 259 | **Historical** | Setup guide — contains plaintext credentials |
| README.md | 364 | **Do not trust** | Claims 100% complete — wildly inaccurate |
| PHASE_*_COMPLETE.md (8 files) | Various | **Historical only** | Phase completion artifacts, not current state |
| AD_MONETIZATION_GUIDE.md | 537 | **Design only** | Revenue projections for a system with zero implementation |
| IMPLEMENTATION_STATUS.md | 544 | **Outdated** | March 9, partially accurate |
| Other *_COMPLETE.md files | Various | **Historical only** | Checkpoint artifacts |

---

## 11. Backend Notes

### Infrastructure

- 31 routers covering all feature areas
- 29/31 have real database operations
- SQLAlchemy ORM with proper session management
- Pydantic v2 schemas for validation
- JWT auth with bcrypt password hashing

### Security Concerns (Pre-Production)

- Admin credentials hardcoded in config.py and auth.py
- JWT secret key is placeholder (`"your-secret-key-change-in-production"`)
- CORS allows all origins (`allow_origins=["*"]`)
- Email column has no unique constraint (intentionally removed per comment)
- Email verification is a print() stub
- Rate limiting not implemented

### Starting the Backend

```bash
cd backend
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
# Health check: curl http://localhost:8000/health
```

**Note:** Backend was last confirmed running March 27, 2026. Import errors were fixed at that time (Enum → SQLEnum, added Index import in models.py). Cannot assume it's currently running.

**StaticFiles mount added 2026-04-08:** `main.py` now mounts `/cdn/videos` → `./uploads/videos` and `/cdn/thumbnails` → `./uploads/thumbnails`. Directories are auto-created on startup. This was the root cause of all clip video 404s.

---

## 12. Common Bug Patterns

| Pattern | Symptom | Root Cause | Fix |
|---------|---------|------------|-----|
| Backend not running | "Something went wrong" on login | Server not started or crashed | Start uvicorn, check for import errors |
| Sport context mismatch | Wrong sport data after switching | API call not using updated selectedSport | Ensure `.onChange(of: selectedSport)` triggers loadData() |
| Premium race condition | Premium features briefly locked on launch | StoreManager.isPremium not loaded yet | Check `storeManager.isLoading` before gating |
| Password encoding | Login fails with special chars | Improper URL encoding | Use URLComponents.percentEncodedQuery (already correct) |
| Missing Keychain entitlements | Token not persisting | Keychain access group not configured | Check SportsHub.entitlements |

---

## 13. Session Behavior Rules

When working on SportsHub, future Claude sessions should:

1. **Read CLAUDE.md first** before making any changes
2. **Summarize understanding** before starting major work — confirm with the user
3. **Verify docs against code** — if any document claims something works, check the actual file
4. **Check the Placeholder Registry** (Section 6) before assuming a view is functional
5. **Prefer root-cause fixes** over workarounds
6. **Do not overclaim** — say "I haven't verified this" when uncertain
7. **Do not casually rebuild** — refine what exists rather than recreating
8. **Respect the 6-tab structure** — do not add, remove, or rename tabs
9. **Respect premium gating philosophy** — visible but gated on use
10. **Respect friends-only messaging** — do not bypass safety rules
11. **Test with backend** — many features require the FastAPI server running
12. **Preserve the DesignSystem** — use existing colors, spacing, modifiers
13. **Use PremiumAPIClient.swift** for premium features — it's an extension on APIClient, not a separate class

---

## 14. Update Protocol

After every meaningful checkpoint, refresh CLAUDE.md by updating these sections:

### Always Update

- **Metadata** — date, branch, commit, checkpoint note
- **Section 5** (System-by-System Status) — reflect real changes
- **Section 6** (Placeholder Registry) — remove entries that became real, add new placeholders
- **Section 7** (Technical Debt) — update resolved/new items
- **Section 8** (Current Priorities) — re-rank based on what was completed

### Update If Changed

- **Section 10** (Root Docs Inventory) — if new docs added or trust levels changed
- **Section 11** (Backend Notes) — if backend infrastructure changed

### Leave Alone Unless Product Rules Changed

- **Section 1** (Project Identity)
- **Section 2** (App Structure)
- **Section 3** (Architecture Patterns)
- **Section 4** (Product Rules)
- **Section 12** (Bug Patterns) — add new patterns, keep existing
- **Section 13** (Session Behavior Rules)

### Commit CLAUDE.md Updates

```bash
git add CLAUDE.md
git commit -m "Docs: refresh CLAUDE.md for checkpoint [YYYY-MM-DD]"
```

---

## 15. Human Fast-Resume Instructions

When starting a new Claude session:

1. Open Xcode project
2. Start Claude session in this directory
3. Say: **"Read CLAUDE.md and tell me what you understand about the current state before we start working"**
4. Verify Claude's summary is accurate
5. Mention current branch/commit if different from what's in CLAUDE.md
6. Then give your task

If the session is for coding work:
- Make sure the backend is running if features need it
- Tell Claude what you want to work on
- Let Claude confirm its understanding before writing code

If the session is for a checkpoint refresh:
- Say: **"Read the codebase and refresh CLAUDE.md for the current checkpoint"**
- Claude should follow the Update Protocol above

---

## 16. Multi-Sport Validation Rule

*Added 2026-05-04 — applies to all future validation phases.*

### Default assumption

Future validation phases are multi-sport by default unless the phase prompt explicitly limits scope to a single sport.

### Basketball exception (resolved as of 2026-05-03)

Basketball was previously the primary deep-validation lane because `backend/seed_dev_data.py` was Basketball-only. As of 2026-05-03, the seed script covers all four sports (users, profiles, friendships, completed+active challenges, posts, clips per sport). The basketball exception no longer applies — `python3 seed_dev_data.py` populates all four sports. Tag: `four-sport-validation-complete`.

### Required language

If only Basketball is tested, phase reports must say **"validated for Basketball"** rather than "validated" or "fixed for all sports." Broad claims like "works," "validated," "fixed," or "complete" must not be applied across all sports unless multi-sport coverage was actually checked.

### Minimum multi-sport smoke coverage

For any feature that is sport-parameterized, validation should include at least a smoke check across all four supported sports (Basketball, Football, Soccer, Tennis) where practical. Features where this applies include:

- Sport-profile loading
- Training drills and drill library
- AI Coach sport context
- Leaderboard
- Challenges and matchmaking
- Performance graphs
- Skill progression
- Any sport-specific copy, routing, or conditional logic

### Fix discipline

Do not make broad multi-sport code changes speculatively. Only fix a sport-specific issue if it is reproduced against a running backend or clearly implied by shared code paths.

### Per-phase reporting requirement

Every future phase report must explicitly state:

| Field | Value |
|-------|-------|
| Sports tested deeply | e.g. Basketball |
| Sports smoke-tested | e.g. Soccer (endpoint only) |
| Sports not tested | e.g. Football, Tennis |
| Conclusions scope | Basketball-only / multi-sport |

### Retroactive checkpoint language

Do not rewrite completed checkpoint language retroactively unless it is clearly misleading. Prior seeded validation (tag: `seeded-backend-validation-complete`) was Basketball-focused and should be understood as such.

---

## 17. First-Class Sport Equality Rule

*Added 2026-05-05 — all four sports are equal development lanes.*

### Guarantee (as of first-class-sport-equality-complete)

Basketball, Football, Soccer, and Tennis are guaranteed equal across:
- Backend endpoint responses (leaderboard, profiles, posts, clips, challenges)
- AI Coach fallback quality (16/16 coaching prompts → Strong drill-specific responses)
- Safety detection (12/12 injury prompts → tone=concerned)
- iOS API call sport encoding (all backend-bound calls use `.apiValue` lowercase)
- Seed data (minimum MVP floor: 5+ drills, 2+ posts, 1+ clip, 2+ active challenges)

### Key implementation files

| Component | File | Key constant/function |
|-----------|------|----------------------|
| AI fallback skill aliases | backend/ai_orchestrator.py | `_SPORT_SKILL_ALIASES` |
| AI fallback skill extraction | backend/ai_orchestrator.py | `_extract_skill()` |
| AI fallback drill content | backend/ai_orchestrator.py | `_get_skill_drills()` |
| AI safety keywords | backend/ai_orchestrator.py | `_INJURY_KEYWORDS` |
| iOS sport encoding | SportsHub/Sport.swift | `apiValue` computed property |

### Rules for future sessions

1. **Never add sport-specific copy outside a `switch selectedSport {}` or `case .sport:` block** — hardcoded sport names in UI text are a leakage bug.
2. **All backend API calls must use `.apiValue` (lowercase)** — never `.rawValue` for sport parameters sent to the backend.
3. **`_SPORT_SKILL_ALIASES` is the authority for what natural language resolves to which drill** — add aliases here, not ad-hoc in callers.
4. **Safety check is always first in `_fallback_coach_response()`** — do not insert any keyword branch before the `_INJURY_KEYWORDS` check.
5. **When adding a new sport-specific feature**, validate it returns correct data for all 4 sports before calling it complete.
