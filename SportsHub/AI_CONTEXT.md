# Project: Sports Hub
**Created:** 2026-02-17  
**Last Updated:** 2026-02-19 (updated after demo scope freeze and initial implementation)  
**Developer:** Aarush Khanna  
**Platform:** iOS (iPhone) — dual iPhone 17 Pro simulators for Friday demo  
**Minimum Deployment Target:** TBD (confirm from Xcode project settings)  
**Swift Version:** Swift 6  
**Xcode Version:** 26.3 (17C519)

---

## 🎯 CURRENT MODE: FRIDAY DEMO PREPARATION

**Demo objective:** Deliver the clearest possible live demonstration of core concept working across two simulators.

**NOT building:** Full architecture, persistence, networking, challenge system, presenter control panel, service protocols, tests.

**Building:** Minimal working demo showing:
1. Player identity selection ("You are Aarush" / "You are Manav")
2. Sport switching (Basketball / Football / Soccer / Tennis)
3. Live rating updates across both simulators
4. Rank labels derived from rating

**Constraints:**
- Modify existing files only — no new architectural layers
- Minimal code changes
- Demo clarity > architectural completeness
- One small step at a time

---

## 🧭 Product Vision

SportsHub is a **competitive integrity platform** for real-world sports.  
It is NOT a scheduling app or a social app.

Core promise: **Fairness and trust**, like ranked matchmaking in online games — applied to physical sports.

> "Real life ranked multiplayer" — not "a chat app that schedules games"

The product succeeds if and only if the fairness engine works correctly.

### Four Pillars (NEVER compromise these)
| Pillar | Description |
|--------|-------------|
| **Match Fairness** | ELO-based skill rating per sport |
| **Commitment Enforcement** | Show up or receive penalties |
| **Competitive Progression** | Improvement unlocks tournaments and recognition |
| **Trust & Safety** | Meeting strangers must feel safe |

---

## 🏗️ Current Architecture (As Implemented)

### Simplified Demo Architecture

```
┌────────────────────────────────────────────────────┐
│              UI LAYER (SwiftUI)                    │
│  ContentView — demo interface                      │
│  - Player list with ratings                        │
│  - "Simulate Match" button                         │
│  - Match log (last 5 results)                      │
│  - Sport picker (pending)                          │
│  - Player identity selector (pending)              │
└──────────────────┬─────────────────────────────────┘
                   │ observes via @Observable
┌──────────────────▼─────────────────────────────────┐
│           VIEWMODEL LAYER                          │
│  DemoViewModel (@Observable, @MainActor)           │
│  - Subscribes to DemoAuthority via AsyncStream     │
│  - Projects GameState → UI-friendly DemoPlayer     │
│  - simulateMatch() — triggers random match         │
│  - matchLog — last 5 match results                 │
└──────────────────┬─────────────────────────────────┘
                   │ calls directly (no service layer)
┌──────────────────▼─────────────────────────────────┐
│      DemoAuthority (Swift actor — singleton)       │
│                                                    │
│  In-memory state:                                  │
│  - players: [Player]                               │
│  - matches: [MatchResult]                          │
│                                                    │
│  Functions:                                        │
│  - seedPlayers() — creates Aarush + Manav          │
│  - subscribe() → AsyncStream<GameState>            │
│  - applyMatchResult(...) — updates ratings         │
│  - publish() — notifies all subscribers            │
│                                                    │
│  Calls:                                            │
│  - ELORatingEngine.calculateDelta(...)             │
└──────────────────┬─────────────────────────────────┘
                   │ uses
┌──────────────────▼─────────────────────────────────┐
│         DOMAIN ENGINES (pure functions)            │
│  ELORatingEngine — ELO math, K-factor schedule     │
│  CommitmentEngine — strike + cooldown logic        │
│  (ProgressionEngine — NOT IMPLEMENTED YET)         │
│  (MatchmakingEngine — NOT IMPLEMENTED, NOT NEEDED) │
│  (TrustEngine — NOT IMPLEMENTED, NOT NEEDED)       │
└──────────────────┬─────────────────────────────────┘
                   │ reads from
┌──────────────────▼─────────────────────────────────┐
│          POLICY LAYER (constants)                  │
│  SportConfig — K-factor, initial rating, ELO scale │
│  PenaltyPolicy — strike thresholds, cooldowns      │
│  ProgressionPolicy — rank tier thresholds          │
│  MatchRules — fairness scale factor                │
└────────────────────────────────────────────────────┘
```

