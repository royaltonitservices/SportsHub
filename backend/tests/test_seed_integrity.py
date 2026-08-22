"""Group G — demo/seed honesty + canonical consistency (mirrors production semantics).

Proves:
  - fail-closed guard requiring APP_ENV in {development,demo} AND SAMPLE_DATA_ENVIRONMENT
    truthy AND --confirm-demo-data (seed authorization can never drift apart from the
    sample-data disclosure)
  - reconcile derives counters with the REAL production split:
      RANKED-only : ranked_games_played, provisional_games, is_provisional
      LIFETIME    : games_played, wins, losses, matches_completed  (ranked OR unranked)
  - normal backend startup does not import/run the seed
  - GET /config/public sample_data_environment defaults false; true only when configured
  - seed IDs are stable/deterministic

Run from backend/:  ../.venv/bin/python -m unittest tests.test_seed_integrity -v
"""
import asyncio
import os
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import seed_dev_data as seed


class DemoEnvGuardTests(unittest.TestCase):
    def setUp(self):
        self._app = os.environ.get("APP_ENV")
        self._sample = os.environ.get("SAMPLE_DATA_ENVIRONMENT")

    def tearDown(self):
        for k, v in (("APP_ENV", self._app), ("SAMPLE_DATA_ENVIRONMENT", self._sample)):
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def _set(self, app_env=None, sample=None):
        if app_env is None:
            os.environ.pop("APP_ENV", None)
        else:
            os.environ["APP_ENV"] = app_env
        if sample is None:
            os.environ.pop("SAMPLE_DATA_ENVIRONMENT", None)
        else:
            os.environ["SAMPLE_DATA_ENVIRONMENT"] = sample

    def test_refuses_production(self):
        self._set("production", "true")
        self.assertFalse(seed._demo_env_guard(True)[0])

    def test_refuses_unset_env(self):
        self._set(None, "true")
        self.assertFalse(seed._demo_env_guard(True)[0])

    def test_refuses_staging(self):
        self._set("staging", "true")
        self.assertFalse(seed._demo_env_guard(True)[0])

    def test_refuses_dev_when_sample_disabled(self):
        self._set("development", "false")
        self.assertFalse(seed._demo_env_guard(True)[0])

    def test_refuses_demo_when_sample_unset(self):
        self._set("demo", None)
        self.assertFalse(seed._demo_env_guard(True)[0])

    def test_refuses_without_confirmation(self):
        self._set("development", "true")
        self.assertFalse(seed._demo_env_guard(False)[0])

    def test_allows_development_all_three(self):
        self._set("development", "true")
        self.assertTrue(seed._demo_env_guard(True)[0])

    def test_allows_demo_all_three(self):
        self._set("demo", "1")
        self.assertTrue(seed._demo_env_guard(True)[0])


