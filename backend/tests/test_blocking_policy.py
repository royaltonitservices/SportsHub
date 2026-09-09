"""Gate 1.4B — canonical block + direct-contact enforcement.

Drives the REAL router coroutines on disposable temp DBs (create_all). Every changed
security boundary has an allow case and a deny/bypass case. Observed = TESTED here.
SQLite serializes writers, so the "competing operations" test proves the guarded outcome,
not true parallel row-locking (Postgres proof = Gate 2.1A).

Run from backend/:  ../.venv/bin/python -m unittest tests.test_blocking_policy -v
"""
import asyncio
import os
import sys
import tempfile
import unittest
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from database import Base
import models
import models_premium  # noqa: F401
import schemas
import blocking_policy
from routers import friends as friends_r
from routers import messages as messages_r
from routers import users as users_r
from routers import blocking as blocking_r
from routers import moderation as moderation_r

ADULT = datetime(2000, 1, 1)


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def _engine():
    fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
    eng = create_engine(f"sqlite:///{path}", connect_args={"check_same_thread": False})
    with eng.connect() as c:
        c.exec_driver_sql("PRAGMA journal_mode=WAL")
    Base.metadata.create_all(eng)
    return eng, path


def _mk_user(db, name):
    u = models.User(email=f"{name}@x.com", username=name, password_hash="x",
                    display_name=name.title(), date_of_birth=ADULT)
    db.add(u); db.flush()
    return u


def _friend(db, a, b):
    db.add(models.Friendship(user_a_id=a.id, user_b_id=b.id,
                             status=models.FriendshipStatus.ACCEPTED, initiated_by=a.id))
    db.commit()


