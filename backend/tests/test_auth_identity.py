"""Gate 1.2 — auth identity + OAuth age-gate integrity.

Proves (from FRESH databases, not just model metadata):
  - email normalization at the persistence boundary + DB-unique normalized email
  - nullable password_hash (provider-only) + UNIQUE(provider, subject)
  - OAuth resolves by (provider, subject); typed states authenticated / dob_required
    / account_conflict / identity_incomplete; no email-based auto-link
  - shared >=13 age gate; no fabricated DOB; atomic create
  - provider-only password + reset fail-safe
  - Google fail-closed when unconfigured
  - AuthIdentity removed on account deletion
  - pre-Alembic dev transition: preflight-abort + idempotency

Run from backend/:  ../.venv/bin/python -m unittest tests.test_auth_identity -v
"""
import asyncio
import os
import sys
import tempfile
import unittest
from datetime import date, datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text, inspect
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import IntegrityError
from fastapi import HTTPException

from database import Base
import models
import models_premium  # noqa: F401 — registers premium tables so create_all builds them (deletion touches them)
from identity import normalize_email, is_valid_signup_dob, canonical_provider, calendar_age
from routers.oauth import resolve_or_onboard_oauth

ADULT = datetime(2000, 1, 1)
UNDER_13 = datetime.now() - timedelta(days=int(365.25 * 10))
JUST_UNDER_13 = datetime.now() - timedelta(days=int(365.25 * 13) - 40)
JUST_OVER_13 = datetime.now() - timedelta(days=int(365.25 * 13) + 40)
FUTURE = datetime.now() + timedelta(days=365)


def _fresh_session():
    fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
    eng = create_engine(f"sqlite:///{path}", connect_args={"check_same_thread": False})
    Base.metadata.create_all(eng)
    return sessionmaker(bind=eng)(), eng, path


def _wal_sessionmaker():
    """A WAL-mode engine + sessionmaker so two sessions can model a create race
    WITHOUT flaky lock contention: WAL lets one writer commit while another holds a
    read snapshot. Used to fire the real IntegrityError recovery branches, not to
    claim true OS-thread concurrency (that stays a Gate 2.1A / Postgres concern)."""
    fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
    eng = create_engine(f"sqlite:///{path}", connect_args={"check_same_thread": False})
    with eng.connect() as c:
        c.exec_driver_sql("PRAGMA journal_mode=WAL")
        c.exec_driver_sql("PRAGMA busy_timeout=5000")
    Base.metadata.create_all(eng)
    return sessionmaker(bind=eng), eng, path


def _mk_user(db, email, *, password_hash="x", username=None, dob=ADULT):
    u = models.User(email=email, username=username or email.split("@")[0],
                    password_hash=password_hash, display_name="T", date_of_birth=dob)
    db.add(u); db.flush(); return u


class NormalizationHelperTests(unittest.TestCase):
    def test_normalize_email(self):
        self.assertEqual(normalize_email("  Foo@X.CoM "), "foo@x.com")
        self.assertIsNone(normalize_email(None))
    def test_canonical_provider(self):
        self.assertEqual(canonical_provider(" Apple "), "apple")
    def test_age_gate(self):
        self.assertTrue(is_valid_signup_dob(ADULT))
        self.assertTrue(is_valid_signup_dob(JUST_OVER_13))
        self.assertFalse(is_valid_signup_dob(JUST_UNDER_13))
        self.assertFalse(is_valid_signup_dob(UNDER_13))
        self.assertFalse(is_valid_signup_dob(FUTURE))
        self.assertFalse(is_valid_signup_dob(None))