### How It Works (Plain English)
1. App launches → `DemoViewModel.startListening()` runs in `.task` modifier
2. ViewModel subscribes to `DemoAuthority.shared.subscribe()`
3. DemoAuthority seeds players (Aarush + Manav) if empty
4. DemoAuthority yields initial `GameState` via `AsyncStream`
5. ViewModel receives `GameState`, projects it to `[DemoPlayer]`
6. UI updates automatically via `@Observable`
7. User taps "Simulate Match" → random match is simulated
8. `ELORatingEngine.calculateDelta(...)` computes rating changes
9. `DemoAuthority.applyMatchResult(...)` updates in-memory state
10. DemoAuthority publishes new `GameState` to all subscribers
11. Both simulators (if running) receive update simultaneously
12. Both UIs update live — no disk, no network, no configuration

### Why In-Memory Singleton Works
- **Zero configuration** — no entitlements, no App Groups, no signing hassles
- **Guaranteed delivery** — same memory space, actor serializes mutations
- **Instant reset** — one actor call clears everything
- **Perfect for demo** — both simulators share one process on macOS
- **Backend-ready** — service protocol layer can wrap this later

---

## 📦 Current Implementation Status

### ✅ IMPLEMENTED — SportsHubCore Framework

| Component | File | Description |
|-----------|------|-------------|
| **Models** | | |
| `Player` | `SportsHubCoreModelsPlayer.swift` | Player with per-sport ratings + match counts |
| `Sport` | `SportsHubCoreModelsSport.swift` | Enum: basketball, football, soccer, tennis |
| `MatchResult` | `SportsHubCoreModelsMatchResult.swift` | Winner/loser/sport/date |
| `CommitmentRecord` | `SportsHubCoreModelsCommitmentRecord.swift` | Strike tracking per player per sport |
| `ProgressionRecord` | `SportsHubCoreModelsProgressionRecord.swift` | Rank tier + rating (model exists, engine not implemented) |
| `RankTier` | Same file | Enum: rookie, bronze, silver, gold, platinum, elite |
| `PenaltyState` | Same as CommitmentRecord | Enum: clear, warned, cooldown |
| **Engines** | | |
| `ELORatingEngine` | `SportsHubCoreEnginesELORatingEngine.swift` | ✅ Pure functions: expectedScore, calculateDelta |
| `CommitmentEngine` | `SportsHubCoreEnginesCommitmentEngine.swift` | ✅ Pure functions: penaltyState, applyStrike |
| **Policies** | | |
| `SportConfig` | `SportsHubCorePolicySportConfig.swift` | ✅ K-factor schedule (40→24→16), initial rating (1000), ELO scale (400) |
| `PenaltyPolicy` | `SportsHubCorePolicyPenaltyPolicy.swift` | ✅ Strike thresholds (1/2/3), cooldown durations (24h/72h) |
| `ProgressionPolicy` | `SportsHubCorePolicyProgressionPolicy.swift` | ✅ Rank tier thresholds (900, 1100, 1300, 1500, 1700) |
| `MatchRules` | `SportsHubCorePolicyMatchRules.swift` | ✅ Fairness scale factor (400) |

### ✅ IMPLEMENTED — SportsHub App Target

| Component | File | Description |
|-----------|------|-------------|
| `SportsHubApp` | `SportsHubApp.swift` | App entry point, launches ContentView |
| `DemoAuthority` | `DemoAuthority.swift` | ✅ Singleton actor, in-memory state, AsyncStream pub/sub, seedPlayers(), applyMatchResult() |
| `DemoViewModel` | `DemoViewModel.swift` | ✅ @Observable, subscribes to DemoAuthority, projects GameState → DemoPlayer, simulateMatch() |
| `ContentView` | `ContentView.swift` | ✅ List with players, ratings, "Simulate Match" button, match log (last 5) |
| `DemoPlayer` | DemoViewModel.swift | ✅ UI projection struct: id, name, rating, matchCount |
| `MatchLogEntry` | DemoViewModel.swift | ✅ UI projection struct for match log |

### ⬜ NOT IMPLEMENTED (Intentionally Deferred for Demo)

