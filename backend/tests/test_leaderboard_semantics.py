"""Pre-deploy — visible leaderboard semantics.

The user-visible leaderboard is GET /matchmaking/leaderboard/{sport} (iOS
LeaderboardView -> APIClient.getLeaderboard). These tests drive that exact endpoint
through the real ASGI app (httpx.ASGITransport) because the endpoint response IS the
user-facing contract.

Enforces:
  - the response includes `rank` and `full_name` (iOS LeaderboardEntry requires them;
    the old response omitted both, so the leaderboard failed to decode)
  - displayed wins/losses/games are RANKED-ONLY (from canonical ranked Match rows),
    NOT SportProfile lifetime W/L
  - unranked matches do not affect the visible record
  - a removed ranked Match (as dispute-reverse does) stops contributing
  - both player perspectives are correct
  - cross-sport isolation
  - ordering remains by ranked ELO (rating desc)
  - an eligible profile with no ranked matches shows 0-0

Rows are prefixed __validation_ and removed in tearDownClass.
Run from backend/:  ../.venv/bin/python -m unittest tests.test_leaderboard_semantics -v
"""
import asyncio
import os
import sqlite3
import sys
import unittest
import uuid
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import httpx
import main
import models
from database import SessionLocal

_PREFIX = "__validation_lb_"
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DB = os.path.join(_ROOT, "sportshub.db")


def _get(path):
    async def _go():
        transport = httpx.ASGITransport(app=main.app)
        async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as c:
            r = await c.get(path)
            return r.status_code, r.json()
    return asyncio.get_event_loop().run_until_complete(_go())


def _mk_user(db):
    u = models.User(
        email=f"{_PREFIX}{uuid.uuid4().hex[:8]}@t.com", username=_PREFIX + uuid.uuid4().hex[:6],
        password_hash="x", display_name="LB", date_of_birth=datetime(2005, 1, 1),
        role=models.UserRole.USER, account_status=models.AccountStatus.ACTIVE,
        age_verified=True, email_verified=True, created_at=datetime.utcnow(),
    )
    db.add(u); db.flush(); return u


def _mk_profile(db, uid, sport, rating, ranked_games=5):
    p = models.SportProfile(user_id=uid, sport=sport, rating=rating, is_provisional=False,
                            ranked_games_played=ranked_games, wins=99, losses=99,
                            games_played=198)  # lifetime deliberately bogus — must be ignored
    db.add(p); db.flush(); return p


def _mk_match(db, sport, p1, p2, winner, match_type=models.MatchType.RANKED):
    m = models.Match(sport=sport, match_type=match_type, player1_id=p1, player2_id=p2,
                     status="completed", winner_id=winner)
    db.add(m); db.flush(); return m


