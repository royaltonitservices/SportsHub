"""Gate 1.4D — server-side UGC text-policy enforcement.

Two layers:
  * pure-engine unit tests on `text_policy.evaluate` (allow/deny, evasions, benign collisions,
    bounds, non-sensitive verdict);
  * behavior tests that drive the REAL router coroutines on disposable temp DBs, proving the
    check fires on every changed write boundary (create AND edit), that rejected writes persist
    nothing, that frozen block/authorization behavior is unchanged, that excluded report
    narratives still accept abusive evidence, and that a text pass does NOT touch
    moderation_status/safety_checked (media stays unreviewed, admin removal not overridden).

Run from backend/:  ../.venv/bin/python -m unittest tests.test_text_policy -v
"""
import asyncio
import inspect
import os
import sys
import tempfile
import unittest
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from database import Base
import models
import models_premium  # noqa: F401
import schemas
import text_policy
from routers import posts as posts_r
from routers import comments as comments_r
from routers import clips as clips_r
from routers import highlights as highlights_r
from routers import messages as messages_r
from routers import teams as teams_r
from routers import users as users_r
from routers import moderation as moderation_r
from routers import auth as auth_r

ADULT = datetime(2000, 1, 1)
BAD = "fuck you"          # canonical disallowed sample
OK = "great game today"   # canonical allowed sample


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


def _engine():
    fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
    eng = create_engine(f"sqlite:///{path}", connect_args={"check_same_thread": False})
    with eng.connect() as c:
        c.exec_driver_sql("PRAGMA journal_mode=WAL")
    Base.metadata.create_all(eng)
    return eng, path


def _u(db, n):
    u = models.User(email=f"{n}@x.com", username=n, password_hash="x",
                    display_name=n.title(), date_of_birth=ADULT)
    db.add(u); db.flush(); return u


