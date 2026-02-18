# Project: Sports Hub
**Created:** 2026-02-17
**Last Updated:** 2026-02-17 (update this date manually when resuming a new session)
**Developer:** Aarush Khanna
**Platform:** iOS (iPhone) — dual iPhone 17 Pro simulators for demo
**Minimum Deployment Target:** TBD (confirm from Xcode project settings)
**Swift Version:** Swift 6
**Xcode Version:** 26.3 (17C519)

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

## 🎯 Current Assignment — Demo Mode

We are building a **presentation simulator**, not a production deployment.

### Demo Rules
- Runs 100% locally — no internet, no permissions required
- Never crashes during live presentation
- Uses **fake data, real rules** — ELO math is correct, penalties are enforced
- Two simulated users: **Aarush** and **Manav**
- Both run on **one Mac with two iPhone simulators** feeling like two separate phones
- Hidden **Presenter Control Panel** for instant recovery, result overrides, time jumps, full reset

### Demo Sports Scope
- **Basketball** — primary, actively demonstrated
- **Football, Soccer, Tennis** — visible in UI, switching must change ratings/challenges/leaderboards
- Rating engine is **shared across sports** with per-sport configuration parameters

---

## 🏗️ Architecture

### Layer Diagram
```
┌──────────────────────────────────────────────────────────────┐
│                        UI LAYER                              │
│  SwiftUI Views — purely declarative, zero logic              │
│  PlayerDashboardView, MatchView, LeaderboardView,            │
│  ChallengeView, PresenterControlPanel (hidden)               │
└──────────────────┬───────────────────────────────────────────┘
                   │ observes via @Observable
┌──────────────────▼───────────────────────────────────────────┐
│                   VIEWMODEL LAYER                            │
│  @Observable classes — state + intent only                   │
│  DashboardViewModel, MatchViewModel,                         │
│  LeaderboardViewModel, SessionViewModel                      │
└──────────────────┬───────────────────────────────────────────┘
                   │ calls via protocol
┌──────────────────▼───────────────────────────────────────────┐
│                SERVICE LAYER (protocols)                     │
│  MatchServiceProtocol                                        │
│  RatingServiceProtocol                                       │
│  PlayerServiceProtocol                                       │
│  LeaderboardServiceProtocol                                  │
│  CommitmentServiceProtocol                                   │
└──────────────────┬───────────────────────────────────────────┘
                   │ implemented by (demo only)
┌──────────────────▼───────────────────────────────────────────┐
│             DEMO SERVICE IMPLEMENTATIONS                     │
│  DemoMatchService, DemoRatingService, etc.                   │
│  Thin wrappers — delegate all logic to DemoAuthority         │
│  Replaced by RealMatchService etc. in production             │
└──────────────────┬───────────────────────────────────────────┘
                   │ calls
┌──────────────────▼───────────────────────────────────────────┐
│              DemoAuthority (Swift actor — singleton)         │
│                                                              │
│  Single source of truth — lives in process memory           │
│  Shared by both simulator instances automatically            │
│  Zero configuration, zero entitlements, zero disk I/O        │
│  Serial execution — actor guarantees no race conditions      │
│  Publishes state via AsyncStream to all registered clients   │
│  PresenterOverrideStore lives here                           │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              DOMAIN ENGINES (pure Swift)             │   │
│  │  ELORatingEngine — pure functions, no side effects   │   │
│  │  CommitmentEngine — penalty + strike logic           │   │
│  │  ProgressionEngine — rank tiers, unlocks             │   │
│  │  MatchmakingEngine — fairness scoring                │   │
│  │  TrustEngine — safety flags (stubbed for demo)       │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              POLICY LAYER (constants)                │   │
│  │  SportConfig — K-factor, rating floor per sport      │   │
│  │  PenaltyPolicy — strike rules, timeouts              │   │
│  │  ProgressionPolicy — rank thresholds, unlocks        │   │
│  │  MatchRules — score reporting, dispute resolution    │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  In-memory state:                                            │
│  [PlayerRecord], [MatchRecord], [ChallengeRecord]            │
│  Seeded deterministically at launch                          │
│  Reset instantly via PresenterOverride                       │
└──────────────────────────────────────────────────────────────┘
```

