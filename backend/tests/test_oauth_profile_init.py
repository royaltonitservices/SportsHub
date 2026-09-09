"""Gate 1.4D — OAuth new-account public-profile initialization under the text policy.

New provider accounts must not publish an unchecked username/display_name. This drives the REAL
onboarding chokepoint `resolve_or_onboard_oauth` on disposable temp DBs and proves:
  * an objectionable email-derived username → neutral fallback (independent of email contents);
  * an objectionable OR oversized supplied display name → neutral fallback;
  * benign values are retained unchanged;
  * fallback usernames still recover from collisions;
  * authentication SUCCEEDS and exactly one User + one AuthIdentity exist;
  * same-auth DOB completion still works and returning identities are not re-onboarded;
  * repeat login never overwrites an existing user's (possibly self-edited) profile values;
  * a staged (commit=False) onboarding rolls back cleanly — no orphan User/identity/profiles.

Frozen identity invariants (provider/subject key, email canonicalization, single-use attempts,
atomic identity+redemption, replay protection) live in the Apple endpoint + attempt lifecycle and
are unchanged here; they remain covered by tests.test_siwa_nonce and tests.test_auth_identity.

Run from backend/:  ../.venv/bin/python -m unittest tests.test_oauth_profile_init -v
"""
import os
import sys
import tempfile
import unittest
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from database import Base
import models
import models_premium  # noqa: F401
import text_policy
from routers.oauth import resolve_or_onboard_oauth

ADULT = datetime(2000, 1, 1)
PROV = "apple"


def _engine():
    fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
    eng = create_engine(f"sqlite:///{path}", connect_args={"check_same_thread": False})
    with eng.connect() as c:
        c.exec_driver_sql("PRAGMA journal_mode=WAL")
    Base.metadata.create_all(eng)
    return eng, path


class OAuthProfileInitTests(unittest.TestCase):
    def setUp(self):
        self.eng, self.path = _engine()
        self.S = sessionmaker(bind=self.eng)
        self.db = self.S()

    def tearDown(self):
        self.db.close(); self.eng.dispose(); os.remove(self.path)

    def _onboard(self, *, subject, email, display_name, dob=ADULT, commit=True):
        return resolve_or_onboard_oauth(
            self.db, provider=PROV, subject=subject, verified_email=email,
            display_name=display_name, date_of_birth=dob, commit=commit)

    def _user_by_email(self, email):
        return self.db.query(models.User).filter(models.User.email == email).first()

    # ── fallback substitution ────────────────────────────────────────────────
    def test_objectionable_email_username_gets_neutral_fallback(self):
        res = self._onboard(subject="s1", email="fuckyou@example.com", display_name=None)
        self.assertEqual(res["status"], "authenticated")
        u = self._user_by_email("fuckyou@example.com")
        self.assertTrue(text_policy.evaluate(u.username).allowed)       # published name is clean
        self.assertTrue(u.username.startswith("athlete"))              # neutral, not email-derived
        self.assertNotIn("fuck", u.username.lower())
        self.assertEqual(u.display_name, u.username)                   # display fallback = clean username

    def test_objectionable_display_name_gets_neutral_fallback(self):
        res = self._onboard(subject="s2", email="coach@example.com", display_name="fuck this")
        self.assertEqual(res["status"], "authenticated")
        u = self._user_by_email("coach@example.com")
        self.assertEqual(u.username, "coach")                          # clean email base retained
        self.assertTrue(text_policy.evaluate(u.display_name).allowed)
        self.assertEqual(u.display_name, "coach")                      # neutral fallback (the username)

    def test_oversized_display_name_gets_neutral_fallback(self):
        big = "x" * (text_policy.MAX_TEXT_LEN + 1)
        self._onboard(subject="s3", email="jane@example.com", display_name=big)
        u = self._user_by_email("jane@example.com")
        self.assertEqual(u.display_name, u.username)                   # oversized → fallback
        self.assertLessEqual(len(u.display_name), text_policy.MAX_TEXT_LEN)

    def test_benign_values_are_retained(self):
        self._onboard(subject="s4", email="coachjane@example.com", display_name="Jane Coach")
        u = self._user_by_email("coachjane@example.com")
        self.assertEqual(u.username, "coachjane")
        self.assertEqual(u.display_name, "Jane Coach")

    def test_fallback_username_recovers_from_collision(self):
        # An existing "athlete" forces the neutral fallback to recover as "athlete1".
        self.db.add(models.User(email="taken@example.com", username="athlete",
                                password_hash="x", display_name="Taken", date_of_birth=ADULT))
        self.db.commit()
        self._onboard(subject="s5", email="shithead@example.com", display_name=None)
        u = self._user_by_email("shithead@example.com")
        self.assertEqual(u.username, "athlete1")                       # collision-recovered fallback
        self.assertTrue(text_policy.evaluate(u.username).allowed)

    # ── identity invariants preserved ────────────────────────────────────────
    def test_auth_succeeds_exactly_one_user_and_identity(self):
        res = self._onboard(subject="s6", email="fuckface@example.com", display_name="badword shit")
        self.assertEqual(res["status"], "authenticated")
        self.assertEqual(self.db.query(models.User).count(), 1)
        self.assertEqual(self.db.query(models.AuthIdentity).filter_by(
            provider=PROV, subject="s6").count(), 1)

    def test_dob_completion_then_create_same_auth(self):
        # No DOB first → dob_required, nothing created. Same (provider,subject) WITH dob → created.
        first = self._onboard(subject="s7", email="newuser@example.com", display_name=None, dob=None)
        self.assertEqual(first["status"], "dob_required")
        self.assertEqual(self.db.query(models.User).count(), 0)
        second = self._onboard(subject="s7", email="newuser@example.com", display_name=None)
        self.assertEqual(second["status"], "authenticated")
        self.assertEqual(self.db.query(models.AuthIdentity).filter_by(
            provider=PROV, subject="s7").count(), 1)

    def test_repeat_login_preserves_existing_profile(self):
        # First login with objectionable email → neutral username. User later self-edits name.
        self._onboard(subject="s8", email="fuckyou2@example.com", display_name=None)
        u = self._user_by_email("fuckyou2@example.com")
        u.username = "coachpro"; u.display_name = "Coach Pro"; self.db.commit()
        # Repeat login (same provider/subject) resolves the returning identity — no re-onboard.
        res = self._onboard(subject="s8", email="fuckyou2@example.com", display_name="ignored new name")
        self.assertEqual(res["status"], "authenticated")
        self.db.expire_all()
        again = self._user_by_email("fuckyou2@example.com")
        self.assertEqual(again.username, "coachpro")                   # NOT reset/overwritten
        self.assertEqual(again.display_name, "Coach Pro")
        self.assertEqual(self.db.query(models.User).count(), 1)        # no duplicate account

    def test_staged_onboarding_rolls_back_cleanly(self):
        # commit=False stages the new identity in the caller's transaction; a rollback must leave
        # NO user / identity / sport profiles (atomic identity+redemption contract).
        res = self._onboard(subject="s9", email="fuckoff@example.com", display_name=None, commit=False)
        self.assertEqual(res["status"], "authenticated")
        self.db.rollback()
        self.assertEqual(self.db.query(models.User).count(), 0)
        self.assertEqual(self.db.query(models.AuthIdentity).count(), 0)
        self.assertEqual(self.db.query(models.SportProfile).count(), 0)


if __name__ == "__main__":
    unittest.main()