| Component | Reason |
|-----------|--------|
| `ProgressionEngine` | Not needed yet — rank label will be computed inline in ViewModel |
| `MatchmakingEngine` | Not needed for demo — no matchmaking UI |
| `TrustEngine` | Not needed for demo — stubbed for future |
| Service protocols | Not needed for demo — ViewModel calls DemoAuthority directly |
| Demo service implementations | Not needed for demo — no protocol layer |
| Presenter control panel | Not needed for minimal demo |
| Challenge system | Not needed for minimal demo — only "Simulate Match" |
| Unit tests | Deferred — focus is Friday demo, not TDD |
| Persistence | Not needed — in-memory only |
| UserSession | Not needed — identity will be selected in UI, stored in ViewModel only |

---

## 🎯 Friday Demo Scope (LOCKED)

### What the Demo MUST Show
1. ✅ Two players (Aarush + Manav) with separate ratings per sport
2. ✅ "Simulate Match" button triggers rating updates
3. ✅ Live match log shows last 5 results
4. 🔜 Player identity selector ("I am Aarush" / "I am Manav")
5. 🔜 Sport picker (Basketball / Football / Soccer / Tennis)
6. 🔜 Rank labels displayed next to ratings (Rookie / Amateur / Pro / Elite)
7. 🔜 Ratings update when sport is switched
8. 🔜 Both simulators see updates simultaneously

### Demo Rank Tiers (Simplified for Friday)
| Tier | Rating Range |
|------|--------------|
| Rookie | < 1000 |
| Amateur | 1000 – 1199 |
| Pro | 1200 – 1399 |
| Elite | 1400+ |

*(Different from `ProgressionPolicy` — intentional simplification for demo clarity)*

### Known Demo Shortcuts
- No persistence — state resets on app relaunch
- No challenge flow — only random simulation
- No presenter control panel — manual relaunch to reset
- Rank tiers computed inline — no `ProgressionEngine` call
- Player identity stored in ViewModel only — no UserDefaults
- Match log only shows winner's delta — not both players' changes

---

## 🔧 Xcode Targets (Confirmed)

| Target | Type | Files |
|--------|------|-------|
| `SportsHub` | iOS App | `SportsHubApp.swift`, `ContentView.swift`, `DemoViewModel.swift`, `DemoAuthority.swift` |
| `SportsHubCore` | Swift Framework | All models, engines, policies (imported by SportsHub) |
| `SportsHubTests` | Test Bundle | (Not yet implemented) |

---

## 💬 Notes for AI Assistant

### Workflow Rules (NON-NEGOTIABLE)
1. **READ before writing** — always check current file state
2. **SHOW before doing** — propose changes, wait for confirmation
3. **One step at a time** — no multi-step edits without approval
4. **Modify, don't create** — prefer editing existing files
5. **Minimal code** — smallest change that works
6. **No redesigns** — architecture is frozen for Friday demo
7. **Ask if uncertain** — better to check than break

### Boundaries (What You CANNOT Do)
- ❌ Create new architectural layers
- ❌ Add persistence (SwiftData, UserDefaults for state)
- ❌ Add networking
- ❌ Add Combine or DispatchQueue
- ❌ Refactor engines
- ❌ Change DemoAuthority concurrency model
- ❌ Rename targets
- ❌ Reorganize folders
- ❌ Create duplicate files
- ❌ Delete files

### What You MAY Do
- ✅ Read existing files
- ✅ Propose small incremental changes
- ✅ Modify DemoViewModel and ContentView for demo features
- ✅ Add computed properties for rank labels
- ✅ Update AI_CONTEXT.md to reflect current state

### Developer Context
- Non-technical — explain in plain English
- Friday demo deadline — prioritize clarity over completeness
- Two simulators on one Mac — architecture supports this already

### Technical Constraints
- Swift 6, Swift Concurrency only (no Combine, no DispatchQueue)
- SwiftUI for all UI
- `@Observable` for ViewModels (not `ObservableObject`)
- Pure functions for all engines (no side effects)
- Actor serialization for DemoAuthority (no race conditions)

---

## 🔧 Developer Environment (Confirmed)
- **Xcode 26.3 (17C519)** — RC release, includes Swift 6.2.3
- **SDKs:** iOS 26.2, iPadOS 26.2, tvOS 26.2, macOS 26.2, visionOS 26.2
- **On-device debugging:** iOS 15+, tvOS 15+, watchOS 8+, visionOS
- **Requires:** macOS Sequoia 15.6 or later
- **Claude Agent** (Anthropic) — enabled, active agent
- **OpenAI Codex** — also available
- **MCP (Model Context Protocol)** — open standard