### How DemoAuthority Works (Plain English)
1. App launches on both simulators — both attach to the same `DemoAuthority.shared` actor in memory
2. Both register as clients and receive an `AsyncStream<GameState>` — a live feed of state updates
3. Simulator A (Aarush) takes an action — e.g. sends a challenge
4. `DemoMatchService` calls `DemoAuthority.shared.sendChallenge(...)`
5. Actor processes the command serially — applies domain rules — updates in-memory state
6. Actor pushes new `GameState` snapshot to all registered `AsyncStream` subscribers
7. Both ViewModels receive the update on their async streams
8. Both UIs update simultaneously — no disk, no network, no notification, no configuration

### Core Principles
- **MVVM** — Views know nothing about data sources
- **Protocol-based services** — demo implementations and real backend are interchangeable
- **DemoAuthority singleton actor** — one authority, zero configuration, zero environment risk
- **In-memory only** — no disk I/O, no entitlements, no App Groups, no Darwin notifications
- **AsyncStream** — Swift-native push delivery from actor to all clients
- **Rules engine is pure Swift** — no UI dependencies, no side effects, fully testable
- **Deterministic** — actor serialises all mutations, seeded state is reproducible
- **`UserSession`** — each simulator knows which player it is via UserDefaults
- **Transport layer is a protocol** — DemoAuthority is one implementation, real backend is another

### Architecture Decisions (Locked)
- Swift Concurrency (async/await + actors) — NO Combine, NO DispatchQueue
- In-memory state only for demo — no SwiftData writes during demo flow
- SwiftUI for all UI
- Codable structs for all state snapshots — identical shape to real API responses
- AsyncStream for state delivery — zero configuration, Swift-native
- UserDefaults for active player selection only
- No hardcoded UI hacks that block backend replacement
- `SportsHubCore` — shared framework target containing DemoAuthority + domain engines
- `SportsHub` — iOS app target, imports SportsHubCore

### Xcode Targets
| Target | Type | Purpose |
|---|---|---|
| `SportsHub` | iOS App | Runs on both simulators |
| `SportsHubCore` | Swift Framework | DemoAuthority + domain engines + service protocols |
| `SportsHubTests` | Test Bundle | Unit tests for all engines |

### Backend Replacement Path
When real backend is ready, only the Demo Service implementations are replaced:

| Now (Demo) | Future (Production) |
|---|---|
| `DemoMatchService` → `DemoAuthority` | `RemoteMatchService` → REST/WebSocket API |
| `DemoRatingService` → `DemoAuthority` | `RemoteRatingService` → REST API |
| In-memory `GameState` | Server-authoritative `GameState` via API responses |
| `AsyncStream` from actor | `AsyncStream` from URLSession WebSocket |

ViewModels, Views, domain engines — **zero changes required.**

### Why In-Memory Singleton Is Correct for This Demo
| Risk | App Group + Darwin | In-Memory DemoAuthority |
|---|---|---|
| Entitlement configuration | ❌ Must be correct | ✅ None required |
| Simulator container behaviour | ❌ Can differ from device | ✅ Pure Swift — identical everywhere |
| Signing configuration | ❌ Can break between machines | ✅ Not involved |
| Setup steps before demo | ❌ Exists | ✅ Zero |
| Communication failure | ❌ Possible | ✅ Impossible — same memory |
| Race conditions | ❌ Possible across processes | ✅ Actor eliminates them |
| Reset speed | ❌ Must clear disk + re-notify | ✅ One actor call — instant |
| Backend replacement | ✅ Swap service | ✅ Swap service |

---

## 🔭 Long-Term Production Vision (NOT current task)

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

**None of this is being built now.** The demo proves the product concept. The architecture is designed so production features slot in without redesigning anything above the service layer.

## ⚠️ Demo vs Production — Explicit Differences

| Concern | Demo (Now) | Production (Future) |
|---|---|---|
| Transport | `DemoAuthority` in-memory actor | Remote REST + WebSocket API |
| Accounts | Hardcoded Aarush + Manav | Real auth (Sign in with Apple) |
| Persistence | In-memory only | Server database + SwiftData cache |
| Matchmaking | Scripted/deterministic | Real queue algorithm |
| Arrival | Timer only | GPS verification |
| Notifications | None | Push notifications (APNs) |
| Moderation | Stubbed | Real moderation backend |
| Distribution | Simulator only | App Store |

## 🔁 Transport Replacement Plan

`DemoAuthority` is a **temporary adapter** behind the service protocol layer.