class AgeBoundaryTests(unittest.TestCase):
    """Calendar-EXACT 13+ gate (Gate 1.2 defect fix). Reference date is injected so
    the boundary is deterministic and never depends on wall-clock timing."""

    def test_day_before_13th_birthday_is_under_13(self):
        dob = date(2013, 6, 15)
        self.assertEqual(calendar_age(dob, today=date(2026, 6, 14)), 12)
        self.assertFalse(is_valid_signup_dob(dob, today=date(2026, 6, 14)))

    def test_exact_13th_birthday_is_13_and_eligible(self):
        dob = date(2013, 6, 15)
        self.assertEqual(calendar_age(dob, today=date(2026, 6, 15)), 13)
        self.assertTrue(is_valid_signup_dob(dob, today=date(2026, 6, 15)))

    def test_day_after_13th_birthday_is_eligible(self):
        dob = date(2013, 6, 15)
        self.assertEqual(calendar_age(dob, today=date(2026, 6, 16)), 13)
        self.assertTrue(is_valid_signup_dob(dob, today=date(2026, 6, 16)))

    def test_future_dob_invalid(self):
        self.assertFalse(is_valid_signup_dob(date(2030, 1, 1), today=date(2026, 6, 15)))

    def test_leap_day_dob_defined_behavior(self):
        # Feb-29 DOB: birthday is treated as Mar-1 in non-leap years. Person born
        # 2008-02-29 crosses 13 at 2021-03-01 (2021 is not a leap year).
        dob = date(2008, 2, 29)
        self.assertEqual(calendar_age(dob, today=date(2021, 2, 28)), 12)  # not yet
        self.assertFalse(is_valid_signup_dob(dob, today=date(2021, 2, 28)))
        self.assertEqual(calendar_age(dob, today=date(2021, 3, 1)), 13)   # now 13
        self.assertTrue(is_valid_signup_dob(dob, today=date(2021, 3, 1)))
        # On a real leap year the actual Feb-29 birthday counts.
        self.assertEqual(calendar_age(dob, today=date(2028, 2, 29)), 20)

    def test_signup_and_oauth_share_identical_boundary(self):
        # routers/auth.py (signup) and routers/oauth.py (OAuth) both call this exact
        # function — so proving it here proves both call sites at once.
        from routers.auth import is_valid_signup_dob as auth_gate
        from routers.oauth import is_valid_signup_dob as oauth_gate
        self.assertIs(auth_gate, oauth_gate)
        self.assertIs(auth_gate, is_valid_signup_dob)
        dob = date(2013, 6, 15)
        for gate in (auth_gate, oauth_gate):
            self.assertFalse(gate(dob, today=date(2026, 6, 14)))
            self.assertTrue(gate(dob, today=date(2026, 6, 15)))

    def test_accepts_datetime_and_date_equivalently(self):
        self.assertEqual(calendar_age(datetime(2013, 6, 15, 23, 59), today=date(2026, 6, 15)), 13)
        self.assertEqual(calendar_age(date(2013, 6, 15), today=datetime(2026, 6, 15, 0, 1)), 13)


class SchemaConstraintTests(unittest.TestCase):
    """Prove the FRESH-DB constraints directly."""
    def setUp(self): self.db, self.eng, self.path = _fresh_session()
    def tearDown(self): self.db.close(); os.remove(self.path)

    def test_email_stored_normalized_via_orm(self):
        u = _mk_user(self.db, "Mixed@Case.COM ", username="a")
        self.db.commit()
        self.assertEqual(u.email, "mixed@case.com")

    def test_email_unique_normalized(self):
        _mk_user(self.db, "dup@x.com", username="a"); self.db.commit()
        with self.assertRaises(IntegrityError):
            _mk_user(self.db, "DUP@x.com ", username="b")  # normalizes to same → flush raises
            self.db.commit()

    def test_password_hash_nullable(self):
        u = _mk_user(self.db, "np@x.com", username="np", password_hash=None)
        self.db.commit()
        self.assertIsNone(u.password_hash)

    def test_authidentity_unique_provider_subject(self):
        u = _mk_user(self.db, "ai@x.com", username="ai"); self.db.commit()
        self.db.add(models.AuthIdentity(user_id=u.id, provider="apple", subject="S1")); self.db.commit()
        self.db.add(models.AuthIdentity(user_id=u.id, provider="apple", subject="S1"))
        with self.assertRaises(IntegrityError):
            self.db.commit()

    def test_authidentity_blank_provider_rejected(self):
        u = _mk_user(self.db, "b1@x.com", username="b1"); self.db.commit()
        with self.assertRaises(ValueError):
            models.AuthIdentity(user_id=u.id, provider="  ", subject="S")

    def test_authidentity_blank_subject_rejected(self):
        u = _mk_user(self.db, "b2@x.com", username="b2"); self.db.commit()
        with self.assertRaises(ValueError):
            models.AuthIdentity(user_id=u.id, provider="apple", subject="  ")


