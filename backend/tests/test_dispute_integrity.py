"""Pre-deploy — dispute result integrity.

Enforces the invariants that dispute resolution must never violate. Drives the real
route/service functions against the SQLite DB (matching the other regression suites;
starlette TestClient is incompatible with the installed httpx).

Covered:
  - REVERSE of a score-mismatch dispute (nothing was ever applied) must NOT crash,
    must NOT create negative W/L, must NOT null the rating  [reproduces the fixed bug]
  - UPHOLD of a mismatch dispute fabricates no winner/Match
  - REVERSE of an applied ranked result undoes W/L + restores exact pre-match ELO +
    deletes the canonical Match (Challenge and Match agree afterwards)
  - REVERSE of an applied UNRANKED result undoes W/L, no rating change
  - repeated resolution is rejected (idempotent at the dispute level)
  - UPHOLD of an applied result keeps exactly one Match
  - all four sports share the same path

Rows are prefixed __validation_ and removed in tearDownClass.
Run from backend/:  ../.venv/bin/python -m unittest tests.test_dispute_integrity -v
"""
import asyncio
import os
import sqlite3
import sys
import unittest
import uuid
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import models
import schemas
import routers.matchmaking as mm
import routers.disputes as dsp
from database import SessionLocal

_PREFIX = "__validation_dispint_"
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DB = os.path.join(_ROOT, "sportshub.db")


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def _mk_user(db, admin=False):
    u = models.User(
        email=f"{_PREFIX}{uuid.uuid4().hex[:8]}@t.com",
        username=_PREFIX + uuid.uuid4().hex[:6],
        password_hash="x", display_name="DI", date_of_birth=datetime(2005, 1, 1),
        role=models.UserRole.ADMIN if admin else models.UserRole.USER,
        account_status=models.AccountStatus.ACTIVE, age_verified=True,
        email_verified=True, created_at=datetime.utcnow(),
    )
    db.add(u); db.flush(); return u


def _mk_profile(db, uid, sport):
    p = models.SportProfile(user_id=uid, sport=sport, rating=1500,
                            is_provisional=True, provisional_games=0)
    db.add(p); db.flush(); return p


def _accepted(db, sport, a, b, mt):
    c = models.Challenge(sport=sport, match_type=mt, challenger_id=a, opponent_id=b,
                         status=models.ChallengeStatus.ACCEPTED)
    db.add(c); db.flush(); return c


def _submit(db, cid, user, winner, score):
    return _run(mm.submit_match_result(
        result=schemas.SubmitMatchResult(challenge_id=cid, winner_id=winner, score_data=score),
        current_user=user, db=db))


