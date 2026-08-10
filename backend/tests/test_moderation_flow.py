"""Group E — UGC report / moderation flow regression tests.

Verifies the report → admin-review → resolve/dismiss pipeline against the real
SQLite DB by calling route functions directly:

  - any active user can report a post / clip / user
  - reporting invalid type → 400; nonexistent content → 404
  - duplicate reports are safe (each creates a flag; no crash/corruption)
  - the admin guard (get_current_admin_user) rejects normal users (403) and
    admits admins — this is the real authorization boundary
  - admin can list flags, resolve (remove) a post/clip, and dismiss a flag
  - resolve→remove actually changes content state; dismiss persists 'dismissed'

Users are prefixed __validation_ and removed in tearDownClass.
Run from backend/:  ../.venv/bin/python -m unittest tests.test_moderation_flow -v
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
import routers.moderation as mod
import dependencies as deps
from database import SessionLocal

_PREFIX = "__validation_mod_"
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DB = os.path.join(_ROOT, "sportshub.db")


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def _mk_user(db, admin=False):
    u = models.User(
        email=f"{_PREFIX}{uuid.uuid4().hex[:8]}@test.com",
        username=_PREFIX + uuid.uuid4().hex[:6],
        password_hash="x",
        display_name="ModVal",
        date_of_birth=datetime(2005, 1, 1),
        role=models.UserRole.ADMIN if admin else models.UserRole.USER,
        account_status=models.AccountStatus.ACTIVE,
        age_verified=True,
        email_verified=True,
        created_at=datetime.utcnow(),
    )
    db.add(u)
    db.flush()
    return u


def _mk_post(db, author_id):
    p = models.Post(author_id=author_id, content=_PREFIX + "post", sport=models.Sport.BASKETBALL)
    db.add(p)
    db.flush()
    return p


def _mk_clip(db, author_id):
    c = models.Clip(author_id=author_id, sport=models.Sport.BASKETBALL,
                    title=_PREFIX + "clip", video_url="/cdn/videos/x.mov")
    db.add(c)
    db.flush()
    return c


class ModerationFlowTests(unittest.TestCase):

    @classmethod
    def tearDownClass(cls):
        db = sqlite3.connect(_DB)
        rows = db.execute("SELECT id FROM users WHERE username LIKE ?", (_PREFIX + "%",)).fetchall()
        ids = [r[0] for r in rows]
        for uid in ids:
            db.execute("DELETE FROM moderation_flags WHERE reporter_id=?", (uid,))
            db.execute("DELETE FROM admin_actions WHERE admin_id=?", (uid,))
            db.execute("DELETE FROM clips WHERE author_id=?", (uid,))
            db.execute("DELETE FROM posts WHERE author_id=?", (uid,))
        # Flags/admin_actions may reference validation content by id — clean by content too.
        db.execute("DELETE FROM moderation_flags WHERE reason LIKE ?", (_PREFIX + "%",))
        for uid in ids:
            db.execute("DELETE FROM users WHERE id=?", (uid,))
        db.commit()
        db.close()

    # ── users can report post / clip / user ───────────────────────────────────
    def test_report_post_clip_user(self):
        db = SessionLocal()
        try:
            reporter = _mk_user(db)
            author = _mk_user(db)
            post = _mk_post(db, author.id)
            clip = _mk_clip(db, author.id)
            db.commit()

            for ctype, cid in (("post", post.id), ("clip", clip.id), ("user", author.id)):
                r = _run(mod.report_content(content_type=ctype, content_id=cid,
                                            reason=_PREFIX + "bad", current_user=reporter, db=db))
                self.assertIn("reported", r["message"].lower())
                flag = db.query(models.ModerationFlag).filter(
                    models.ModerationFlag.content_type == ctype,
                    models.ModerationFlag.content_id == cid,
                    models.ModerationFlag.reporter_id == reporter.id).first()
                self.assertIsNotNone(flag, f"{ctype} report should create a flag")
                self.assertEqual(flag.status, "pending")
        finally:
            db.close()

    def test_report_invalid_type_and_missing_content(self):
        from fastapi import HTTPException
        db = SessionLocal()
        try:
            reporter = _mk_user(db)
            db.commit()
            with self.assertRaises(HTTPException) as c1:
                _run(mod.report_content(content_type="banana", content_id=uuid.uuid4(),
                                        reason="x", current_user=reporter, db=db))
            self.assertEqual(c1.exception.status_code, 400)
            with self.assertRaises(HTTPException) as c2:
                _run(mod.report_content(content_type="post", content_id=uuid.uuid4(),
                                        reason="x", current_user=reporter, db=db))
            self.assertEqual(c2.exception.status_code, 404)
        finally:
            db.close()

    def test_duplicate_report_is_safe(self):
        db = SessionLocal()
        try:
            reporter = _mk_user(db)
            author = _mk_user(db)
            post = _mk_post(db, author.id)
            db.commit()
            for _ in range(2):
                _run(mod.report_content(content_type="post", content_id=post.id,
                                        reason=_PREFIX + "dup", current_user=reporter, db=db))
            # Duplicate reports are permitted (each is a flag); the point is no crash
            # and no corruption. Documented as accepted behavior, not dedup'd.
            count = db.query(models.ModerationFlag).filter(
                models.ModerationFlag.content_id == post.id,
                models.ModerationFlag.reporter_id == reporter.id).count()
            self.assertEqual(count, 2)
        finally:
            db.close()

    # ── admin authorization boundary ──────────────────────────────────────────
    def test_admin_guard_rejects_normal_user(self):
        from fastapi import HTTPException
        db = SessionLocal()
        try:
            normal = _mk_user(db, admin=False)
            db.commit()
            with self.assertRaises(HTTPException) as c:
                _run(deps.get_current_admin_user(current_user=normal))
            self.assertEqual(c.exception.status_code, 403)
        finally:
            db.close()

    def test_admin_guard_admits_admin(self):
        db = SessionLocal()
        try:
            admin = _mk_user(db, admin=True)
            db.commit()
            out = _run(deps.get_current_admin_user(current_user=admin))
            self.assertEqual(out.id, admin.id)
        finally:
            db.close()

    # ── admin list / resolve(remove) / dismiss ────────────────────────────────
    def test_admin_list_and_resolve_remove_post(self):
        db = SessionLocal()
        try:
            admin = _mk_user(db, admin=True)
            reporter = _mk_user(db)
            author = _mk_user(db)
            post = _mk_post(db, author.id)
            db.commit()
            _run(mod.report_content(content_type="post", content_id=post.id,
                                    reason=_PREFIX + "remove-me", current_user=reporter, db=db))
            flags = _run(mod.get_moderation_flags(db=db, admin=admin,
                                                  status_filter="pending", content_type="post"))
            mine = [f for f in flags if f.content_id == post.id]
            self.assertTrue(mine, "admin should see the pending post flag")
            flag_id = mine[0].id
            _run(mod.resolve_flag(flag_id=flag_id, action="remove", db=db, admin=admin))
            db.refresh(post)
            self.assertEqual(post.moderation_status, "removed")
            flag = db.query(models.ModerationFlag).filter(models.ModerationFlag.id == flag_id).first()
            self.assertEqual(flag.status, "resolved")
        finally:
            db.close()

    def test_admin_resolve_remove_deletes_clip(self):
        db = SessionLocal()
        try:
            admin = _mk_user(db, admin=True)
            reporter = _mk_user(db)
            author = _mk_user(db)
            clip = _mk_clip(db, author.id)
            db.commit()
            clip_id = clip.id
            _run(mod.report_content(content_type="clip", content_id=clip_id,
                                    reason=_PREFIX + "bad-clip", current_user=reporter, db=db))
            flag = db.query(models.ModerationFlag).filter(
                models.ModerationFlag.content_id == clip_id).first()
            _run(mod.resolve_flag(flag_id=flag.id, action="remove", db=db, admin=admin))
            self.assertIsNone(
                db.query(models.Clip).filter(models.Clip.id == clip_id).first(),
                "removed clip should be deleted")
        finally:
            db.close()

    def test_admin_dismiss_persists_dismissed_state(self):
        db = SessionLocal()
        try:
            admin = _mk_user(db, admin=True)
            reporter = _mk_user(db)
            author = _mk_user(db)
            post = _mk_post(db, author.id)
            db.commit()
            _run(mod.report_content(content_type="post", content_id=post.id,
                                    reason=_PREFIX + "dismiss-me", current_user=reporter, db=db))
            flag = db.query(models.ModerationFlag).filter(
                models.ModerationFlag.content_id == post.id).first()
            _run(mod.dismiss_flag(flag_id=flag.id, db=db, admin=admin))
            db.refresh(flag)
            self.assertEqual(flag.status, "dismissed")
            # Dismiss must NOT alter the content.
            db.refresh(post)
            self.assertNotEqual(post.moderation_status, "removed")
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
