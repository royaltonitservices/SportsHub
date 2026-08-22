# SportsHub Project State

> Canonical baton-pass document. Read this first in any new session or on a new machine.
> Last updated at HEAD `d6bc68c` (continuity checkpoint, pre–Gate 1).

## Authoritative Git State
- **Branch:** `current-state-stabilization-checkpoint`
- **HEAD:** `d6bc68c26da704b589ee848bd8c045d5f0aa0f36`
- **Upstream:** `origin/current-state-stabilization-checkpoint` (0 / 0 — in sync)
- **Main branch:** `main` (checkpoint work lives on the stabilization branch)
- **Latest frozen tags (top of stack):**
  - `ai-coach-clarification-continuity-complete` → `d6bc68c`
  - `identity-casing-consistency-complete` → `10a4374`
  - `group-g-seed-honesty-complete` → `50d9740`

## Product Summary
SportsHub is a **SwiftUI iOS + Python FastAPI** multi-sport competitive/social platform for **13+** athletes. Four **first-class** sports: **Basketball, Football, Soccer, Tennis**. Features: ELO matchmaking, challenges, two-party result submission, disputes, ranked leaderboards, posts/comments, short-form clips, friends, friends-only DMs, group chats, tournaments, AI Coach (OpenAI + deterministic fallback), StoreKit 2 premium, HealthKit/smartwatch, admin moderation.

## Completed / Frozen Work (invariant each phase established)
| Phase | Tag | Invariant established |
|---|---|---|
| Upload validation hardening | `upload-validation-hardening-complete` | Atomic media writes + validated uploads. |
| Competitive/moderation verification | `group-e-competitive-moderation-verification-complete` | Ranked W/L + moderation flows verified against real backend. |
| Report entry points | `report-entry-points-complete` | Report affordances wired with HTTP-contract coverage; block ≠ report kept separate. |
| Dispute result integrity | `dispute-result-integrity-complete` | Dispute resolution is result-integrity-safe and idempotent. |
| Visible leaderboard semantics | `visible-leaderboard-semantics-complete` | Leaderboard is ranked-only with a correct decode contract. |
| Challenge result clarity | `challenge-result-clarity-complete` | Role-aware result submission for both players. |
| **Group G seed honesty** | `group-g-seed-honesty-complete` | Dev-seed counters derive from canonical completed RANKED matches; **fail-closed triple-gate** (`APP_ENV∈{development,demo}` + `SAMPLE_DATA_ENVIRONMENT=true` + `--confirm-demo-data`) required to seed; seed authorization is coupled to the in-app "Sample community data" disclosure so they cannot drift. Lifetime vs ranked counter split mirrors production. |
| **Identity consistency** | `identity-casing-consistency-complete` | One canonical `idsEqual()` primitive: **UUID-strict, fail-closed** (nil/blank/malformed → false; case-insensitive same-UUID → true). `FriendshipResponse.otherUserId()` returns `String?` fail-closed. All user-ID comparisons and pairwise friend/challenge targets route through it. |
| **AI clarification continuity** | `ai-coach-clarification-continuity-complete` | A short answer to the coach's gathering question is no longer reset by the Phase-1 `.unclear` gate; natural duration parsing (hr/hour/word-forms); arithmetic `x` escape; injury→safety precedence in that branch; AI-bubble Markdown renders inline with **link attributes stripped (AI links inert)**; user bubbles stay plain. |

*(Full historical tag list is in `git tag`; this table is the load-bearing subset.)*

## Current Infrastructure Reality
- **Backend:** local only (FastAPI/uvicorn on `localhost:8000`). No hosted deployment.
- **DB:** SQLite for dev (`backend/sportshub.db`, gitignored). Postgres is the production default in config but **not deployed**.
- **Schema authority:** `Base.metadata.create_all()` on startup + ad-hoc `migrate_*.py` scripts. **Alembic is a dependency but not yet the authority.**
- **Media:** local disk under `backend/uploads/*` served via StaticFiles `/cdn/*`. No object storage/CDN. **DM media does not exist.**
- **Release API URL:** not productionized (`APIConfig.baseURL` = `http://localhost:8000`).
- **Notifications:** local `UNUserNotificationCenter` only; **no APNs** (no `registerForRemoteNotifications`). Polling is the realtime path.
- **StoreKit:** backend trusts a local `Subscription` row (`status=="active"`); **no signed-transaction / App Store Server API verification.**
- **Rate limiting:** only the AI Coach daily limit (in-memory, process-local, 200/day). No global/auth/upload rate limiting.

