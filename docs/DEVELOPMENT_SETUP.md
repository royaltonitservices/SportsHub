# SportsHub Development Setup

Clean-machine setup for SportsHub (SwiftUI iOS + FastAPI backend). Only verified requirements are listed. **Never print or commit secret values.** `backend/.env` is local and gitignored.

## Repository
```bash
git clone https://github.com/royaltonitservices/SportsHub.git
cd SportsHub
git fetch --tags origin
git checkout current-state-stabilization-checkpoint
git rev-parse HEAD          # expect d6bc68c26da704b589ee848bd8c045d5f0aa0f36
```

## Toolchain (verified on the source Mac 2026-08-22)
| Tool | Version on source Mac | Notes |
|---|---|---|
| macOS | 26.6.2 (25G83) | verify on new Mac |
| Xcode | 26.6 (17F113) | required for the iOS build |
| Swift | 6.3.3 | bundled with Xcode |
| Python | 3.11.3 | backend venv interpreter |
| Git | 2.50.1 (Apple Git-155) | any recent Git is fine |

No submodules, no Git LFS.

## Backend Setup
Dependencies: `backend/requirements.txt` (FastAPI, uvicorn, SQLAlchemy 2, pydantic v2 + settings, python-jose, passlib[bcrypt], PyJWT, openai, alembic, psycopg2-binary, aiofiles, email-validator).

```bash
cd backend
python3 -m venv .venv                 # dev_backend.sh expects backend/.venv
./.venv/bin/pip install -r requirements.txt
```

Environment: copy the template and fill values locally (never commit):
```bash
cp .env.example .env                  # then edit backend/.env
```
Required environment variable **names** (values live only in `backend/.env`): see `docs`-level “External Non-Git State” below and `backend/config.py`.

Start / health / stop (helper script — uses `backend/.venv`, never touches `.env`, prints no secrets; logs+PID under `backend/.local/`, gitignored):
```bash
./../scripts/dev_backend.sh start
./../scripts/dev_backend.sh health    # curl http://localhost:8000/health -> {"status":"healthy"}
./../scripts/dev_backend.sh status
./../scripts/dev_backend.sh stop
```
(Equivalent manual start: `./.venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000` from `backend/`.)

## Dev Database
- Dev uses **SQLite** at `backend/sportshub.db` (gitignored, `DATABASE_URL=sqlite:///./sportshub.db`). Schema is created via `Base.metadata.create_all()` (`init_db()` in `database.py`) — but **only when the models have been imported** so `Base.metadata` is populated.
- **First-run schema init (REQUIRED before the backend test suite — the suite is not self-contained; it uses the app DB and assumes tables already exist):** run from `backend/`:
  ```bash
  ./.venv/bin/python -c "import models, models_premium; from database import init_db; init_db()"
  ```
  (Starting the backend once, or running the guarded seed, also creates the schema because both import the models. A bare `init_db()` **without** importing the models produces an empty 0-byte DB — do not do that.)
- Seed (fail-closed — all three required):
  ```bash
  APP_ENV=development SAMPLE_DATA_ENVIRONMENT=true ./.venv/bin/python seed_dev_data.py --reset --confirm-demo-data
  ```
  Seeding **refuses** unless `APP_ENV∈{development,demo}` **and** `SAMPLE_DATA_ENVIRONMENT=true` **and** `--confirm-demo-data`. `SAMPLE_DATA_ENVIRONMENT=true` also drives the in-app "Sample community data" banner.
- **Never run `seed_dev_data.py` against production.**

## iOS Setup
- Open `SportsHub.xcodeproj` (at the repo root) in Xcode; scheme **SportsHub** (auto-generated from the project — not a tracked shared scheme).
- Debug builds target `http://localhost:8000` (`APIConfig.baseURL`); run the backend first for networked flows.
- Signing: set your Apple Developer **team** on the target (Signing & Capabilities). Simulator builds/tests need no paid account; device installs + HealthKit/SIWA testing need a team.
- Simulator used for validation this cycle: iPhone 17 Pro (iOS 26.x).

