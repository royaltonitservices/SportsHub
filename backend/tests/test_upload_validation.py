"""Upload validation hardening tests (Group D).

Two layers:
  1. upload_validation helper — magic-byte sniffing + size/format enforcement
     (the single gate all four upload routes share).
  2. route-level — avatar / highlight / clip / evidence accept real media and
     reject fakes/oversized WITHOUT creating a DB row or leaving an orphan file.

Routes are called directly with a starlette UploadFile (TestClient is
incompatible with the installed httpx). All rows/files are prefixed with
__validation_upload_ and removed in tearDownClass.
Run from backend/:  ../.venv/bin/python -m unittest tests.test_upload_validation -v
"""
import asyncio
import glob
import io
import os
import sqlite3
import sys
import unittest
import uuid
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from starlette.datastructures import Headers, UploadFile

import models
import routers.users as users_router
import routers.highlights as highlights_router
import routers.clips as clips_router
import routers.evidence as evidence_router
import upload_validation as uv
from database import SessionLocal

_PREFIX = "__validation_upload_"
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DB = os.path.join(_ROOT, "sportshub.db")

# Minimal byte signatures — enough for content sniffing (not playable media).
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 32
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
GIF = b"GIF89a" + b"\x00" * 32
WEBP = b"RIFF\x00\x00\x00\x00WEBP" + b"\x00" * 32
MP4 = b"\x00\x00\x00\x18ftypisom" + b"\x00" * 32
MOV = b"\x00\x00\x00\x18ftypqt  " + b"\x00" * 32
FAKE = b"this is definitely not a real media file, just text bytes " * 2


