# SportsHub Productionization & App Store Readiness Plan

## Status
Approved by Staff/Principal engineering + independent architecture review (Round 4 final reconciliation).
**Gate 0 complete.** A **migration/continuity checkpoint** is required before any Gate 1 work.

Classification key: **ARB** Apple-Review Blocker · **PRB** Product-Release Blocker · **SEC** Security Blocker · **LEG** Legal review · **Hyg** hygiene · **Opt** optional. Effort: **S** ≤1d · **M** ≤3d · **L** ≤1wk · **XL** >1wk.

## Final corrections preserved
- **Photos:** SwiftUI `PhotosPicker` / selected-item `UIImagePickerController(.photoLibrary)` reads do **NOT** require a photo-library permission. Only direct protected Photos APIs / save-to-library would. → **No `NSPhotoLibraryUsageDescription` needed.**
- **Camera:** required — direct `.camera` capture ships (`ProofSubmissionView`).
- **Location:** if shipped, permission + App-Privacy + minor-safety + minimization mandatory; if dropped, **remove** the protected location path rather than merely adding a permission.
- **AI third-party consent:** Apple Review (5.1.2) **and** product/privacy blocker; distinct from HealthKit authorization.
- **StoreKit:** blocker **iff Premium ships**; App Store Server API / Notifications V2 are architecture choices, not universal Apple mandates.
- **UGC:** filtering **+** report **+** moderation ops **+** block **+** published contact (not block-only).
- **SIWA:** nonce validation is security hardening (part of 4.8 conformance, not standalone wording).
- **Privacy manifest:** Gate 1 early inventory/baseline; Gate 3 final Release/archive authority.
- **Account delete:** an active subscription must **not** block deletion; show billing-continues notice + Manage-Subscription; per-class delete / anonymize / bounded-justified retention.
- **APNs/CloudKit** unused entitlements: hygiene/least-privilege (remove), **not** automatic rejection.

---

## GATE 0 — COMPLETE
Group G seed honesty · identity consistency · AI clarification continuity (tags pushed). Only deferred manual runtime QA remains.

## MIGRATION / CONTINUITY CHECKPOINT (before Gate 1)
Goal: durable handoff + portability proof on a new Mac. See `PROJECT_STATE.md` + `DEVELOPMENT_SETUP.md`. Exit: fresh clone rebuilds backend (backend suite **192**) + iOS build + full `SportsHubTests` unit target (**312**, includes the AI Coach and identity suites), with **no undocumented local-only dependency**. (312 is the authoritative full iOS unit count; "106" was only a prior AI subset.) Freeze tag: `continuity-checkpoint-pre-gate1`.

## GATE 1 — LOCAL RELEASE / SECURITY / PRIVACY
| # | Phase | Class | Goal / outline | Claude can do | User / external | Verify · Exit |
|---|---|---|---|---|---|---|
| 1.1 | Protected-API & capability audit + required-reason inventory | ARB+PRB+Hyg | Add `NSCameraUsageDescription`; add **SIWA entitlement**; remove unused **APNs + CloudKit/iCloud** entitlements; create `PrivacyInfo.xcprivacy` (UserDefaults etc.). No Photo Library string. Location string deferred to 1.5 decision. | All edits + build | Confirm APNs/CloudKit truly unused | Build; each used API prompts; no unused-entitlement · every used API has truthful string. **S–M** |
| 1.2 | Auth identity + OAuth age-gate integrity | **SEC**+LEG | `USER` / `AUTH_IDENTITY(provider,subject unique)` / verified `EMAIL`; stop email-only provider resolution; persist Apple/Google `sub`; drop fabricated OAuth passwords; `email_verified`; require real DOB/age for OAuth; explicit linking (no silent merge); remediate duplicate emails. | Schema+resolver+migration+tests | **Decision:** one account/email vs multiple | HTTP tests: no cross-account takeover; OAuth user age-gated · duplicates remediated. **L–XL** |
| 1.3 | Sign in with Apple hardening | ARB(4.8)+SEC | Validate nonce/state; persist stable `sub`; returning-user (no email/name); entitlement (1.1); **token revocation on delete**. | Code+tests | Apple key/Services config | SIWA sign-in + returning-user + revoke path · verified. **M** |
| 1.4 | UGC safety + moderation + block | ARB(1.2)+SEC+PRB | Wire filtering on create (usernames/bios/posts/comments/clip captions); verify report; moderation queue/policy; **consolidate one block model + enforce server-side** (DM/friend/challenge/group/discovery); published contact; DM/group report+block+recipient+abuse controls. | Enforcement+filter wiring+tests | Post-block visibility policy | Tests: blocked user cannot DM/challenge/invite/appear; create-time filter fires · matrix documented. **L** |
| 1.5 | Minor-interaction safety matrix (incl. location) | LEG+PRB | Matrix (discoverability, adult↔minor DMs/friend/challenge/matchmaking/group, profile/age/location visibility, post-block, escalation) tagged APPLE/PRODUCT/LEGAL/USER; **location decision** (ship w/ controls — reduce precision, not persisted, not exposed, string+App-Privacy — or drop→remove path). | Matrix + code | Location ship/drop; minor policy | Decisions recorded + enforced. **M** + legal |
| 1.6 | AI/HealthKit third-party consent + minimization | ARB(5.1.2)+PRB+LEG | Explicit in-app consent + disclosure (separate from HealthKit auth); field table **REQUIRED/OPTIONAL/DO-NOT-SEND**; gate health→AI behind consent; minors' health→AI decision. | Consent gate + minimization + doc | Consent copy; minors decision | Health→AI only after consent · field table enforced. **M** + legal |
| 1.7 | AI physical-safety/readiness verification | PRB(safety) HIGH | Verify no-diagnosis, injury red-flags, head-impact escalation, accurate readiness wording, fallback parity, provider-failure safety, minor tone. *(Largely already built.)* | Test matrix + wording | — | Prompt battery incl. provider-down · all pass. **S–M** |
| 1.8 | Full account-deletion semantics | ARB(5.1.1v) | Audit full server+device coverage (already strong); **add Apple token revocation**; deletion available with active sub + billing notice + Manage-Subscription; per-class delete/anonymize/bounded retention. | Audit doc + revoke + messaging | — | Deletion removes/anonymizes per matrix; revoke called. **S–M** |
| 1.9 | StoreKit production entitlement | ARB+PRB+SEC **iff Premium ships** | Signed-transaction (JWS) trust, bundle/env/product allowlist, account association (`appAccountToken`/`originalTransactionId`), idempotency, restore, expiry/refund/revocation, sandbox/TestFlight; ASSN V2 where appropriate. | Verification service + webhook | **Decision: Premium ships v1 or disable door**; ASC keys | Sandbox purchase+restore server-verified · entitlement authoritative. **L** |