### ⚠️ Known Issues in Xcode 26.3 RC
| Issue | Impact | Workaround |
|-------|--------|------------|
| Denying Claude access to project in Desktop/Downloads/Documents is permanent | HIGH | Move project outside Desktop/Downloads/Documents |
| Pasting files into coding assistant doesn't reliably send contents | Medium | Move file to project, tell agent location |
| "Generate fix for issue" may crash Xcode | Medium | Don't use that button — ask agent to fix |
| Agent settings changes may not apply until Xcode relaunch | Low | Relaunch Xcode after settings changes |

---

## 📋 Confirmed API Documentation

### SwiftUI Observation Framework (iOS 17.0+)
- `@Observable` macro — attach to class to make it observable
- `Observable` protocol — type emits notifications when data changes
- `@ObservationIgnored` — disables tracking on specific property
- SwiftUI integration: `@Observable` works with `@State`, `@Environment`, `@Bindable`
- Pattern:
```swift
@Observable
class MyViewModel {
    var someState: String = ""
    @ObservationIgnored private var internalOnly: String = ""
}
```

### SwiftUI NavigationStack (iOS 16.0+)
- `NavigationStack` — creates stack managing navigation state
- `init(root:)` — stack manages its own state
- `init(path:root:)` — externally controlled state via `Binding`
- `NavigationLink(value:label:)` — pushes views by value type
- `.navigationDestination(for:destination:)` — associates data type with destination

### Swift Concurrency
- `actor` — reference type with serial execution
- `async`/`await` — asynchronous function calls
- `AsyncStream` — stream of values delivered asynchronously
- `Task` — unit of asynchronous work
- `@MainActor` — ensures code runs on main thread

---

## 📅 Session Log

| Date | Summary |
|---|---|
| 2026-02-17 | Project created with SwiftData template. Product vision received. Demo scope defined. Full engineering validation completed (6 phases). Architecture iterated through 3 versions — shared SwiftData → WebSocket → App Group+Darwin → final: in-memory DemoAuthority actor. All decisions documented. GitHub connected (royaltonitservices). AI_CONTEXT.md is single source of truth. File structure not yet proposed. No code written yet. |
| 2026-02-19 | Implementation phase began. Built SportsHubCore framework: all models (Player, Sport, MatchResult, CommitmentRecord, ProgressionRecord), ELORatingEngine (pure functions), CommitmentEngine (pure functions), all policy structs (SportConfig, PenaltyPolicy, ProgressionPolicy, MatchRules). Built SportsHub app: DemoAuthority actor (singleton, AsyncStream pub/sub, seedPlayers, applyMatchResult), DemoViewModel (@Observable, subscribes to authority, projects state), ContentView (player list, Simulate Match button, match log). Demo works but lacks: player identity selector, sport picker, rank labels. Friday demo scope frozen: minimal UI changes only, no new architecture, no persistence, no challenge system, no tests. AI_CONTEXT.md updated to reflect current state. Next: add player identity + sport picker + rank labels to existing ContentView and DemoViewModel. |

---

## 🔭 Long-Term Production Vision (NOT Current Task)

The real SportsHub platform will eventually include:
- Real user accounts with authentication
- Remote backend servers with persistent database
- Real-time matchmaking queues
- GPS arrival verification
- Push notifications for challenges and match events
- Moderation tools and reporting system
- Media uploads (player profiles, highlights)
- App Store distribution
- Tournament brackets and ranked seasons

**None of this is being built now.** The demo proves the product concept.

---

## ⚠️ Demo vs Production — Explicit Differences

| Concern | Demo (Now) | Production (Future) |
|---|---|---|
| Transport | `DemoAuthority` in-memory actor | Remote REST + WebSocket API |
| Accounts | Hardcoded Aarush + Manav | Real auth (Sign in with Apple) |
| Persistence | In-memory only | Server database + SwiftData cache |
| Matchmaking | Random simulation | Real queue algorithm |
| Arrival | N/A | GPS verification |
| Notifications | None | Push notifications (APNs) |
| Moderation | Stubbed | Real moderation backend |
| Distribution | Simulator only | App Store |

---

*This file is the single source of truth. Always update after meaningful work. Never create duplicate context files.*

