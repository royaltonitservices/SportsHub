# SportsHub — Unified AI Context
Last Updated: 2026-03-21

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

SportsHub is a production-quality, multi-sport, account-based platform for teenagers and young athletes.

It combines:
- pickup and competitive sports matchmaking
- sport-specific progression and Elo/rating systems
- training and AI coaching
- social graph / friends / messaging
- short-form clips and posts
- trust, evidence, dispute, and moderation systems
- notifications
- profile identity and sport-specific reputation

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
- Tracking branch: `origin/checkpoint/state-of-union-2026-03-21`

Important commits:
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

### 5.5 Authentication is real
- login once, stay logged in
- signup includes 13+ gate
- date of birth matters
- session persistence matters
- logout exists
- auth should feel production-quality

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
7. PLAY / MATCHMAKING RULES
============================================================

Play is one of the most important parts of the product.

Requirements:
- users can find matches
- users can challenge others
- system should support 1v1, 2v2, 3v3 where applicable
- trust and reliability matter
- users should not hit dead-end empty states

Important concepts already in product direction:
- skill/rating-aware matching
- trust-aware surfaces
- evidence/dispute flows
- sport-specific realism
- location/zone awareness
- tennis court-specific handling

The difference between:
- discovering people
and
- discovering a realistically playable match
matters.

============================================================
8. TRUST / SAFETY / DISPUTE SYSTEMS
============================================================

SportsHub includes or is actively building toward:
- trust signals
- evidence uploads
- dispute handling
- moderation
- admin surfaces
- content safety
- account restrictions when needed

Important product rule:
trust systems should feel protective, not hostile.

They should help answer:
- is this player reliable?
- is this content safe?
- can this match result be trusted?
- what happens if players disagree?

Users should not see raw backend/admin language.

============================================================
9. AI COACH — CURRENT PRODUCT TRUTH
============================================================

The AI Coach is a major feature area.

Important rule:
The AI Coach must behave like a real coach, not a passive widget.

### Required coach behavior
The coach must:
- answer direct user questions
- ask smart coaching questions
- remain useful even without smartwatch data
- never end in a dead “All Caught Up” state with nothing helpful to do

The coach should support user-led prompts such as:
- “What should I train today?”
- “How do I improve my left hand?”
- “Should I recover or train hard today?”
- “Give me a 20-minute workout.”

The coach should also ask questions like:
- “What do you think are your weak points?”
- “What sport are you focused on right now?”
- “How much time do you have?”
- “How is your body feeling today?”
- “Are you training for a game, improvement, or recovery?”

Critical rule:
The AI Coach should be wearable-enhanced, not wearable-dependent.

If smartwatch/recovery data is missing, the coach should still be useful via:
- user questions
- self-reported readiness
- weak-point input
- sport context
- time available
- training goals

Bad behavior to avoid:
- dead-end “No insights”
- passive refresh-only behavior
- raw “Internal Server Error” shown to user
- inability to ask the coach questions

============================================================
10. NOTIFICATIONS
============================================================

Available Now notifications are an important current requirement.

Desired behavior:
- when a user marks themselves as Available Now, relevant users can be notified
- notifications should be smart, filtered, and not spammy

Use relevance such as:
- same sport
- similar skill/rating
- same city/zone
- friend relationship
- recent opponent/rival
- team format interest
- notification preferences

Important rule:
Do NOT blast everyone.
This should feel alive, timely, and high-signal.

Tennis-specific notification behavior should preserve court realism where possible.

============================================================
11. PROFILE / USERNAME / IDENTITY
============================================================

Profile identity matters a lot in SportsHub.

Users need:
- account identity
- profile presentation
- sport-specific reputation
- editable settings

Important current requirement:
Users should be able to change their username through a controlled username editing flow.

Username editing should include:
- validation
- availability checking
- uniqueness
- update propagation across profile surfaces
- protection against malformed/offensive usernames

Do NOT assume username is permanently fixed.

============================================================
12. CURRENT IMPLEMENTATION REALITY
============================================================

This project is far beyond the earlier “UI shell only” stage.

There are already substantial frontend and backend files present.

Examples of notable frontend/product areas present in repo:
- `SportsHub/LoginView.swift`
- `SportsHub/SignUpView.swift`
- `SportsHub/SessionManager.swift`
- `SportsHub/APIClient.swift`
- `SportsHub/PlayView.swift`
- `SportsHub/TrainView.swift`
- `SportsHub/ProfileView.swift`
- `SportsHub/PostsView.swift`
- `SportsHub/ClipsView.swift`
- `SportsHub/MatchmakingView.swift`
- `SportsHub/EvidenceUploadView.swift`
- `SportsHub/NotificationManager.swift`
- `SportsHub/AdminDashboardView.swift`
- `SportsHub/SettingsView.swift`

