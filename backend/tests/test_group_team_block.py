"""Gate 1.4C — group/team block enforcement.

Disposable temp DBs (create_all includes the Gate 1.4B BlockedUser unique constraint). Drives
the REAL router coroutines. Allow + deny/bypass for every changed boundary. SQLite serializes
writers; the independent-session case proves the guarded outcome, not parallel row-locking
(Postgres = Gate 2.1A).

Run from backend/:  ../.venv/bin/python -m unittest tests.test_group_team_block -v
"""
import asyncio
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from database import Base
import models
import models_premium  # noqa: F401
import schemas
import blocking_policy
from routers import messages as messages_r
from routers import teams as teams_r
from routers import moderation as moderation_r

ADULT = datetime(2000, 1, 1)


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


class GroupBlockTests(unittest.TestCase):
    def setUp(self):
        self.eng, self.path = _engine()
        self.S = sessionmaker(bind=self.eng)
        self.db = self.S()
        self.a = _u(self.db, "alice"); self.b = _u(self.db, "bob"); self.c = _u(self.db, "carol")
        self.db.commit()

    def tearDown(self):
        self.db.close(); self.eng.dispose(); os.remove(self.path)

    def _group_with(self, creator, member_ids):
        return _run(messages_r.create_group_chat(
            schemas.GroupChatCreate(name="G", description=None, member_ids=member_ids),
            creator, self.db))

    # ── creation / membership introduction ───────────────────────────────────
    def test_group_create_allowed_without_blocked_pair(self):
        g = self._group_with(self.a, [str(self.b.id), str(self.c.id)])
        self.assertEqual(g.member_count, 3)

    def test_group_create_denied_when_creator_blocked_member(self):
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        with self.assertRaises(HTTPException) as e:
            self._group_with(self.a, [str(self.b.id)])
        self.assertEqual(e.exception.status_code, 403)
        self.assertEqual(self.db.query(models.GroupChat).count(), 0)   # nothing created

    def test_group_create_denied_when_third_party_pair_blocked(self):
        # Inviter a is not part of the block; b and c blocked each other. a must not be able
        # to introduce them into the same group.
        blocking_policy.apply_block(self.db, self.b.id, self.c.id)
        with self.assertRaises(HTTPException) as e:
            self._group_with(self.a, [str(self.b.id), str(self.c.id)])
        self.assertEqual(e.exception.status_code, 403)

    def test_add_members_denied_against_existing_member(self):
        g = self._group_with(self.a, [str(self.b.id)])            # a,b in group
        blocking_policy.apply_block(self.db, self.b.id, self.c.id)  # b blocks c
        with self.assertRaises(HTTPException) as e:                # admin a adds c
            _run(messages_r.add_group_members(str(g.id), [str(self.c.id)], self.a, self.db))
        self.assertEqual(e.exception.status_code, 403)
        self.assertEqual(self.db.query(models.GroupChatMember).filter_by(
            group_id=g.id, user_id=self.c.id).count(), 0)          # not added

    def test_add_members_allowed_without_block(self):
        g = self._group_with(self.a, [str(self.b.id)])
        _run(messages_r.add_group_members(str(g.id), [str(self.c.id)], self.a, self.db))
        self.assertEqual(self.db.query(models.GroupChatMember).filter_by(
            group_id=g.id, user_id=self.c.id).count(), 1)

    # ── Gate 1.4C contract: addition rejects ONLY pairs involving a NEW member ─
    def test_add_members_allowed_despite_retained_existing_block(self):
        # Contract 1: a and b are both existing members; they block each other AFTER joining
        # (retained, no eject). Unrelated c must still be able to join — the existing a/b pair
        # does not, by itself, deny an eligible candidate.
        g = self._group_with(self.a, [str(self.b.id)])            # a (admin) + b in group
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)  # retained existing pair
        _run(messages_r.add_group_members(str(g.id), [str(self.c.id)], self.a, self.db))
        self.assertEqual(self.db.query(models.GroupChatMember).filter_by(
            group_id=g.id, user_id=self.c.id).count(), 1)         # c joined
        self.assertEqual(self.db.query(models.GroupChatMember).filter_by(
            group_id=g.id, user_id=self.b.id).count(), 1)         # b still a member (not ejected)

    def test_add_members_denied_new_candidate_blocked_with_existing(self):
        # Contract 2: candidate c blocked with an existing member (here the admin a) -> denied.
        g = self._group_with(self.a, [str(self.b.id)])
        blocking_policy.apply_block(self.db, self.a.id, self.c.id)  # a (existing) blocks c
        with self.assertRaises(HTTPException) as e:
            _run(messages_r.add_group_members(str(g.id), [str(self.c.id)], self.a, self.db))
        self.assertEqual(e.exception.status_code, 403)
        self.assertEqual(self.db.query(models.GroupChatMember).filter_by(
            group_id=g.id, user_id=self.c.id).count(), 0)         # not added

    def test_add_members_denied_two_new_candidates_blocked_all_or_nothing(self):
        # Contract 3: two NEW candidates (d, e) blocked with each other -> the WHOLE addition is
        # denied, even alongside an eligible candidate (c). All-or-nothing: none are added.
        d = _u(self.db, "dave"); e = _u(self.db, "erin"); self.db.commit()
        g = self._group_with(self.a, [str(self.b.id)])
        blocking_policy.apply_block(self.db, d.id, e.id)          # new-vs-new blocked pair
        with self.assertRaises(HTTPException) as ex:
            _run(messages_r.add_group_members(
                str(g.id), [str(self.c.id), str(d.id), str(e.id)], self.a, self.db))
        self.assertEqual(ex.exception.status_code, 403)
        self.assertEqual(self.db.query(models.GroupChatMember).filter(
            models.GroupChatMember.group_id == g.id,
            models.GroupChatMember.user_id.in_([self.c.id, d.id, e.id])).count(), 0)  # none added

    def test_suppression_intact_after_unrelated_member_joins(self):
        # Contract 4: a/b suppression survives an unrelated member (c) joining afterwards.
        g = self._group_with(self.a, [str(self.b.id)])
        _run(messages_r.send_group_message(str(g.id),
             schemas.GroupMessageCreate(content="from-b"), self.b, self.db))
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)  # retained a/b block
        _run(messages_r.add_group_members(str(g.id), [str(self.c.id)], self.a, self.db))  # c joins
        msgs = _run(messages_r.get_group_messages(str(g.id), self.a, self.db))
        self.assertNotIn("from-b", [m.content for m in msgs])     # a still can't see b's message
        self.assertEqual(self.db.query(models.GroupChatMember).filter_by(
            group_id=g.id, user_id=self.c.id).count(), 1)         # and c did join

    # ── existing shared group: recipient-specific suppression ────────────────
    def _seed_group_msgs(self):
        g = self._group_with(self.a, [str(self.b.id), str(self.c.id)])
        # b and c each post; then a blocks b AFTER membership exists (no eject).
        _run(messages_r.send_group_message(str(g.id), schemas.GroupMessageCreate(content="from-b"),
                                           self.b, self.db))
        _run(messages_r.send_group_message(str(g.id), schemas.GroupMessageCreate(content="from-c"),
                                           self.c, self.db))
        return g

    def test_membership_retained_after_block(self):
        g = self._seed_group_msgs()
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        self.assertEqual(self.db.query(models.GroupChatMember).filter_by(
            group_id=g.id, user_id=self.b.id).count(), 1)          # b NOT ejected

    def test_blocked_authors_message_suppressed_from_reader_list(self):
        g = self._seed_group_msgs()
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        msgs = _run(messages_r.get_group_messages(str(g.id), self.a, self.db))
        contents = [m.content for m in msgs]
        self.assertNotIn("from-b", contents)     # blocked author suppressed for a
        self.assertIn("from-c", contents)        # non-blocked visible

    def test_unaffected_member_still_sees_message(self):
        g = self._seed_group_msgs()
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        msgs = _run(messages_r.get_group_messages(str(g.id), self.c, self.db))  # c not blocked
        self.assertIn("from-b", [m.content for m in msgs])          # c still receives b's msg

    def test_preview_and_unread_exclude_blocked_author(self):
        g = self._seed_group_msgs()   # last message is from-c already; make b post last
        _run(messages_r.send_group_message(str(g.id), schemas.GroupMessageCreate(content="b-last"),
                                           self.b, self.db))
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        groups = _run(messages_r.get_user_groups(self.a, self.db))
        gr = next(x for x in groups if x.id == g.id)
        self.assertNotEqual(gr.last_message, "b-last")   # blocked author's msg not previewed
        self.assertEqual(gr.last_message, "from-c")

    def test_pagination_limit_does_not_expose_suppressed(self):
        g = self._group_with(self.a, [str(self.b.id)])
        for i in range(5):
            _run(messages_r.send_group_message(str(g.id), schemas.GroupMessageCreate(content=f"b{i}"),
                                               self.b, self.db))
        _run(messages_r.send_group_message(str(g.id), schemas.GroupMessageCreate(content="a-msg"),
                                           self.a, self.db))
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        msgs = _run(messages_r.get_group_messages(str(g.id), self.a, self.db, limit=2))
        self.assertTrue(all(not m.content.startswith("b") for m in msgs))  # no b* leaks into page

    def test_send_not_rejected_when_blocked_member_present(self):
        # Whole-group message must still be accepted (and reach unaffected members) even though
        # a blocked counterpart remains a member.
        g = self._group_with(self.a, [str(self.b.id), str(self.c.id)])
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        msg = _run(messages_r.send_group_message(
            str(g.id), schemas.GroupMessageCreate(content="hello all"), self.a, self.db))
        self.assertEqual(msg.content, "hello all")
        self.assertIn("hello all", [m.content for m in
                                    _run(messages_r.get_group_messages(str(g.id), self.c, self.db))])

    def test_unblock_restores_visibility(self):
        g = self._seed_group_msgs()
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        blocking_policy.remove_block(self.db, self.a.id, self.b.id)
        msgs = _run(messages_r.get_group_messages(str(g.id), self.a, self.db))
        self.assertIn("from-b", [m.content for m in msgs])          # visible again

    def test_report_blocked_group_message_still_allowed(self):
        g = self._seed_group_msgs()
        b_msg = self.db.query(models.Message).filter_by(
            group_id=g.id, sender_id=self.b.id).first()
        blocking_policy.apply_block(self.db, self.a.id, self.b.id)
        # suppressed from ordinary read...
        self.assertNotIn("from-b", [m.content for m in
                                    _run(messages_r.get_group_messages(str(g.id), self.a, self.db))])
        # ...but authorized reporting of that message still works (not unrestricted retrieval)
        _run(moderation_r.report_content("message", b_msg.id, "harassment", self.a, self.db))
        self.assertEqual(self.db.query(models.ModerationFlag).filter_by(
            content_id=b_msg.id, reporter_id=self.a.id).count(), 1)

    def test_independent_session_block_then_read_suppresses(self):
        g = self._seed_group_msgs()
        s1, s2 = self.S(), self.S()
        try:
            blocking_policy.apply_block(s1, self.a.id, self.b.id)   # commit in s1
            msgs = _run(messages_r.get_group_messages(str(g.id), self.a, s2))  # read in s2
            self.assertNotIn("from-b", [m.content for m in msgs])
        finally:
            s1.close(); s2.close()