To replace it with a real backend:
1. Implement `RemoteMatchService: MatchServiceProtocol`
2. Implement `RemoteRatingService: RatingServiceProtocol`
3. Implement `RemotePlayerService: PlayerServiceProtocol`
4. Implement `RemoteLeaderboardService: LeaderboardServiceProtocol`
5. Implement `RemoteCommitmentService: CommitmentServiceProtocol`
6. Inject real implementations at app startup instead of demo implementations

**Nothing above the service layer changes.** ViewModels, Views, and domain engines are untouched.



When unsure, prioritize in this order:
1. Demo reliability
2. Product rule accuracy
3. Code clarity
4. UI polish
5. Feature completeness

---

## 🔨 Build Sequence

| Phase | Deliverable | Status |
|-------|-------------|--------|
| 1 | Domain models + Rules Engine (ELO, penalties, progression) | 🔜 Not started |
| 2 | Service protocols (contracts before implementation) | 🔜 Not started |
| 3 | Simulation engine (demo data behind service protocol) | 🔜 Not started |
| 4 | SwiftData repositories | 🔜 Not started |
| 5 | ViewModels | 🔜 Not started |
| 6 | Core SwiftUI views | 🔜 Not started |
| 7 | Presenter Control Panel (hidden demo recovery) | 🔜 Not started |
| 8 | Polish & HIG compliance | 🔜 Not started |

---

## 📦 Key Files & Their Roles

| File | Role |
|------|------|
| `SportsHubApp.swift` | App entry point. ModelContainer wired up for SwiftData. |
| `AI_CONTEXT.md` | Living project brief. Updated automatically each session. |
| `SportsHubTests.swift` | Unit test target using Swift Testing (`@Test` macros). |
| `SportsHubUITests.swift` | UI test target. |
| `SportsHubUITestsLaunchTests.swift` | Launch UI tests. |

> More files will be added as phases begin. This table is updated automatically.

---

## 🏃 Domain / Feature Areas

| Area | Description |
|------|-------------|
| **ELO Rating Engine** | Shared engine, per-sport config (Basketball, Football, Soccer, Tennis) |
| **Match Lifecycle** | Challenge → Accept → Play → Report → Resolve |
| **Commitment System** | Attendance tracking, penalty rules, no-show enforcement |
| **Progression System** | Rank tiers, unlocks, tournament access |
| **Leaderboards** | Per-sport, filterable by region/skill tier |
| **Trust & Safety** | Reporting, moderation hooks (stubbed for demo) |
| **Presenter Control Panel** | Hidden UI for demo override, time travel, full reset |

---

## 🧪 Testing Strategy

- Rules engine → **100% unit tested with Swift Testing BEFORE implementation** (TDD)
- ViewModels → tested with mock service implementations
- UI → UI tests for critical demo paths (login, match flow, leaderboard)
- No test is skipped because "it's a demo" — rules must be mathematically correct

---

## 🐛 Known Issues
*(None yet)*

---

### Xcode 26.3 (17C519) — What's New (Ground Truth)
- **Coding Intelligence** — natural language coding assistant, Coding Tools for inline fixes/docs/changes
  - Requires Mac with Apple silicon + macOS Tahoe
  - Supports Claude (Anthropic) and OpenAI models
- **`#Playground` macro** — preview non-UI Swift code inline (NEW in Xcode 26)
- **Redesigned Tab experience** — easier file navigation
- **Localization catalog enhancements**
- **Instruments — NEW tools in Xcode 26:**
  - `Processor Trace` — hardware-assisted CPU tracing (Apple silicon)
  - `CPU Counter` — hardware-assisted CPU performance counters
  - **SwiftUI Instrument** — visualizes how data changes affect SwiftUI view updates ⬅️ directly useful for SportsHub
- **XCUIAutomation** — record, run, maintain UI tests; replay in multiple locales/devices/conditions
- **Icon Composer** — creates layered Liquid Glass icons from single design for iPhone/iPad/Mac/Watch
  - Multi-layer icon format with Liquid Glass properties
  - Dynamic lighting preview, appearance mode annotation
  - Exports flattened version for marketing
- **macOS Tahoe** — required OS for Xcode 26 intelligence features

