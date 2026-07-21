"""Account deletion foundation tests (Group B).

Covers:
  - the route targets ONLY the authenticated user (no user_id param → can't
    delete anyone else)
  - admin accounts cannot self-delete (403)
  - a normal user can delete self; private/owned data is removed
  - the deleted user row is gone → any old JWT can no longer resolve (401)
  - an unrelated user and their data are untouched
  - shared competitive history (a Match) is preserved and re-pointed at the
    sentinel, so the opponent's leaderboard record is not corrupted
  - exclusively-owned media files are cleaned up
  - calling the service again on an already-deleted user is a safe no-op

Calls the real route/service directly (TestClient is incompatible with the
installed httpx). All rows are prefixed and removed in tearDownClass.

Note: rows are inserted with an explicit created_at because SQLite renders the
ORM `server_default=func.now()` as a literal string default; setting the value
explicitly keeps datetime read-back valid in this offline test DB.

Run from backend/:  ../.venv/bin/python -m unittest tests.test_account_deletion -v
"""
import asyncio
import inspect
import os
import sqlite3
import sys
import unittest
import uuid
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import models
import models_premium as mp
import routers.users as users_router
from account_deletion import SENTINEL_USERNAME, delete_user_account
from database import SessionLocal

_PREFIX = "__validation_delete_"
_DB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sportshub.db")
_UPLOAD_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "uploads", "videos")


def _name():
    return _PREFIX + uuid.uuid4().hex[:8]


def _now():
    return datetime.now(timezone.utc)


def _make_user(db, role=models.UserRole.USER):
    u = models.User(
        email=f"{_name()}@test.com",
        username=_name(),
        password_hash="x",
        display_name="Validation",
        date_of_birth=datetime(2005, 1, 1),
        role=role,
        account_status=models.AccountStatus.ACTIVE,
        age_verified=True,
        email_verified=True,
        created_at=_now(),
    )
    db.add(u)
    db.flush()
    uid = u.id
    db.commit()
    return uid


def _call_delete_by_id(uid):
    """Invoke the real DELETE /users/me route coroutine as the given user."""
    db = SessionLocal()
    try:
        u = db.query(models.User).filter(models.User.id == uid).first()
        return asyncio.get_event_loop().run_until_complete(
            users_router.delete_my_account(current_user=u, db=db)
        )
    finally:
        db.close()


