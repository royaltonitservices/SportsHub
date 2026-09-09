"""Gate 1.4B dev transition — make BlockedUser the canonical block store on an EXISTING DB.

Two data conversions, both idempotent and rerun-safe (no schema DDL here):
  1. Convert legacy `Friendship.BLOCKED` rows -> directed `BlockedUser(blocker=initiated_by,
     blocked=the other party)`, then delete the legacy row. Rows whose `initiated_by` is NULL
     or not a participant are AMBIGUOUS: they are NOT guessed — left in place and reported.
  2. Deduplicate any duplicate directed `BlockedUser(blocker, blocked)` rows (keep one).

The `uq_blocked_directed` UNIQUE constraint itself lands on fresh DBs via create_all; adding
it to an existing SQLite table needs an Alembic table-rebuild (Gate 2.1A). This dedupe makes
that future add safe. Wrapped in one transaction; a failure rolls back with no partial state.

Run from backend/:  python migrate_gate14_blocking.py
"""
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker

from database import engine
import models

# A UNIQUE INDEX enforces directed-block uniqueness on an EXISTING SQLite DB without the
# table rebuild a table-level constraint would require. Fresh DBs already get the
# `uq_blocked_directed` table constraint via create_all; formal Alembic = Gate 2.1A.
UNIQUE_INDEX_NAME = "ux_blocked_users_directed"


def convert_legacy_blocks(db) -> dict:
    """Returns {'converted','ambiguous','deduped'}. Idempotent + rerun-safe."""
    converted = 0
    ambiguous = 0
    legacy = db.query(models.Friendship).filter(
        models.Friendship.status == models.FriendshipStatus.BLOCKED
    ).all()
    for f in legacy:
        blocker = f.initiated_by
        if blocker is None or blocker not in (f.user_a_id, f.user_b_id):
            ambiguous += 1          # do NOT guess direction — leave the row untouched
            continue
        blocked = f.user_b_id if f.user_a_id == blocker else f.user_a_id
        exists = db.query(models.BlockedUser).filter(
            models.BlockedUser.blocker_id == blocker,
            models.BlockedUser.blocked_id == blocked,
        ).first()
        if exists is None:
            db.add(models.BlockedUser(blocker_id=blocker, blocked_id=blocked))
            db.flush()
        db.delete(f)
        converted += 1
    deduped = _dedupe_blocked(db)
    return {"converted": converted, "ambiguous": ambiguous, "deduped": deduped}


def ensure_unique_index(db) -> None:
    """Create the directed-block UNIQUE index (idempotent). MUST run after dedupe, or the
    index creation will fail on pre-existing duplicates. After this, the DATABASE rejects a
    duplicate directed block — application writes cannot silently bypass it."""
    db.execute(text(
        f"CREATE UNIQUE INDEX IF NOT EXISTS {UNIQUE_INDEX_NAME} "
        "ON blocked_users (blocker_id, blocked_id)"))
    db.commit()


def _dedupe_blocked(db) -> int:
    """Remove duplicate directed BlockedUser rows, keeping the first per (blocker, blocked)."""
    seen = set()
    removed = 0
    for b in db.query(models.BlockedUser).order_by(models.BlockedUser.id.asc()).all():
        key = (str(b.blocker_id), str(b.blocked_id))
        if key in seen:
            db.delete(b)
            removed += 1
        else:
            seen.add(key)
    return removed


def main() -> None:
    Session = sessionmaker(bind=engine)
    db = Session()
    try:
        result = convert_legacy_blocks(db)   # convert + dedupe (commits internally)
        ensure_unique_index(db)               # DB-level uniqueness AFTER dedupe
        db.commit()
        print(f"Gate 1.4B transition complete: {result}; unique index ensured.")
        if result["ambiguous"]:
            print(f"  WARNING: {result['ambiguous']} legacy BLOCKED row(s) had no usable "
                  f"direction (initiated_by NULL/invalid) — left untouched, NOT converted.")
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    main()
