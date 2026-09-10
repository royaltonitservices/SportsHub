"""Group E follow-up — HTTP-level moderation report contract test.

Why this exists: test_moderation_flow.py calls the route *functions* directly, which
bypasses FastAPI's request-parameter binding. That is exactly why the iOS false door
(JSON body vs query params) went undetected. These tests drive the real ASGI app
through httpx so parameter binding is actually exercised.

Mechanism: starlette's TestClient is incompatible with the installed httpx 0.28
(it passes `app=` to httpx.Client, which was removed), so we use
httpx.ASGITransport + AsyncClient — the supported in-process HTTP path.

Proves the contract the iOS client now depends on:
  - query params (content_type, content_id, reason) + auth  -> 201, flag persisted
  - the OLD broken shape (JSON body, no query)               -> 422 (binding is real)
  - missing auth                                             -> 403
  - unknown content_type / missing content                  -> 400 / 404

Rows are prefixed __validation_ and removed in tearDownClass.
Run from backend/:  ../.venv/bin/python -m unittest tests.test_report_http_contract -v
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
from auth import create_access_token

_PREFIX = "__validation_httpreport_"
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DB = os.path.join(_ROOT, "sportshub.db")


def _request(method: str, path: str, token: str = None, json_body=None):
    """Drive the real ASGI app once through httpx; return (status, json_or_none)."""
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


class ReportHttpContractTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        db = SessionLocal()
        try:
            cls.reporter = cls._mk_user(db)
            cls.author = cls._mk_user(db)
            post = models.Post(author_id=cls.author.id, content=_PREFIX + "post",
                               sport=models.Sport.BASKETBALL)
            db.add(post)
            db.flush()
            comment = models.Comment(post_id=post.id, author_id=cls.author.id,
                                     content=_PREFIX + "comment")
            db.add(comment)
            # A comment authored by the REPORTER — used to prove self-report is rejected server-side.
            own_comment = models.Comment(post_id=post.id, author_id=cls.reporter.id,
                                         content=_PREFIX + "own")
            db.add(own_comment)
            db.commit()
            cls.post_id = str(post.id)
            cls.comment_id = str(comment.id)
            cls.own_comment_id = str(own_comment.id)
            cls.token = create_access_token({"sub": str(cls.reporter.id)})
        finally:
            db.close()

    @staticmethod
    def _mk_user(db):
        u = models.User(
            email=f"{_PREFIX}{uuid.uuid4().hex[:8]}@t.com",
            username=_PREFIX + uuid.uuid4().hex[:6],
            password_hash="x", display_name="HTTPRep",
            date_of_birth=datetime(2005, 1, 1),
            role=models.UserRole.USER, account_status=models.AccountStatus.ACTIVE,
            age_verified=True, email_verified=True, created_at=datetime.utcnow(),
        )
        db.add(u)
        db.flush()
        return u

    @classmethod
    def tearDownClass(cls):
        db = sqlite3.connect(_DB)
        for uid, in db.execute("SELECT id FROM users WHERE username LIKE ?", (_PREFIX + "%",)).fetchall():
            db.execute("DELETE FROM moderation_flags WHERE reporter_id=?", (uid,))
            db.execute("DELETE FROM comments WHERE author_id=?", (uid,))
            db.execute("DELETE FROM posts WHERE author_id=?", (uid,))
            db.execute("DELETE FROM users WHERE id=?", (uid,))
        db.commit()
        db.close()

    # The supported contract iOS now uses.
    def test_report_http_query_contract(self):
        status, body = _request(
            "POST",
            f"/moderation/report?content_type=post&content_id={self.post_id}&reason={_PREFIX}spam",
            token=self.token,
        )
        self.assertEqual(status, 201, f"query-param report should create; got {status} {body}")
        # Persisted with pending status.
        db = SessionLocal()
        try:
            flag = db.query(models.ModerationFlag).filter(
                models.ModerationFlag.content_id == uuid.UUID(self.post_id),
                models.ModerationFlag.reporter_id == self.reporter.id,
            ).first()
            self.assertIsNotNone(flag, "report must persist a flag")
            self.assertEqual(flag.status, "pending")
        finally:
            db.close()

    # The OLD broken iOS shape. Proves binding is genuinely exercised (not a route
    # function called directly). Not a promise that 422 is forever — a guard that a
    # body-only client would be caught as a contract mismatch.
    def test_report_http_json_body_is_not_the_contract(self):
        status, _ = _request(
            "POST", "/moderation/report", token=self.token,
            json_body={"content_type": "post", "content_id": self.post_id, "reason": "x"},
        )
        self.assertEqual(status, 422, "JSON body (no query params) must not satisfy the contract")

    # Gate 1.4E: comment reporting is a first-class content type end-to-end.
    def test_report_http_comment_contract(self):
        status, body = _request(
            "POST",
            f"/moderation/report?content_type=comment&content_id={self.comment_id}"
            f"&reason={_PREFIX}they%20harassed%20me",
            token=self.token,
        )
        self.assertEqual(status, 201, f"comment report should create; got {status} {body}")
        db = SessionLocal()
        try:
            flag = db.query(models.ModerationFlag).filter(
                models.ModerationFlag.content_id == uuid.UUID(self.comment_id),
                models.ModerationFlag.reporter_id == self.reporter.id,
            ).first()
            self.assertIsNotNone(flag, "comment report must persist a flag")
            self.assertEqual(flag.content_type, "comment")
        finally:
            db.close()

    def test_report_http_comment_missing_content(self):
        status, _ = _request(
            "POST",
            f"/moderation/report?content_type=comment&content_id={uuid.uuid4()}&reason=x",
            token=self.token,
        )
        self.assertEqual(status, 404)

    # Gate 1.4E: self-report is rejected server-side (authoritative — direct API bypass of the UI
    # guard). Generic 400, no sensitive detail. Reporting SOMEONE ELSE stays allowed (201 above).
    def test_self_report_account_rejected(self):
        reporter_id = str(self.reporter.id)
        status, _ = _request(
            "POST", f"/moderation/report?content_type=user&content_id={reporter_id}&reason=x",
            token=self.token)
        self.assertEqual(status, 400, "reporting your own account must be rejected")

    def test_self_report_own_comment_rejected(self):
        status, _ = _request(
            "POST", f"/moderation/report?content_type=comment&content_id={self.own_comment_id}&reason=x",
            token=self.token)
        self.assertEqual(status, 400, "reporting your own comment must be rejected")

    # Gate 1.4E: the admin moderation destination is not reachable by an ordinary user.
    def test_moderation_flags_requires_admin(self):
        status, _ = _request("GET", "/moderation/flags", token=self.token)
        self.assertEqual(status, 403, "non-admin must not reach the admin moderation queue")

    def test_report_http_requires_auth(self):
        status, _ = _request(
            "POST",
            f"/moderation/report?content_type=post&content_id={self.post_id}&reason=x",
        )
        self.assertEqual(status, 403)

    def test_report_http_invalid_content_type(self):
        status, _ = _request(
            "POST",
            f"/moderation/report?content_type=banana&content_id={self.post_id}&reason=x",
            token=self.token,
        )
        self.assertEqual(status, 400)

    def test_report_http_missing_content(self):
        status, _ = _request(
            "POST",
            f"/moderation/report?content_type=post&content_id={uuid.uuid4()}&reason=x",
            token=self.token,
        )
        self.assertEqual(status, 404)


if __name__ == "__main__":
    unittest.main()