class LeaderboardSemanticsTests(unittest.TestCase):

    @classmethod
    def tearDownClass(cls):
        db = sqlite3.connect(_DB)
        for uid, in db.execute("SELECT id FROM users WHERE username LIKE ?", (_PREFIX + "%",)).fetchall():
            db.execute("DELETE FROM matches WHERE player1_id=? OR player2_id=?", (uid, uid))
            db.execute("DELETE FROM sport_profiles WHERE user_id=?", (uid,))
            db.execute("DELETE FROM users WHERE id=?", (uid,))
        db.commit(); db.close()

    def _row(self, body, uid):
        return next((e for e in body if e["user_id"] == str(uid)), None)

    def test_contract_has_rank_and_full_name(self):
        db = SessionLocal()
        try:
            a = _mk_user(db); b = _mk_user(db)
            _mk_profile(db, a.id, models.Sport.BASKETBALL, 1700)
            _mk_profile(db, b.id, models.Sport.BASKETBALL, 1600)
            _mk_match(db, models.Sport.BASKETBALL, a.id, b.id, a.id)
            db.commit()
            status, body = _get("/matchmaking/leaderboard/basketball?limit=1000")
            self.assertEqual(status, 200)
            ra = self._row(body, a.id)
            self.assertIsNotNone(ra)
            # Fields the iOS LeaderboardEntry requires (previously absent).
            for key in ("rank", "user_id", "username", "full_name", "rating",
                        "games_played", "wins", "losses", "rank_tier"):
                self.assertIn(key, ra, f"missing {key}")
            self.assertEqual(ra["full_name"], "LB")
            self.assertIsInstance(ra["rank"], int)
        finally:
            db.close()

    def test_ranked_only_wl_both_perspectives(self):
        db = SessionLocal()
        try:
            a = _mk_user(db); b = _mk_user(db)
            _mk_profile(db, a.id, models.Sport.BASKETBALL, 1700)
            _mk_profile(db, b.id, models.Sport.BASKETBALL, 1600)
            # 2 ranked wins for A, 1 ranked win for B
            _mk_match(db, models.Sport.BASKETBALL, a.id, b.id, a.id)
            _mk_match(db, models.Sport.BASKETBALL, a.id, b.id, a.id)
            _mk_match(db, models.Sport.BASKETBALL, b.id, a.id, b.id)
            db.commit()
            _, body = _get("/matchmaking/leaderboard/basketball?limit=1000")
            ra = self._row(body, a.id); rb = self._row(body, b.id)
            # Ranked-only — NOT the bogus lifetime 99/99 on the profile.
            self.assertEqual((ra["wins"], ra["losses"], ra["games_played"]), (2, 1, 3))
            self.assertEqual((rb["wins"], rb["losses"], rb["games_played"]), (1, 2, 3))
            # ELO ordering preserved (A rating 1700 > B 1600).
            self.assertLess(ra["rank"], rb["rank"])
        finally:
            db.close()

    def test_unranked_excluded(self):
        db = SessionLocal()
        try:
            a = _mk_user(db); b = _mk_user(db)
            _mk_profile(db, a.id, models.Sport.SOCCER, 1700)
            _mk_profile(db, b.id, models.Sport.SOCCER, 1600)
            _mk_match(db, models.Sport.SOCCER, a.id, b.id, a.id)  # ranked win A
            _mk_match(db, models.Sport.SOCCER, a.id, b.id, a.id, match_type=models.MatchType.UNRANKED)  # ignored
            _mk_match(db, models.Sport.SOCCER, b.id, a.id, b.id, match_type=models.MatchType.UNRANKED)  # ignored
            db.commit()
            _, body = _get("/matchmaking/leaderboard/soccer?limit=1000")
            ra = self._row(body, a.id)
            self.assertEqual((ra["wins"], ra["losses"], ra["games_played"]), (1, 0, 1),
                             "unranked matches must not affect the ranked record")
        finally:
            db.close()

    def test_removed_match_stops_contributing(self):
        db = SessionLocal()
        try:
            a = _mk_user(db); b = _mk_user(db)
            _mk_profile(db, a.id, models.Sport.TENNIS, 1700)
            _mk_profile(db, b.id, models.Sport.TENNIS, 1600)
            m1 = _mk_match(db, models.Sport.TENNIS, a.id, b.id, a.id)
            _mk_match(db, models.Sport.TENNIS, a.id, b.id, a.id)
            db.commit()
            _, body = _get("/matchmaking/leaderboard/tennis?limit=1000")
            self.assertEqual(self._row(body, a.id)["wins"], 2)
            # Simulate dispute-reverse deleting a Match row.
            db.delete(db.get(models.Match, m1.id)); db.commit()
            _, body2 = _get("/matchmaking/leaderboard/tennis?limit=1000")
            self.assertEqual(self._row(body2, a.id)["wins"], 1,
                             "a removed (reversed) Match must stop contributing")
        finally:
            db.close()

    def test_cross_sport_isolation(self):
        db = SessionLocal()
        try:
            a = _mk_user(db); b = _mk_user(db)
            _mk_profile(db, a.id, models.Sport.FOOTBALL, 1700)
            _mk_profile(db, b.id, models.Sport.FOOTBALL, 1600)
            _mk_match(db, models.Sport.FOOTBALL, a.id, b.id, a.id)   # football ranked win A
            _mk_match(db, models.Sport.BASKETBALL, a.id, b.id, a.id)  # different sport, must not count
            db.commit()
            _, body = _get("/matchmaking/leaderboard/football?limit=1000")
            self.assertEqual(self._row(body, a.id)["games_played"], 1,
                             "only football ranked matches count on the football board")
        finally:
            db.close()

    def test_eligible_with_no_ranked_matches_shows_zero(self):
        db = SessionLocal()
        try:
            a = _mk_user(db)
            # Eligible by the ranked_games_played gate, but no Match rows exist.
            _mk_profile(db, a.id, models.Sport.BASKETBALL, 1555, ranked_games=5)
            db.commit()
            _, body = _get("/matchmaking/leaderboard/basketball?limit=1000")
            ra = self._row(body, a.id)
            self.assertIsNotNone(ra, "profile with ranked_games_played>=5 should still appear")
            self.assertEqual((ra["wins"], ra["losses"], ra["games_played"]), (0, 0, 0))
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
