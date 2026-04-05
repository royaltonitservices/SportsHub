# CLAUDE.md — SportsHub Project Context

## Metadata

- **Purpose:** Living source of truth for Claude sessions working on SportsHub
- **Last Updated:** 2026-04-04
- **Checkpoint Branch:** `checkpoint/state-of-union-2026-03-21`
- **Checkpoint Commit:** `6263607`
- **Checkpoint Note:** Major integration pass before restart handoff (March 27, 2026)
- **Overall Completion:** ~65-75% (verified against code, not documentation claims)

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

*Last verified: 2026-04-04 against commit 6263607*

### Auth/Session — FULLY IMPLEMENTED (95%)

- Real login/signup with JWT
- Keychain token persistence
- Session restoration on app launch
- OAuth buttons present (Apple/Google) — not end-to-end tested
- Password encoding handles special characters correctly
- 13+ age gate enforced
- **Missing:** password reset, email verification (backend stub only), 2FA

### Play/Matchmaking — FULLY IMPLEMENTED (90%)

- Real API: `findOpponents`, `createChallenge`, `getPendingChallenges`, `acceptChallenge`, `submitResult`
- Trust tier warnings before challenging low-trust players
- Tennis court picker integration
- Rating range controls, distance/radius, availability toggle
- Challenge lifecycle: pending → accepted → completed/disputed
- **Missing:** decline challenge (TODO stub in PlayView), team matchmaking ("Coming Soon" button)

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

### Premium Subscription — FULLY IMPLEMENTED (90%)

- StoreKit 2 product fetching, purchase flow, transaction listener
- Dual-source: StoreKit + backend admin grants
- Feature showcase, pricing tiers, purchase restoration
- **Missing:** subscription cancellation flow, plan management, promo codes

### AI Coach — MOSTLY IMPLEMENTED (80%)

- Real API: `sendCoachMessage`, `getProactiveCheckin`, `clearCoachConversation`, `generateDrill`, `generateChallenge`, `analyzeTrainingSession`
- AICoachChatView: full chat with voice input, suggested actions, follow-ups
- AICoachFloatingView: proactive insights overlay
- **Local-only:** conversation history cached in UserDefaults, not synced to backend
- **Placeholder:** AICoachLevelView has hardcoded progress values (not fetched from API)

### Smartwatch Sync — MOSTLY IMPLEMENTED (80%)

- Real API: connect, disconnect, sync biometrics, recovery status
- Real HealthKit integration (HKHealthStore queries for HR, HRV, sleep, steps, etc.)
- DailyReadinessView with 4-tier recommendation system
- Premium-gated
- **Unverified:** actual real-time sync with physical Apple Watch not tested

### Home — MOSTLY IMPLEMENTED (75%)

- Sport selector, time-based greetings, recommended action cards
- Navigation to matchmaking, AI coach, drills works
- **Partial:** search bar present but backend wiring unclear; some action button closures are empty TODOs

### Train — PARTIALLY IMPLEMENTED (60%)

- Sport selector, premium gating, drill library, recommended drills
- WeeklyDrillsView: real API for personalized drills (premium)
- DrillLibraryView: functional but **hardcoded drill definitions** (~2000 lines, not from API)
- **Placeholder:** TrainingSessionView.saveSession() is TODO with fake delay
- **Placeholder:** WorkoutBuilderView save/start are no-ops
- **Placeholder:** Training Programs section is "Coming Soon"

### Profile — PARTIALLY IMPLEMENTED (70%)

- Real API: display name update, username update (with availability check), sport profile stats
- Gradient avatar, bio editing (local only)
- **Missing:** bio backend sync (TODO in SessionManager), profile picture upload (UI present, no backend integration)

### Clips — PARTIALLY IMPLEMENTED (40%)