class OAuthResolutionTests(unittest.TestCase):
    def setUp(self): self.db, self.eng, self.path = _fresh_session()
    def tearDown(self): self.db.close(); os.remove(self.path)

    def _apple(self, subject=None, email=None, dob=None):
        return resolve_or_onboard_oauth(self.db, provider="apple", subject=subject,
                                        verified_email=email, display_name="A", date_of_birth=dob)

    def test_first_apple_creates_user_and_identity(self):
        r = self._apple(subject="S1", email="new@x.com", dob=ADULT)
        self.assertEqual(r["status"], "authenticated")
        self.assertIn("access_token", r)
        u = self.db.query(models.User).filter(models.User.email == "new@x.com").first()
        self.assertIsNotNone(u)
        self.assertIsNone(u.password_hash)  # provider-only: no fabricated password
        self.assertTrue(u.age_verified)
        ai = self.db.query(models.AuthIdentity).filter_by(provider="apple", subject="S1").first()
        self.assertEqual(ai.user_id, u.id)

    def test_returning_apple_resolves_by_subject_without_email(self):
        self._apple(subject="S1", email="new@x.com", dob=ADULT)
        r = self._apple(subject="S1", email=None, dob=None)   # email absent on return
        self.assertEqual(r["status"], "authenticated")

    def test_returning_apple_changed_email_same_user(self):
        r1 = self._apple(subject="S1", email="new@x.com", dob=ADULT)
        r2 = self._apple(subject="S1", email="relay@privaterelay.appleid.com", dob=None)
        self.assertEqual(r2["status"], "authenticated")
        self.assertEqual(self.db.query(models.User).count(), 1)  # no second account

    def test_unknown_subject_existing_email_conflict_no_autolink(self):
        _mk_user(self.db, "taken@x.com", username="local", password_hash="pw"); self.db.commit()
        r = self._apple(subject="NEW", email="Taken@x.com", dob=ADULT)
        self.assertEqual(r["status"], "account_conflict")
        # No new user, no identity created.
        self.assertEqual(self.db.query(models.User).count(), 1)
        self.assertEqual(self.db.query(models.AuthIdentity).count(), 0)

    def test_unknown_subject_no_email_identity_incomplete(self):
        r = self._apple(subject="S9", email=None, dob=ADULT)
        self.assertEqual(r["status"], "identity_incomplete")
        self.assertEqual(self.db.query(models.User).count(), 0)

    def test_no_subject_identity_incomplete(self):
        r = self._apple(subject=None, email="x@x.com", dob=ADULT)
        self.assertEqual(r["status"], "identity_incomplete")

    def test_new_identity_no_dob_requires_dob(self):
        r = self._apple(subject="S2", email="fresh@x.com", dob=None)
        self.assertEqual(r["status"], "dob_required")
        self.assertEqual(self.db.query(models.User).count(), 0)
        self.assertEqual(self.db.query(models.AuthIdentity).count(), 0)

    def test_under_13_rejected(self):
        with self.assertRaises(HTTPException) as ctx:
            self._apple(subject="S3", email="kid@x.com", dob=UNDER_13)
        self.assertEqual(ctx.exception.status_code, 400)
        self.assertEqual(self.db.query(models.User).count(), 0)

    def test_future_dob_rejected(self):
        with self.assertRaises(HTTPException):
            self._apple(subject="S4", email="f@x.com", dob=FUTURE)

    def test_boundary_just_over_13_ok(self):
        r = self._apple(subject="S5", email="teen@x.com", dob=JUST_OVER_13)
        self.assertEqual(r["status"], "authenticated")

    def test_different_subject_cannot_take_existing_by_email(self):
        self._apple(subject="OWNER", email="owned@x.com", dob=ADULT)
        r = self._apple(subject="ATTACKER", email="owned@x.com", dob=ADULT)
        self.assertEqual(r["status"], "account_conflict")

    # ── Gate 1.2 Round 2 — two-phase DOB completion + no-orphan rollback ─────────

    def test_dob_completion_same_identity_creates_one_account(self):
        """Two-phase Apple onboarding (dob_required -> retry with DOB) for the SAME
        (provider, subject) must create exactly one account. Mirrors the iOS retry
        that reuses the first AppleSignInResult (no second ASAuthorization)."""
        r1 = self._apple(subject="TWOPHASE", email="two@x.com", dob=None)
        self.assertEqual(r1["status"], "dob_required")
        self.assertEqual(self.db.query(models.User).count(), 0)  # nothing created yet

        r2 = self._apple(subject="TWOPHASE", email="two@x.com", dob=ADULT)
        self.assertEqual(r2["status"], "authenticated")
        self.assertEqual(
            self.db.query(models.User).filter(models.User.email == "two@x.com").count(), 1)
        self.assertEqual(
            self.db.query(models.AuthIdentity).filter_by(provider="apple", subject="TWOPHASE").count(), 1)

    def test_under_13_on_dob_completion_creates_nothing(self):
        """Second-phase retry with an under-13 DOB fails closed: 400, no account."""
        self.assertEqual(self._apple(subject="KIDPHASE", email="kid2@x.com", dob=None)["status"],
                         "dob_required")
        with self.assertRaises(HTTPException) as ctx:
            self._apple(subject="KIDPHASE", email="kid2@x.com", dob=UNDER_13)
        self.assertEqual(ctx.exception.status_code, 400)
        self.assertEqual(self.db.query(models.User).count(), 0)
        self.assertEqual(self.db.query(models.AuthIdentity).count(), 0)

    def test_failed_create_rolls_user_back_no_orphan(self):
        """If the atomic create fails at commit, the added User must NOT persist —
        no orphan User row and no dangling AuthIdentity."""
        real_commit = self.db.commit
        def boom():
            raise IntegrityError("forced create failure", None, Exception("forced"))
        self.db.commit = boom
        try:
            with self.assertRaises(IntegrityError):
                self._apple(subject="ORPHAN", email="orphan@x.com", dob=ADULT)
        finally:
            self.db.commit = real_commit
        self.db.rollback()
        self.assertEqual(
            self.db.query(models.User).filter(models.User.email == "orphan@x.com").count(), 0)
        self.assertEqual(
            self.db.query(models.AuthIdentity).filter_by(provider="apple", subject="ORPHAN").count(), 0)