class AccountDeletionTests(unittest.TestCase):
    @classmethod
    def tearDownClass(cls):
        db = sqlite3.connect(_DB)
        rows = db.execute(
            "SELECT id FROM users WHERE username LIKE ? OR username = ?",
            (_PREFIX + "%", SENTINEL_USERNAME),
        ).fetchall()
        ids = [r[0] for r in rows]
        for uid in ids:
            for tbl, col in [
                ("matches", "player1_id"), ("matches", "player2_id"), ("matches", "winner_id"),
                ("challenges", "challenger_id"), ("challenges", "opponent_id"), ("challenges", "winner_id"),
                ("sport_profiles", "user_id"), ("posts", "author_id"), ("comments", "author_id"),
                ("training_sessions", "user_id"), ("subscriptions", "user_id"),
                ("biometric_data", "user_id"), ("coach_conversation_messages", "user_id"),
                ("clips", "author_id"),
            ]:
                try:
                    db.execute(f"DELETE FROM {tbl} WHERE {col}=?", (uid,))
                except sqlite3.OperationalError:
                    pass
            db.execute("DELETE FROM users WHERE id=?", (uid,))
        db.commit()
        db.close()

    # ── targeting / authorization ──────────────────────────────────────────────

    def test_route_has_no_user_id_param(self):
        params = set(inspect.signature(users_router.delete_my_account).parameters)
        self.assertNotIn("user_id", params)
        self.assertEqual(params, {"current_user", "db"})

    def test_admin_cannot_self_delete(self):
        from fastapi import HTTPException
        db = SessionLocal()
        try:
            uid = _make_user(db, role=models.UserRole.ADMIN)
        finally:
            db.close()
        from fastapi import HTTPException as HE
        db = SessionLocal()
        try:
            admin = db.query(models.User).filter(models.User.id == uid).first()
            with self.assertRaises(HE) as ctx:
                asyncio.get_event_loop().run_until_complete(
                    users_router.delete_my_account(current_user=admin, db=db)
                )
            self.assertEqual(ctx.exception.status_code, 403)
        finally:
            db.close()
        db = SessionLocal()
        try:
            self.assertIsNotNone(db.query(models.User).filter(models.User.id == uid).first())
        finally:
            db.close()

    # ── self deletion + private data removal ────────────────────────────────────

    def test_deletes_self_and_private_data(self):
        db = SessionLocal()
        try:
            uid = _make_user(db)
            db.add_all([
                models.SportProfile(user_id=uid, sport=models.Sport.BASKETBALL, created_at=_now()),
                models.Post(author_id=uid, content="hello", sport=models.Sport.BASKETBALL, created_at=_now()),
                models.TrainingSession(user_id=uid, sport=models.Sport.BASKETBALL,
                                       total_duration=30, created_at=_now()),
                mp.Subscription(user_id=uid, tier=mp.SubscriptionTier.PREMIUM,
                                status=mp.SubscriptionStatus.ACTIVE, started_at=_now()),
                mp.BiometricData(user_id=uid, date=_now(), recovery_score=60.0, created_at=_now()),
                models.CoachConversationMessage(user_id=uid, sport=models.Sport.BASKETBALL,
                                                role="user", content="hi coach", created_at=_now()),
            ])
            db.commit()
        finally:
            db.close()

        res = _call_delete_by_id(uid)
        self.assertIn("deleted", res["message"].lower())

        db = SessionLocal()
        try:
            self.assertIsNone(db.query(models.User).filter(models.User.id == uid).first())
            self.assertEqual(db.query(models.SportProfile).filter(models.SportProfile.user_id == uid).count(), 0)
            self.assertEqual(db.query(models.Post).filter(models.Post.author_id == uid).count(), 0)
            self.assertEqual(db.query(models.TrainingSession).filter(models.TrainingSession.user_id == uid).count(), 0)
            self.assertEqual(db.query(mp.Subscription).filter(mp.Subscription.user_id == uid).count(), 0)
            self.assertEqual(db.query(mp.BiometricData).filter(mp.BiometricData.user_id == uid).count(), 0)
            self.assertEqual(db.query(models.CoachConversationMessage)
                             .filter(models.CoachConversationMessage.user_id == uid).count(), 0)
        finally:
            db.close()

    def test_old_token_cannot_resolve_after_delete(self):
        # get_current_user does a DB lookup by id; once the row is gone that
        # lookup returns None and the dependency raises 401. We assert the row.
        db = SessionLocal()
        try:
            uid = _make_user(db)
        finally:
            db.close()
        _call_delete_by_id(uid)
        db = SessionLocal()
        try:
            self.assertIsNone(db.query(models.User).filter(models.User.id == uid).first())
        finally:
            db.close()

    # ── competitive integrity + unrelated users ────────────────────────────────

    def test_competitive_history_preserved_and_unrelated_user_untouched(self):
        db = SessionLocal()
        try:
            a_id = _make_user(db)
            b_id = _make_user(db)
            m = models.Match(
                sport=models.Sport.BASKETBALL, match_type=models.MatchType.RANKED,
                player1_id=a_id, player2_id=b_id, status="completed", winner_id=a_id,
                created_at=_now(),
            )
            db.add(m)
            db.flush()
            match_id = m.id
            db.commit()
        finally:
            db.close()

        _call_delete_by_id(a_id)

        db = SessionLocal()
        try:
            self.assertIsNotNone(db.query(models.User).filter(models.User.id == b_id).first())
            match = db.query(models.Match).filter(models.Match.id == match_id).first()
            self.assertIsNotNone(match, "opponent's match history must not be destroyed")
            sentinel = db.query(models.User).filter(models.User.username == SENTINEL_USERNAME).first()
            self.assertIsNotNone(sentinel)
            self.assertEqual(match.player1_id, sentinel.id)     # A → sentinel
            self.assertEqual(match.player2_id, b_id)            # B untouched
            self.assertEqual(match.winner_id, sentinel.id)      # winner detached, not nulled
            self.assertEqual(sentinel.account_status, models.AccountStatus.BANNED)
            self.assertEqual(db.query(models.SportProfile)
                             .filter(models.SportProfile.user_id == sentinel.id).count(), 0)
        finally:
            db.close()

    # ── media cleanup ───────────────────────────────────────────────────────────

    def test_owned_media_file_cleaned_up(self):
        os.makedirs(_UPLOAD_DIR, exist_ok=True)
        fname = f"{_name()}.mov"
        fpath = os.path.join(_UPLOAD_DIR, fname)
        with open(fpath, "wb") as f:
            f.write(b"\x00\x01validation clip")
        self.assertTrue(os.path.isfile(fpath))

        db = SessionLocal()
        try:
            uid = _make_user(db)
            db.add(models.Clip(author_id=uid, sport=models.Sport.BASKETBALL,
                               title="v", video_url=f"/cdn/videos/{fname}", created_at=_now()))
            db.commit()
        finally:
            db.close()

        _call_delete_by_id(uid)
        self.assertFalse(os.path.isfile(fpath), "exclusively-owned clip file should be removed")

    # ── idempotency / re-entrancy ────────────────────────────────────────────────

    def test_second_delete_is_safe_noop(self):
        db = SessionLocal()
        try:
            uid = _make_user(db)
        finally:
            db.close()
        _call_delete_by_id(uid)
        db = SessionLocal()
        try:
            ghost = models.User(id=uid, email="x@x.com", username="ghost",
                                password_hash="x", date_of_birth=datetime(2005, 1, 1),
                                role=models.UserRole.USER)
            delete_user_account(db, ghost)  # must not raise
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
