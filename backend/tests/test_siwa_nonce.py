"""Gate 1.3 — Sign in with Apple: nonce binding + token verification.

Two tiers of evidence:
  A. REAL CRYPTOGRAPHIC verification of `_verify_apple_id_token` using a locally
     generated RSA key + a fake JWKS served in place of Apple's. This exercises the
     actual jwt.decode path (RS256 pinning, iss/aud/exp, required nonce claim) and the
     new SHA-256 nonce binding. It is NOT live Apple authorization (that stays manual).
  B. ENDPOINT-level nonce plumbing through apple_sign_in + resolve_or_onboard_oauth,
     proving valid flow, mismatch/cross-attempt denial, and that the Gate 1.2 two-phase
     DOB completion (same token+nonce reused) still works and creates exactly one user.

Run from backend/:  ../.venv/bin/python -m unittest tests.test_siwa_nonce -v
"""
import asyncio
import json
import os
import sys
import time
import tempfile
import unittest
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import jwt
from jwt.algorithms import RSAAlgorithm
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from database import Base
import models
import models_premium  # noqa: F401
import routers.oauth as oauth_mod
from routers.oauth import _verify_apple_id_token, _sha256_hex, apple_sign_in, OAuthLoginRequest

ADULT = datetime(2000, 1, 1)
BUNDLE = oauth_mod.APPLE_BUNDLE_ID
ISS = "https://appleid.apple.com"

# One RSA key for the whole module; JWKS advertises its public half under kid=testkid.
_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_PRIV_PEM = _KEY.private_bytes(serialization.Encoding.PEM,
                              serialization.PrivateFormat.PKCS8,
                              serialization.NoEncryption())
_PUB_JWK = json.loads(RSAAlgorithm.to_jwk(_KEY.public_key()))
_PUB_JWK.update({"kid": "testkid", "alg": "RS256", "use": "sig"})
_JWKS = {"keys": [_PUB_JWK]}


class _FakeResp:
    def __init__(self, data, fail=False): self._d, self._fail = data, fail
    def raise_for_status(self):
        if self._fail: raise RuntimeError("JWKS 500")
    def json(self): return self._d


def _fake_client(fail=False):
    class _C:
        def __init__(self, *a, **k): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def get(self, url): return _FakeResp(_JWKS, fail=fail)
    return _C


def _make_token(*, raw_nonce="nonceRAW", nonce_hash="__use_raw__", aud=BUNDLE, iss=ISS,
                exp_delta=600, alg="RS256", kid="testkid", sub="apple-sub-123",
                email=None, include_nonce=True):
    now = int(time.time())
    claims = {"iss": iss, "aud": aud, "sub": sub, "iat": now, "exp": now + exp_delta}
    if include_nonce:
        claims["nonce"] = _sha256_hex(raw_nonce) if nonce_hash == "__use_raw__" else nonce_hash
    if email is not None:
        claims["email"] = email
    if alg == "RS256":
        return jwt.encode(claims, _PRIV_PEM, algorithm="RS256", headers={"kid": kid})
    # alg-confusion attempt: mint an HS256 token (attacker-controlled secret). The
    # verifier pins algorithms=["RS256"], so this must be rejected regardless of secret.
    return jwt.encode(claims, "attacker-hmac-secret", algorithm=alg, headers={"kid": kid})


def _verify(token, expected_nonce, fail_jwks=False):
    orig = oauth_mod.httpx.AsyncClient
    oauth_mod.httpx.AsyncClient = _fake_client(fail=fail_jwks)
    try:
        return asyncio.get_event_loop().run_until_complete(
            _verify_apple_id_token(token, expected_nonce=expected_nonce))
    finally:
        oauth_mod.httpx.AsyncClient = orig