class GoogleFailClosedTests(unittest.TestCase):
    def test_unconfigured_google_fails_closed(self):
        from routers.oauth import google_sign_in, OAuthLoginRequest
        os.environ.pop("GOOGLE_OAUTH_CLIENT_ID", None)
        db, eng, path = _fresh_session()
        try:
            req = OAuthLoginRequest(provider="google", id_token="anything", email="attacker@x.com")
            with self.assertRaises(HTTPException) as ctx:
                asyncio.get_event_loop().run_until_complete(google_sign_in(req, db))
            self.assertEqual(ctx.exception.status_code, 503)   # never trusts client email
            self.assertEqual(db.query(models.User).count(), 0)
        finally:
            db.close(); os.remove(path)


class OAuthIntegrityRecoveryTests(unittest.TestCase):
    """Deterministically exercise the ACTUAL IntegrityError / rollback / re-resolve
    branches in resolve_or_onboard_oauth (oauth.py STEP 5), not just the schema
    constraints or the pre-checks. A concurrent writer commits between our pre-check
    and our flush (injected at _unique_username_from_email, which runs after all
    pre-checks and before we add any row) so the DB constraint fires for real."""

    def _inject_race(self, Session, make_competitor):
        """Patch oauth._unique_username_from_email so that, on first call, a second
        session commits `make_competitor` before returning a real username."""
        from routers import oauth as oauth_mod
        orig = oauth_mod._unique_username_from_email
        def racing(db, email):
            B = Session()
            try:
                make_competitor(B, email)
                B.commit()
            finally:
                B.close()
            return orig(db, email)
        oauth_mod._unique_username_from_email = racing
        return oauth_mod, orig

    def test_email_unique_fire_recovers_account_conflict_no_orphan(self):
        Session, eng, path = _wal_sessionmaker()
        A = Session()
        def competitor(B, email):
            B.add(models.User(email=email, username="winner_local",
                              password_hash="pw", display_name="W", date_of_birth=ADULT))
        oauth_mod, orig = self._inject_race(Session, competitor)
        try:
            r = resolve_or_onboard_oauth(A, provider="apple", subject="RACE_EMAIL",
                                         verified_email="race@x.com", display_name="A",
                                         date_of_birth=ADULT)
            # UNIQUE(email) fired on our flush -> rollback -> re-resolve sees the email
            # now taken -> fail closed with account_conflict (never auto-links).
            self.assertEqual(r["status"], "account_conflict")
            self.assertEqual(A.query(models.User).filter(models.User.email == "race@x.com").count(), 1)
            self.assertEqual(
                A.query(models.AuthIdentity).filter_by(provider="apple", subject="RACE_EMAIL").count(), 0)
        finally:
            oauth_mod._unique_username_from_email = orig
            A.close(); eng.dispose(); os.remove(path)

    def test_provider_subject_unique_fire_recovers_authenticated_no_orphan(self):
        Session, eng, path = _wal_sessionmaker()
        A = Session()
        def competitor(B, _email):
            w = models.User(email="winner@x.com", username="winner_oauth",
                            password_hash=None, display_name="W", date_of_birth=ADULT,
                            age_verified=True, email_verified=True)
            B.add(w); B.flush()
            B.add(models.AuthIdentity(user_id=w.id, provider="apple", subject="RACE_SUBJ"))
        oauth_mod, orig = self._inject_race(Session, competitor)
        try:
            r = resolve_or_onboard_oauth(A, provider="apple", subject="RACE_SUBJ",
                                         verified_email="loser@x.com", display_name="A",
                                         date_of_birth=ADULT)
            # UNIQUE(provider,subject) fired on our insert -> rollback -> re-resolve finds
            # the winner's identity -> authenticated as the EXISTING account (no takeover).
            self.assertEqual(r["status"], "authenticated")
            self.assertEqual(
                A.query(models.AuthIdentity).filter_by(provider="apple", subject="RACE_SUBJ").count(), 1)
            self.assertEqual(A.query(models.User).filter(models.User.email == "loser@x.com").count(), 0)
            self.assertEqual(A.query(models.User).filter(models.User.email == "winner@x.com").count(), 1)
        finally:
            oauth_mod._unique_username_from_email = orig
            A.close(); eng.dispose(); os.remove(path)


