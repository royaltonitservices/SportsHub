"""Password reset dev/beta honesty tests (Group C).

Covers:
  email_service:
    - smtp_configured() reflects env
    - reset email returns False when no SMTP
    - expose_dev_code=True prints the code (dev); False withholds it (prod)
  forgot/reset routes (called directly — TestClient is incompatible with httpx):
    - debug/no-SMTP → honest "dev_log" response + code minted
    - production + no-SMTP → "unavailable", code NEVER exposed
    - unknown email → same mode-based response (no enumeration)
    - valid code resets password; old password stops working, new one works
    - invalid / expired / reused codes are rejected with a clean 400

Uses a known code by monkeypatching the code generator. All rows are prefixed
and removed in tearDownClass.
Run from backend/:  ../.venv/bin/python -m unittest tests.test_password_reset -v
"""
import asyncio
import io
import os
import sqlite3
import sys
import types
import unittest
import uuid
from contextlib import redirect_stdout
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import auth as auth_core
import email_service
import models
import routers.auth as auth
import schemas
from database import SessionLocal

_PREFIX = "__validation_reset_"
_DB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sportshub.db")
_KNOWN_CODE = "424242"
_OLD_PW = "OldPassw0rd!"
_NEW_PW = "NewPassw0rd!"


def _email():
    return _PREFIX + uuid.uuid4().hex[:8] + "@test.com"


def _make_user(email):
    db = SessionLocal()
    try:
        u = models.User(
            email=email,
            username=_PREFIX + uuid.uuid4().hex[:6],
            password_hash=auth_core.get_password_hash(_OLD_PW),
            display_name="ResetVal",
            date_of_birth=datetime(2005, 1, 1),
            role=models.UserRole.USER,
            account_status=models.AccountStatus.ACTIVE,
            age_verified=True,
            email_verified=True,
            created_at=datetime.utcnow(),
        )
        db.add(u)
        db.commit()
        return u.id
    finally:
        db.close()


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def _forgot(email):
    db = SessionLocal()
    try:
        return _run(auth.forgot_password(auth.ForgotPasswordRequest(email=email), db))
    finally:
        db.close()


def _reset(email, code, new_pw):
    db = SessionLocal()
    try:
        return _run(auth.reset_password(
            auth.ResetPasswordRequest(email=email, code=code, new_password=new_pw), db))
    finally:
        db.close()


def _reload_user(uid):
    db = SessionLocal()
    try:
        return db.query(models.User).filter(models.User.id == uid).first()
    finally:
        db.close()


class EmailServiceTests(unittest.TestCase):
    def test_smtp_not_configured_without_env(self):
        self.assertFalse(email_service.smtp_configured())

    def test_reset_email_false_without_smtp(self):
        self.assertFalse(email_service.send_password_reset_email("x@test.com", "111111"))

    def test_expose_dev_code_prints_code(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            email_service.send_password_reset_email("x@test.com", "654321", expose_dev_code=True)
        self.assertIn("654321", buf.getvalue())
        self.assertIn("PASSWORD RESET CODE", buf.getvalue())

    def test_no_expose_withholds_code(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            email_service.send_password_reset_email("x@test.com", "654321", expose_dev_code=False)
        out = buf.getvalue()
        self.assertNotIn("654321", out)
        self.assertIn("withheld", out.lower())


class ForgotResetRouteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._orig_settings = auth._settings
        cls._orig_gen = auth.generate_verification_code
        # Deterministic code so we can drive the reset step.
        auth.generate_verification_code = lambda: _KNOWN_CODE

    @classmethod
    def tearDownClass(cls):
        auth._settings = cls._orig_settings
        auth.generate_verification_code = cls._orig_gen
        db = sqlite3.connect(_DB)
        for uid, in db.execute("SELECT id FROM users WHERE username LIKE ?", (_PREFIX + "%",)).fetchall():
            db.execute("DELETE FROM sport_profiles WHERE user_id=?", (uid,))
            db.execute("DELETE FROM users WHERE id=?", (uid,))
        db.commit()
        db.close()

    def _debug_mode(self):
        auth._settings = types.SimpleNamespace(debug=True, email_verification_mode="auto")

    def _prod_mode(self):
        auth._settings = types.SimpleNamespace(debug=False, email_verification_mode="required")

    # ── forgot-password mode honesty ────────────────────────────────────────────

    def test_debug_returns_dev_log_and_mints_code(self):
        self._debug_mode()
        email = _email(); uid = _make_user(email)
        res = _forgot(email)
        self.assertEqual(res["email_delivery"], "dev_log")
        self.assertIn("log", res["message"].lower())
        self.assertIsNotNone(_reload_user(uid).reset_code_hash)

    def test_production_no_smtp_is_unavailable_and_hides_code(self):
        self._prod_mode()
        captured = {}
        orig = auth.send_password_reset_email
        def spy(email, code, expose_dev_code=False):
            captured["expose"] = expose_dev_code
            return orig(email, code, expose_dev_code=expose_dev_code)
        auth.send_password_reset_email = spy
        try:
            email = _email(); _make_user(email)
            res = _forgot(email)
        finally:
            auth.send_password_reset_email = orig
        self.assertEqual(res["email_delivery"], "unavailable")
        self.assertNotIn("log", res["message"].lower())
        self.assertFalse(captured.get("expose"), "production must never expose the dev code")

    def test_unknown_email_is_safe_and_mode_based(self):
        self._debug_mode()
        res = _forgot("__validation_reset_" + uuid.uuid4().hex[:8] + "@nobody.test")
        # Same mode-based response as an existing account → no enumeration.
        self.assertEqual(res["email_delivery"], "dev_log")
        self.assertIn("if an account exists", res["message"].lower())

    # ── reset-password behavior ─────────────────────────────────────────────────

    def test_valid_code_resets_password(self):
        self._debug_mode()
        email = _email(); uid = _make_user(email)
        _forgot(email)
        res = _reset(email, _KNOWN_CODE, _NEW_PW)
        self.assertIn("updated", res["message"].lower())
        u = _reload_user(uid)
        self.assertTrue(auth_core.verify_password(_NEW_PW, u.password_hash))   # new works
        self.assertFalse(auth_core.verify_password(_OLD_PW, u.password_hash))  # old rejected

    def test_invalid_code_rejected(self):
        from fastapi import HTTPException
        self._debug_mode()
        email = _email(); _make_user(email)
        _forgot(email)
        with self.assertRaises(HTTPException) as ctx:
            _reset(email, "000000", _NEW_PW)
        self.assertEqual(ctx.exception.status_code, 400)

    def test_expired_code_rejected(self):
        from fastapi import HTTPException
        self._debug_mode()
        email = _email(); uid = _make_user(email)
        _forgot(email)
        # Force expiry.
        db = SessionLocal()
        try:
            u = db.query(models.User).filter(models.User.id == uid).first()
            u.reset_code_expires_at = datetime.utcnow() - timedelta(minutes=1)
            db.commit()
        finally:
            db.close()
        with self.assertRaises(HTTPException) as ctx:
            _reset(email, _KNOWN_CODE, _NEW_PW)
        self.assertEqual(ctx.exception.status_code, 400)

    def test_reused_code_rejected(self):
        from fastapi import HTTPException
        self._debug_mode()
        email = _email(); _make_user(email)
        _forgot(email)
        _reset(email, _KNOWN_CODE, _NEW_PW)          # first use OK
        with self.assertRaises(HTTPException) as ctx:  # second use rejected
            _reset(email, _KNOWN_CODE, "AnotherPw1!")
        self.assertEqual(ctx.exception.status_code, 400)


if __name__ == "__main__":
    unittest.main()
