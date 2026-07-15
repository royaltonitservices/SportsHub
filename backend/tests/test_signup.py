"""Signup / email-verification-mode tests (Phase 1A).

Covers:
  1. dev/beta signup succeeds without SMTP (auto mode) → ACTIVE + bypassed
  2. explicit production mode does NOT bypass → PENDING_VERIFICATION
  3. auto mode is ignored in a non-debug (production) build → PENDING_VERIFICATION
  4. duplicate username still fails (400)
  5. underage still fails (400)
  6. account created by dev/beta signup is ACTIVE + email_verified (usable, no SMTP)

Calls the real signup coroutine directly (TestClient is incompatible with the
installed httpx). Created users are prefixed and removed in tearDownClass.
Run from backend/:  ../.venv/bin/python -m unittest tests.test_signup -v
"""
import asyncio
import os
import sqlite3
import sys
import unittest
import uuid
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import routers.auth as auth
import schemas
import types
from database import SessionLocal
import models

_PREFIX = "t1atest_"
_DB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sportshub.db")


def _name():
    return _PREFIX + uuid.uuid4().hex[:8]


def _signup_payload(**over):
    body = dict(email=f"{_name()}@test.com", password="Passw0rd!23",
                username=_name(), display_name="T1A",
                date_of_birth=datetime(2005, 1, 1))
    body.update(over)
    return schemas.UserSignup(**body)


def _call_signup(payload):
    db = SessionLocal()
    try:
        return asyncio.get_event_loop().run_until_complete(auth.signup(payload, db))
    finally:
        db.close()


class SignupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._orig = auth._settings

    @classmethod
    def tearDownClass(cls):
        auth._settings = cls._orig
        db = sqlite3.connect(_DB)
        ids = [r[0] for r in db.execute("SELECT id FROM users WHERE username LIKE ?", (_PREFIX + "%",))]
        for uid in ids:
            db.execute("DELETE FROM sport_profiles WHERE user_id=?", (uid,))
            db.execute("DELETE FROM subscriptions WHERE user_id=?", (uid,))
            db.execute("DELETE FROM users WHERE id=?", (uid,))
        db.commit(); db.close()

    def test_dev_auto_signup_active_without_smtp(self):
        auth._settings = types.SimpleNamespace(email_verification_mode="auto", debug=True)
        res = _call_signup(_signup_payload())
        self.assertTrue(res["access_token"])
        self.assertEqual(res["account_status"], "active")
        self.assertEqual(res["email_verification"], "bypassed")

    def test_created_account_is_active_and_verified(self):
        auth._settings = types.SimpleNamespace(email_verification_mode="auto", debug=True)
        p = _signup_payload()
        _call_signup(p)
        db = SessionLocal()
        u = db.query(models.User).filter(models.User.username == p.username).first()
        self.assertIsNotNone(u)
        self.assertEqual(u.account_status, models.AccountStatus.ACTIVE)
        self.assertTrue(u.email_verified)
        db.close()

    def test_explicit_required_mode_does_not_bypass(self):
        auth._settings = types.SimpleNamespace(email_verification_mode="required", debug=True)
        res = _call_signup(_signup_payload())
        self.assertEqual(res["account_status"], "pending_verification")

    def test_auto_ignored_in_production_build(self):
        auth._settings = types.SimpleNamespace(email_verification_mode="auto", debug=False)
        res = _call_signup(_signup_payload())
        self.assertEqual(res["account_status"], "pending_verification")

    def test_duplicate_username_fails(self):
        auth._settings = types.SimpleNamespace(email_verification_mode="auto", debug=True)
        uname = _name()
        _call_signup(_signup_payload(username=uname))
        from fastapi import HTTPException
        with self.assertRaises(HTTPException) as ctx:
            _call_signup(_signup_payload(username=uname))
        self.assertEqual(ctx.exception.status_code, 400)

    def test_underage_fails(self):
        auth._settings = types.SimpleNamespace(email_verification_mode="auto", debug=True)
        from fastapi import HTTPException
        with self.assertRaises(HTTPException) as ctx:
            _call_signup(_signup_payload(date_of_birth=datetime(2020, 1, 1)))
        self.assertEqual(ctx.exception.status_code, 400)


if __name__ == "__main__":
    unittest.main()
