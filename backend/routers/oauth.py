# OAuth authentication endpoints for Apple Sign-In
# Google Sign-In requires the Google Sign-In SDK on iOS — backend stub kept for future use.

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from collections import defaultdict
import httpx
import jwt
from jwt.algorithms import RSAAlgorithm
from datetime import datetime, timedelta
import hashlib
import os
import secrets

from sqlalchemy.exc import IntegrityError

from database import get_db
import models
from models import AuthAttempt, AuthAttemptStatus
from auth import create_access_token
from schemas import Token
from identity import normalize_email, canonical_provider, is_valid_signup_dob
import text_policy

router = APIRouter(prefix="/auth/oauth", tags=["OAuth"])

# Apple validates against this audience claim in the JWT.
# Set APPLE_BUNDLE_ID env var in production (e.g. "com.royaltonitservices.SportsHub").
APPLE_BUNDLE_ID = os.environ.get("APPLE_BUNDLE_ID", "com.royaltonitservices.SportsHub")
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"

# Server-bound authentication-attempt lifetimes. The PENDING window must comfortably
# cover the user completing Apple auth (Apple id_tokens are themselves short-lived); the
# AWAITING_DOB window covers the user typing a birth date on first-time onboarding.
ATTEMPT_TTL = timedelta(minutes=10)
DOB_TTL = timedelta(minutes=15)

# Local (in-process) abuse control for attempt allocation, mirroring the login limiter in
# routers/auth.py. Keyed by client IP; resets on restart. This is a SINGLE-WORKER guard —
# it does NOT bound storage across multiple workers/hosts. Distributed limiting + globally
# bounded storage is Gate 2.4.
_ATTEMPT_MAX_PER_WINDOW: int = 20
_ATTEMPT_WINDOW_SECONDS: int = 60
_PRUNE_BATCH_LIMIT: int = 500                        # bound the work of each cleanup pass
_attempt_alloc_log: dict[str, list[datetime]] = defaultdict(list)   # client IP → alloc timestamps


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------

class AttemptResponse(BaseModel):
    attempt_id: str
    nonce: str          # server-issued RAW nonce; the app hashes it into the ASAuthorization request


class OAuthLoginRequest(BaseModel):
    provider: str           # "apple" or "google"
    id_token: str
    attempt_id: Optional[str] = None       # server-bound attempt id (Gate 1.3); required for Apple
    nonce: Optional[str] = None            # RAW nonce echoed by the client; server trusts the STORED attempt nonce
    email: Optional[str] = None            # display/first-time hint ONLY — never used as identity
    full_name: Optional[str] = None
    date_of_birth: Optional[datetime] = None   # required only on first-time onboarding


# ---------------------------------------------------------------------------
# Apple JWKS verification helper
# ---------------------------------------------------------------------------

def _sha256_hex(value: str) -> str:
    """SHA-256 hex digest — the transform Apple applies to the request nonce before
    embedding it as the id_token `nonce` claim."""
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