class CryptoVerifyTests(unittest.TestCase):
    """Tier A — real RS256 signature + claim + nonce-binding verification."""

    def test_valid_token_and_nonce_passes(self):
        payload = _verify(_make_token(raw_nonce="abc"), expected_nonce="abc")
        self.assertEqual(payload["sub"], "apple-sub-123")

    def test_nonce_mismatch_rejected(self):
        with self.assertRaises(ValueError) as c:
            _verify(_make_token(raw_nonce="abc"), expected_nonce="different")
        self.assertIn("nonce", str(c.exception).lower())

    def test_missing_expected_nonce_rejected(self):
        with self.assertRaises(ValueError) as c:
            _verify(_make_token(raw_nonce="abc"), expected_nonce=None)
        self.assertIn("nonce", str(c.exception).lower())

    def test_token_without_nonce_claim_rejected(self):
        with self.assertRaises(ValueError):
            _verify(_make_token(include_nonce=False), expected_nonce="abc")

    def test_expired_token_rejected(self):
        with self.assertRaises(ValueError) as c:
            _verify(_make_token(raw_nonce="abc", exp_delta=-10), expected_nonce="abc")
        self.assertIn("expired", str(c.exception).lower())

    def test_wrong_audience_rejected(self):
        with self.assertRaises(ValueError) as c:
            _verify(_make_token(raw_nonce="abc", aud="com.evil.app"), expected_nonce="abc")
        self.assertIn("audience", str(c.exception).lower())

    def test_wrong_issuer_rejected(self):
        with self.assertRaises(ValueError):
            _verify(_make_token(raw_nonce="abc", iss="https://evil.example.com"), expected_nonce="abc")

    def test_alg_confusion_hs256_rejected(self):
        # A token whose header claims HS256 must never verify against the RSA key set.
        with self.assertRaises(ValueError):
            _verify(_make_token(raw_nonce="abc", alg="HS256"), expected_nonce="abc")

    def test_unknown_kid_rejected(self):
        with self.assertRaises(ValueError) as c:
            _verify(_make_token(raw_nonce="abc", kid="not-apple"), expected_nonce="abc")
        self.assertIn("public key", str(c.exception).lower())

    def test_jwks_fetch_failure_fails_closed(self):
        with self.assertRaises(ValueError) as c:
            _verify(_make_token(raw_nonce="abc"), expected_nonce="abc", fail_jwks=True)
        self.assertIn("jwks", str(c.exception).lower())


from datetime import timedelta
from routers.oauth import (_create_apple_attempt, _transition_attempt,
                           _load_live_attempt, _now)
from models import AuthAttempt, AuthAttemptStatus

UNDER_13 = datetime.now() - timedelta(days=int(365.25 * 10))


def _fresh_session():
    fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
    eng = create_engine(f"sqlite:///{path}", connect_args={"check_same_thread": False})
    Base.metadata.create_all(eng)
    return sessionmaker(bind=eng)(), path


