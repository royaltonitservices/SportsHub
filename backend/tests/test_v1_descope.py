"""Milestone 2 — V1 shipping-surface de-scope (backend proofs).

Drives the real ASGI app through httpx (in-process) to prove the v1 backend surface:
  - The AI Coach / LLM provider surface is HARD-DISABLED server-side (require_ai_enabled
    -> 503) independently of premium/subscription/age. A non-premium user, a user WITH an
    active Subscription row, a minor, and an adult ALL get 503 on every AI route, and the
    AIOrchestrator (which would call OpenAI) is NEVER constructed (invocation count = 0).
  - The tournament and smartwatch/HealthKit routers are UNREGISTERED -> routes 404.
  - Non-HealthKit analytics (ranked leaderboard) stay FREE -> 200, no subscription.

Rows are prefixed __validation_ and removed in tearDownClass.
Run from backend/:  ../.venv/bin/python -m unittest tests.test_v1_descope -v
"""
import asyncio
import os
import sqlite3
import sys
import unittest
import uuid
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import httpx
import main
import models
import routers.ai_conversation as aiconv
from database import SessionLocal
from auth import create_access_token
from models_premium import Subscription, SubscriptionStatus, SubscriptionTier

_PREFIX = "__validation_v1descope_"
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DB = os.path.join(_ROOT, "sportshub.db")

# Spy that flips a counter if the AI orchestrator is ever constructed. If the router-level
# kill-switch works, the handler never runs and this is never instantiated.
_provider_ctor = {"count": 0}


class _SpyOrchestrator:
    def __init__(self, *a, **k):
        _provider_ctor["count"] += 1

    async def generate_coach_response(self, *a, **k): return {}
    async def generate_personalized_drill(self, *a, **k): return {}
    async def generate_challenge(self, *a, **k): return {}
    async def analyze_training_session(self, *a, **k): return {}
    async def generate_proactive_checkin(self, *a, **k): return ""


def _request(method: str, path: str, token: str = None, json_body=None):
    async def _go():
        transport = httpx.ASGITransport(app=main.app)
        async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
            headers = {"Authorization": f"Bearer {token}"} if token else {}
            resp = await client.request(method, path, headers=headers, json=json_body)
            try:
                return resp.status_code, resp.json()
            except Exception:
                return resp.status_code, None
    return asyncio.get_event_loop().run_until_complete(_go())


def _mk_user(db, *, dob, premium=False):
    u = models.User(
        email=f"{_PREFIX}{uuid.uuid4().hex[:8]}@t.com",
        username=_PREFIX + uuid.uuid4().hex[:6],
        password_hash="x", display_name="V1Descope", date_of_birth=dob,
        role=models.UserRole.USER, account_status=models.AccountStatus.ACTIVE,
        age_verified=True, email_verified=True, created_at=datetime.utcnow(),
    )
    db.add(u); db.commit(); db.refresh(u)
    if premium:
        db.add(Subscription(user_id=u.id, tier=SubscriptionTier.PREMIUM,
                            status=SubscriptionStatus.ACTIVE, platform="admin_grant",
                            started_at=datetime.utcnow()))
        db.commit()
    return u