async def _verify_apple_id_token(id_token: str, expected_nonce: Optional[str]) -> dict:
    """
    Verify an Apple identity token (JWT) against Apple's published public keys and bind
    it to THIS login attempt via the nonce.

    Steps:
    1. Fetch Apple's JWKS from https://appleid.apple.com/auth/keys
    2. Match the token's `kid` header to a key in the set
    3. Decode and verify the JWT (RS256 only) using that RSA public key
    4. Validate iss = "https://appleid.apple.com", aud = APPLE_BUNDLE_ID, exp, and
       require the `nonce` claim to be present
    5. Bind: require `nonce` claim == SHA-256(expected_nonce). The client sends the RAW
       per-authorization nonce; the app put SHA-256(nonce) into the ASAuthorization
       request, so Apple embedded that hash as the token's nonce claim. We never trust a
       client-asserted "match" — we derive the expected hash from the client's preimage
       and compare it to Apple's signed claim.

    Returns the decoded JWT payload on success.
    Raises ValueError on any verification failure (fail-closed).
    """
    if not expected_nonce:
        raise ValueError("Missing nonce for Apple Sign-In")
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(APPLE_JWKS_URL)
            response.raise_for_status()
            jwks = response.json()
    except Exception as exc:
        raise ValueError(f"Failed to fetch Apple JWKS: {exc}") from exc

    # Read the key ID from the token header (unverified at this stage)
    try:
        header = jwt.get_unverified_header(id_token)
    except jwt.DecodeError as exc:
        raise ValueError(f"Malformed Apple identity token: {exc}") from exc

    kid = header.get("kid")
    matching_key = next((k for k in jwks.get("keys", []) if k.get("kid") == kid), None)
    if not matching_key:
        raise ValueError(f"No Apple public key found for kid={kid!r}")

    # Convert the JWK to an RSA public key object
    try:
        public_key = RSAAlgorithm.from_jwk(matching_key)
    except Exception as exc:
        raise ValueError(f"Failed to build RSA public key from Apple JWK: {exc}") from exc

    # Decode and verify the token
    try:
        payload = jwt.decode(
            id_token,
            public_key,
            algorithms=["RS256"],
            audience=APPLE_BUNDLE_ID,
            issuer="https://appleid.apple.com",
            options={"require": ["sub", "iat", "exp", "nonce"]},
        )
    except jwt.ExpiredSignatureError:
        raise ValueError("Apple identity token has expired")
    except jwt.InvalidAudienceError:
        raise ValueError(
            f"Apple token audience mismatch — expected {APPLE_BUNDLE_ID!r}. "
            "Set APPLE_BUNDLE_ID env var to your app's bundle ID."
        )
    except jwt.PyJWTError as exc:
        raise ValueError(f"Apple identity token verification failed: {exc}") from exc

    # Nonce binding: the signed `nonce` claim must equal SHA-256(expected_nonce).
    # Reject missing or mismatched — this prevents replaying an Apple id_token obtained
    # in a different authorization context to this endpoint.
    token_nonce = payload.get("nonce")
    if not token_nonce or token_nonce != _sha256_hex(expected_nonce):
        raise ValueError("Apple identity token nonce mismatch")

    return payload


# ---------------------------------------------------------------------------
# Server-bound authentication attempts (Gate 1.3 replay resistance)
# ---------------------------------------------------------------------------

def _now() -> datetime:
    return datetime.utcnow()


def _prune_expired_attempts(db: Session) -> int:
    """Delete up to `_PRUNE_BATCH_LIMIT` expired attempts. Best-effort, runs on each new
    attempt. Each call is BOUNDED so cleanup can never become an unbounded operation; if a
    large backlog exists it drains a batch per attempt over time. Returns rows deleted."""
    ids = [row[0] for row in db.query(AuthAttempt.id)
           .filter(AuthAttempt.expires_at < _now())
           .limit(_PRUNE_BATCH_LIMIT).all()]
    if not ids:
        return 0
    deleted = db.query(AuthAttempt).filter(AuthAttempt.id.in_(ids)).delete(synchronize_session=False)
    db.commit()
    return deleted


def _check_attempt_rate_limit(client_ip: str) -> None:
    """Raise 429 if this client has allocated too many attempts recently. Prunes its own
    window in place (bounded by the window). Enforced BEFORE any row is allocated."""
    now = _now()
    cutoff = now - timedelta(seconds=_ATTEMPT_WINDOW_SECONDS)
    recent = [t for t in _attempt_alloc_log[client_ip] if t > cutoff]
    _attempt_alloc_log[client_ip] = recent
    if len(recent) >= _ATTEMPT_MAX_PER_WINDOW:
        wait = max(int((recent[0] + timedelta(seconds=_ATTEMPT_WINDOW_SECONDS) - now).total_seconds()), 1)
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                            detail="Too many sign-in attempts. Please wait a moment.",
                            headers={"Retry-After": str(wait)})
    _attempt_alloc_log[client_ip].append(now)


def _create_apple_attempt(db: Session) -> AuthAttempt:
    _prune_expired_attempts(db)
    attempt = AuthAttempt(
        provider="apple",
        nonce=secrets.token_urlsafe(32),          # unpredictable server-issued nonce
        status=AuthAttemptStatus.PENDING,
        expires_at=_now() + ATTEMPT_TTL,
    )
    db.add(attempt)
    db.commit()
    db.refresh(attempt)
    return attempt