class AttemptLifecycleTests(unittest.TestCase):
    """Tier B — server-bound single-use attempt lifecycle through the real endpoint."""

    def setUp(self):
        self._orig = oauth_mod.httpx.AsyncClient
        oauth_mod.httpx.AsyncClient = _fake_client()
        self.db, self.path = _fresh_session()

    def tearDown(self):
        oauth_mod.httpx.AsyncClient = self._orig
        self.db.close(); os.remove(self.path)

    def _attempt(self):
        return _create_apple_attempt(self.db)

    def _call(self, token, attempt_id, dob=None):
        req = OAuthLoginRequest(provider="apple", id_token=token, attempt_id=attempt_id,
                                nonce="client-echo-ignored", email=None, full_name="A",
                                date_of_birth=dob)
        return asyncio.get_event_loop().run_until_complete(apple_sign_in(req, self.db))

    def _status(self, attempt_id):
        return self.db.query(AuthAttempt).filter(AuthAttempt.id == attempt_id).first().status

    # ── valid flows ──────────────────────────────────────────────────────────
    def test_valid_first_time_with_dob_consumes_attempt(self):
        a = self._attempt()
        tok = _make_token(raw_nonce=a.nonce, sub="SUB1", email="a@x.com")
        r = self._call(tok, str(a.id), dob=ADULT)
        self.assertEqual(r["status"], "authenticated")
        self.assertEqual(self.db.query(models.User).filter(models.User.email == "a@x.com").count(), 1)
        self.assertEqual(self._status(a.id), AuthAttemptStatus.CONSUMED)

    def test_two_phase_dob_completion_one_user(self):
        a = self._attempt()
        tok = _make_token(raw_nonce=a.nonce, sub="SUB2", email="b@x.com")
        r1 = self._call(tok, str(a.id), dob=None)
        self.assertEqual(r1["status"], "dob_required")
        self.assertEqual(self._status(a.id), AuthAttemptStatus.AWAITING_DOB)
        self.assertEqual(self.db.query(models.User).count(), 0)
        r2 = self._call(tok, str(a.id), dob=ADULT)   # same token + same attempt
        self.assertEqual(r2["status"], "authenticated")
        self.assertEqual(self.db.query(models.User).filter(models.User.email == "b@x.com").count(), 1)
        self.assertEqual(self._status(a.id), AuthAttemptStatus.CONSUMED)

    # ── attempt existence / expiry ───────────────────────────────────────────
    def test_missing_attempt_id_401(self):
        tok = _make_token(raw_nonce="x", sub="S", email="m@x.com")
        with self.assertRaises(HTTPException) as c:
            self._call(tok, None, dob=ADULT)
        self.assertEqual(c.exception.status_code, 401)

    def test_unknown_attempt_401(self):
        tok = _make_token(raw_nonce="x", sub="S", email="u@x.com")
        with self.assertRaises(HTTPException) as c:
            self._call(tok, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", dob=ADULT)
        self.assertEqual(c.exception.status_code, 401)

    def test_expired_attempt_401(self):
        a = self._attempt()
        a.expires_at = datetime.utcnow() - timedelta(minutes=1); self.db.commit()
        tok = _make_token(raw_nonce=a.nonce, sub="S", email="e@x.com")
        with self.assertRaises(HTTPException) as c:
            self._call(tok, str(a.id), dob=ADULT)
        self.assertEqual(c.exception.status_code, 401)
        self.assertEqual(self.db.query(models.User).count(), 0)

    # ── replay / substitution ────────────────────────────────────────────────
    def test_replay_after_redemption_rejected(self):
        a = self._attempt()
        tok = _make_token(raw_nonce=a.nonce, sub="SUB3", email="r@x.com")
        self.assertEqual(self._call(tok, str(a.id), dob=ADULT)["status"], "authenticated")
        with self.assertRaises(HTTPException) as c:   # identical token+attempt again
            self._call(tok, str(a.id), dob=ADULT)
        self.assertEqual(c.exception.status_code, 401)

    def test_cross_attempt_nonce_mismatch_rejected(self):
        a, b = self._attempt(), self._attempt()
        tok = _make_token(raw_nonce=a.nonce, sub="SUB4", email="x@x.com")  # bound to A
        with self.assertRaises(HTTPException) as c:
            self._call(tok, str(b.id), dob=ADULT)                          # submitted with B
        self.assertEqual(c.exception.status_code, 401)

    def test_cross_identity_substitution_on_completion_rejected(self):
        a = self._attempt()
        tok1 = _make_token(raw_nonce=a.nonce, sub="IDENTITY_A", email="ca@x.com")
        self.assertEqual(self._call(tok1, str(a.id), dob=None)["status"], "dob_required")
        # Different Apple subject, same (still-live) attempt nonce -> identity mismatch.
        tok2 = _make_token(raw_nonce=a.nonce, sub="IDENTITY_B", email="cb@x.com")
        with self.assertRaises(HTTPException) as c:
            self._call(tok2, str(a.id), dob=ADULT)
        self.assertEqual(c.exception.status_code, 401)

    # ── concurrency (single terminal transition) ─────────────────────────────
    def test_only_one_terminal_transition_wins(self):
        a = self._attempt()
        first = _transition_attempt(self.db, a.id, AuthAttemptStatus.PENDING, AuthAttemptStatus.CONSUMED)
        second = _transition_attempt(self.db, a.id, AuthAttemptStatus.PENDING, AuthAttemptStatus.CONSUMED)
        self.assertTrue(first)
        self.assertFalse(second)   # attempt already CONSUMED -> guarded UPDATE affects 0 rows

    # ── DOB completion failure paths ─────────────────────────────────────────
    def test_under_13_consumes_attempt_no_user(self):
        a = self._attempt()
        tok = _make_token(raw_nonce=a.nonce, sub="SUB5", email="kid@x.com")
        with self.assertRaises(HTTPException) as c:
            self._call(tok, str(a.id), dob=UNDER_13)
        self.assertEqual(c.exception.status_code, 400)
        self.assertEqual(self.db.query(models.User).count(), 0)
        self.assertEqual(self._status(a.id), AuthAttemptStatus.CONSUMED)   # cannot retry

    def test_malformed_attempt_id_fails_closed(self):
        tok = _make_token(raw_nonce="x", sub="S", email="mal@x.com")
        with self.assertRaises(HTTPException) as c:
            self._call(tok, "not-a-uuid", dob=ADULT)   # non-UUID -> unknown attempt
        self.assertEqual(c.exception.status_code, 401)

    def test_attempt_endpoint_mints_pending(self):
        from routers.oauth import create_apple_attempt
        oauth_mod._attempt_alloc_log.clear()
        class _Client: host = "127.0.0.1"
        class _Req: client = _Client()
        resp = asyncio.get_event_loop().run_until_complete(create_apple_attempt(_Req(), self.db))
        self.assertTrue(resp.attempt_id and resp.nonce)
        self.assertEqual(self._status(resp.attempt_id), AuthAttemptStatus.PENDING)

    def test_account_conflict_consumes_attempt(self):
        # A new Apple subject presenting an email already held by a local account -> conflict,
        # never auto-link (Gate 1.2). The attempt is consumed so it can't be retried.
        u = models.User(email="taken@x.com", username="localu", password_hash="pw",
                        display_name="L", date_of_birth=ADULT)
        self.db.add(u); self.db.commit()
        a = self._attempt()
        tok = _make_token(raw_nonce=a.nonce, sub="NEWSUB", email="taken@x.com")
        r = self._call(tok, str(a.id), dob=ADULT)
        self.assertEqual(r["status"], "account_conflict")
        self.assertEqual(self._status(a.id), AuthAttemptStatus.CONSUMED)

    def test_expired_completion_rejected(self):
        a = self._attempt()
        tok = _make_token(raw_nonce=a.nonce, sub="SUB6", email="dc@x.com")
        self.assertEqual(self._call(tok, str(a.id), dob=None)["status"], "dob_required")
        a2 = self.db.query(AuthAttempt).filter(AuthAttempt.id == a.id).first()
        a2.expires_at = datetime.utcnow() - timedelta(minutes=1); self.db.commit()
        with self.assertRaises(HTTPException) as c:
            self._call(tok, str(a.id), dob=ADULT)
        self.assertEqual(c.exception.status_code, 401)
        self.assertEqual(self.db.query(models.User).count(), 0)

    def test_lost_response_after_redemption_forces_reauth(self):
        # A successful redemption whose HTTP response is lost: the client retries the SAME
        # attempt+token. It must NOT silently mint a second session — the consumed attempt
        # is rejected (401), forcing a fresh sign-in (new attempt).
        a = self._attempt()
        tok = _make_token(raw_nonce=a.nonce, sub="LOST", email="lost@x.com")
        self.assertEqual(self._call(tok, str(a.id), dob=ADULT)["status"], "authenticated")
        users_after_first = self.db.query(models.User).count()
        with self.assertRaises(HTTPException) as c:
            self._call(tok, str(a.id), dob=ADULT)               # lost-response retry
        self.assertEqual(c.exception.status_code, 401)
        self.assertEqual(self.db.query(models.User).count(), users_after_first)  # no 2nd grant


# ─────────────────────────────────────────────────────────────────────────────
# Concurrency — competing redemption / DOB binding across INDEPENDENT sessions.
# SQLite serializes writers, so this proves the WHERE-guarded UPDATE admits exactly one
# winner; true parallel row-locking on Postgres remains Gate 2.1A.
# ─────────────────────────────────────────────────────────────────────────────

def _wal_engine():
    fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
    eng = create_engine(f"sqlite:///{path}", connect_args={"check_same_thread": False})
    with eng.connect() as c:
        c.exec_driver_sql("PRAGMA journal_mode=WAL")   # concurrent readers, serialized writers
    Base.metadata.create_all(eng)
    return eng, path


class AttemptConcurrencyTests(unittest.TestCase):
    def setUp(self):
        self.eng, self.path = _wal_engine()
        self.S = sessionmaker(bind=self.eng)

    def tearDown(self):
        self.eng.dispose(); os.remove(self.path)

    def _seed(self):
        s = self.S(); aid = _create_apple_attempt(s).id; s.close(); return aid

    def test_competing_consumption_only_one_wins(self):
        aid = self._seed()
        A, B = self.S(), self.S()
        try:
            # Both independent sessions observe PENDING before either writes.
            self.assertEqual(A.get(AuthAttempt, aid).status, AuthAttemptStatus.PENDING)
            self.assertEqual(B.get(AuthAttempt, aid).status, AuthAttemptStatus.PENDING)
            wonA = _transition_attempt(A, aid, AuthAttemptStatus.PENDING, AuthAttemptStatus.CONSUMED)
            wonB = _transition_attempt(B, aid, AuthAttemptStatus.PENDING, AuthAttemptStatus.CONSUMED)
            self.assertTrue(wonA)
            self.assertFalse(wonB)      # loser: guarded UPDATE matched 0 rows -> no session
        finally:
            A.close(); B.close()

    def test_competing_dob_binding_does_not_overwrite_subject(self):
        aid = self._seed()
        A, B = self.S(), self.S()
        try:
            wonA = _transition_attempt(A, aid, AuthAttemptStatus.PENDING,
                                       AuthAttemptStatus.AWAITING_DOB, subject="SUBJ_A")
            wonB = _transition_attempt(B, aid, AuthAttemptStatus.PENDING,
                                       AuthAttemptStatus.AWAITING_DOB, subject="SUBJ_B")
            self.assertTrue(wonA)
            self.assertFalse(wonB)
            C = self.S()
            try:
                self.assertEqual(C.get(AuthAttempt, aid).subject, "SUBJ_A")   # loser cannot overwrite
            finally:
                C.close()
        finally:
            A.close(); B.close()


class AtomicIdentityRedemptionTests(unittest.TestCase):
    """Identity mutation + terminal consumption commit atomically (one transaction); a
    session is issued only after that single commit succeeds."""

    def setUp(self):
        self._orig = oauth_mod.httpx.AsyncClient
        oauth_mod.httpx.AsyncClient = _fake_client()
        self.db, self.path = _fresh_session()

    def tearDown(self):
        oauth_mod.httpx.AsyncClient = self._orig
        self.db.close(); os.remove(self.path)

    def _run(self, req, db=None):
        return asyncio.get_event_loop().run_until_complete(apple_sign_in(req, db or self.db))

    def _req(self, tok, aid, dob=ADULT):
        return OAuthLoginRequest(provider="apple", id_token=tok, attempt_id=str(aid),
                                 nonce="x", email=None, full_name="A", date_of_birth=dob)

    def test_failure_before_consume_persists_nothing_and_retry_succeeds(self):
        # Inject a failure AFTER identity mutation is staged but BEFORE consumption: because
        # the mutation is only flushed (not committed), request teardown discards it — no user,
        # no identity, no session. A retry then succeeds and consumes exactly once.
        a = _create_apple_attempt(self.db)
        tok = _make_token(raw_nonce=a.nonce, sub="INJ", email="inj@x.com")
        req = self._req(tok, a.id)
        orig = oauth_mod._transition_attempt
        oauth_mod._transition_attempt = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("crash"))
        try:
            with self.assertRaises(RuntimeError):
                self._run(req)
        finally:
            oauth_mod._transition_attempt = orig
        self.db.rollback()                                   # emulate get_db teardown
        self.assertEqual(self.db.query(models.User).filter_by(email="inj@x.com").count(), 0)
        self.assertEqual(self.db.query(models.AuthIdentity).filter_by(subject="INJ").count(), 0)
        self.assertEqual(self.db.query(AuthAttempt).filter(AuthAttempt.id == a.id).first().status,
                         AuthAttemptStatus.PENDING)
        r = self._run(req)                                   # retry
        self.assertEqual(r["status"], "authenticated")
        self.assertEqual(self.db.query(models.User).filter_by(email="inj@x.com").count(), 1)
        self.assertEqual(self.db.query(AuthAttempt).filter(AuthAttempt.id == a.id).first().status,
                         AuthAttemptStatus.CONSUMED)

    def test_losing_consume_rolls_back_new_identity(self):
        # First-time identity staged, then the guarded consume loses the race (False): the
        # endpoint rolls back — NO user/identity persists, NO session, attempt stays PENDING.
        a = _create_apple_attempt(self.db)
        tok = _make_token(raw_nonce=a.nonce, sub="LOSER", email="loser@x.com")
        orig = oauth_mod._transition_attempt
        oauth_mod._transition_attempt = lambda *a, **k: False
        try:
            with self.assertRaises(HTTPException) as c:
                self._run(self._req(tok, a.id))
            self.assertEqual(c.exception.status_code, 401)
        finally:
            oauth_mod._transition_attempt = orig
        self.db.rollback()
        self.assertEqual(self.db.query(models.User).filter_by(email="loser@x.com").count(), 0)
        self.assertEqual(self.db.query(models.AuthIdentity).filter_by(subject="LOSER").count(), 0)
        self.assertEqual(self.db.query(AuthAttempt).filter(AuthAttempt.id == a.id).first().status,
                         AuthAttemptStatus.PENDING)

    def test_commit_failure_returns_no_session(self):
        a = _create_apple_attempt(self.db)
        tok = _make_token(raw_nonce=a.nonce, sub="CF", email="cf@x.com")
        orig_commit = self.db.commit
        def _bad(): raise RuntimeError("commit failed")
        self.db.commit = _bad
        try:
            with self.assertRaises(HTTPException) as c:
                self._run(self._req(tok, a.id))
            self.assertEqual(c.exception.status_code, 401)
        finally:
            self.db.commit = orig_commit
        self.db.rollback()
        self.assertEqual(self.db.query(models.User).filter_by(email="cf@x.com").count(), 0)

    def test_competing_endpoint_requests_only_winner_issues_session(self):
        # Endpoint-level (distinct from the isolated guarded-UPDATE tests): two INDEPENDENT
        # sessions redeem the SAME attempt+token. Exactly one authenticates and persists one
        # user; the other is refused and leaves no identity mutation.
        from sqlalchemy import create_engine
        from sqlalchemy.orm import sessionmaker
        fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
        eng = create_engine(f"sqlite:///{path}", connect_args={"check_same_thread": False})
        with eng.connect() as c:
            c.exec_driver_sql("PRAGMA journal_mode=WAL")
        Base.metadata.create_all(eng)
        S = sessionmaker(bind=eng)
        setup = S(); a = _create_apple_attempt(setup); aid, nonce = a.id, a.nonce; setup.close()
        tok = _make_token(raw_nonce=nonce, sub="COMPETE", email="compete@x.com")
        A, B = S(), S()
        try:
            r1 = self._run(self._req(tok, aid), db=A)
            self.assertEqual(r1["status"], "authenticated")
            with self.assertRaises(HTTPException) as c:
                self._run(self._req(tok, aid), db=B)
            self.assertEqual(c.exception.status_code, 401)      # loser refused
        finally:
            A.close(); B.close()
        v = S()
        try:
            self.assertEqual(v.query(models.User).filter_by(email="compete@x.com").count(), 1)
            self.assertEqual(v.query(AuthAttempt).filter(AuthAttempt.id == aid).first().status,
                             AuthAttemptStatus.CONSUMED)
        finally:
            v.close(); eng.dispose(); os.remove(path)