## Tests (verified commands)
Backend (from `backend/`, 192 tests):
```bash
./.venv/bin/python -m unittest discover -s tests -p "test_*.py"
```
Seed-integrity subset:
```bash
./.venv/bin/python -m unittest tests.test_seed_integrity
```
iOS unit tests — target `SportsHubTests` (includes AI Coach routing/quality: clarification continuity, duration parser, inert-link Markdown; and identity matching `IdentityMatchTests`). **Verified from a clean origin clone: 312 unit tests pass, 0 failures.** Command-line run (the scheme is auto-generated from the tracked project — no shared scheme needed; use `CODE_SIGNING_ALLOWED=NO` so simulator source-portability is not gated by Apple signing):
```bash
# 1) pick an installed simulator: xcrun simctl list devices available | grep iPhone
# 2) boot it first (a shutdown sim throws "Invalid device state" on install):
xcrun simctl boot "<DEVICE_ID>"
# 3) run the whole unit-test target (Swift Testing suites resolve reliably at target scope,
#    not via -only-testing:SportsHubTests/<SwiftTestingSuite>):
xcodebuild test -project SportsHub.xcodeproj -scheme SportsHub \
  -destination "id=<DEVICE_ID>" -only-testing:SportsHubTests CODE_SIGNING_ALLOWED=NO
```
In-session, the xcode-tools MCP (`BuildProject`, `RunSomeTests`) runs against the open project; individual Swift Testing suites (`AICoachRoutingTests` ≈ AI routing, `AICoachQualityTests`, `IdentityMatchTests` = 11) resolve there by name.

## External Non-Git State
**Required for local dev today** (names only; values in `backend/.env`, gitignored — never commit):
| Name | Purpose | Obtain on new Mac |
|---|---|---|
| `OPENAI_API_KEY` | AI Coach live model calls (blank → deterministic fallback) | user’s OpenAI account |
| `SECRET_KEY` | JWT signing (dev default exists; set your own) | generate locally |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` (or `ADMIN_PASSWORD_HASH`) | admin bootstrap | user chooses |
| `DATABASE_URL` | DB (defaults to Postgres string; dev uses SQLite path) | leave default for SQLite dev |
| `APP_ENV`, `SAMPLE_DATA_ENVIRONMENT` | seed guard + banner | set only for seeding |
| `EMAIL_VERIFICATION_MODE` | signup verification policy (`auto` dev) | optional |
| `SPORTSHUB_AI_*` model / limit overrides | optional AI tuning | optional |
| Apple Developer account/team | iOS signing, HealthKit, SIWA | user’s Apple ID/team |

**Future production-only credentials (do NOT exist yet; provision when the relevant phase starts):**
Sign in with Apple key/Services ID · App Store Connect API key · APNs key (if APNs implemented) · hosted Postgres URL · object-storage + CDN credentials · Redis/shared-store URL · production `SECRET_KEY` + rotated admin creds · Sentry DSN.

## New-Mac Verification Checklist
1. `git clone` + `git checkout current-state-stabilization-checkpoint`; confirm HEAD `d6bc68c`.
2. Create `backend/.venv`; `pip install -r backend/requirements.txt`.
3. `cp backend/.env.example backend/.env`; fill required names.
4. Initialize schema (required before tests): `./backend/.venv/bin/python -c "import models, models_premium; from database import init_db; init_db()"` (run from `backend/`).
5. `scripts/dev_backend.sh start` → `health` returns `{"status":"healthy"}`.
6. Backend suite: **192 pass** (verified reproducible from a clean origin clone on 2026-08-22 after step 4).
7. iOS: boot a simulator, then build + run the `SportsHubTests` target (`CODE_SIGNING_ALLOWED=NO`) — **312 unit tests pass, 0 failures** (incl. all AI Coach + identity suites). Verified reproducible from a clean origin clone on 2026-08-22 (build 0 errors).
8. `git status` clean; confirm HEAD + tags match origin.
9. Confirm **no undocumented local-only dependency** was needed (documented externals in `backend/.env` are expected).