Examples of notable backend areas present in repo:
- `backend/main.py`
- `backend/auth.py`
- `backend/config.py`
- `backend/database.py`
- `backend/models.py`
- `backend/models_premium.py`
- `backend/schemas.py`
- `backend/ai_coach.py`
- `backend/ai_orchestrator.py`
- `backend/push_notifications.py`
- `backend/video_cdn.py`
- `backend/routers/auth.py`
- `backend/routers/matchmaking.py`
- `backend/routers/disputes.py`
- `backend/routers/evidence.py`
- `backend/routers/friends.py`
- `backend/routers/messages.py`
- `backend/routers/smartwatch.py`
- `backend/routers/tennis_courts.py`
- `backend/routers/tournaments.py`
- `backend/routers/users.py`

There are also many supporting product/docs files such as:
- `STATE_OF_THE_UNION_2026_03_21.md`
- `PHASE_4_COMPLETE.md`
- `PHASE_5_COMPLETE.md`
- `API_GUIDE.md`
- `IMPLEMENTATION_STATUS.md`
- `QUICKSTART.md`

Important implication:
Do NOT plan as though backend/API/auth/social/AI are still hypothetical.
Work from the real codebase and refine current implementation rather than rebuilding imagined architecture from scratch.

============================================================
13. IMPORTANT ARCHITECTURE / PRODUCT NOTES
============================================================

### 13.1 Avoid unnecessary abstraction
Do not invent service layers just because they sound nice.
Work with the actual current codebase structure.

If the project uses:
- `SessionManager.swift`
- `APIClient.swift`
- actual view files already in place

then refine those, do not casually introduce speculative layers like `AuthService.swift` unless truly justified.

### 13.2 Production polish matters
Major active refinement areas include:
- auth correctness
- error mapping
- login/signup polish
- AI Coach realism
- notification logic
- profile editing
- trust/dispute/evidence clarity

### 13.3 Do not regress to fake/demo assumptions
Earlier remote branches include demo/architecture-freeze style checkpoints.
Current work has moved far beyond that.
Do not simplify current product direction into a demo-only architecture.

============================================================
14. WHAT IS OUTDATED FROM EARLIER CONTEXT
============================================================

The following earlier assumptions are no longer reliable:
- “pre-backend”
- “empty-state shell only”
- “auth not implemented”
- “backend API not implemented”
- “database not implemented”
- “network layer not implemented”
- “files to create” for many files that already exist
- “next immediate step = build backend API”
- “Current App State (as of 2026-03-06)” as a representation of today’s reality

Do not use those assumptions when generating code or plans.

============================================================
15. KNOWN PRIORITIES / NEXT AREAS OF FOCUS
============================================================

High-priority continuing areas include:
- auth and login flow debugging/polish
- error mapping and server/auth failure clarity
- AI Coach conversational improvements
- smartwatch fallback behavior
- Available Now notifications
- username editing
- continued trust/dispute/evidence refinement
- sport-specific realism
- comparison against old remote baseline before any merge strategy into remote `main`

============================================================
16. HOW AN LLM SHOULD BEHAVE WHEN HELPING THIS PROJECT
============================================================

When helping with SportsHub:
- treat it as a real product
- use the actual codebase state, not stale assumptions
- avoid generic startup fluff
- avoid toy-prototype simplifications
- respect the six-tab structure
- respect sport-specific realism
- preserve safety-first messaging rules
- preserve friends-only DM rules
- preserve tennis-specific venue constraints
- preserve AI Coach conversational requirements
- preserve notification anti-spam realism
- preserve trust / evidence / moderation direction
- build with current repo/checkpoint awareness

If something is already implemented, refine it.
Do not casually propose recreating the whole app.

============================================================
17. SHORT STATE OF THE UNION
============================================================

SportsHub has progressed from an earlier lightweight/demonstration baseline into a much larger product with real frontend breadth, backend/API work, AI systems, notifications, trust flows, and sport-specific features. The project now has a formal checkpoint branch on GitHub preserving the 2026-03-21 state. Any future coding assistant should work from this current reality, not from the older assumption that SportsHub is only an empty UI shell awaiting backend creation.