class AttemptEndpointSafeguardTests(unittest.TestCase):
    """Local (single-worker) attempt-allocation rate limit + bounded cleanup."""

    def setUp(self):
        self.db, self.path = _fresh_session()
        oauth_mod._attempt_alloc_log.clear()

    def tearDown(self):
        self.db.close(); os.remove(self.path)
        oauth_mod._attempt_alloc_log.clear()

    def _create(self, ip):
        class _Client: host = ip
        class _Req: client = _Client()
        return asyncio.get_event_loop().run_until_complete(
            oauth_mod.create_apple_attempt(_Req(), self.db))

    def test_rate_limited_request_creates_no_row(self):
        ip = "203.0.113.7"
        for _ in range(oauth_mod._ATTEMPT_MAX_PER_WINDOW):
            self._create(ip)
        before = self.db.query(AuthAttempt).count()
        with self.assertRaises(HTTPException) as c:
            self._create(ip)                                   # over the limit
        self.assertEqual(c.exception.status_code, 429)
        self.assertEqual(self.db.query(AuthAttempt).count(), before)   # rejected -> no new row

    def test_prune_is_bounded_per_call(self):
        orig = oauth_mod._PRUNE_BATCH_LIMIT
        oauth_mod._PRUNE_BATCH_LIMIT = 5
        try:
            past = datetime.utcnow() - timedelta(minutes=1)
            for i in range(12):
                self.db.add(AuthAttempt(provider="apple", nonce=f"n{i}",
                                        status=AuthAttemptStatus.PENDING, expires_at=past))
            self.db.commit()
            self.assertEqual(oauth_mod._prune_expired_attempts(self.db), 5)   # bounded
            self.assertEqual(oauth_mod._prune_expired_attempts(self.db), 5)
            self.assertEqual(oauth_mod._prune_expired_attempts(self.db), 2)   # drains remainder
            self.assertEqual(self.db.query(AuthAttempt).count(), 0)
        finally:
            oauth_mod._PRUNE_BATCH_LIMIT = orig


