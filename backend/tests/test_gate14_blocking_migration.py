"""Gate 1.4B — legacy Friendship.BLOCKED -> canonical BlockedUser transition evidence.

Disposable temp DBs. Proves: direction from initiated_by; ambiguous rows NOT guessed;
dedupe; rerun safety (idempotent); rollback on failure; unrelated data preserved.

Run from backend/:  ../.venv/bin/python -m unittest tests.test_gate14_blocking_migration -v
"""
import os
import sys
import tempfile
import unittest
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from database import Base
import models
import models_premium  # noqa: F401
from migrate_gate14_blocking import (convert_legacy_blocks, _dedupe_blocked,
                                      ensure_unique_index, UNIQUE_INDEX_NAME)
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
import uuid as _uuid

ADULT = datetime(2000, 1, 1)


def _blocked(user_a, user_b, initiated_by):
    """A legacy Friendship.BLOCKED row exactly as the frozen block route wrote it:
    friends.py@5f7f329:296-297 sets `initiated_by = current_user.id  # Track who blocked`,
    so initiated_by is ALWAYS the blocker (overwriting any original requester)."""
    return models.Friendship(user_a_id=user_a.id, user_b_id=user_b.id,
                             status=models.FriendshipStatus.BLOCKED, initiated_by=initiated_by.id)


def _session():
    fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
    eng = create_engine(f"sqlite:///{path}", connect_args={"check_same_thread": False})
    Base.metadata.create_all(eng)
    return sessionmaker(bind=eng)(), eng, path


def _u(db, n):
    u = models.User(email=f"{n}@x.com", username=n, password_hash="x",
                    display_name=n, date_of_birth=ADULT)
    db.add(u); db.flush(); return u