def _load_live_attempt(db: Session, attempt_id, provider: str) -> AuthAttempt:
    """Load a redeemable attempt or raise 401 — rejects missing/unknown/expired/consumed."""
    if not attempt_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Missing authentication attempt")
    try:
        attempt = db.query(AuthAttempt).filter(AuthAttempt.id == attempt_id).first()
    except Exception:
        attempt = None       # malformed attempt id (e.g. not a UUID) -> unknown
    if attempt is None or canonical_provider(attempt.provider) != canonical_provider(provider):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Unknown authentication attempt")
    if attempt.status == AuthAttemptStatus.CONSUMED:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Authentication attempt already used")
    if attempt.expires_at < _now():
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Authentication attempt expired")
    return attempt


def _transition_attempt(db: Session, attempt_id, from_status, to_status, *, subject=None,
                        commit: bool = True) -> bool:
    """Atomically move an attempt from `from_status` to `to_status` via a WHERE-guarded
    UPDATE, so only ONE concurrent caller can perform a given transition. Returns True iff
    this caller won it (rowcount == 1).

    When `commit=False` the guarded UPDATE is STAGED in the caller's transaction and NOT
    committed here — so the caller can commit it atomically together with the identity
    mutation (single transaction: identity + consumption commit together, or neither)."""
    values = {AuthAttempt.status: to_status}
    if to_status == AuthAttemptStatus.CONSUMED:
        values[AuthAttempt.consumed_at] = _now()
    if to_status == AuthAttemptStatus.AWAITING_DOB:
        values[AuthAttempt.expires_at] = _now() + DOB_TTL
    if subject is not None:
        values[AuthAttempt.subject] = subject
    rows = db.query(AuthAttempt).filter(
        AuthAttempt.id == attempt_id,
        AuthAttempt.status == from_status,
    ).update(values, synchronize_session=False)
    if commit:
        db.commit()
    return rows == 1


# ---------------------------------------------------------------------------
# Helper: find or create a user from OAuth credentials
# ---------------------------------------------------------------------------

def _session_for(user: "models.User") -> dict:
    """The authenticated envelope for a resolved user."""
    return {
        "status": "authenticated",
        "access_token": create_access_token(data={"sub": str(user.id)}),
        "token_type": "bearer",
    }


def _uniquify_username(db: Session, base: str) -> str:
    """Return `base`, or `base{n}` for the smallest free n — the existing collision-recovery
    contract shared by every generated username."""
    username = base
    counter = 1
    while db.query(models.User).filter(models.User.username == username).first():
        username = f"{base}{counter}"
        counter += 1
    return username


def _unique_username_from_email(db: Session, email: str) -> str:
    base = (email.split("@")[0].replace(".", "_").replace("+", "_")[:40]) or "athlete"
    return _uniquify_username(db, base)


def _neutral_username(db: Session) -> str:
    """A policy-safe username generated INDEPENDENTLY of email contents, used as the fallback when
    the email-derived candidate would publish objectionable language. Same format + uniqueness +
    counter-based collision recovery."""
    return _uniquify_username(db, "athlete")