class AttemptTTLTests(unittest.TestCase):
    def setUp(self):
        self._orig = oauth_mod.httpx.AsyncClient
        oauth_mod.httpx.AsyncClient = _fake_client()
        self.db, self.path = _fresh_session()

    def tearDown(self):
        oauth_mod.httpx.AsyncClient = self._orig
        self.db.close(); os.remove(self.path)

    def _call(self, token, attempt_id, dob=None):
        req = OAuthLoginRequest(provider="apple", id_token=token, attempt_id=attempt_id,
                                nonce="x", email=None, full_name="A", date_of_birth=dob)
        return asyncio.get_event_loop().run_until_complete(apple_sign_in(req, self.db))

    def _exp(self, aid):
        return self.db.query(AuthAttempt).filter(AuthAttempt.id == aid).first().expires_at

    def test_dob_retry_does_not_extend_deadline(self):
        # DOB_TTL starts once at PENDING->AWAITING_DOB; a subsequent dob_required retry stays
        # AWAITING_DOB (guarded UPDATE matches 0 rows) and must NOT push the deadline out.
        a = _create_apple_attempt(self.db)
        tok = _make_token(raw_nonce=a.nonce, sub="TTL1", email="t1@x.com")
        self.assertEqual(self._call(tok, str(a.id), dob=None)["status"], "dob_required")
        exp1 = self._exp(a.id)
        self.assertEqual(self._call(tok, str(a.id), dob=None)["status"], "dob_required")
        self.assertEqual(self._exp(a.id), exp1)          # deadline unchanged by retry

    def test_completion_requires_still_valid_apple_token(self):
        # The attempt's DOB window can still be open while the reused Apple id_token has
        # expired; completion re-verifies the token and refuses (401).
        a = _create_apple_attempt(self.db)
        live = _make_token(raw_nonce=a.nonce, sub="TTL2", email="t2@x.com")
        self.assertEqual(self._call(live, str(a.id), dob=None)["status"], "dob_required")
        expired = _make_token(raw_nonce=a.nonce, sub="TTL2", email="t2@x.com", exp_delta=-10)
        with self.assertRaises(HTTPException) as c:
            self._call(expired, str(a.id), dob=ADULT)
        self.assertEqual(c.exception.status_code, 401)
        self.assertEqual(self.db.query(models.User).count(), 0)

    def test_expiry_boundary_future_ok_past_rejected(self):
        # _load_live_attempt uses strict `expires_at < now`: a future deadline is live,
        # a past one is rejected.
        a = _create_apple_attempt(self.db)
        a.expires_at = _now() + timedelta(seconds=30); self.db.commit()
        self.assertIsNotNone(_load_live_attempt(self.db, str(a.id), "apple"))
        a.expires_at = _now() - timedelta(seconds=1); self.db.commit()
        with self.assertRaises(HTTPException) as c:
            _load_live_attempt(self.db, str(a.id), "apple")
        self.assertEqual(c.exception.status_code, 401)