class Gate14MigrationTests(unittest.TestCase):
    def setUp(self):
        self.db, self.eng, self.path = _session()
        self.a = _u(self.db, "a"); self.b = _u(self.db, "b"); self.c = _u(self.db, "c")
        self.db.commit()

    def tearDown(self):
        self.db.close(); self.eng.dispose(); os.remove(self.path)

    def test_directional_conversion_and_enforcement(self):
        # a blocked b (initiated_by = a)
        self.db.add(models.Friendship(user_a_id=self.a.id, user_b_id=self.b.id,
                    status=models.FriendshipStatus.BLOCKED, initiated_by=self.a.id))
        self.db.commit()
        res = convert_legacy_blocks(self.db); self.db.commit()
        self.assertEqual(res["converted"], 1)
        self.assertEqual(res["ambiguous"], 0)
        blk = self.db.query(models.BlockedUser).one()
        self.assertEqual(blk.blocker_id, self.a.id)      # direction preserved
        self.assertEqual(blk.blocked_id, self.b.id)
        self.assertEqual(self.db.query(models.Friendship).count(), 0)  # legacy row removed

    def test_ambiguous_row_not_guessed(self):
        # Friendship.initiated_by is NOT NULL, so the reachable ambiguity is initiated_by
        # pointing at a NON-participant (data corruption). Direction is unknowable -> the
        # migration must NOT guess: leave the row in place and count it ambiguous.
        self.db.add(models.Friendship(user_a_id=self.a.id, user_b_id=self.b.id,
                    status=models.FriendshipStatus.BLOCKED, initiated_by=self.c.id))
        self.db.commit()
        res = convert_legacy_blocks(self.db); self.db.commit()
        self.assertEqual(res["converted"], 0)
        self.assertEqual(res["ambiguous"], 1)
        self.assertEqual(self.db.query(models.BlockedUser).count(), 0)   # no guess
        self.assertEqual(self.db.query(models.Friendship).count(), 1)    # left in place

    def test_dedupe_directed_blocks(self):
        # Simulate a LEGACY pre-constraint table (fresh DBs have uq_blocked_directed, which
        # would reject duplicates) by rebuilding blocked_users without the UNIQUE constraint.
        import uuid as _uuid
        from sqlalchemy import text
        self.db.execute(text("DROP TABLE blocked_users"))
        self.db.execute(text(
            "CREATE TABLE blocked_users (id VARCHAR(36) PRIMARY KEY, "
            "blocker_id VARCHAR(36) NOT NULL, blocked_id VARCHAR(36) NOT NULL, "
            "created_at DATETIME)"))
        for _ in range(3):   # three identical directed rows
            self.db.execute(text(
                "INSERT INTO blocked_users (id, blocker_id, blocked_id) VALUES (:i,:a,:b)"),
                {"i": str(_uuid.uuid4()), "a": str(self.a.id), "b": str(self.b.id)})
        self.db.commit()
        removed = _dedupe_blocked(self.db); self.db.commit()
        self.assertEqual(removed, 2)
        self.assertEqual(self.db.query(models.BlockedUser).filter_by(
            blocker_id=self.a.id, blocked_id=self.b.id).count(), 1)

    def test_rerun_is_idempotent(self):
        self.db.add(models.Friendship(user_a_id=self.a.id, user_b_id=self.b.id,
                    status=models.FriendshipStatus.BLOCKED, initiated_by=self.a.id))
        self.db.commit()
        convert_legacy_blocks(self.db); self.db.commit()
        res2 = convert_legacy_blocks(self.db); self.db.commit()   # second run
        self.assertEqual(res2["converted"], 0)
        self.assertEqual(self.db.query(models.BlockedUser).count(), 1)

    def test_rollback_leaves_no_partial(self):
        self.db.add(models.Friendship(user_a_id=self.a.id, user_b_id=self.b.id,
                    status=models.FriendshipStatus.BLOCKED, initiated_by=self.a.id))
        self.db.commit()
        try:
            convert_legacy_blocks(self.db)
            raise RuntimeError("boom before commit")
        except RuntimeError:
            self.db.rollback()
        # rolled back: legacy row still present, no BlockedUser persisted
        self.assertEqual(self.db.query(models.BlockedUser).count(), 0)
        self.assertEqual(self.db.query(models.Friendship).filter_by(
            status=models.FriendshipStatus.BLOCKED).count(), 1)

    # ── ownership proof: initiated_by == blocker in every legacy scenario ─────
    def test_ownership_requester_blocks_recipient(self):
        # a requested, then a blocks b -> frozen route overwrote initiated_by=a (blocker).
        self.db.add(_blocked(self.a, self.b, self.a)); self.db.commit()
        convert_legacy_blocks(self.db); self.db.commit()
        blk = self.db.query(models.BlockedUser).one()
        self.assertEqual((blk.blocker_id, blk.blocked_id), (self.a.id, self.b.id))

    def test_ownership_recipient_blocks_requester(self):
        # a requested (user_a=a), but b (recipient) blocked a -> frozen route OVERWROTE
        # initiated_by=b. Migration must credit b as blocker, NOT the original requester a.
        self.db.add(_blocked(self.a, self.b, self.b)); self.db.commit()
        convert_legacy_blocks(self.db); self.db.commit()
        blk = self.db.query(models.BlockedUser).one()
        self.assertEqual((blk.blocker_id, blk.blocked_id), (self.b.id, self.a.id))

    def test_ownership_block_after_accepted(self):
        # accepted friendship then a blocks b -> initiated_by overwritten to a.
        self.db.add(_blocked(self.a, self.b, self.a)); self.db.commit()
        convert_legacy_blocks(self.db); self.db.commit()
        blk = self.db.query(models.BlockedUser).one()
        self.assertEqual(blk.blocker_id, self.a.id)

    # ── existing-DB uniqueness (UNIQUE INDEX) ────────────────────────────────
    def _legacy_blocked_table(self):
        """Rebuild blocked_users WITHOUT the model constraint to represent a frozen-parent DB."""
        self.db.execute(text("DROP TABLE blocked_users"))
        self.db.execute(text(
            "CREATE TABLE blocked_users (id VARCHAR(36) PRIMARY KEY, "
            "blocker_id VARCHAR(36) NOT NULL, blocked_id VARCHAR(36) NOT NULL, "
            "created_at DATETIME)"))
        self.db.commit()

    def _raw_block(self, a, b):
        self.db.execute(text(
            "INSERT INTO blocked_users (id, blocker_id, blocked_id) VALUES (:i,:a,:b)"),
            {"i": str(_uuid.uuid4()), "a": str(a.id), "b": str(b.id)})

    def test_unique_index_rejects_duplicate_after_upgrade(self):
        self._legacy_blocked_table()
        self._raw_block(self.a, self.b); self.db.commit()
        ensure_unique_index(self.db)                    # dedupe not needed (no dups yet)
        with self.assertRaises(IntegrityError):         # DB now rejects a duplicate directed row
            self._raw_block(self.a, self.b); self.db.commit()
        self.db.rollback()

    def test_upgrade_dedupes_then_indexes(self):
        self._legacy_blocked_table()
        for _ in range(3):
            self._raw_block(self.a, self.b)             # legacy duplicates
        self.db.commit()
        removed = _dedupe_blocked(self.db); self.db.commit()
        self.assertEqual(removed, 2)
        ensure_unique_index(self.db)                    # succeeds only because deduped first
        idx = self.db.execute(text(
            "SELECT name FROM sqlite_master WHERE type='index' AND name=:n"),
            {"n": UNIQUE_INDEX_NAME}).first()
        self.assertIsNotNone(idx)

    def test_ensure_unique_index_is_idempotent(self):
        self._legacy_blocked_table()
        ensure_unique_index(self.db)
        ensure_unique_index(self.db)                    # IF NOT EXISTS -> safe re-run
        self.assertEqual(self.db.query(models.BlockedUser).count(), 0)

    def test_unrelated_data_preserved(self):
        # an accepted friendship between a and c must survive the transition untouched
        self.db.add(models.Friendship(user_a_id=self.a.id, user_b_id=self.c.id,
                    status=models.FriendshipStatus.ACCEPTED, initiated_by=self.a.id))
        self.db.add(models.Friendship(user_a_id=self.a.id, user_b_id=self.b.id,
                    status=models.FriendshipStatus.BLOCKED, initiated_by=self.a.id))
        self.db.commit()
        convert_legacy_blocks(self.db); self.db.commit()
        self.assertEqual(self.db.query(models.Friendship).filter_by(
            status=models.FriendshipStatus.ACCEPTED).count(), 1)
        self.assertEqual(self.db.query(models.User).count(), 3)


if __name__ == "__main__":
    unittest.main()