class ReconcileSemanticsTests(unittest.TestCase):
    def _db(self):
        fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
        conn = sqlite3.connect(path)
        c = conn.cursor()
        c.execute("""CREATE TABLE sport_profiles (id TEXT, user_id TEXT, sport TEXT,
            rating INT, games_played INT, ranked_games_played INT, provisional_games INT,
            wins INT, losses INT, is_provisional INT, rank_tier TEXT, matches_completed INT)""")
        c.execute("""CREATE TABLE matches (id TEXT, sport TEXT, match_type TEXT,
            player1_id TEXT, player2_id TEXT, status TEXT, winner_id TEXT)""")
        conn.commit()
        return conn, c, path

    def test_lifetime_vs_ranked_split(self):
        """The decisive semantic test: an UNRANKED match counts toward LIFETIME
        (games_played/wins) but NOT toward ranked_games_played."""
        uid, opp = seed.SAM_ID, seed.MAYA_ID
        conn, c, path = self._db()
        try:
            c.execute("INSERT INTO sport_profiles VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                      ("p1", uid, "BASKETBALL", 1600, 99, 99, 99, 88, 11, 0, "gold", 99))
            # 3 RANKED (uid wins 2, loses 1) + 1 UNRANKED (uid wins).
            rows = [("RANKED", uid), ("RANKED", uid), ("RANKED", opp), ("UNRANKED", uid)]
            for i, (mt, w) in enumerate(rows):
                c.execute("INSERT INTO matches VALUES (?,?,?,?,?,?,?)",
                          (f"m{i}", "BASKETBALL", mt, uid, opp, "completed", w))
            conn.commit()
            seed.reconcile_ranked_counters(c, dry_run=False); conn.commit()
            row = c.execute("SELECT ranked_games_played, provisional_games, games_played, "
                            "wins, losses, matches_completed, is_provisional FROM sport_profiles "
                            "WHERE user_id=? AND sport='BASKETBALL'", (uid,)).fetchone()
            rgp, pg, gp, w, l, mc, prov = row
            self.assertEqual(rgp, 3, "ranked_games_played = RANKED only (excludes unranked)")
            self.assertEqual(pg, 3, "provisional_games = RANKED only")
            self.assertEqual(gp, 4, "games_played = LIFETIME (includes the unranked match)")
            self.assertEqual(w, 3, "wins = LIFETIME (2 ranked + 1 unranked)")
            self.assertEqual(l, 1)
            self.assertEqual(mc, 4, "matches_completed = LIFETIME")
            self.assertEqual(prov, 1, "3 ranked < threshold(10) → provisional")
            # Eligibility can never exceed canonical ranked history.
            self.assertLessEqual(rgp, 3)
        finally:
            conn.close(); os.remove(path)

    def test_zero_when_no_matches(self):
        uid = seed.JJ_ID
        conn, c, path = self._db()
        try:
            c.execute("INSERT INTO sport_profiles VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                      ("p2", uid, "BASKETBALL", 1500, 12, 12, 12, 7, 5, 0, "silver", 12))
            conn.commit()
            seed.reconcile_ranked_counters(c, dry_run=False); conn.commit()
            row = c.execute("SELECT ranked_games_played, games_played, wins, losses "
                            "FROM sport_profiles WHERE user_id=? AND sport='BASKETBALL'", (uid,)).fetchone()
            self.assertEqual(row, (0, 0, 0, 0), "no matches → all zeroed; cannot qualify on inflated counter")
        finally:
            conn.close(); os.remove(path)


class StartupAndConfigTests(unittest.TestCase):
    def test_startup_does_not_seed(self):
        import inspect, main
        self.assertNotIn("seed_dev_data", inspect.getsource(main),
                         "main must not import/run the seed script")

    def test_public_config_default_false_and_toggle(self):
        import httpx, config as cfg, main
        os.environ.pop("SAMPLE_DATA_ENVIRONMENT", None)
        cfg.get_settings.cache_clear()

        async def _get():
            t = httpx.ASGITransport(app=main.app)
            async with httpx.AsyncClient(transport=t, base_url="http://testserver") as c:
                r = await c.get("/config/public")
                return r.status_code, r.json()

        status, body = asyncio.get_event_loop().run_until_complete(_get())
        self.assertEqual(status, 200)
        self.assertFalse(body["sample_data_environment"], "defaults false (production safe)")

        os.environ["SAMPLE_DATA_ENVIRONMENT"] = "true"
        cfg.get_settings.cache_clear()
        _, body2 = asyncio.get_event_loop().run_until_complete(_get())
        self.assertTrue(body2["sample_data_environment"], "true only when explicitly configured")
        os.environ.pop("SAMPLE_DATA_ENVIRONMENT", None)
        cfg.get_settings.cache_clear()

    def test_seed_ids_stable(self):
        for attr in ("SAM_ID", "MAYA_ID", "JJ_ID", "RJ_ID", "KAI_ID", "TEST_USER_ID"):
            self.assertTrue(hasattr(seed, attr))
            self.assertRegex(getattr(seed, attr), r"^[0-9a-fA-F-]{36}$")


if __name__ == "__main__":
    unittest.main()