class AppleEndpointFailClosedTests(unittest.TestCase):
    """The /auth/oauth/apple endpoint must fail closed when the identity token is
    not verifiable (expired / tampered) — 401 and NO partial account."""

    def _run_apple(self, db, verify_impl):
        from routers import oauth as oauth_mod
        from routers.oauth import apple_sign_in, OAuthLoginRequest
        orig = oauth_mod._verify_apple_id_token
        oauth_mod._verify_apple_id_token = verify_impl
        try:
            req = OAuthLoginRequest(provider="apple", id_token="tok", date_of_birth=ADULT)
            return asyncio.get_event_loop().run_until_complete(apple_sign_in(req, db))
        finally:
            oauth_mod._verify_apple_id_token = orig

    def test_expired_apple_token_fails_closed(self):
        async def _expired(_token):
            raise ValueError("Apple identity token has expired")
        db, eng, path = _fresh_session()
        try:
            with self.assertRaises(HTTPException) as ctx:
                self._run_apple(db, _expired)
            self.assertEqual(ctx.exception.status_code, 401)
            self.assertEqual(db.query(models.User).count(), 0)          # no partial account
            self.assertEqual(db.query(models.AuthIdentity).count(), 0)
        finally:
            db.close(); os.remove(path)

    def test_tampered_apple_token_fails_closed(self):
        async def _bad(_token):
            raise ValueError("Apple identity token verification failed")
        db, eng, path = _fresh_session()
        try:
            with self.assertRaises(HTTPException) as ctx:
                self._run_apple(db, _bad)
            self.assertEqual(ctx.exception.status_code, 401)
            self.assertEqual(db.query(models.User).count(), 0)
        finally:
            db.close(); os.remove(path)