class JWTParseNegativeTests(unittest.TestCase):
    """The two previously-uncovered defensive JWT-parse branches, driven as security boundaries."""

    def test_malformed_token_rejected(self):          # oauth.py 100-102 (DecodeError)
        with self.assertRaises(ValueError) as c:
            _verify("this-is-not-a-jwt", expected_nonce="abc")
        self.assertIn("malformed", str(c.exception).lower())

    def test_corrupt_jwk_fails_closed(self):          # oauth.py 110-113 (from_jwk failure)
        corrupt = {"keys": [{"kid": "testkid", "kty": "RSA", "alg": "RS256",
                             "use": "sig", "n": "@@@not-base64@@@", "e": "AQAB"}]}

        class _C:
            def __init__(self, *a, **k): pass
            async def __aenter__(self): return self
            async def __aexit__(self, *a): return False
            async def get(self, url): return _FakeResp(corrupt)

        orig = oauth_mod.httpx.AsyncClient
        oauth_mod.httpx.AsyncClient = _C
        try:
            tok = _make_token(raw_nonce="abc")        # real signature, kid=testkid
            with self.assertRaises(ValueError) as c:
                asyncio.get_event_loop().run_until_complete(
                    _verify_apple_id_token(tok, expected_nonce="abc"))
            self.assertIn("rsa public key", str(c.exception).lower())
        finally:
            oauth_mod.httpx.AsyncClient = orig


if __name__ == "__main__":
    unittest.main()