def resolve_or_onboard_oauth(
    db: Session,
    *,
    provider: str,
    subject: Optional[str],
    verified_email: Optional[str],
    display_name: Optional[str],
    date_of_birth: Optional[datetime],
    commit: bool = True,
) -> dict:
    """Resolve a returning external identity or onboard a first-time one.

    Identity key is (provider, subject) — NEVER email. Returns a typed envelope:
      authenticated / dob_required / account_conflict / identity_incomplete
    Raises HTTPException(400) only for an actually-invalid/under-13 DOB.

    When `commit=False`, a first-time identity is STAGED (flushed) in the caller's
    transaction but NOT committed — the caller commits it atomically with the single-use
    attempt consumption, so a failed/lost redemption persists NO user or identity.

    Fail-closed rules (Gate 1.2):
      - unknown subject + provider email matches an existing account -> account_conflict
        (NO auto-link, NO account returned)
      - unknown subject + no verified provider email -> identity_incomplete
      - unknown subject + new email + no DOB -> dob_required (nothing created)
    """
    provider = canonical_provider(provider)
    subject = (subject or "").strip()
    if not subject:
        # A verified token with no subject is unusable as a durable identity.
        return {"status": "identity_incomplete"}

    # STEP 1 — returning identity resolves by (provider, subject); email not required.
    identity = db.query(models.AuthIdentity).filter(
        models.AuthIdentity.provider == provider,
        models.AuthIdentity.subject == subject,
    ).first()
    if identity is not None:
        return _session_for(identity.user)

    # STEP 2 — first-time/unlinked external identity. We require a VERIFIED provider
    # email (never a client-claimed one) to proceed.
    email = normalize_email(verified_email)
    if not email:
        return {"status": "identity_incomplete"}

    # STEP 3 — fail closed if that email already belongs to a SportsHub account.
    # We do NOT auto-link an external identity to an existing local/other account.
    if db.query(models.User).filter(models.User.email == email).first() is not None:
        return {"status": "account_conflict"}

    # STEP 4 — brand-new identity + new email. Require a real, >=13 DOB before creating.
    if date_of_birth is None:
        return {"status": "dob_required"}
    if not is_valid_signup_dob(date_of_birth):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A valid date of birth is required and you must be at least 13 years old.",
        )

    # STEP 5 — atomic create: User (no password) + AuthIdentity, or neither.
    # New-account public-profile initialization: evaluate the proposed public username and
    # display name BEFORE first persistence. A provider/email value that fails policy (or an
    # oversized display name) is replaced with a neutral, policy-valid fallback — authentication
    # is NEVER rejected over a name, and the rejected value is never logged. Returning identities
    # (STEP 1) never reach here, so existing users' names are never overwritten on repeat login.
    username = _unique_username_from_email(db, email)
    if not text_policy.evaluate(username).allowed:
        username = _neutral_username(db)          # neutral fallback, independent of email contents
    proposed_display = display_name or username
    if not text_policy.evaluate(proposed_display).allowed:
        proposed_display = username               # neutral, policy-valid fallback (already checked)
    user = models.User(
        email=email,
        username=username,
        display_name=proposed_display,
        password_hash=None,                # provider-only account: no local credential
        date_of_birth=date_of_birth,
        age_verified=True,                 # only AFTER passing the same >=13 gate as signup
        email_verified=True,               # provider asserted control of the email
        role=models.UserRole.USER,
        account_status=models.AccountStatus.ACTIVE,
    )
    db.add(user)
    try:
        db.flush()                         # assigns user.id; surfaces email-unique races
        db.add(models.AuthIdentity(user_id=user.id, provider=provider, subject=subject))
        for sport in models.Sport:
            db.add(models.SportProfile(user_id=user.id, sport=sport))
        if commit:
            db.commit()
            db.refresh(user)
        else:
            db.flush()                     # stage only; caller commits atomically w/ consume
    except IntegrityError:
        db.rollback()
        # Concurrency: another request won the race. Re-resolve deterministically.
        identity = db.query(models.AuthIdentity).filter(
            models.AuthIdentity.provider == provider,
            models.AuthIdentity.subject == subject,
        ).first()
        if identity is not None:
            return _session_for(identity.user)
        if db.query(models.User).filter(models.User.email == email).first() is not None:
            return {"status": "account_conflict"}
        raise
    return _session_for(user)


# ---------------------------------------------------------------------------
# Apple Sign-In endpoint
# ---------------------------------------------------------------------------

@router.post("/apple/attempt", response_model=AttemptResponse)
async def create_apple_attempt(request: Request, db: Session = Depends(get_db)):
    """Mint a server-bound authentication attempt BEFORE Apple authorization.

    The app hashes the returned nonce (SHA-256) into its ASAuthorization request, so the
    resulting Apple id_token is bound to THIS attempt and can be redeemed exactly once.
    A local per-IP rate limit is enforced BEFORE any row is allocated — a rejected request
    creates no attempt. (Single-worker guard; distributed limiting is Gate 2.4.)
    """
    client_ip = request.client.host if request.client else "unknown"
    _check_attempt_rate_limit(client_ip)          # raises 429 before allocation
    attempt = _create_apple_attempt(db)
    return AttemptResponse(attempt_id=str(attempt.id), nonce=attempt.nonce)