class AccountDeletionIdentityTests(unittest.TestCase):
    def test_deletion_removes_auth_identity(self):
        from account_deletion import delete_user_account
        db, eng, path = _fresh_session()
        try:
            r = resolve_or_onboard_oauth(db, provider="apple", subject="DELME",
                                         verified_email="del@x.com", display_name="D", date_of_birth=ADULT)
            self.assertEqual(r["status"], "authenticated")
            u = db.query(models.User).filter(models.User.email == "del@x.com").first()
            uid = u.id  # capture before deletion (the instance is expired afterward)
            self.assertEqual(db.query(models.AuthIdentity).count(), 1)
            delete_user_account(db, u)
            self.assertEqual(db.query(models.AuthIdentity).count(), 0)
            self.assertEqual(db.query(models.User).filter(models.User.id == uid).count(), 0)
        finally:
            db.close(); os.remove(path)


class DevTransitionTests(unittest.TestCase):
    """Exercise the pre-Alembic transition helpers against a temp OLD-style DB."""
    def _old_style_db(self, dup=False):
        fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
        eng = create_engine(f"sqlite:///{path}", connect_args={"check_same_thread": False})
        with eng.begin() as c:
            c.execute(text("CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT NOT NULL, "
                           "username TEXT NOT NULL, password_hash TEXT NOT NULL, "
                           "date_of_birth TEXT, display_name TEXT)"))
            c.execute(text("INSERT INTO users VALUES ('1','a@x.com','a','h','2000-01-01','A')"))
            second = "a@x.com" if dup else "b@x.com"
            c.execute(text(f"INSERT INTO users VALUES ('2','{second}','b','h','2000-01-01','B')"))
            # Pre-existing email index (as the real dev DB had via the model's index=True)
            # so the rebuild's moved-index drop path is exercised.
            c.execute(text("CREATE INDEX ix_users_email ON users(email)"))
        return eng, path

    def test_preflight_aborts_on_duplicate_without_mutation(self):
        import migrate_gate12_identity as m
        eng, path = self._old_style_db(dup=True)
        try:
            with eng.connect() as conn:
                with self.assertRaises(SystemExit):
                    m._preflight_duplicate_emails(conn)
                # No auth_identities created — preflight ran before any change.
                self.assertNotIn("auth_identities", inspect(conn).get_table_names())
        finally:
            eng.dispose(); os.remove(path)

    def _mixed_email_db(self):
        """OLD-style DB with non-canonical legacy emails (mixed case / whitespace)
        that do NOT collide once normalized."""
        fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
        eng = create_engine(f"sqlite:///{path}", connect_args={"check_same_thread": False})
        with eng.begin() as c:
            c.execute(text("CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT NOT NULL, "
                           "username TEXT NOT NULL, password_hash TEXT NOT NULL, "
                           "date_of_birth TEXT, display_name TEXT)"))
            c.execute(text("INSERT INTO users VALUES ('1','Mixed@Case.COM','a','h','2000-01-01','A')"))
            c.execute(text("INSERT INTO users VALUES ('2','  spacey@x.com  ','b','h','2000-01-01','B')"))
            c.execute(text("INSERT INTO users VALUES ('3','already@x.com','c','h','2000-01-01','C')"))
            c.execute(text("CREATE INDEX ix_users_email ON users(email)"))
        return eng, path

    def test_email_backfill_canonicalizes_and_is_idempotent(self):
        import migrate_gate12_identity as m
        eng, path = self._mixed_email_db()
        try:
            with eng.begin() as conn:
                changed = m._canonicalize_existing_emails(conn)
            self.assertEqual(changed, 2)  # rows 1 and 2 rewritten; 3 already canonical
            with eng.connect() as conn:
                emails = {r[0]: r[1] for r in conn.execute(text("SELECT id, email FROM users")).fetchall()}
            self.assertEqual(emails["1"], "mixed@case.com")
            self.assertEqual(emails["2"], "spacey@x.com")
            self.assertEqual(emails["3"], "already@x.com")
            with eng.begin() as conn:            # idempotent second pass
                self.assertEqual(m._canonicalize_existing_emails(conn), 0)
        finally:
            eng.dispose(); os.remove(path)

    def test_full_transition_backfills_then_enforces_unique(self):
        """Integrated order (preflight -> auth_identities -> backfill -> rebuild ->
        unique index): legacy non-canonical email ends up canonical, password_hash
        becomes nullable, and the unique email index is present."""
        import migrate_gate12_identity as m
        eng, path = self._mixed_email_db()
        try:
            with eng.begin() as conn:
                m._preflight_duplicate_emails(conn)
                m._ensure_auth_identities(conn)
                m._canonicalize_existing_emails(conn)
                m._relax_password_hash_nullable(conn)
                m._ensure_unique_email_index(conn)
            with eng.connect() as conn:
                self.assertEqual(
                    conn.execute(text("SELECT email FROM users WHERE id='1'")).scalar(),
                    "mixed@case.com")
                cols = {c["name"]: c for c in inspect(conn).get_columns("users")}
                self.assertTrue(cols["password_hash"]["nullable"])
                self.assertTrue(any(ix["unique"] and ix["column_names"] == ["email"]
                                    for ix in inspect(conn).get_indexes("users")))
                self.assertEqual(conn.execute(text("SELECT COUNT(*) FROM users")).scalar(), 3)
        finally:
            eng.dispose(); os.remove(path)

    def test_preflight_still_aborts_when_normalized_forms_collide(self):
        """Two legacy rows that only differ by case/space must be caught by preflight
        BEFORE any backfill could merge them into a unique-constraint violation."""
        import migrate_gate12_identity as m
        fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
        eng = create_engine(f"sqlite:///{path}", connect_args={"check_same_thread": False})
        try:
            with eng.begin() as c:
                c.execute(text("CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT NOT NULL, "
                               "username TEXT NOT NULL, password_hash TEXT NOT NULL, "
                               "date_of_birth TEXT, display_name TEXT)"))
                c.execute(text("INSERT INTO users VALUES ('1','Dup@x.com','a','h','2000-01-01','A')"))
                c.execute(text("INSERT INTO users VALUES ('2','dup@x.com','b','h','2000-01-01','B')"))
            with eng.connect() as conn:
                with self.assertRaises(SystemExit):
                    m._preflight_duplicate_emails(conn)
        finally:
            eng.dispose(); os.remove(path)

    def test_failure_after_canonicalization_rolls_back(self):
        """A failure AFTER canonicalization but before completion leaves the DB in its
        valid pre-transition state — no half-applied email canonicalization."""
        import migrate_gate12_identity as m
        eng, path = self._mixed_email_db()
        m.enable_sqlite_transactional_ddl(eng); eng.dispose()  # atomic-DDL for new conns
        try:
            with self.assertRaises(RuntimeError):
                with eng.begin() as conn:
                    m._preflight_duplicate_emails(conn)
                    m._ensure_auth_identities(conn)
                    m._canonicalize_existing_emails(conn)      # mutates emails
                    raise RuntimeError("boom during rebuild stage")
            with eng.connect() as conn:
                self.assertEqual(
                    conn.execute(text("SELECT email FROM users WHERE id='1'")).scalar(),
                    "Mixed@Case.COM")                           # canonicalization rolled back
                self.assertNotIn("auth_identities", inspect(conn).get_table_names())
                self.assertEqual(conn.execute(text("SELECT COUNT(*) FROM users")).scalar(), 3)
        finally:
            eng.dispose(); os.remove(path)

    def test_failure_during_rebuild_restores_valid_schema(self):
        """A failure DURING the table rebuild (after RENAME) restores the original
        users table with every row and its original NOT NULL schema — no half-rebuilt
        table, no leftover users_old, no lost rows."""
        import migrate_gate12_identity as m
        eng, path = self._mixed_email_db()
        m.enable_sqlite_transactional_ddl(eng); eng.dispose()  # atomic-DDL for new conns
        orig_create = models.User.__table__.create
        def boom_create(*a, **k):
            raise RuntimeError("boom mid-rebuild")
        try:
            models.User.__table__.create = boom_create
            with self.assertRaises(RuntimeError):
                with eng.begin() as conn:
                    m._preflight_duplicate_emails(conn)
                    m._ensure_auth_identities(conn)
                    m._canonicalize_existing_emails(conn)
                    m._relax_password_hash_nullable(conn)       # RENAME then create() -> raises
        finally:
            models.User.__table__.create = orig_create
        with eng.connect() as conn:
            names = inspect(conn).get_table_names()
            self.assertIn("users", names)
            self.assertNotIn("users_old", names)                # no half-rebuilt leftover
            cols = {c["name"]: c for c in inspect(conn).get_columns("users")}
            self.assertFalse(cols["password_hash"]["nullable"]) # original schema restored
            self.assertEqual(conn.execute(text("SELECT COUNT(*) FROM users")).scalar(), 3)
            self.assertEqual(
                conn.execute(text("SELECT email FROM users WHERE id='1'")).scalar(),
                "Mixed@Case.COM")                               # canonicalization rolled back too
        eng.dispose(); os.remove(path)

    def test_transition_is_idempotent_and_relaxes_nullability(self):
        import migrate_gate12_identity as m
        eng, path = self._old_style_db(dup=False)
        try:
            with eng.begin() as conn:
                m._preflight_duplicate_emails(conn)
                m._ensure_auth_identities(conn)
                m._ensure_unique_email_index(conn)
                m._relax_password_hash_nullable(conn)
                # Idempotent second pass — no error, same end state.
                m._ensure_auth_identities(conn)
                m._ensure_unique_email_index(conn)
                m._relax_password_hash_nullable(conn)
            with eng.connect() as conn:
                cols = {c["name"]: c for c in inspect(conn).get_columns("users")}
                self.assertTrue(cols["password_hash"]["nullable"])
                self.assertIn("auth_identities", inspect(conn).get_table_names())
                self.assertEqual(conn.execute(text("SELECT COUNT(*) FROM users")).scalar(), 2)
        finally:
            eng.dispose(); os.remove(path)


if __name__ == "__main__":
    unittest.main()