def _upload(data, filename, content_type):
    return UploadFile(filename=filename, file=io.BytesIO(data),
                      headers=Headers({"content-type": content_type}))


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def _make_user():
    db = SessionLocal()
    try:
        u = models.User(
            email=f"{_PREFIX}{uuid.uuid4().hex[:8]}@test.com",
            username=_PREFIX + uuid.uuid4().hex[:6],
            password_hash="x",
            display_name="UploadVal",
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


def _user(uid):
    db = SessionLocal()
    try:
        return db.query(models.User).filter(models.User.id == uid).first(), db
    except Exception:
        db.close()
        raise


class HelperTests(unittest.TestCase):
    def test_valid_kinds_detected(self):
        self.assertEqual(uv.sniff_media_kind(JPEG), "jpeg")
        self.assertEqual(uv.sniff_media_kind(PNG), "png")
        self.assertEqual(uv.sniff_media_kind(GIF), "gif")
        self.assertEqual(uv.sniff_media_kind(WEBP), "webp")
        self.assertEqual(uv.sniff_media_kind(MP4), "mp4")
        self.assertEqual(uv.sniff_media_kind(MOV), "mov")

    def test_fake_bytes_unrecognized(self):
        self.assertIsNone(uv.sniff_media_kind(FAKE))

    def test_valid_image_accepted(self):
        kind, ext = uv.validate_media(JPEG, allowed=uv.IMAGE_KINDS, max_bytes=5 * uv.MB, label="Image")
        self.assertEqual((kind, ext), ("jpeg", ".jpg"))

    def test_empty_rejected_400(self):
        from fastapi import HTTPException
        with self.assertRaises(HTTPException) as c:
            uv.validate_media(b"", allowed=uv.IMAGE_KINDS, max_bytes=5 * uv.MB)
        self.assertEqual(c.exception.status_code, 400)

    def test_oversized_rejected_413(self):
        from fastapi import HTTPException
        with self.assertRaises(HTTPException) as c:
            uv.validate_media(JPEG, allowed=uv.IMAGE_KINDS, max_bytes=8)
        self.assertEqual(c.exception.status_code, 413)

    def test_fake_media_rejected_400(self):
        from fastapi import HTTPException
        with self.assertRaises(HTTPException) as c:
            uv.validate_media(FAKE, allowed=uv.IMAGE_KINDS, max_bytes=5 * uv.MB)
        self.assertEqual(c.exception.status_code, 400)

    def test_disallowed_kind_rejected_415(self):
        from fastapi import HTTPException
        # A real MP4, but the surface only allows images.
        with self.assertRaises(HTTPException) as c:
            uv.validate_media(MP4, allowed=uv.IMAGE_KINDS, max_bytes=100 * uv.MB)
        self.assertEqual(c.exception.status_code, 415)


class RouteTests(unittest.TestCase):
    _files = []

    @classmethod
    def tearDownClass(cls):
        for p in cls._files:
            try:
                if p and os.path.isfile(p):
                    os.remove(p)
            except OSError:
                pass
        db = sqlite3.connect(_DB)
        for uid, in db.execute("SELECT id FROM users WHERE username LIKE ?", (_PREFIX + "%",)).fetchall():
            db.execute("DELETE FROM clips WHERE author_id=?", (uid,))
            db.execute("DELETE FROM upload_records WHERE owner_id=?", (uid,))
            db.execute("DELETE FROM users WHERE id=?", (uid,))
        db.commit()
        db.close()

    # ── avatar ──────────────────────────────────────────────────────────────
    def test_avatar_valid_jpeg_accepted(self):
        uid = _make_user()
        u, db = _user(uid)
        try:
            res = _run(users_router.upload_avatar(avatar=_upload(JPEG, "a.jpg", "image/jpeg"),
                                                   current_user=u, db=db))
            self.assertTrue(res["avatar_url"].endswith(".jpg"))
            self._files.append(os.path.join(_ROOT, "uploads", "avatars", f"{uid}.jpg"))
        finally:
            db.close()

    def test_avatar_fake_bytes_rejected_no_file(self):
        from fastapi import HTTPException
        uid = _make_user()
        u, db = _user(uid)
        path = os.path.join(_ROOT, "uploads", "avatars", f"{uid}.jpg")
        try:
            with self.assertRaises(HTTPException) as c:
                _run(users_router.upload_avatar(avatar=_upload(FAKE, "a.jpg", "image/jpeg"),
                                                current_user=u, db=db))
            self.assertEqual(c.exception.status_code, 400)
            self.assertFalse(os.path.isfile(path), "rejected avatar must leave no file")
        finally:
            db.close()

    # ── highlight ────────────────────────────────────────────────────────────
    def test_highlight_valid_png_accepted(self):
        uid = _make_user()
        u, _db = _user(uid); _db.close()
        res = _run(highlights_router.upload_highlight_media(
            media=_upload(PNG, "h.png", "image/jpeg"), current_user=u))
        self.assertTrue(res["media_url"].endswith(".png"))
        self._files.append(os.path.join(_ROOT, "uploads", res["media_url"].split("/cdn/")[1]))

    def test_highlight_fake_video_rejected(self):
        from fastapi import HTTPException
        uid = _make_user()
        u, _db = _user(uid); _db.close()
        before = set(glob.glob(os.path.join(_ROOT, "uploads", "highlights", "*")))
        with self.assertRaises(HTTPException) as c:
            _run(highlights_router.upload_highlight_media(
                media=_upload(FAKE, "h.mp4", "video/mp4"), current_user=u))
        self.assertEqual(c.exception.status_code, 400)
        after = set(glob.glob(os.path.join(_ROOT, "uploads", "highlights", "*")))
        self.assertEqual(before, after, "rejected highlight must leave no orphan file")

    # ── clip ───────────────────────────────────────────────────────────────────
    def test_clip_valid_mp4_accepted(self):
        uid = _make_user()
        u, db = _user(uid)
        try:
            res = _run(clips_router.upload_clip(
                video=_upload(MP4, "c.mp4", "video/mp4"),
                title="val", sport="basketball", description=None,
                current_user=u, db=db))
            # _build_clip_response returns a dict; track ONLY the file this test
            # created (never glob the whole dir — that could delete unrelated media).
            video_url = res["video_url"] if isinstance(res, dict) else getattr(res, "video_url", None)
            self.assertIsNotNone(video_url)
            if video_url and "/cdn/videos/" in video_url:
                self._files.append(os.path.join(_ROOT, "uploads", "videos",
                                                 video_url.split("/cdn/videos/")[1]))
        finally:
            db.close()

    def test_clip_fake_video_rejected_no_row(self):
        from fastapi import HTTPException
        uid = _make_user()
        u, db = _user(uid)
        try:
            with self.assertRaises(HTTPException) as c:
                _run(clips_router.upload_clip(
                    video=_upload(FAKE, "c.mp4", "video/mp4"),
                    title="val", sport="basketball", description=None,
                    current_user=u, db=db))
            self.assertEqual(c.exception.status_code, 400)
            self.assertEqual(db.query(models.Clip).filter(models.Clip.author_id == uid).count(), 0,
                             "rejected clip must create no DB row")
        finally:
            db.close()

    # ── evidence ─────────────────────────────────────────────────────────────
    def test_evidence_valid_png_accepted(self):
        uid = _make_user()
        u, db = _user(uid)
        try:
            res = _run(evidence_router.upload_evidence_file(
                file=_upload(PNG, "e.png", "image/png"), current_user=u, db=db))
            self.assertEqual(res.mime_type, "image/png")
            self._files.append(os.path.join(_ROOT, "uploads", "evidence",
                                            res.file_url.split("/cdn/evidence/")[1]))
        finally:
            db.close()

    def test_evidence_fake_bytes_rejected_no_row(self):
        from fastapi import HTTPException
        uid = _make_user()
        u, db = _user(uid)
        try:
            before = set(glob.glob(os.path.join(_ROOT, "uploads", "evidence", "*")))
            with self.assertRaises(HTTPException) as c:
                _run(evidence_router.upload_evidence_file(
                    file=_upload(FAKE, "e.png", "image/png"), current_user=u, db=db))
            self.assertEqual(c.exception.status_code, 400)
            self.assertEqual(db.query(models.UploadRecord).filter(models.UploadRecord.owner_id == uid).count(), 0)
            after = set(glob.glob(os.path.join(_ROOT, "uploads", "evidence", "*")))
            self.assertEqual(before, after, "rejected evidence must leave no orphan file")
        finally:
            db.close()


# ── D2: bounded reading ──────────────────────────────────────────────────────
class BoundedReadTests(unittest.TestCase):
    def test_at_limit_ok(self):
        data = b"x" * 100
        out = _run(uv.read_upload_capped(_upload(data, "f.bin", "application/octet-stream"),
                                         max_bytes=100, label="File"))
        self.assertEqual(len(out), 100)

    def test_one_byte_over_raises_413(self):
        from fastapi import HTTPException
        data = b"x" * 101
        with self.assertRaises(HTTPException) as c:
            _run(uv.read_upload_capped(_upload(data, "f.bin", "application/octet-stream"),
                                       max_bytes=100, label="File"))
        self.assertEqual(c.exception.status_code, 413)


# ── D2: strict ISO-BMFF ftyp parsing ─────────────────────────────────────────
class StrictFtypTests(unittest.TestCase):
    def test_valid_mp4_and_mov(self):
        self.assertEqual(uv.sniff_media_kind(MP4), "mp4")
        self.assertEqual(uv.sniff_media_kind(MOV), "mov")

    def test_planted_ftyp_wrong_offset_rejected(self):
        self.assertIsNone(uv.sniff_media_kind(b"\x00" * 40 + b"ftyp" + b"\x00" * 8))

    def test_implausible_box_size_rejected(self):
        self.assertIsNone(uv.sniff_media_kind(b"\xff\xff\xff\xffftypisom" + b"\x00" * 8))

    def test_truncated_box_rejected(self):
        # size field claims 0x30 (48) bytes but only 16 present
        self.assertIsNone(uv.sniff_media_kind(b"\x00\x00\x00\x30ftypqt  "))

    def test_unknown_brand_rejected(self):
        self.assertIsNone(uv.sniff_media_kind(b"\x00\x00\x00\x18ftypXXXX" + b"\x00" * 32))


# ── D2: adversarial metadata + failure injection ─────────────────────────────
class AdversarialAndFailureTests(unittest.TestCase):
    _files = []

    @classmethod
    def tearDownClass(cls):
        for p in cls._files:
            try:
                if p and os.path.isfile(p):
                    os.remove(p)
            except OSError:
                pass
        db = sqlite3.connect(_DB)
        for uid, in db.execute("SELECT id FROM users WHERE username LIKE ?", (_PREFIX + "%",)).fetchall():
            db.execute("DELETE FROM clips WHERE author_id=?", (uid,))
            db.execute("DELETE FROM upload_records WHERE owner_id=?", (uid,))
            db.execute("DELETE FROM users WHERE id=?", (uid,))
        db.commit()
        db.close()

    # 1. bytes win over a lying filename + MIME (image)
    def test_jpeg_with_false_ext_and_octet_mime_accepted_as_jpg(self):
        uid = _make_user()
        u, db = _user(uid)
        try:
            res = _run(users_router.upload_avatar(
                avatar=_upload(JPEG, "totally.exe", "application/octet-stream"),
                current_user=u, db=db))
            self.assertTrue(res["avatar_url"].endswith(".jpg"))  # canonical, from bytes
            self._files.append(os.path.join(_ROOT, "uploads", "avatars", f"{uid}.jpg"))
        finally:
            db.close()

    # 2. MOV bytes mislabeled .mp4 / video/mp4 → accepted, normalized to .mov
    def test_mov_bytes_mislabeled_mp4_normalized(self):
        uid = _make_user()
        u, db = _user(uid)
        try:
            res = _run(clips_router.upload_clip(
                video=_upload(MOV, "c.mp4", "video/mp4"),
                title="v", sport="basketball", description=None, current_user=u, db=db))
            vu = res["video_url"]
            self.assertTrue(vu.endswith(".mov"), f"expected canonical .mov, got {vu}")
            if "/cdn/videos/" in vu:
                self._files.append(os.path.join(_ROOT, "uploads", "videos", vu.split("/cdn/videos/")[1]))
        finally:
            db.close()

    # 3. MP4 bytes mislabeled .mov / video/quicktime → accepted, normalized to .mp4
    def test_mp4_bytes_mislabeled_mov_normalized(self):
        uid = _make_user()
        u, db = _user(uid)
        try:
            res = _run(clips_router.upload_clip(
                video=_upload(MP4, "c.mov", "video/quicktime"),
                title="v", sport="basketball", description=None, current_user=u, db=db))
            vu = res["video_url"]
            self.assertTrue(vu.endswith(".mp4"), f"expected canonical .mp4, got {vu}")
            if "/cdn/videos/" in vu:
                self._files.append(os.path.join(_ROOT, "uploads", "videos", vu.split("/cdn/videos/")[1]))
        finally:
            db.close()

    # 4. fake bytes with a legit filename + MIME → rejected
    def test_fake_bytes_legit_metadata_rejected(self):
        from fastapi import HTTPException
        uid = _make_user()
        u, _db = _user(uid); _db.close()
        with self.assertRaises(HTTPException) as c:
            _run(highlights_router.upload_highlight_media(
                media=_upload(FAKE, "real.jpg", "image/jpeg"), current_user=u))
        self.assertEqual(c.exception.status_code, 400)

    # 5. planted 'ftyp' at invalid offset → rejected (no clip row)
    def test_planted_ftyp_rejected_no_row(self):
        from fastapi import HTTPException
        uid = _make_user()
        u, db = _user(uid)
        planted = b"\x00" * 40 + b"ftyp" + b"\x00" * 8
        try:
            with self.assertRaises(HTTPException) as c:
                _run(clips_router.upload_clip(
                    video=_upload(planted, "c.mp4", "video/mp4"),
                    title="v", sport="basketball", description=None, current_user=u, db=db))
            self.assertEqual(c.exception.status_code, 400)
            self.assertEqual(db.query(models.Clip).filter(models.Clip.author_id == uid).count(), 0)
        finally:
            db.close()

    # 6. truncated ftyp box → rejected
    def test_truncated_ftyp_rejected(self):
        from fastapi import HTTPException
        uid = _make_user()
        u, db = _user(uid)
        try:
            with self.assertRaises(HTTPException) as c:
                _run(clips_router.upload_clip(
                    video=_upload(b"\x00\x00\x00\x30ftypqt  ", "c.mov", "video/quicktime"),
                    title="v", sport="basketball", description=None, current_user=u, db=db))
            self.assertEqual(c.exception.status_code, 400)
        finally:
            db.close()

    # 7. one byte over the surface limit → 413, no file
    def test_avatar_one_byte_over_limit_413_no_file(self):
        from fastapi import HTTPException
        uid = _make_user()
        u, db = _user(uid)
        oversized = b"\xff\xd8\xff\xe0" + b"\x00" * (5 * uv.MB)  # 5 MB + 4 bytes
        path = os.path.join(_ROOT, "uploads", "avatars", f"{uid}.jpg")
        try:
            with self.assertRaises(HTTPException) as c:
                _run(users_router.upload_avatar(avatar=_upload(oversized, "a.jpg", "image/jpeg"),
                                                current_user=u, db=db))
            self.assertEqual(c.exception.status_code, 413)
            self.assertFalse(os.path.isfile(path), "oversized upload must leave no file")
        finally:
            db.close()

    # 8. filesystem write failure → safe 500, no file
    def test_fs_write_failure_safe_500(self):
        from fastapi import HTTPException
        uid = _make_user()
        u, db = _user(uid)
        orig = uv.save_bytes_atomic
        uv.save_bytes_atomic = lambda *a, **k: (_ for _ in ()).throw(OSError("disk full"))
        try:
            with self.assertRaises(HTTPException) as c:
                _run(users_router.upload_avatar(avatar=_upload(JPEG, "a.jpg", "image/jpeg"),
                                                current_user=u, db=db))
            self.assertEqual(c.exception.status_code, 500)
            self.assertNotIn("disk full", str(c.exception.detail))  # no raw OS error leaked
            self.assertFalse(os.path.isfile(os.path.join(_ROOT, "uploads", "avatars", f"{uid}.jpg")))
        finally:
            uv.save_bytes_atomic = orig
            db.close()

    # 9. DB commit failure after a successful write → file removed, safe 500
    def test_db_commit_failure_removes_file(self):
        from fastapi import HTTPException
        uid = _make_user()
        u, db = _user(uid)
        path = os.path.join(_ROOT, "uploads", "avatars", f"{uid}.jpg")
        db.commit = lambda: (_ for _ in ()).throw(RuntimeError("db down"))
        try:
            with self.assertRaises(HTTPException) as c:
                _run(users_router.upload_avatar(avatar=_upload(JPEG, "a.jpg", "image/jpeg"),
                                                current_user=u, db=db))
            self.assertEqual(c.exception.status_code, 500)
            self.assertNotIn("db down", str(c.exception.detail))
            self.assertFalse(os.path.isfile(path), "file must be removed when DB commit fails")
        finally:
            db.close()

    # 10. an HTTPException raised in validation keeps its status (not 500)
    def test_validation_httpexception_not_converted_to_500(self):
        from fastapi import HTTPException
        uid = _make_user()
        u, db = _user(uid)
        try:
            with self.assertRaises(HTTPException) as c:
                _run(clips_router.upload_clip(
                    video=_upload(FAKE, "c.mp4", "video/mp4"),
                    title="v", sport="basketball", description=None, current_user=u, db=db))
            self.assertEqual(c.exception.status_code, 400)  # not 500
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