## 🔧 Developer Environment (Confirmed)
- **Xcode 26.3 (17C519)** — RC release, includes Swift 6.2.3
- **SDKs:** iOS 26.2, iPadOS 26.2, tvOS 26.2, macOS 26.2, visionOS 26.2
- **On-device debugging:** iOS 15+, tvOS 15+, watchOS 8+, visionOS
- **Requires:** macOS Sequoia 15.6 or later
- **Claude Agent** (Anthropic) — enabled, this IS the active agent for this session
- **OpenAI Codex** — also available
- **MCP (Model Context Protocol)** — open standard, any compatible agent can connect

### ⚠️ Known Issues in Xcode 26.3 RC — Affects Our Workflow
| Issue | Impact on SportsHub | Workaround |
|---|---|---|
| Denying Claude access to project in Desktop/Downloads/Documents is **permanent** — no retry | **HIGH** — if project is on Desktop, move it now | Move project outside Desktop/Downloads/Documents |
| Pasting files into coding assistant doesn't reliably send contents | Medium — affects doc pasting | Move file to project directory, tell agent its location |
| "Allow agents to use integrated internet access tools" only applies to Codex, **not Claude** | Low — we don't need internet | Manually allow each web command for Claude if needed |
| `#Preview` / `#Playground` may fail after "Run snippet" tool | Low | Build active scheme to clear error |
| "Generate fix for issue" may crash Xcode | Medium | Don't use that specific button — ask me to fix instead |
| Agent settings changes may not apply until Xcode relaunch | Low | Relaunch Xcode after changing agent settings |

## 💬 Notes for AI Assistant
- Developer is non-technical — explain decisions in plain English alongside code
- ALWAYS update this file automatically after any meaningful session work
- ALWAYS use `str_replace` for edits — never rewrite whole files unless asked
- NEVER create duplicate files — check before creating anything
- NEVER delete files — only the developer deletes files
- Xcode version is **26.3 (17C519)** — treat as authoritative
- Use Swift Testing (`@Test`, `#expect`, `#require`) — not XCTest
- Prefer `@Observable` over `ObservableObject`
- No Combine, no DispatchQueue — Swift Concurrency only
- This file (`AI_CONTEXT.md`) is the **single source of truth** — no other context files should exist

## 📋 Confirmed API Documentation (Pasted by Developer — Treat as Ground Truth)

### SwiftData (iOS 17.0+ / confirmed current as of 2026)
- `@Model` macro — converts Swift class into SwiftData managed model
- `@Attribute` macro — customises property behaviour (options, originalName, hashModifier)
- `@Relationship` macro — defines relationships with deleteRule, min/max counts, inverse
- `@Transient` macro — excludes property from persistence
- `@Unique` macro — enforces uniqueness constraints on key paths
- `@Index` macro — creates binary or R-tree indices
- `@Query` macro — fetches model instances in SwiftUI views, auto-updates view on changes
- `ModelContainer` — manages schema and storage configuration
- `ModelContext` — insert, update, delete, save models
- `FetchDescriptor` — criteria + sort order for fetches
- `modelContext` environment value — access context in any SwiftUI view
- `.modelContainer()` / `.modelContext()` view modifiers
- `DataStore` protocol — custom storage backend (key for our demo → real backend swap)
- `DefaultStore` — Core Data backed default store
- History/audit trail APIs available (`HistoryDescriptor`, `HistoryTransaction`, etc.)
### NavigationStack (iOS 16.0+ / confirmed current as of 2026)
- `NavigationStack` — `@MainActor @preconcurrency struct NavigationStack<Data, Root> where Root: View`
- `init(root:)` — creates stack managing its own navigation state
- `init(path:root:)` — creates stack with externally controlled navigation state via `Binding`
- `NavigationLink(value:label:)` — pushes views by value type
- `.navigationDestination(for:destination:)` — associates a data type with a destination view
- `.navigationDestination(isPresented:destination:)` — binding-based push
- `.navigationDestination(item:destination:)` — optional binding push
- `NavigationPath` — type-erased path for stacks that navigate to multiple data types
- Pattern: `@State private var path: [MyType] = []` then `NavigationStack(path: $path)`
### Observation Framework (iOS 17.0+ / confirmed current as of 2026)
- `@Observable` macro — attach to a class to make it observable (declares + implements `Observable` protocol at compile time)
- `Observable` protocol — type emits notifications when underlying data changes
- `@ObservationIgnored` — disables observation tracking on a specific property
- `@ObservationTracked` — synthesizes accessors for a property (explicit, usually automatic)
- `ObservationRegistrar` — provides storage for tracking (used internally, rarely directly)
- `withObservationTracking(_:onChange:)` — tracks property access in apply closure, fires onChange when those specific properties change
- `Observations` — async sequence of transactional changes to `@Observable` types
- **Key rule:** Only properties accessed inside the tracking closure are observed — not all properties
- **SwiftUI integration:** `@Observable` classes work directly with `@State`, `@Environment`, and `@Bindable` — no need for `@StateObject` or `@ObservedObject`
- **Pattern for ViewModels:**
```swift
@Observable
class MyViewModel {
    var someState: String = ""
    @ObservationIgnored private var internalOnly: String = ""
}
```
### SwiftUI Updates — iOS 26 / June 2025 (Xcode 26 — Ground Truth)