## Known Open Product / Security / Apple Issues (from the approved plan)
- **Camera** usage-description missing (`.camera` capture in `ProofSubmissionView`) — required.
- **Location** decision pending: precise location → backend for tennis nearby-court search; by-city fallback exists. Ship-with-controls **or** drop for v1.
- **Sign in with Apple:** entitlement missing; verification is real (JWKS/RS256) but nonce not validated, provider `sub` not persisted, no token revocation on delete.
- **Auth identity/email/age-gate (SECURITY):** `email` not unique; OAuth resolves user **by email** (account-takeover vector); OAuth users get placeholder DOB `1990-01-01` + `age_verified=True` (13+ gate bypass).
- **UGC:** report endpoint works; **automated filtering is aspirational/unwired**; **block is not enforced server-side**; two competing block stores (`BlockedUser` vs `Friendship.BLOCKED`).
- **Minor interaction safety:** matrix not yet defined (incl. location).
- **AI/HealthKit third-party consent:** OpenAI receives sport/performance/goals/weak-points/training-history/survey/free-text and **HealthKit-derived biometrics** (relevance-gated); no dedicated third-party-AI consent. No id/name/age sent.
- **Account deletion:** already strong (hard-delete + sentinel-anonymized competitive history + media); missing Apple token revocation + subscription messaging.
- **StoreKit server verification:** blocker **iff Premium ships** in the binary.
- **Postgres/Alembic parity; object storage; shared rate limits; PrivacyInfo.xcprivacy; Privacy Policy/Terms/support; legal review** — all in the plan (`PRODUCTIONIZATION_PLAN.md`).

## Deferred Manual Runtime QA
Report sheets · leaderboard rendering · result challenger/opponent flows · DM bubble direction · identity-derived friend/challenge targets · SampleDataBanner (demo mode only) · AI clarification flow (Turn 1→2 retains sport+focus+~60 min) · Markdown visual (bold, no literal `**`) · **AI links inert** · Block UX/enforcement (once implemented) · HealthKit prompts · StoreKit sandbox purchase/restore · SIWA · account deletion · network/retry/offline behavior · camera/location permission prompts.

## Important Architectural Decisions (already made — do not relitigate)
- Completed **RANKED Matches are canonical ranked truth**; leaderboard eligibility ≥5 ranked.
- **No fake production community seed** (`seed_dev_data.py` is fail-closed; never in prod).
- **UUID identity matching is strict/fail-closed** (`idsEqual`).
- **AI-authored Markdown links are inert** (formatting only, never navigation).
- **No WebSockets** in the v1 critical path. No read replica / PgBouncer / Kubernetes / multi-region for initial scale.
- **APNs optional for v1.**
- **Object storage/CDN is an engineering design, not an Apple mandate.**
- **DM media does not currently exist** — do not design it.
- **No destructive full test suite against shared staging.**
- **Alembic should become the production schema authority.**
- **Shared quota state required before multi-process AI quota.**
- **No secrets in Git.**

## User Decisions Still Required
1) One SportsHub account per verified email vs multiple. 2) Account-linking policy. 3) **Premium ships v1 or disabled.** 4) **Location ships v1 or dropped.** 5) Minors' health-derived data → OpenAI (allow-with-consent vs suppress). 6) Keep/remove APNs. 7) Shared store (Redis vs alternative). 8) Host / object storage / CDN / domain. 9) Post-block visibility & shared-history deletion policy.

## Legal Review Required
COPPA / under-13 exclusion & age-gate integrity · GDPR-K / UK AADC / EU DSA minor protections · minors' health/training data → OpenAI + subprocessor/DPA/retention · dispute-evidence retention · DMCA / user-uploaded music in clips · Privacy Policy / Terms / Community Guidelines · data access/export rights.

## Exact Next Step
**NEXT:** Migration/continuity validation on the new Mac (fresh clone → documented external setup → backend schema init → backend suite (192) → boot an installed simulator → iOS build + full `SportsHubTests` unit target (**312** tests, which includes the AI Coach and identity suites) → confirm no undocumented local-only dependency). *(The full iOS unit-target count is 312; "106" was only a prior AI subset run via the in-session MCP, not the full suite.)*

**AFTER THAT:** Gate 1.1 — Protected API / capability audit (add `NSCameraUsageDescription`; add Sign in with Apple entitlement; remove unused APNs + CloudKit entitlements; create `PrivacyInfo.xcprivacy` required-reason inventory; **do not** add a Photo Library string — not required by call path).