## GATE 2 — PRODUCTION FOUNDATION
| # | Phase | Class | Notes | Effort |
|---|---|---|---|---|
| 2.1A | Alembic + disposable-Postgres parity | PRB | Alembic sole authority; retire prod `create_all`; UUID/JSON/enum/timestamp parity on ephemeral Postgres. | M–L |
| 2.1B | Managed staging Postgres | PRB | Provision only after 2.1A green. User: DB host. | S + provision |
| 2.2 | Media / object storage | PRB HIGH | Public (validate, **EXIF/location strip**, thumbnail, CDN, delete/invalidate) + private evidence (authorize→short-lived signed URL, bounded retention). No DM media. User: storage+CDN. | L |
| 2.3 | Shared rate limits / abuse | SEC HIGH | Shared-store limiter for signup/login/reset/posts/comments/messages/reports/friend+challenge/uploads(count+bytes)/AI. User: Redis-or-alt. | M–L |
| 2.4 | Release/staging config + secrets + HTTPS | PRB | Release URL, ATS-clean, prod ASGI, secrets out of repo, prod JWT secret, **CORS allowlist**, rotate admin creds. User: host+domain+TLS. | M |
| 2.5 | Observability / backups / restore | PRB HIGH | Structured logs+request IDs, Sentry, health/readiness, DB metrics, **backups/PITR + restore test**, alerts, kill switches. | M |
| 2.6 | Background workers / APNs (**Opt v1**) | MEDIUM/Opt | email/thumbnails/ffprobe/moderation/cleanup; APNs deferred-but-high. | M–L |
| 2.7 | Lightweight migration/compat discipline | MEDIUM | Alembic expand/contract, no destructive drops; defer full multi-client matrix (no live clients). | S |

## GATE 3 — SUBMISSION / VALIDATION
3.1 final `PrivacyInfo.xcprivacy` Release/archive audit · 3.2 Privacy Policy / Terms / Community Guidelines / support **(LEG)** · 3.3 production-like staging (HTTPS, **no prod seed**) · 3.4 CI (disposable Postgres) + staging-safe smoke · 3.5 **TestFlight runtime QA** (all deferred items) · 3.6 App Store Connect (metadata, screenshots, age rating, App Privacy, IAP if shipping, export compliance, support/privacy URLs, content-rights, review notes) · 3.7 dedicated reviewer account (**never** `seed_dev_data.py` in prod) · 3.8 RC deploy + non-destructive smoke · 3.9 final adversarial audit (Claude + architect) · 3.10 submit. Aggregate **L–XL** + legal/provider lead.

## Cost / Effort
Infra: **~$40–90 / ~$90–200 / ~$200–500+ per month** across 100 / 1,000 / 1,000-video-heavy DAU tiers + variable OpenAI. Engineering: **G1 ≈ 2–4 wks** (1.2 long pole), **G2 ≈ 2–3 wks**, **G3 ≈ 1–2 wks** + external legal/provider lead. No tighter precision.

## Out of v1 critical path (accepted)
APNs (high-value, optional) · WebSockets · read replicas · PgBouncer · Kubernetes · multi-region · full multi-client rollback matrix. CloudKit removed (unused). DM media not designed (absent).