class TeamBlockTests(unittest.TestCase):
    def setUp(self):
        self.eng, self.path = _engine()
        self.S = sessionmaker(bind=self.eng)
        self.db = self.S()
        self.cap1 = _u(self.db, "cap1"); self.cap2 = _u(self.db, "cap2")
        self.p1 = _u(self.db, "p1"); self.p2 = _u(self.db, "p2")
        self.db.commit()

    def tearDown(self):
        self.db.close(); self.eng.dispose(); os.remove(self.path)

    def _team(self, captain, name):
        t = models.Team(name=name, sport=models.Sport.BASKETBALL, captain_id=captain.id)
        self.db.add(t); self.db.flush()
        self.db.add(models.TeamMember(team_id=t.id, user_id=captain.id))
        self.db.commit(); return t

    def test_add_team_member_denied_when_blocked_with_member(self):
        t = self._team(self.cap1, "T1")
        blocking_policy.apply_block(self.db, self.cap1.id, self.p1.id)   # captain blocks p1
        with self.assertRaises(HTTPException) as e:
            _run(teams_r.add_team_member(t.id, self.p1.id, self.cap1, self.db))
        self.assertEqual(e.exception.status_code, 403)
        self.assertEqual(self.db.query(models.TeamMember).filter_by(
            team_id=t.id, user_id=self.p1.id).count(), 0)

    def test_add_team_member_allowed_without_block(self):
        t = self._team(self.cap1, "T1")
        _run(teams_r.add_team_member(t.id, self.p1.id, self.cap1, self.db))
        self.assertEqual(self.db.query(models.TeamMember).filter_by(
            team_id=t.id, user_id=self.p1.id).count(), 1)

    def test_team_challenge_denied_on_cross_team_block(self):
        t1 = self._team(self.cap1, "T1"); t2 = self._team(self.cap2, "T2")
        self.db.add(models.TeamMember(team_id=t1.id, user_id=self.p1.id))
        self.db.add(models.TeamMember(team_id=t2.id, user_id=self.p2.id))
        self.db.commit()
        blocking_policy.apply_block(self.db, self.p1.id, self.p2.id)   # cross-team pair blocked
        with self.assertRaises(HTTPException) as e:
            _run(teams_r.create_team_challenge(
                t1.id, t2.id, models.Sport.BASKETBALL, models.MatchType.RANKED, self.cap1, self.db))
        self.assertEqual(e.exception.status_code, 403)
        self.assertEqual(self.db.query(models.TeamChallenge).count(), 0)

    def test_team_challenge_allowed_without_cross_block(self):
        t1 = self._team(self.cap1, "T1"); t2 = self._team(self.cap2, "T2")
        ch = _run(teams_r.create_team_challenge(
            t1.id, t2.id, models.Sport.BASKETBALL, models.MatchType.UNRANKED, self.cap1, self.db))
        self.assertEqual(ch.status, models.ChallengeStatus.PENDING)

    def test_existing_challenge_completion_untouched_by_block(self):
        # A challenge created before any block completes normally (existing competition intact).
        t1 = self._team(self.cap1, "T1"); t2 = self._team(self.cap2, "T2")
        ch = _run(teams_r.create_team_challenge(
            t1.id, t2.id, models.Sport.BASKETBALL, models.MatchType.UNRANKED, self.cap1, self.db))
        blocking_policy.apply_block(self.db, self.cap1.id, self.cap2.id)  # block added after
        res = _run(teams_r.complete_team_challenge(ch.id, t1.id, self.cap1, self.db))
        self.assertIn("completed", res["message"].lower())


if __name__ == "__main__":
    unittest.main()