@router.post("/apple")
async def apple_sign_in(request: OAuthLoginRequest, db: Session = Depends(get_db)):
    """
    Authenticate with Apple Sign-In against a server-bound, single-use attempt.

    A valid Apple id_token alone is NOT sufficient: it must redeem a live, unconsumed
    attempt (Gate 1.3) whose SERVER-stored nonce the token was bound to. The token is
    verified (RS256 JWT + nonce), the durable (apple, sub) identity is resolved/onboarded
    (Gate 1.2), and the attempt is atomically consumed on any terminal outcome — or moved
    to AWAITING_DOB (bound to the subject) when first-time onboarding needs a birth date.
    Returns a typed envelope (authenticated / dob_required / account_conflict /
    identity_incomplete).
    """
    attempt = _load_live_attempt(db, request.attempt_id, "apple")

    # Bind to the SERVER-STORED nonce (authoritative), never a client-asserted match.
    try:
        payload = await _verify_apple_id_token(request.id_token, expected_nonce=attempt.nonce)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc))
    subject = payload.get("sub")

    # A completion (AWAITING_DOB) attempt is bound to a specific Apple subject — the token
    # subject must match, preventing cross-identity substitution of a pending completion.
    if attempt.status == AuthAttemptStatus.AWAITING_DOB:
        if not subject or (attempt.subject or "") != subject:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                                detail="Authentication attempt identity mismatch")

    # Identity comes from the VERIFIED token only (sub durable, verified email never used
    # as identity). Resolve with commit=False so a first-time identity is only STAGED — it is
    # committed atomically with the single-use consumption below, never before. An under-13/
    # invalid DOB raises 400 before any mutation; consume so it can't be retried with a
    # different claimed DOB.
    try:
        result = resolve_or_onboard_oauth(
            db,
            provider="apple",
            subject=subject,
            verified_email=payload.get("email"),
            display_name=request.full_name,
            date_of_birth=request.date_of_birth,
            commit=False,
        )
    except HTTPException:
        db.rollback()                                     # discard any staged mutation
        _transition_attempt(db, attempt.id, attempt.status, AuthAttemptStatus.CONSUMED)
        raise

    st = result.get("status")
    if st == "authenticated":
        # ATOMIC: stage the terminal consume in the SAME transaction as the (possibly new)
        # identity mutation, then commit both together. A concurrent/replayed redemption loses
        # the guarded UPDATE (rowcount 0) -> roll everything back (no user, no session). A
        # commit failure -> roll back -> no session. Session is issued ONLY after this commit.
        won = _transition_attempt(db, attempt.id, attempt.status,
                                  AuthAttemptStatus.CONSUMED, commit=False)
        if not won:
            db.rollback()
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                                detail="Authentication attempt already used")
        try:
            db.commit()                                   # identity (if new) + consume, atomically
        except Exception:
            db.rollback()
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                                detail="Authentication attempt could not be completed")
        return result
    if st == "dob_required":
        # New identity, awaiting DOB: bind the subject and move PENDING -> AWAITING_DOB so the
        # initial Apple proof can no longer mint a fresh PENDING redemption. This transition is
        # committed separately (no identity mutation to bind it to). Retries stay in
        # AWAITING_DOB within DOB_TTL.
        _transition_attempt(db, attempt.id, AuthAttemptStatus.PENDING,
                            AuthAttemptStatus.AWAITING_DOB, subject=subject)
        return result
    # account_conflict / identity_incomplete: terminal rejection, no identity mutation — consume.
    db.rollback()                                         # defensive: drop any staged state
    _transition_attempt(db, attempt.id, attempt.status, AuthAttemptStatus.CONSUMED)
    return result


# ---------------------------------------------------------------------------
# Google Sign-In endpoint (stub — requires iOS Google SDK)
# ---------------------------------------------------------------------------

@router.post("/google")
async def google_sign_in(request: OAuthLoginRequest, db: Session = Depends(get_db)):
    """
    Authenticate with Google Sign-In.

    FAIL CLOSED: without a configured GOOGLE_OAUTH_CLIENT_ID there is no way to
    verify the token, so the endpoint refuses (503). A client-claimed email is NEVER
    trusted as an authenticated identity. When configured, the verified Google `sub`
    is the durable identity and onboarding follows the same rules as Apple.
    """
    GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_OAUTH_CLIENT_ID")
    if not GOOGLE_CLIENT_ID:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Google Sign-In is not available on this server.",
        )

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(
                "https://www.googleapis.com/oauth2/v3/tokeninfo",
                params={"id_token": request.id_token},
            )
        if resp.status_code != 200:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Google ID token")
        token_info = resp.json()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=f"Google verification failed: {exc}")

    if token_info.get("aud") != GOOGLE_CLIENT_ID:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Google token audience mismatch")

    return resolve_or_onboard_oauth(
        db,
        provider="google",
        subject=token_info.get("sub"),
        verified_email=token_info.get("email"),   # verified by Google, not client-claimed
        display_name=token_info.get("name") or request.full_name,
        date_of_birth=request.date_of_birth,
    )