class BlockingPolicyTests(unittest.TestCase):
    def setUp(self):
        self.eng, self.path = _engine()
        self.S = sessionmaker(bind=self.eng)
        self.db = self.S()
        self.a = _mk_user(self.db, "alice")
        self.b = _mk_user(self.db, "bob")
        self.db.commit()

    def tearDown(self):
        self.db.close(); self.eng.dispose(); os.remove(self.path)

    # ── allow: unblocked friends can DM ──────────────────────────────────────
    def test_unblocked_friends_can_message(self):
        _friend(self.db, self.a, self.b)
        msg = _run(messages_r.send_message(
            schemas.MessageCreate(receiver_id=self.b.id, content="hi"), self.a, self.db))
        self.assertEqual(msg.receiver_id, self.b.id)

    # ── either-direction block denies contact ────────────────────────────────
    def test_block_denies_dm_both_directions(self):
        _friend(self.db, self.a, self.b)
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)   # A blocks B
        for sender, receiver in ((self.a, self.b), (self.b, self.a)):
            with self.assertRaises(HTTPException) as c:
                _run(messages_r.send_message(
                    schemas.MessageCreate(receiver_id=receiver.id, content="x"), sender, self.db))
            self.assertEqual(c.exception.status_code, 403)

    def test_block_denies_new_friend_request_both_directions(self):
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        for me, them in ((self.a, self.b), (self.b, self.a)):
            with self.assertRaises(HTTPException) as c:
                _run(friends_r.send_friend_request(
                    schemas.FriendRequest(target_user_id=them.id), me, self.db))
            self.assertEqual(c.exception.status_code, 403)

    def test_block_hides_profile_both_directions_404(self):
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        with self.assertRaises(HTTPException) as c1:
            _run(users_r.get_user_by_id(self.b.id, self.db, self.a))
        self.assertEqual(c1.exception.status_code, 404)          # non-disclosing
        with self.assertRaises(HTTPException) as c2:
            _run(users_r.get_user_by_id(self.a.id, self.db, self.b))
        self.assertEqual(c2.exception.status_code, 404)

    # ── block ends friendship + cancels pending; stale acceptance denied ──────
    def test_block_ends_friendship_and_cancels_pending(self):
        # pending request A->B, then A blocks B
        _run(friends_r.send_friend_request(schemas.FriendRequest(target_user_id=self.b.id),
                                           self.a, self.db))
        pending_id = self.db.query(models.Friendship).first().id   # capture BEFORE severing
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        # pending row severed
        self.assertEqual(self.db.query(models.Friendship).count(), 0)
        # stale acceptance by B now fails (request gone -> 404)
        with self.assertRaises(HTTPException) as c:
            _run(friends_r.accept_friend_request(pending_id, self.b, self.db))
        self.assertEqual(c.exception.status_code, 404)

    def test_stale_acceptance_denied_when_block_added_but_row_present(self):
        # Craft a pending row AND a block coexisting (defensive path): accept must 403.
        pending = models.Friendship(user_a_id=self.b.id, user_b_id=self.a.id,
                                    status=models.FriendshipStatus.PENDING, initiated_by=self.b.id)
        self.db.add(pending); self.db.commit()
        self.db.add(models.BlockedUser(blocker_id=self.a.id, blocked_id=self.b.id)); self.db.commit()
        with self.assertRaises(HTTPException) as c:
            _run(friends_r.accept_friend_request(pending.id, self.a, self.db))
        self.assertEqual(c.exception.status_code, 403)

    # ── existing-conversation send bypass + history retention ────────────────
    def test_block_denies_existing_conversation_but_retains_history(self):
        _friend(self.db, self.a, self.b)
        _run(messages_r.send_message(schemas.MessageCreate(receiver_id=self.b.id, content="hello"),
                                     self.a, self.db))
        before = self.db.query(models.Message).count()
        self.assertEqual(before, 1)
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        # live conversation now denied both ways
        with self.assertRaises(HTTPException) as c:
            _run(messages_r.get_conversation(self.b.id, self.a, self.db))
        self.assertEqual(c.exception.status_code, 403)
        # history rows RETAINED (moderation/evidence)
        self.assertEqual(self.db.query(models.Message).count(), before)

    # ── unblock semantics ────────────────────────────────────────────────────
    def test_unblock_removes_only_callers_directed_block(self):
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)   # A blocks B
        blocking_policy.apply_block(self.db, self.b.id, self.a.id)   # B blocks A (reciprocal)
        self.assertTrue(blocking_policy.remove_block(self.db, self.a.id, self.b.id))  # A unblocks
        # reverse block still enforces -> still blocked bidirectionally
        self.assertTrue(blocking_policy.is_blocked(self.db, self.a.id, self.b.id))
        with self.assertRaises(HTTPException):
            _run(messages_r.send_message(
                schemas.MessageCreate(receiver_id=self.b.id, content="x"), self.a, self.db))

    def test_unblock_does_not_restore_friendship(self):
        _friend(self.db, self.a, self.b)
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        blocking_policy.remove_block(self.db, self.a.id, self.b.id)
        self.assertEqual(self.db.query(models.Friendship).count(), 0)   # not restored
        # DM still requires accepted friendship (now absent) -> 403
        with self.assertRaises(HTTPException) as c:
            _run(messages_r.send_message(
                schemas.MessageCreate(receiver_id=self.b.id, content="x"), self.a, self.db))
        self.assertEqual(c.exception.status_code, 403)

    def test_unauthorized_unblock_is_noop(self):
        c = _mk_user(self.db, "carol"); self.db.commit()
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)     # A blocks B
        # carol cannot remove A's directed block of B
        self.assertFalse(blocking_policy.remove_block(self.db, c.id, self.b.id))
        self.assertTrue(blocking_policy.is_blocked(self.db, self.a.id, self.b.id))

    # ── idempotency ──────────────────────────────────────────────────────────
    def test_repeated_block_unblock_idempotent(self):
        b1 = blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        b2 = blocking_policy.apply_block(self.db, self.a.id, self.b.id)   # no duplicate
        self.assertEqual(b1.id, b2.id)
        self.assertEqual(self.db.query(models.BlockedUser).filter_by(
            blocker_id=self.a.id, blocked_id=self.b.id).count(), 1)
        self.assertTrue(blocking_policy.remove_block(self.db, self.a.id, self.b.id))
        self.assertFalse(blocking_policy.remove_block(self.db, self.a.id, self.b.id))  # second no-op

    # ── reporting works despite profile hiding ───────────────────────────────
    def test_can_report_blocked_user_though_profile_hidden(self):
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        # profile hidden
        with self.assertRaises(HTTPException):
            _run(users_r.get_user_by_id(self.b.id, self.db, self.a))
        # but reporting the abusive account still succeeds (does not go through profile route)
        resp = _run(moderation_r.report_content("user", self.b.id, "harassment", self.a, self.db))
        self.assertTrue(self.db.query(models.ModerationFlag).filter_by(
            reporter_id=self.a.id, content_id=self.b.id).count() >= 1)

    # ── competing operations, independent sessions ───────────────────────────
    def test_competing_block_vs_message_block_wins(self):
        _friend(self.db, self.a, self.b)
        s1, s2 = self.S(), self.S()
        try:
            blocking_policy.apply_block(s1, self.a.id, self.b.id)   # session 1 blocks (commits)
            # session 2 (independent) now attempts a DM B->A; block must win
            with self.assertRaises(HTTPException) as c:
                _run(messages_r.send_message(
                    schemas.MessageCreate(receiver_id=self.a.id, content="x"), self.b, s2))
            self.assertEqual(c.exception.status_code, 403)
        finally:
            s1.close(); s2.close()

    # ── legacy /friends block routes now canonical + wire-compatible ─────────
    def test_friends_block_route_is_canonical_and_wire_compatible(self):
        result = _run(friends_r.block_user(self.b.id, self.a, self.db))
        # Validates against the legacy response_model -> proves API compatibility.
        fr = schemas.FriendshipResponse.model_validate(result)
        self.assertEqual(fr.status, models.FriendshipStatus.BLOCKED)
        self.assertEqual(fr.user_a_id, self.a.id)
        self.assertEqual(fr.user_b_id, self.b.id)
        # Writes the CANONICAL store (not the dead Friendship.BLOCKED status).
        self.assertEqual(self.db.query(models.BlockedUser).filter_by(
            blocker_id=self.a.id, blocked_id=self.b.id).count(), 1)
        self.assertEqual(self.db.query(models.Friendship).filter_by(
            status=models.FriendshipStatus.BLOCKED).count(), 0)
        # Appears in the blocked list, same shape.
        blocked = _run(friends_r.get_blocked_users(self.a, self.db))
        self.assertEqual(len(blocked), 1)
        schemas.FriendshipResponse.model_validate(blocked[0])
        # Unblock removes it.
        _run(friends_r.unblock_user(self.b.id, self.a, self.db))
        self.assertEqual(len(_run(friends_r.get_blocked_users(self.a, self.db))), 0)

    def test_username_lookup_hidden_when_blocked_404(self):
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        with self.assertRaises(HTTPException) as c:
            _run(users_r.get_user_by_username(self.b.username, self.db, self.a))
        self.assertEqual(c.exception.status_code, 404)

    def test_search_by_username_hidden_when_blocked_404(self):
        from routers import search as search_r
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        with self.assertRaises(HTTPException) as c:
            _run(search_r.search_user_by_username(self.b.username, self.a, self.db))
        self.assertEqual(c.exception.status_code, 404)   # non-disclosing, was 403 "not accessible"

    # ── /blocking/* routes also canonical ────────────────────────────────────
    def test_blocking_router_canonical_block_unblock(self):
        _friend(self.db, self.a, self.b)
        _run(blocking_r.block_user(schemas.BlockUser(blocked_user_id=self.b.id), self.a, self.db))
        self.assertEqual(self.db.query(models.BlockedUser).filter_by(
            blocker_id=self.a.id, blocked_id=self.b.id).count(), 1)
        self.assertEqual(self.db.query(models.Friendship).count(), 0)   # friendship severed
        listed = _run(blocking_r.get_blocked_users(self.a, self.db))
        self.assertEqual(len(listed), 1)
        _run(blocking_r.unblock_user(self.b.id, self.a, self.db))
        self.assertEqual(self.db.query(models.BlockedUser).count(), 0)
        with self.assertRaises(HTTPException) as c:                     # unblock again -> 404
            _run(blocking_r.unblock_user(self.b.id, self.a, self.db))
        self.assertEqual(c.exception.status_code, 404)

    def test_blocking_router_self_and_missing_guards(self):
        import uuid as _uuid
        with self.assertRaises(HTTPException) as c1:
            _run(blocking_r.block_user(schemas.BlockUser(blocked_user_id=self.a.id), self.a, self.db))
        self.assertEqual(c1.exception.status_code, 400)                 # self-block
        with self.assertRaises(HTTPException) as c2:
            _run(blocking_r.block_user(schemas.BlockUser(blocked_user_id=_uuid.uuid4()), self.a, self.db))
        self.assertEqual(c2.exception.status_code, 404)                 # unknown target

    # ── concurrency precision ────────────────────────────────────────────────
    def test_send_after_block_commit_is_denied(self):
        # Ordering: the block transaction COMMITS, then a DM is attempted -> the DM's
        # block-check reads the committed block and is denied (403).
        _friend(self.db, self.a, self.b)
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        self.db.commit()
        with self.assertRaises(HTTPException) as c:
            _run(messages_r.send_message(
                schemas.MessageCreate(receiver_id=self.a.id, content="x"), self.b, self.db))
        self.assertEqual(c.exception.status_code, 403)

    def test_message_committed_before_block_is_retained(self):
        # Permitted outcome: a DM committed BEFORE the block is NOT retroactively removed —
        # block is prospective. The pre-block row persists (and remains for moderation).
        _friend(self.db, self.a, self.b)
        msg = _run(messages_r.send_message(
            schemas.MessageCreate(receiver_id=self.b.id, content="pre"), self.a, self.db))
        mid = msg.id
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        self.assertIsNotNone(self.db.query(models.Message).filter_by(id=mid).first())

    def test_concurrent_duplicate_block_idempotent_no_error(self):
        # A racing request that read "no block" before the winner committed attempts a
        # duplicate INSERT; the UNIQUE constraint rejects it and apply_block recovers with
        # NO server error and NO lost enforcement (exactly one directed row).
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)          # winner
        real = blocking_policy.directed_block
        calls = {"n": 0}
        def _flaky(db, a, b):
            calls["n"] += 1
            return None if calls["n"] == 1 else real(db, a, b)              # stale read once
        blocking_policy.directed_block = _flaky
        try:
            result = blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        finally:
            blocking_policy.directed_block = real
        self.assertIsNotNone(result)
        self.assertEqual(self.db.query(models.BlockedUser).filter_by(
            blocker_id=self.a.id, blocked_id=self.b.id).count(), 1)
        self.assertTrue(blocking_policy.is_blocked(self.db, self.a.id, self.b.id))  # enforcement intact

    def test_block_status_reports_bidirectional_without_direction_leak_via_error(self):
        blocking_policy.apply_block(self.db, self.b.id, self.a.id)   # B blocks A
        st = _run(friends_r.get_friend_status(self.b.id, self.a, self.db))
        self.assertTrue(st.is_blocked)
        self.assertFalse(st.initiated_by_me)   # A did not initiate; but no error leaks direction


if __name__ == "__main__":
    unittest.main()
