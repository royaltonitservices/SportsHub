"""
migrate_schema_v2.py — Idempotent migration for schema gaps found during
backend-up validation (2026-04-26).

Covers columns that were added to models.py but never applied to existing
SQLite databases. Safe to run against any sportshub.db at any state:
- Skips columns that already exist
- No data is deleted or modified
- Works with SQLite (uses PRAGMA table_info, not information_schema)

For a FRESH database this script is unnecessary — Base.metadata.create_all()
on startup will produce the correct schema from models.py directly.

Usage:
  cd backend
  python migrate_schema_v2.py          # live
  python migrate_schema_v2.py --dry-run

Tables affected:
  challenges        — 5 new columns (result submission + accepted_at)
  clips             — 2 new columns (description, thumbnail_url)
  onboarding_surveys — 1 new column (goals, also in migrate_auth_onboarding.py Step 2b)
"""

import sys
import os
import argparse
import sqlite3

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
# Change to the backend dir so pydantic-settings finds .env
os.chdir(SCRIPT_DIR)
from config import get_settings
DATABASE_URL = get_settings().database_url


def get_sqlite_path(url: str) -> str:
    """Extract file path from a SQLite DATABASE_URL."""
    # sqlite:///./foo.db  or  sqlite:////abs/path/foo.db
    if url.startswith("sqlite:///"):
        return url[len("sqlite:///"):]
    raise ValueError(f"Not a SQLite URL: {url}")


def column_exists(cur: sqlite3.Cursor, table: str, column: str) -> bool:
    cur.execute(f"PRAGMA table_info({table})")
    return any(row[1] == column for row in cur.fetchall())


MIGRATIONS = [
    # (table, column, type)
    ("challenges", "accepted_at",              "DATETIME"),
    ("challenges", "challenger_submitted_score", "VARCHAR(50)"),
    ("challenges", "opponent_submitted_score",   "VARCHAR(50)"),
    ("challenges", "challenger_submitted_at",    "DATETIME"),
    ("challenges", "opponent_submitted_at",      "DATETIME"),
    ("clips",      "description",               "TEXT"),
    ("clips",      "thumbnail_url",             "VARCHAR(500)"),
    ("onboarding_surveys", "goals",             "JSON"),
]


def run_migration(dry_run: bool = False) -> None:
    print("=" * 60)
    print("SportsHub — Schema v2 Migration")
    print(f"Mode: {'DRY RUN (no changes will be written)' if dry_run else 'LIVE'}")
    print("=" * 60)

    db_path = get_sqlite_path(DATABASE_URL)
    if not os.path.exists(db_path):
        print(f"\nDatabase not found at: {db_path}")
        print("A fresh DB will be created by create_all() on next server start.")
        print("This migration is only needed for existing databases.")
        return

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    applied = []
    skipped = []

    for table, column, col_type in MIGRATIONS:
        if column_exists(cur, table, column):
            print(f"  SKIP  {table}.{column} — already exists")
            skipped.append(f"{table}.{column}")
        else:
            sql = f"ALTER TABLE {table} ADD COLUMN {column} {col_type}"
            print(f"  ADD   {table}.{column} ({col_type})")
            if not dry_run:
                cur.execute(sql)
            applied.append(f"{table}.{column}")

    if not dry_run:
        conn.commit()
    conn.close()

    print("\n" + "=" * 60)
    if applied:
        status = "Would add" if dry_run else "Added"
        print(f"{status} {len(applied)} column(s): {', '.join(applied)}")
    if skipped:
        print(f"Skipped {len(skipped)} already-present column(s).")
    if not applied and not skipped:
        print("Nothing to do.")
    print("=" * 60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="SportsHub schema v2 migration")
    parser.add_argument("--dry-run", action="store_true",
                        help="Preview changes without applying them")
    args = parser.parse_args()
    run_migration(dry_run=args.dry_run)