#### Liquid Glass & Visual Design (NEW in iOS 26)
- `glassEffect(_:in:)` — apply Liquid Glass to any view
- `.buttonStyle(.glass)` — Liquid Glass on `Button`
- `ToolbarSpacer` — visual break between Liquid Glass toolbar items
- `scrollEdgeEffectStyle(_:for:)` — scroll edge effect style
- `backgroundExtensionEffect()` — duplicates/mirrors/blurs views at safe area edges
- `tabBarMinimizeBehavior(_:)` — tab bar minimization behaviour

#### Tab View (NEW in iOS 26)
- `TabViewBottomAccessoryPlacement` — adjust accessory content by tab position
- Search tab role — search field replaces tab bar

#### WebView (NEW in iOS 26)
- `WebView` + `WebPage` — full browser control in SwiftUI

#### Drag and Drop (NEW in iOS 26)
- `draggable(containerItemID:containerNamespace:)` — drag multiple items
- `dragContainer(for:itemID:in:_:)` — container for draggable views

#### Animation (NEW in iOS 26)
- `Animatable()` macro — synthesizes custom animatable data
- `Slider` — tick marks now supported, appear automatically with `step`
- `windowResizeAnchor(_:)` — window anchor on resize

#### Text & Editing (NEW in iOS 26)
- `TextEditor` now supports `AttributedString` directly
- `AttributedTextSelection` — selection handling with attributed text
- `AttributedTextFormattingDefinition` — context-specific text styling rules
- `FindContext` — find navigator for text editing views

#### Accessibility (NEW in iOS 26)
- `AssistiveAccess` scene type for iOS/iPadOS

#### HDR (NEW in iOS 26)
- `Color.ResolvedHDR` — RGBA + HDR headroom

#### UIKit/AppKit Integration (NEW in iOS 26)
- `UIHostingSceneDelegate` — SwiftUI scenes hosted in UIKit
- `NSHostingSceneRepresentation` — SwiftUI scenes in AppKit
- `NSGestureRecognizerRepresentable` — AppKit gesture recognizers in SwiftUI

#### Also confirmed available (from June 2024 section)
- `NavigationStack` path-based navigation ✅ (already documented above)
- `TabView` with `sidebarAdaptable`, `tabBarOnly`, `grouped` styles
- `TabSection` — nested tabs
- `tabViewCustomization(_:)` — user-customizable tab views
- `presentationSizing(_:)` — sheet sizing with `.form`, `.page`, or custom
- `scrollPosition(_:anchor:)` — programmatic scroll to view/offset/edge
- `MeshGradient` — mesh gradients with grid of points and colors
- `Entry()` macro — for `EnvironmentValues`, `Transaction`, `ContainerValues`
- `Previewable()` macro — dynamic properties inline in previews
- `PreviewModifier` — inject shared dependencies into previews

⚠️ **iOS 26 NOTE:** Liquid Glass APIs (`glassEffect`, `.buttonStyle(.glass)`, `ToolbarSpacer`) are NEW and only available on iOS 26+. Do not use without availability checks for older targets.

---

## 📅 Session Log

| Date | Summary |
|---|---|
| 2026-02-17 | Project created with SwiftData template. Product vision received. Demo scope defined. Full engineering validation completed (6 phases). Architecture iterated through 3 versions — shared SwiftData → WebSocket → App Group+Darwin → final: in-memory DemoAuthority actor. All decisions documented. GitHub connected (royaltonitservices). AI_CONTEXT.md is single source of truth. File structure not yet proposed. No code written yet. |