class V1DescopeContractTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        db = SessionLocal()
        try:
            adult = _mk_user(db, dob=datetime(2000, 1, 1))
            premium = _mk_user(db, dob=datetime(1998, 1, 1), premium=True)
            minor = _mk_user(db, dob=datetime.utcnow() - timedelta(days=int(365.25 * 14)))
            cls.adult_token = create_access_token({"sub": str(adult.id)})
            cls.premium_token = create_access_token({"sub": str(premium.id)})
            cls.minor_token = create_access_token({"sub": str(minor.id)})
        finally:
            db.close()

    @classmethod
    def tearDownClass(cls):
        db = sqlite3.connect(_DB)
        for uid, in db.execute("SELECT id FROM users WHERE username LIKE ?", (_PREFIX + "%",)).fetchall():
            db.execute("DELETE FROM subscriptions WHERE user_id=?", (uid,))
            db.execute("DELETE FROM users WHERE id=?", (uid,))
        db.commit()
        db.close()

    # ── AI is hard-disabled server-side for EVERYONE (no provider invocation) ────
    _AI_ROUTES = [
        ("POST", "/ai/coach/drill/generate", {"sport": "basketball"}),
        ("POST", "/ai/coach/challenge/generate", {"sport": "basketball"}),
        ("POST", "/ai/coach/message", {"message": "hi", "sport": "basketball"}),
        ("POST", "/ai/coach/analyze", {"sport": "basketball"}),
        ("GET", "/ai/coach/checkin", None),
        ("GET", "/ai-coach/readiness", None),
        ("GET", "/ai-coach/drills", None),
    ]

    def _assert_all_ai_503(self, token, who):
        _provider_ctor["count"] = 0
        original = aiconv.AIOrchestrator
        aiconv.AIOrchestrator = _SpyOrchestrator
        try:
            for method, path, body in self._AI_ROUTES:
                status, _ = _request(method, path, token=token, json_body=body)
                self.assertEqual(status, 503, f"{who}: {method} {path} must be 503 (AI disabled), got {status}")
        finally:
            aiconv.AIOrchestrator = original
        self.assertEqual(_provider_ctor["count"], 0,
                         f"{who}: AI provider/orchestrator must NEVER be constructed while AI is disabled")

    def test_ai_disabled_for_non_premium_adult(self):
        self._assert_all_ai_503(self.adult_token, "adult non-premium")

    def test_ai_disabled_for_active_subscription(self):
        # An ACTIVE Subscription row must NOT bypass the AI feature-disable.
        self._assert_all_ai_503(self.premium_token, "active-subscription user")

    def test_ai_disabled_for_minor(self):
        self._assert_all_ai_503(self.minor_token, "minor user")

    # ── Tournament surface is unregistered -> 404 ────────────────────────────────
    def test_tournament_routes_absent(self):
        s1, _ = _request("POST", "/tournaments/create", token=self.adult_token,
                        json_body={"name": "X", "sport": "basketball", "format": "single_elimination"})
        s2, _ = _request("GET", "/tournaments/discover", token=self.adult_token)
        self.assertEqual((s1, s2), (404, 404), "tournament create/discover must be absent in v1")

    # ── Smartwatch/HealthKit ingestion is unregistered -> 404 ────────────────────
    def test_smartwatch_routes_absent(self):
        s1, _ = _request("POST", "/smartwatch/sync", token=self.adult_token, json_body={})
        s2, _ = _request("GET", "/smartwatch/connection", token=self.adult_token)
        self.assertEqual((s1, s2), (404, 404), "smartwatch routes must be absent in v1")

    # ── Non-HealthKit analytics stay free (no subscription required) ─────────────
    def test_ranked_leaderboard_is_free(self):
        status, _ = _request("GET", "/leaderboards/ranked/basketball", token=self.adult_token)
        self.assertEqual(status, 200, "ranked leaderboard must be free for a non-premium user")


class AIKillSwitchUnitTests(unittest.TestCase):
    """Both directions of the AI kill-switch primitive, so the toggle is proven to be a
    real toggle (not a permanent block) and the flag parser is exercised end-to-end."""

    def test_flag_parses_truthy_and_falsy(self):
        import feature_flags as ff
        key = "SPORTSHUB_TEST_FLAG_XYZ"
        for v in ("1", "true", "TRUE", "Yes", "on"):
            os.environ[key] = v
            self.assertTrue(ff._flag(key), f"{v!r} should parse truthy")
        for v in ("0", "false", "no", "off", "", "garbage"):
            os.environ[key] = v
            self.assertFalse(ff._flag(key), f"{v!r} should parse falsy")
        os.environ.pop(key, None)
        self.assertFalse(ff._flag(key, default=False))  # unset -> default
        self.assertTrue(ff._flag(key, default=True))

    def test_require_ai_enabled_both_directions(self):
        import dependencies
        import feature_flags
        from fastapi import HTTPException
        original = feature_flags.AI_COACH_ENABLED
        try:
            # v1 default: OFF -> hard 503, independent of any caller.
            feature_flags.AI_COACH_ENABLED = False
            with self.assertRaises(HTTPException) as ctx:
                dependencies.require_ai_enabled()
            self.assertEqual(ctx.exception.status_code, 503)
            # Gate 1.6 future: ON -> allows through (no raise). Proves it truly toggles.
            feature_flags.AI_COACH_ENABLED = True
            self.assertIsNone(dependencies.require_ai_enabled())
        finally:
            feature_flags.AI_COACH_ENABLED = original