class DisputeIntegrityTests(unittest.TestCase):

    @classmethod
    def tearDownClass(cls):
        db = sqlite3.connect(_DB)
        for uid, in db.execute("SELECT id FROM users WHERE username LIKE ?", (_PREFIX + "%",)).fetchall():
            db.execute("DELETE FROM matches WHERE player1_id=? OR player2_id=?", (uid, uid))
            db.execute("DELETE FROM disputes WHERE initiator_id=?", (uid,))
            db.execute("DELETE FROM challenges WHERE challenger_id=? OR opponent_id=?", (uid, uid))
            db.execute("DELETE FROM sport_profiles WHERE user_id=?", (uid,))
            db.execute("DELETE FROM users WHERE id=?", (uid,))
        db.commit(); db.close()

    # ── helpers ───────────────────────────────────────────────────────────────
    def _mismatch_dispute(self, db, sport, mt=models.MatchType.RANKED):
        a = _mk_user(db); b = _mk_user(db); admin = _mk_user(db, admin=True)
        ca = _mk_profile(db, a.id, sport); cb = _mk_profile(db, b.id, sport)
        c = _accepted(db, sport, a.id, b.id, mt)
        db.commit()
        _submit(db, c.id, a, a.id, "21-15")
        _submit(db, c.id, b, b.id, "10-21")  # mismatch -> DISPUTED, nothing applied
        disp = db.query(models.Dispute).filter(models.Dispute.challenge_id == c.id).first()
        return a, b, admin, ca, cb, c, disp

    def _applied_then_disputed(self, db, sport, mt=models.MatchType.RANKED):
        a = _mk_user(db); b = _mk_user(db); admin = _mk_user(db, admin=True)
        ca = _mk_profile(db, a.id, sport); cb = _mk_profile(db, b.id, sport)
        c = _accepted(db, sport, a.id, b.id, mt)
        db.commit()
        _submit(db, c.id, a, a.id, "21-15")
        _submit(db, c.id, b, a.id, "21-15")  # match -> COMPLETED, applied, Match created
        # dispute the completed result
        _run(dsp.create_dispute(
            dispute_data=schemas.DisputeCreate(challenge_id=c.id, reason=_PREFIX + "r", evidence=None),
            current_user=b, db=db))
        disp = db.query(models.Dispute).filter(models.Dispute.challenge_id == c.id).first()
        return a, b, admin, ca, cb, c, disp

    # ── mismatch-origin dispute: nothing applied ────────────────────────────────
    def test_reverse_mismatch_no_crash_no_negative_no_null_rating(self):
        db = SessionLocal()
        try:
            a, b, admin, ca, cb, c, disp = self._mismatch_dispute(db, models.Sport.BASKETBALL)
            self.assertEqual(db.query(models.Match).filter(models.Match.challenge_id == c.id).count(), 0)
            # Must not raise (previously TypeError on None rating).
            _run(dsp.resolve_dispute(dispute_id=disp.id, resolution="reverse",
                                     admin_notes="x", current_user=admin, db=db))
            db.refresh(ca); db.refresh(cb); db.refresh(c)
            self.assertEqual((ca.wins, ca.losses, ca.games_played), (0, 0, 0))
            self.assertEqual((cb.wins, cb.losses, cb.games_played), (0, 0, 0))
            self.assertEqual(ca.rating, 1500)      # not None
            self.assertEqual(cb.rating, 1500)
            self.assertGreaterEqual(ca.wins, 0); self.assertGreaterEqual(ca.losses, 0)
            self.assertIsNone(c.winner_id)
            self.assertEqual(c.status, models.ChallengeStatus.COMPLETED)
            self.assertEqual(db.query(models.Match).filter(models.Match.challenge_id == c.id).count(), 0)
        finally:
            db.close()

    def test_uphold_mismatch_creates_no_result(self):
        db = SessionLocal()
        try:
            a, b, admin, ca, cb, c, disp = self._mismatch_dispute(db, models.Sport.SOCCER)
            _run(dsp.resolve_dispute(dispute_id=disp.id, resolution="uphold",
                                     admin_notes="x", current_user=admin, db=db))
            db.refresh(ca); db.refresh(cb); db.refresh(c)
            self.assertEqual((ca.wins, ca.losses), (0, 0))
            self.assertEqual((cb.wins, cb.losses), (0, 0))
            self.assertEqual(db.query(models.Match).filter(models.Match.challenge_id == c.id).count(), 0)
            self.assertEqual(c.status, models.ChallengeStatus.COMPLETED)
        finally:
            db.close()

    # ── applied ranked result: reverse must be exact ────────────────────────────
    def _assert_applied_reverse(self, sport):
        db = SessionLocal()
        try:
            a, b, admin, ca, cb, c, disp = self._applied_then_disputed(db, sport)
            db.refresh(ca); db.refresh(cb)
            # Applied: winner has a win, ratings moved off 1500, one Match exists.
            self.assertEqual(ca.wins, 1); self.assertEqual(cb.losses, 1)
            self.assertNotEqual(ca.rating, 1500)
            self.assertEqual(db.query(models.Match).filter(models.Match.challenge_id == c.id).count(), 1)
            _run(dsp.resolve_dispute(dispute_id=disp.id, resolution="reverse",
                                     admin_notes="x", current_user=admin, db=db))
            db.refresh(ca); db.refresh(cb); db.refresh(c)
            self.assertEqual((ca.wins, ca.losses, ca.games_played), (0, 0, 0), f"{sport.value}")
            self.assertEqual((cb.wins, cb.losses, cb.games_played), (0, 0, 0), f"{sport.value}")
            self.assertEqual(ca.rating, 1500, "exact ELO restore from Match before-value")
            self.assertEqual(cb.rating, 1500)
            self.assertEqual(ca.ranked_games_played, 0)
            self.assertTrue(ca.is_provisional)
            self.assertIsNone(c.winner_id)
            self.assertEqual(db.query(models.Match).filter(models.Match.challenge_id == c.id).count(), 0,
                             "Match deleted so Challenge and Match agree")
        finally:
            db.close()

    def test_reverse_applied_basketball(self):
        self._assert_applied_reverse(models.Sport.BASKETBALL)

    def test_reverse_applied_football(self):
        self._assert_applied_reverse(models.Sport.FOOTBALL)

    def test_reverse_applied_soccer(self):
        self._assert_applied_reverse(models.Sport.SOCCER)

    def test_reverse_applied_tennis(self):
        self._assert_applied_reverse(models.Sport.TENNIS)

    # ── applied UNRANKED result: W/L reversed, no rating change ─────────────────
    def test_reverse_applied_unranked(self):
        db = SessionLocal()
        try:
            a, b, admin, ca, cb, c, disp = self._applied_then_disputed(
                db, models.Sport.TENNIS, mt=models.MatchType.UNRANKED)
            db.refresh(ca); db.refresh(cb)
            self.assertEqual(ca.wins, 1)
            self.assertEqual(ca.rating, 1500)  # unranked never changes rating
            _run(dsp.resolve_dispute(dispute_id=disp.id, resolution="reverse",
                                     admin_notes="x", current_user=admin, db=db))
            db.refresh(ca); db.refresh(cb)
            self.assertEqual((ca.wins, ca.losses), (0, 0))
            self.assertEqual(ca.rating, 1500)
            self.assertEqual(db.query(models.Match).filter(models.Match.challenge_id == c.id).count(), 0)
        finally:
            db.close()

    # ── repeated resolution rejected (idempotent at dispute level) ──────────────
    def test_repeated_resolution_rejected(self):
        from fastapi import HTTPException
        db = SessionLocal()
        try:
            a, b, admin, ca, cb, c, disp = self._applied_then_disputed(db, models.Sport.BASKETBALL)
            _run(dsp.resolve_dispute(dispute_id=disp.id, resolution="reverse",
                                     admin_notes="x", current_user=admin, db=db))
            db.refresh(ca)
            wins_after = ca.wins
            with self.assertRaises(HTTPException) as ctx:
                _run(dsp.resolve_dispute(dispute_id=disp.id, resolution="reverse",
                                         admin_notes="x", current_user=admin, db=db))
            self.assertEqual(ctx.exception.status_code, 400)
            db.refresh(ca)
            self.assertEqual(ca.wins, wins_after, "second resolve must not mutate stats again")
        finally:
            db.close()

    # ── uphold applied result keeps exactly one Match ──────────────────────────
    def test_uphold_applied_keeps_match(self):
        db = SessionLocal()
        try:
            a, b, admin, ca, cb, c, disp = self._applied_then_disputed(db, models.Sport.FOOTBALL)
            _run(dsp.resolve_dispute(dispute_id=disp.id, resolution="uphold",
                                     admin_notes="x", current_user=admin, db=db))
            db.refresh(ca); db.refresh(c)
            self.assertEqual(ca.wins, 1, "upheld result stands")
            self.assertEqual(db.query(models.Match).filter(models.Match.challenge_id == c.id).count(), 1)
            self.assertEqual(c.status, models.ChallengeStatus.COMPLETED)
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
