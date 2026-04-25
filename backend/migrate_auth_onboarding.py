"""
migrate_auth_onboarding.py — Safe DB migration for the auth + onboarding upgrade.

What this migration does:
  1. Adds new columns to the `users` table (skips columns that already exist)
  2. Creates the `onboarding_surveys` table (skips if it already exists)
  3. Backfills existing users as legacy accounts:
       is_legacy_account = TRUE
       email_verified    = TRUE
       survey_completed  = FALSE  (they will be offered the survey the next time
                                   they open the app, but are NOT blocked from it)
  4. Reports a summary of changes made

Safety guarantees:
  - READ-ONLY inspection first — no writes until columns are confirmed present
  - Every ALTER TABLE is guarded by an existence check — idempotent / safe to re-run
  - CREATE TABLE uses IF NOT EXISTS
  - UPDATE uses a WHERE clause — only touches rows that need backfilling
  - All operations run in a single transaction; any failure rolls back cleanly
  - Dry-run mode available: pass --dry-run to see what WOULD run without changing anything

Usage:
  python migrate_auth_onboarding.py          # live migration
  python migrate_auth_onboarding.py --dry-run
"""

import sys
import os
import argparse

# Add the backend directory to path so we can import database/config
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sqlalchemy import text, create_engine, inspect
from database import DATABASE_URL  # Import connection string from existing config


# ── Helpers ──────────────────────────────────────────────────────────────────

def column_exists(conn, table: str, column: str) -> bool:
    """Check if a column exists in a table using INFORMATION_SCHEMA."""
    result = conn.execute(text(
        "SELECT COUNT(*) FROM information_schema.columns "
        "WHERE table_name = :tbl AND column_name = :col"
    ), {"tbl": table, "col": column})
    return result.scalar() > 0


def table_exists(conn, table: str) -> bool:
    """Check if a table exists."""
    result = conn.execute(text(
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE table_name = :tbl"
    ), {"tbl": table})
    return result.scalar() > 0


# ── Column definitions to add to `users` ─────────────────────────────────────

USERS_NEW_COLUMNS = [
    # Auth: email verification
    ("email_verified",                "BOOLEAN DEFAULT FALSE"),
    ("verification_token",            "VARCHAR(255)"),
    ("verification_code_hash",        "VARCHAR(255)"),
    ("verification_code_expires_at",  "TIMESTAMP"),
    ("verification_code_attempts",    "INTEGER DEFAULT 0"),
    ("verification_last_sent_at",     "TIMESTAMP"),
    ("verification_code_used",        "BOOLEAN DEFAULT FALSE"),

    # Onboarding
    ("survey_completed",    "BOOLEAN DEFAULT FALSE"),
    ("onboarding_version",  "INTEGER DEFAULT 1"),
    ("is_legacy_account",   "BOOLEAN DEFAULT FALSE"),
]


# ── onboarding_surveys table ──────────────────────────────────────────────────

CREATE_ONBOARDING_SURVEYS = """
CREATE TABLE IF NOT EXISTS onboarding_surveys (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    main_sport          VARCHAR(50) NOT NULL,
    skill_ratings       JSONB DEFAULT '{}',
    strengths           JSONB DEFAULT '[]',
    weaknesses          JSONB DEFAULT '[]',
    onboarding_version  INTEGER DEFAULT 1,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE,
    CONSTRAINT onboarding_surveys_user_id_unique UNIQUE (user_id)
);
"""


# ── Main ──────────────────────────────────────────────────────────────────────

def run_migration(dry_run: bool = False):
    print("=" * 60)
    print("SportsHub — Auth + Onboarding Migration")
    print(f"Mode: {'DRY RUN (no changes will be written)' if dry_run else 'LIVE'}")
    print("=" * 60)

    engine = create_engine(DATABASE_URL)

    with engine.begin() as conn:
        changes_made = []

        # ── Step 1: Add new columns to `users` ──────────────────────────────
        print("\n[Step 1] Checking users table columns...")

        for col_name, col_def in USERS_NEW_COLUMNS:
            if column_exists(conn, "users", col_name):
                print(f"  ✓ users.{col_name} — already exists, skipping")
            else:
                sql = f"ALTER TABLE users ADD COLUMN {col_name} {col_def}"
                print(f"  + users.{col_name} — ADDING ({col_def})")
                if not dry_run:
                    conn.execute(text(sql))
                changes_made.append(f"Added column users.{col_name}")

        # ── Step 2: Create onboarding_surveys table ──────────────────────────
        print("\n[Step 2] Checking onboarding_surveys table...")

        if table_exists(conn, "onboarding_surveys"):
            print("  ✓ onboarding_surveys — already exists, skipping")
        else:
            print("  + onboarding_surveys — CREATING")
            if not dry_run:
                conn.execute(text(CREATE_ONBOARDING_SURVEYS))
            changes_made.append("Created table onboarding_surveys")

        # ── Step 2b: Add goals column to onboarding_surveys (Phase 13) ───────
        print("\n[Step 2b] Checking onboarding_surveys.goals column (Phase 13)...")

        if table_exists(conn, "onboarding_surveys"):
            if column_exists(conn, "onboarding_surveys", "goals"):
                print("  ✓ onboarding_surveys.goals — already exists, skipping")
            else:
                sql = "ALTER TABLE onboarding_surveys ADD COLUMN goals JSONB DEFAULT '[]'"
                print("  + onboarding_surveys.goals — ADDING (JSONB DEFAULT '[]')")
                if not dry_run:
                    conn.execute(text(sql))
                changes_made.append("Added column onboarding_surveys.goals")

        # ── Step 3: Backfill existing users as legacy accounts ────────────────
        # Only touch rows where is_legacy_account is not already set.
        # email_verified = TRUE so they're not forced through the verification flow.
        # survey_completed = FALSE so they can optionally complete the survey later.
        print("\n[Step 3] Backfilling legacy users...")

        # Count rows that need backfilling
        if column_exists(conn, "users", "is_legacy_account"):
            count_result = conn.execute(text(
                "SELECT COUNT(*) FROM users WHERE is_legacy_account IS NULL OR is_legacy_account = FALSE"
            ))
            affected = count_result.scalar()
            print(f"  {affected} users need backfilling")

            if affected > 0:
                if not dry_run:
                    conn.execute(text("""
                        UPDATE users
                        SET
                            is_legacy_account = TRUE,
                            email_verified    = TRUE,
                            survey_completed  = FALSE
                        WHERE
                            is_legacy_account IS NULL OR is_legacy_account = FALSE
                    """))
                    print(f"  ✓ Backfilled {affected} users as legacy accounts (email_verified=TRUE, survey_completed=FALSE)")
                else:
                    print(f"  [DRY RUN] Would backfill {affected} users")
                changes_made.append(f"Backfilled {affected} legacy users")
        else:
            print("  ⚠  is_legacy_account column not found — skipping backfill (was step 1 successful?)")

        # ── Summary ───────────────────────────────────────────────────────────
        print("\n" + "=" * 60)
        if changes_made:
            print(f"Migration {'preview' if dry_run else 'complete'}. Changes {'that would be made' if dry_run else 'made'}:")
            for c in changes_made:
                print(f"  • {c}")
        else:
            print("No changes needed — database is already up to date.")
        print("=" * 60)

        if dry_run:
            # Rollback so nothing actually commits
            conn.execute(text("ROLLBACK"))
            print("\n[DRY RUN] Transaction rolled back. Re-run without --dry-run to apply.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="SportsHub auth + onboarding DB migration")
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without applying them")
    args = parser.parse_args()

    run_migration(dry_run=args.dry_run)
