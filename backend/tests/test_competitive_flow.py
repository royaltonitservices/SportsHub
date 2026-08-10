"""Group E — competitive flow regression tests.

Verifies leaderboard win/loss integrity end to end against the real SQLite DB by
calling the route functions directly (TestClient is incompatible with the
installed httpx, matching test_upload_validation's approach):

  - a ranked completed challenge creates exactly ONE Match row (all 4 sports)
  - duplicate confirmation / re-mirror is idempotent (still one Match row)
  - a disputed challenge creates NO Match row and no W/L change
  - an unranked completed challenge does NOT count toward the ranked (ELO) board
  - both players' W/L are correct from the Match-backed ranked board
  - the legacy /challenges/{id}/complete route also mirrors to Match (idempotent)

All rows are owned by users prefixed __validation_ and removed in tearDownClass.
Run from backend/:  ../.venv/bin/python -m unittest tests.test_competitive_flow -v
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
import routers.challenges as ch
import routers.leaderboards as lb
from database import SessionLocal

_PREFIX = "__validation_comp_"
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DB = os.path.join(_ROOT, "sportshub.db")


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def _mk_user(db):
    u = models.User(
        email=f"{_PREFIX}{uuid.uuid4().hex[:8]}@test.com",
        username=_PREFIX + uuid.uuid4().hex[:6],
        password_hash="x",
        display_name="CompVal",
        date_of_birth=datetime(2005, 1, 1),
        role=models.UserRole.USER,
        account_status=models.AccountStatus.ACTIVE,
        age_verified=True,
        email_verified=True,
        created_at=datetime.utcnow(),
    )
    db.add(u)
    db.flush()
    return u


def _mk_profile(db, user_id, sport, provisional=False):
    p = models.SportProfile(
        user_id=user_id, sport=sport, rating=1500,
        is_provisional=provisional, provisional_games=0,
    )
    db.add(p)
    db.flush()
    return p


def _mk_accepted_challenge(db, sport, challenger_id, opponent_id, match_type):
    c = models.Challenge(
        sport=sport, match_type=match_type,
        challenger_id=challenger_id, opponent_id=opponent_id,
        status=models.ChallengeStatus.ACCEPTED,
    )
    db.add(c)
    db.flush()
    return c


def _submit(db, challenge_id, user, winner_id, score):
    result = schemas.SubmitMatchResult(
        challenge_id=challenge_id, winner_id=winner_id, score_data=score
    )
    return _run(mm.submit_match_result(result=result, current_user=user, db=db))


class CompetitiveFlowTests(unittest.TestCase):

    @classmethod
    def tearDownClass(cls):
        db = sqlite3.connect(_DB)
        rows = db.execute("SELECT id FROM users WHERE username LIKE ?", (_PREFIX + "%",)).fetchall()
        for uid, in rows:
            db.execute("DELETE FROM matches WHERE player1_id=? OR player2_id=?", (uid, uid))
            db.execute("DELETE FROM disputes WHERE initiator_id=?", (uid,))
            db.execute("DELETE FROM challenges WHERE challenger_id=? OR opponent_id=?", (uid, uid))
            db.execute("DELETE FROM sport_profiles WHERE user_id=?", (uid,))
            db.execute("DELETE FROM users WHERE id=?", (uid,))
        db.commit()
        db.close()

    def _complete_ranked(self, db, sport, match_type=models.MatchType.RANKED):
        """Create two users+profiles and a completed match. Returns (challenger, opponent, challenge)."""
        challenger = _mk_user(db)
        opponent = _mk_user(db)
        _mk_profile(db, challenger.id, sport)
        _mk_profile(db, opponent.id, sport)
        c = _mk_accepted_challenge(db, sport, challenger.id, opponent.id, match_type)
        db.commit()
        _submit(db, c.id, challenger, challenger.id, "21-15")
        r = _submit(db, c.id, opponent, challenger.id, "21-15")
        return challenger, opponent, c, r

    # ── one Match row per ranked completion, all four sports ──────────────────
    def _assert_one_match_per_sport(self, sport):
        db = SessionLocal()
        try:
            challenger, opponent, c, r = self._complete_ranked(db, sport)
            self.assertEqual(r["status"], "completed")
            db.refresh(c)
            self.assertEqual(c.status, models.ChallengeStatus.COMPLETED)
            matches = db.query(models.Match).filter(models.Match.challenge_id == c.id).all()
            self.assertEqual(len(matches), 1, f"{sport.value}: expected exactly one Match row")
            self.assertEqual(matches[0].winner_id, challenger.id)
            self.assertEqual(matches[0].match_type, models.MatchType.RANKED)
        finally:
            db.close()

    def test_basketball_ranked_creates_one_match(self):
        self._assert_one_match_per_sport(models.Sport.BASKETBALL)

    def test_football_ranked_creates_one_match(self):
        self._assert_one_match_per_sport(models.Sport.FOOTBALL)

    def test_soccer_ranked_creates_one_match(self):
        self._assert_one_match_per_sport(models.Sport.SOCCER)

    def test_tennis_ranked_creates_one_match(self):
        self._assert_one_match_per_sport(models.Sport.TENNIS)

    # ── duplicate confirmation is idempotent ──────────────────────────────────
    def test_duplicate_confirmation_no_duplicate_match(self):
        from fastapi import HTTPException
        db = SessionLocal()
        try:
            challenger, opponent, c, _ = self._complete_ranked(db, models.Sport.BASKETBALL)
            # A third submission is rejected because the challenge is no longer ACCEPTED.
            with self.assertRaises(HTTPException) as ctx:
                _submit(db, c.id, opponent, challenger.id, "21-15")
            self.assertEqual(ctx.exception.status_code, 400)
            # Re-running the mirror helper directly must not add a second row.
            db.refresh(c)
            mm._create_match_for_completed_challenge(db, c)
            db.commit()
            self.assertEqual(
                db.query(models.Match).filter(models.Match.challenge_id == c.id).count(), 1)
        finally:
            db.close()

    # ── disputed challenge does not count ─────────────────────────────────────
    def test_disputed_creates_no_match_and_no_wl(self):
        db = SessionLocal()
        try:
            challenger = _mk_user(db)
            opponent = _mk_user(db)
            cp = _mk_profile(db, challenger.id, models.Sport.SOCCER)
            op = _mk_profile(db, opponent.id, models.Sport.SOCCER)
            c = _mk_accepted_challenge(db, models.Sport.SOCCER, challenger.id, opponent.id,
                                       models.MatchType.RANKED)
            db.commit()
            _submit(db, c.id, challenger, challenger.id, "21-15")
            r = _submit(db, c.id, opponent, opponent.id, "10-21")  # mismatch
            self.assertEqual(r["status"], "disputed")
            db.refresh(c); db.refresh(cp); db.refresh(op)
            self.assertEqual(c.status, models.ChallengeStatus.DISPUTED)
            self.assertEqual(db.query(models.Match).filter(models.Match.challenge_id == c.id).count(), 0)
            self.assertEqual(cp.wins, 0)
            self.assertEqual(op.wins, 0)
            self.assertEqual(cp.games_played, 0)
            self.assertEqual(cp.matches_disputed, 1)
        finally:
            db.close()

    # ── unranked does not count toward the ranked (ELO) board ─────────────────
    def test_unranked_excluded_from_ranked_leaderboard_wl(self):
        db = SessionLocal()
        try:
            # One ranked win + one unranked win for the SAME challenger, same sport.
            challenger, opponent, ranked_c, _ = self._complete_ranked(db, models.Sport.TENNIS)
            # Second, unranked match between the same two players.
            uc = _mk_accepted_challenge(db, models.Sport.TENNIS, challenger.id, opponent.id,
                                        models.MatchType.UNRANKED)
            db.commit()
            _submit(db, uc.id, challenger, challenger.id, "21-15")
            _submit(db, uc.id, opponent, challenger.id, "21-15")

            # Both Match rows exist...
            self.assertEqual(
                db.query(models.Match).filter(
                    (models.Match.player1_id == challenger.id)).count(), 2)

            # ...but the ranked board must count only the RANKED win.
            board = _run(lb.get_ranked_leaderboard(
                sport="tennis", limit=100000, offset=0, current_user=challenger, db=db))
            me = next((e for e in board if e.user_id == str(challenger.id)), None)
            self.assertIsNotNone(me, "challenger should appear on ranked board")
            self.assertEqual(me.wins, 1, "ranked board must exclude the unranked win")
            self.assertEqual(me.losses, 0)
        finally:
            db.close()

    # ── both perspectives correct on the ranked board ────────────────────────
    def test_leaderboard_perspective_both_players(self):
        db = SessionLocal()
        try:
            challenger, opponent, c, _ = self._complete_ranked(db, models.Sport.BASKETBALL)
            board = _run(lb.get_ranked_leaderboard(
                sport="basketball", limit=100000, offset=0, current_user=challenger, db=db))
            win = next((e for e in board if e.user_id == str(challenger.id)), None)
            lose = next((e for e in board if e.user_id == str(opponent.id)), None)
            self.assertIsNotNone(win); self.assertIsNotNone(lose)
            self.assertEqual((win.wins, win.losses), (1, 0))
            self.assertEqual((lose.wins, lose.losses), (0, 1))
        finally:
            db.close()

    # ── legacy /challenges/{id}/complete also mirrors to Match, idempotently ──
    def test_legacy_complete_route_mirrors_match_idempotent(self):
        from fastapi import HTTPException
        db = SessionLocal()
        try:
            challenger = _mk_user(db)
            opponent = _mk_user(db)
            _mk_profile(db, challenger.id, models.Sport.FOOTBALL)
            _mk_profile(db, opponent.id, models.Sport.FOOTBALL)
            c = _mk_accepted_challenge(db, models.Sport.FOOTBALL, challenger.id, opponent.id,
                                       models.MatchType.RANKED)
            db.commit()
            _run(ch.complete_challenge(challenge_id=c.id, winner_id=challenger.id,
                                       score_data=None, current_user=challenger, db=db))
            self.assertEqual(
                db.query(models.Match).filter(models.Match.challenge_id == c.id).count(), 1)
            # A second completion is rejected (status no longer ACCEPTED) — no dup row.
            with self.assertRaises(HTTPException):
                _run(ch.complete_challenge(challenge_id=c.id, winner_id=challenger.id,
                                           score_data=None, current_user=opponent, db=db))
            self.assertEqual(
                db.query(models.Match).filter(models.Match.challenge_id == c.id).count(), 1)
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