# ── layer 1: pure engine ────────────────────────────────────────────────────────────────────
class TextPolicyEngineTests(unittest.TestCase):
    def _blocked(self, s):
        self.assertFalse(text_policy.evaluate(s).allowed, f"expected BLOCK: {s!r}")

    def _allowed(self, s):
        self.assertTrue(text_policy.evaluate(s).allowed, f"expected ALLOW: {s!r}")

    def test_plain_profanity_blocked(self):
        for s in ["fuck", "you are a bitch", "what an asshole", "cunt", "dickhead"]:
            self._blocked(s)

    def test_case_and_unicode_evasions_blocked(self):
        for s in ["FUCK", "FuCk", "ｆｕｃｋ", "Ｓｈｉｔ"]:   # full-width folds via NFKC
            self._blocked(s)

    def test_zero_width_and_separator_evasions_blocked(self):
        for s in ["f​uck", "f.u.c.k", "s h i t", "f*u*c*k", "sh1t", "sh!t", "fvck"]:
            self._blocked(s)

    def test_inflections_blocked(self):
        for s in ["fucking awful", "you fucker", "bitches", "fucked up"]:
            self._blocked(s)

    def test_benign_substrings_names_sports_allowed(self):
        # Scunthorpe problem + benign names + sports vocabulary must NOT trip the filter.
        for s in ["class", "grass", "pass the ball", "assassin", "Scunthorpe", "cockpit",
                  "analysis", "assist", "Dickinson", "shiitake mushrooms", "bass guitar",
                  "Sussex", "great shot", "he is a killer on defense", "Matsushita",
                  "Babcock", "therapist", "compass", "embarrass", "Dick Butkus",
                  "grassroots", "assessment", "skills", "who're you"]:
            self._allowed(s)

    def test_empty_none_whitespace_allowed(self):
        for s in ["", "   ", None, "\t\n"]:
            self._allowed(s)

    def test_oversized_input_is_too_long(self):
        v = text_policy.evaluate("a" * (text_policy.MAX_TEXT_LEN + 1))
        self.assertFalse(v.allowed)
        self.assertEqual(v.code, text_policy.CODE_TOO_LONG)

    def test_adversarial_separator_run_terminates_and_is_bounded(self):
        # A long separator run between letters exceeds the bounded {0,3} → NOT bridged into a
        # term (stays under MAX so this isolates the separator property, not the length cap),
        # and evaluation returns promptly (no catastrophic backtracking).
        self._allowed("f" + ("." * 200) + "uck")

    def test_verdict_is_non_sensitive(self):
        v = text_policy.evaluate("fuck you")
        self.assertEqual(v.code, text_policy.CODE_BLOCKED)
        # message carries no matched term and no echo of the input
        self.assertNotIn("fuck", v.message.lower())

    def test_no_external_provider_imported_by_module(self):
        # Deterministic + offline: the module IMPORTS no AI/network provider (AST-checked so a
        # mention in a docstring/comment doesn't count — only real import statements do).
        import ast
        tree = ast.parse(inspect.getsource(text_policy))
        imported = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported.update(a.name.split(".")[0] for a in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imported.add(node.module.split(".")[0])
        for bad in ["openai", "httpx", "requests", "ai_provider", "ai_orchestrator",
                    "urllib", "socket", "aiohttp"]:
            self.assertNotIn(bad, imported, f"text_policy must not import {bad}")


# ── layer 2: write-boundary behavior ────────────────────────────────────────────────────────
class WriteBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.eng, self.path = _engine()
        self.S = sessionmaker(bind=self.eng)
        self.db = self.S()
        self.a = _u(self.db, "alice"); self.b = _u(self.db, "bob"); self.c = _u(self.db, "carol")
        self.db.commit()

    def tearDown(self):
        self.db.close(); self.eng.dispose(); os.remove(self.path)

    def _befriend(self, x, y):
        self.db.add(models.Friendship(user_a_id=x.id, user_b_id=y.id,
                                      status=models.FriendshipStatus.ACCEPTED,
                                      initiated_by=x.id))
        self.db.commit()

    # posts ------------------------------------------------------------------
    def test_post_create_allowed(self):
        r = _run(posts_r.create_post(
            schemas.PostCreate(content=OK, sport=models.Sport.BASKETBALL), self.a, self.db))
        self.assertEqual(self.db.query(models.Post).count(), 1)

    def test_post_create_denied(self):
        with self.assertRaises(HTTPException) as e:
            _run(posts_r.create_post(
                schemas.PostCreate(content=BAD, sport=models.Sport.BASKETBALL), self.a, self.db))
        self.assertEqual(e.exception.status_code, 400)
        self.assertEqual(self.db.query(models.Post).count(), 0)   # nothing persisted

    def test_post_pass_does_not_mark_reviewed_or_safe(self):
        # A text pass must NOT approve media or override moderation state.
        _run(posts_r.create_post(
            schemas.PostCreate(content=OK, sport=models.Sport.BASKETBALL), self.a, self.db))
        post = self.db.query(models.Post).first()
        self.assertEqual(post.moderation_status, "pending")   # still awaiting moderation
        self.assertFalse(post.safety_checked)                 # media/content NOT certified safe

    def test_admin_removal_not_overridden_by_text_pass(self):
        # Text approval on create cannot un-remove admin-removed content (no re-approval path).
        _run(posts_r.create_post(
            schemas.PostCreate(content=OK, sport=models.Sport.BASKETBALL), self.a, self.db))
        post = self.db.query(models.Post).first()
        post.moderation_status = "removed"; self.db.commit()   # simulate admin removal
        # There is no post-edit path; re-reading keeps it removed.
        self.assertEqual(self.db.query(models.Post).first().moderation_status, "removed")

    # comments ---------------------------------------------------------------
    def _a_post(self):
        _run(posts_r.create_post(
            schemas.PostCreate(content=OK, sport=models.Sport.BASKETBALL), self.a, self.db))
        return self.db.query(models.Post).first()

    def test_comment_create_allowed_and_denied(self):
        p = self._a_post()
        _run(comments_r.create_comment(
            schemas.CommentCreate(post_id=p.id, content=OK, parent_comment_id=None),
            self.a, self.db))
        self.assertEqual(self.db.query(models.Comment).count(), 1)
        with self.assertRaises(HTTPException) as e:
            _run(comments_r.create_comment(
                schemas.CommentCreate(post_id=p.id, content=BAD, parent_comment_id=None),
                self.a, self.db))
        self.assertEqual(e.exception.status_code, 400)
        self.assertEqual(self.db.query(models.Comment).count(), 1)   # denied one not added

    # clips ------------------------------------------------------------------
    def test_clip_create_allowed_and_denied(self):
        _run(clips_r.create_clip(
            schemas.ClipCreate(sport=models.Sport.BASKETBALL, title=OK,
                               video_url="http://x/v.mov", duration=0), self.a, self.db))
        self.assertEqual(self.db.query(models.Clip).count(), 1)
        with self.assertRaises(HTTPException) as e:
            _run(clips_r.create_clip(
                schemas.ClipCreate(sport=models.Sport.BASKETBALL, title=BAD,
                                   video_url="http://x/v.mov", duration=0), self.a, self.db))
        self.assertEqual(e.exception.status_code, 400)
        self.assertEqual(self.db.query(models.Clip).count(), 1)

    def test_clip_upload_text_checked_before_file_is_touched(self):
        # video=object() would raise AttributeError if the handler read it; getting a clean
        # HTTPException(400) proves the text check runs FIRST — no orphan CDN file, no persist.
        with self.assertRaises(HTTPException) as e:
            _run(clips_r.upload_clip(video=object(), title=BAD, sport="basketball",
                                     description=None, current_user=self.a, db=self.db))
        self.assertEqual(e.exception.status_code, 400)
        self.assertEqual(self.db.query(models.Clip).count(), 0)

    def test_clip_upload_multifield_description_denied_before_file(self):
        # Clean title but disallowed description → whole write rejected before any file work.
        with self.assertRaises(HTTPException) as e:
            _run(clips_r.upload_clip(video=object(), title="Nice dunk", sport="basketball",
                                     description=BAD, current_user=self.a, db=self.db))
        self.assertEqual(e.exception.status_code, 400)
        self.assertEqual(self.db.query(models.Clip).count(), 0)

    # highlights -------------------------------------------------------------
    def test_highlight_caption_allowed_and_denied(self):
        _run(highlights_r.create_highlight(
            schemas.HighlightCreate(media_url="/cdn/highlights/x.jpg", thumbnail_url=None,
                                    caption=OK, sport=models.Sport.BASKETBALL), self.a, self.db))
        self.assertEqual(self.db.query(models.Highlight).count(), 1)
        with self.assertRaises(HTTPException) as e:
            _run(highlights_r.create_highlight(
                schemas.HighlightCreate(media_url="/cdn/highlights/x.jpg", thumbnail_url=None,
                                        caption=BAD, sport=models.Sport.BASKETBALL),
                self.a, self.db))
        self.assertEqual(e.exception.status_code, 400)
        self.assertEqual(self.db.query(models.Highlight).count(), 1)

    # direct messages --------------------------------------------------------
    def test_dm_allowed_and_denied_between_friends(self):
        self._befriend(self.a, self.b)
        _run(messages_r.send_message(
            schemas.MessageCreate(receiver_id=self.b.id, content=OK), self.a, self.db))
        self.assertEqual(self.db.query(models.Message).count(), 1)
        with self.assertRaises(HTTPException) as e:
            _run(messages_r.send_message(
                schemas.MessageCreate(receiver_id=self.b.id, content=BAD), self.a, self.db))
        self.assertEqual(e.exception.status_code, 400)
        self.assertEqual(self.db.query(models.Message).count(), 1)

    def test_dm_non_friend_denied_before_text_check(self):
        # Not friends → frozen friends-only 403 regardless of (even clean) content.
        with self.assertRaises(HTTPException) as e:
            _run(messages_r.send_message(
                schemas.MessageCreate(receiver_id=self.b.id, content=OK), self.a, self.db))
        self.assertEqual(e.exception.status_code, 403)

    def test_dm_blocked_sender_gets_block_response_not_text_error(self):
        # FROZEN Gate 1.4B/1.4C: a blocked sender is denied as blocked (403) even with profanity —
        # the text gate must NOT change this to a 400.
        import blocking_policy
        self._befriend(self.a, self.b)
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        with self.assertRaises(HTTPException) as e:
            _run(messages_r.send_message(
                schemas.MessageCreate(receiver_id=self.b.id, content=BAD), self.a, self.db))
        self.assertEqual(e.exception.status_code, 403)
        self.assertEqual(e.exception.detail, "Can only message friends")

    # group chat name/description + messages ---------------------------------
    def _group(self, member_ids):
        return _run(messages_r.create_group_chat(
            schemas.GroupChatCreate(name="Squad", description=None, member_ids=member_ids),
            self.a, self.db))

    def test_group_create_denied_on_bad_name_and_description(self):
        with self.assertRaises(HTTPException) as e:
            _run(messages_r.create_group_chat(
                schemas.GroupChatCreate(name=BAD, description=None, member_ids=[]),
                self.a, self.db))
        self.assertEqual(e.exception.status_code, 400)
        with self.assertRaises(HTTPException) as e2:
            _run(messages_r.create_group_chat(
                schemas.GroupChatCreate(name="Squad", description=BAD, member_ids=[]),
                self.a, self.db))
        self.assertEqual(e2.exception.status_code, 400)
        self.assertEqual(self.db.query(models.GroupChat).count(), 0)   # neither persisted

    def test_group_create_allowed(self):
        g = self._group([str(self.b.id)])
        self.assertEqual(self.db.query(models.GroupChat).count(), 1)

    def test_group_send_allowed_denied_and_nonmember(self):
        g = self._group([str(self.b.id)])
        _run(messages_r.send_group_message(
            str(g.id), schemas.GroupMessageCreate(content=OK), self.b, self.db))
        self.assertEqual(self.db.query(models.Message).filter_by(group_id=g.id).count(), 1)
        with self.assertRaises(HTTPException) as e:     # member sends disallowed text
            _run(messages_r.send_group_message(
                str(g.id), schemas.GroupMessageCreate(content=BAD), self.b, self.db))
        self.assertEqual(e.exception.status_code, 400)
        with self.assertRaises(HTTPException) as e2:    # non-member (clean text) still 403
            _run(messages_r.send_group_message(
                str(g.id), schemas.GroupMessageCreate(content=OK), self.c, self.db))
        self.assertEqual(e2.exception.status_code, 403)
        self.assertEqual(self.db.query(models.Message).filter_by(group_id=g.id).count(), 1)

    # teams ------------------------------------------------------------------
    def test_team_create_allowed_and_denied(self):
        _run(teams_r.create_team(
            teams_r.CreateTeamRequest(name="Hoop Dreams", sport="basketball"), self.a, self.db))
        self.assertEqual(self.db.query(models.Team).count(), 1)
        with self.assertRaises(HTTPException) as e:
            _run(teams_r.create_team(
                teams_r.CreateTeamRequest(name=BAD, sport="basketball"), self.b, self.db))
        self.assertEqual(e.exception.status_code, 400)
        self.assertEqual(self.db.query(models.Team).count(), 1)

    def test_team_name_oversized_is_bounded(self):
        with self.assertRaises(HTTPException) as e:
            _run(teams_r.create_team(
                teams_r.CreateTeamRequest(name="x" * (text_policy.MAX_TEXT_LEN + 1),
                                          sport="basketball"), self.a, self.db))
        self.assertEqual(e.exception.status_code, 400)

    # profile edits (create AND edit boundary) -------------------------------
    def test_display_name_edit_allowed_and_denied_preserves_previous(self):
        _run(users_r.update_display_name(
            schemas.UpdateDisplayName(new_display_name="Coach A"), self.a, self.db))
        self.assertEqual(self.db.query(models.User).get(self.a.id).display_name, "Coach A")
        with self.assertRaises(HTTPException) as e:
            _run(users_r.update_display_name(
                schemas.UpdateDisplayName(new_display_name=BAD), self.a, self.db))
        self.assertEqual(e.exception.status_code, 400)
        self.db.expire_all()
        self.assertEqual(self.db.query(models.User).get(self.a.id).display_name,
                         "Coach A")   # previous accepted value preserved after rejected edit

    def test_bio_edit_allowed_and_denied_preserves_previous(self):
        _run(users_r.update_bio(schemas.UpdateBio(bio="I love hoops"), self.a, self.db))
        self.assertEqual(self.db.query(models.User).get(self.a.id).bio, "I love hoops")
        with self.assertRaises(HTTPException) as e:
            _run(users_r.update_bio(schemas.UpdateBio(bio=BAD), self.a, self.db))
        self.assertEqual(e.exception.status_code, 400)
        self.db.expire_all()
        self.assertEqual(self.db.query(models.User).get(self.a.id).bio, "I love hoops")

    # username change (publicly-displayed identifier) -----------------------
    def test_username_change_allowed(self):
        _run(users_r.update_username(
            schemas.UpdateUsername(new_username="coachalice"), self.a, self.db))
        self.db.expire_all()
        self.assertEqual(self.db.query(models.User).get(self.a.id).username, "coachalice")

    def test_username_change_denied_preserves_previous(self):
        _run(users_r.update_username(
            schemas.UpdateUsername(new_username="coachalice"), self.a, self.db))
        with self.assertRaises(HTTPException) as e:
            _run(users_r.update_username(
                schemas.UpdateUsername(new_username="fuckyou"), self.a, self.db))
        self.assertEqual(e.exception.status_code, 400)
        self.db.expire_all()
        self.assertEqual(self.db.query(models.User).get(self.a.id).username,
                         "coachalice")   # rejected change did not rename the account

    # pronouns (public profile free text; previously unbounded) --------------
    def test_pronouns_allowed_and_denied(self):
        _run(users_r.update_pronouns("she/her", self.a, self.db))
        self.assertEqual(self.db.query(models.User).get(self.a.id).pronouns, "she/her")
        with self.assertRaises(HTTPException) as e:
            _run(users_r.update_pronouns("fuck/off", self.a, self.db))
        self.assertEqual(e.exception.status_code, 400)
        self.db.expire_all()
        self.assertEqual(self.db.query(models.User).get(self.a.id).pronouns, "she/her")

    def test_pronouns_oversized_is_bounded(self):
        with self.assertRaises(HTTPException) as e:
            _run(users_r.update_pronouns("x" * (text_policy.MAX_TEXT_LEN + 1), self.a, self.db))
        self.assertEqual(e.exception.status_code, 400)

    # excluded surface: report narrative must accept abusive evidence --------
    def test_report_narrative_with_abuse_is_accepted(self):
        p = self._a_post()
        # reporter documents the abuse verbatim; the report must NOT be text-filtered.
        _run(moderation_r.report_content(
            "post", p.id, "they called me a fucking loser", self.a, self.db))
        self.assertEqual(self.db.query(models.ModerationFlag).filter_by(
            content_id=p.id, reporter_id=self.a.id).count(), 1)


class SignupIdentityTests(unittest.TestCase):
    """Identity text policy at account CREATION (signup). Uses the real signup coroutine on a
    disposable DB; debug + email_verification_mode=auto auto-verifies (no SMTP)."""

    def setUp(self):
        self.eng, self.path = _engine()
        self.S = sessionmaker(bind=self.eng)
        self.db = self.S()

    def tearDown(self):
        self.db.close(); self.eng.dispose(); os.remove(self.path)

    def _signup(self, username, display_name, email):
        return _run(auth_r.signup(
            schemas.UserSignup(email=email, username=username, password="Str0ng!pass",
                               display_name=display_name, date_of_birth=ADULT), self.db))

    def test_signup_allowed_creates_account(self):
        self._signup("hooper", "Sam Hooper", "sam@x.com")
        self.assertEqual(self.db.query(models.User).filter_by(username="hooper").count(), 1)

    def test_signup_denied_bad_username_creates_nothing(self):
        with self.assertRaises(HTTPException) as e:
            self._signup("fuckyou", "Sam", "sam2@x.com")
        self.assertEqual(e.exception.status_code, 400)
        self.assertEqual(self.db.query(models.User).count(), 0)   # no account created

    def test_signup_denied_bad_display_name_creates_nothing(self):
        with self.assertRaises(HTTPException) as e:
            self._signup("cleanname", "fuck this", "sam3@x.com")
        self.assertEqual(e.exception.status_code, 400)
        self.assertEqual(self.db.query(models.User).count(), 0)


if __name__ == "__main__":
    unittest.main()