- Real API: fetch clips, upload clip video (multipart)
- **Broken:** zero video playback — shows gray rectangles with play button overlay, no AVPlayer
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
| GroupChatsView | **NOT IMPLEMENTED** | All API calls commented out; loads empty arrays |
| HighlightsView | **NOT IMPLEMENTED** | All API calls commented out; models defined but unused |
| NotificationsView | **NOT IMPLEMENTED** | `loadNotifications()` is empty; no data loading |
| AdManager + AdExampleView | **ENTIRELY FAKE** | No SDK imports; simulates ads with fake delays |
| HotMapsView | **HARDCODED MOCK** | 3 fake players at San Francisco coordinates |
| TeamLobbyView | **PLACEHOLDER** | All create/join functions are fake delays with mock data |
| ChallengeCreationView | **PLACEHOLDER** | `createChallenge()` is fake delay; friend list is hardcoded mock |
| ProofSubmissionView | **PLACEHOLDER** | File picker works, but `submitProof()` is TODO |
| TrainingSessionView | **PLACEHOLDER** | Data entry UI works, but `saveSession()` is TODO |
| WorkoutBuilderView | **PLACEHOLDER** | UI works, but save/start functions just dismiss |
| PerformanceGraphsView | **MOCK DATA** | Charts render, but use randomly generated values each load |
| AICoachLevelView | **HARDCODED** | Progress values are `@State` constants, never fetched |
| BadgeSystemView | **PARTIAL** | 66 badge definitions hardcoded; earned badges never load from API |
| SkillProgressionEngine | **LOCAL-ONLY** | Full engine, but UserDefaults only — no backend sync |

### Push Notifications: DO NOT EXIST

- NotificationManager.swift is **local notifications only** (UNUserNotificationCenter)
- Zero APNs integration
- All notification action handlers are TODO stubs
- Docs claiming "framework ready, needs testing" are misleading — there is no push infrastructure

---

## 7. Known Technical Debt

### High Priority

1. **No video playback in ClipsView** — gray rectangles instead of videos
2. **Training session persistence missing** — saveSession() is TODO
3. **Decline challenge not implemented** — TODO stub in PlayView
4. **Bio backend sync missing** — local UserDefaults only (TODO in SessionManager)
5. **Profile picture upload not wired** — UI present, no backend endpoint call
6. **Group chat not implemented** — all API calls commented out despite backend support

### Medium Priority

7. **Push notifications absent** — no APNs, local only
8. **Challenge creation placeholder** — UI exists, no API call
9. **Proof submission placeholder** — file picker works, upload is TODO
10. **Badge earned status never loads** — backend endpoint exists but iOS doesn't call it
11. **Performance graphs use mock data** — charts work but data is random
12. **DrillLibraryView hardcoded** — ~2000 lines of drill definitions inline, not from API

### Code Quality

13. **ContentView.swift** — unused Xcode template, should be deleted
14. **Item.swift** — unused SwiftData boilerplate, should be deleted
15. **MockData.swift** — legacy mock data, likely unused by main views
16. **Error handling inconsistency** — some views have robust handling, others just `print()`
17. **No test coverage** — test files exist but contain only boilerplate
18. **Sport enum in HomeView.swift** — should arguably be in its own file

---

## 8. Current Priorities

*Ranked by value and feasibility:*

### Priority 1: Complete Broken Core Flows

1. **Video playback in ClipsView** — high user-facing impact
2. **Training session persistence** — core Train tab functionality
3. **Decline challenge endpoint** — required for user agency in Play
4. **Profile picture upload** — adapt existing multipart upload pattern from clips
5. **Bio backend sync** — simple endpoint call

### Priority 2: Wire Existing Backend Features

6. **Group chat** — backend has full support (routers/messages.py), iOS just needs uncommenting + integration
7. **Badge earned status** — backend endpoint exists, iOS needs to call it
8. **Challenge creation** — backend support exists, iOS needs real API call
9. **Proof submission upload** — follow existing evidence upload pattern

### Priority 3: Polish & Verify

10. **Push notification infrastructure** — requires APNs setup, significant work
11. **Performance graphs with real data** — replace mock generation with API calls
12. **Smartwatch end-to-end verification** — test with actual Apple Watch
13. **Search functionality** — verify and wire backend search endpoints

### Priority 4: Quality

14. **Consistent error handling across all views**
15. **Delete dead code** (ContentView.swift, Item.swift)
16. **Relocate Sport enum** to its own file
17. **Admin settings page**

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
| ClipsView.swift | SportsHub/SportsHub/ | Fetch only | No video playback |
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
| backend/main.py | 96 | FastAPI app, 31 router imports |
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
