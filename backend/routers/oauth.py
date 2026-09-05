# OAuth authentication endpoints for Apple Sign-In
# Google Sign-In requires the Google Sign-In SDK on iOS — backend stub kept for future use.

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
import httpx
import jwt
from jwt.algorithms import RSAAlgorithm
from datetime import datetime, timedelta
import os

from sqlalchemy.exc import IntegrityError

from database import get_db
import models
from auth import create_access_token
from schemas import Token
from identity import normalize_email, canonical_provider, is_valid_signup_dob

router = APIRouter(prefix="/auth/oauth", tags=["OAuth"])

# Apple validates against this audience claim in the JWT.
# Set APPLE_BUNDLE_ID env var in production (e.g. "com.royaltonitservices.SportsHub").
APPLE_BUNDLE_ID = os.environ.get("APPLE_BUNDLE_ID", "com.royaltonitservices.SportsHub")
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------

class OAuthLoginRequest(BaseModel):
    provider: str           # "apple" or "google"
    id_token: str
    nonce: Optional[str] = None            # accepted; nonce VALIDATION is Gate 1.3
    email: Optional[str] = None            # display/first-time hint ONLY — never used as identity
    full_name: Optional[str] = None
    date_of_birth: Optional[datetime] = None   # required only on first-time onboarding


# ---------------------------------------------------------------------------
# Apple JWKS verification helper
# ---------------------------------------------------------------------------

async def _verify_apple_id_token(id_token: str) -> dict:
    """
    Verify an Apple identity token (JWT) against Apple's published public keys.

    Steps:
    1. Fetch Apple's JWKS from https://appleid.apple.com/auth/keys
    2. Match the token's `kid` header to a key in the set
    3. Decode and verify the JWT using that RSA public key
    4. Validate iss = "https://appleid.apple.com" and aud = APPLE_BUNDLE_ID

    Returns the decoded JWT payload on success.
    Raises ValueError on any verification failure.
    """
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
            options={"require": ["sub", "iat", "exp"]},
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

    return payload


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


def _unique_username_from_email(db: Session, email: str) -> str:
    base = (email.split("@")[0].replace(".", "_").replace("+", "_")[:40]) or "athlete"
    username = base
    counter = 1
    while db.query(models.User).filter(models.User.username == username).first():
        username = f"{base}{counter}"
        counter += 1
    return username


def resolve_or_onboard_oauth(
    db: Session,
    *,
    provider: str,
    subject: Optional[str],
    verified_email: Optional[str],
    display_name: Optional[str],
    date_of_birth: Optional[datetime],
) -> dict:
    """Resolve a returning external identity or onboard a first-time one.

    Identity key is (provider, subject) — NEVER email. Returns a typed envelope:
      authenticated / dob_required / account_conflict / identity_incomplete
    Raises HTTPException(400) only for an actually-invalid/under-13 DOB.

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
    username = _unique_username_from_email(db, email)
    user = models.User(
        email=email,
        username=username,
        display_name=display_name or username,
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
        db.commit()
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
    db.refresh(user)
    return _session_for(user)


# ---------------------------------------------------------------------------
# Apple Sign-In endpoint
# ---------------------------------------------------------------------------

@router.post("/apple")
async def apple_sign_in(request: OAuthLoginRequest, db: Session = Depends(get_db)):
    """
    Authenticate with Apple Sign-In.

    Verifies the Apple identity token (RS256 JWT), then resolves the durable
    (apple, sub) identity or onboards a first-time one. Returning users resolve by
    subject and do NOT need an email. Returns a typed envelope
    (authenticated / dob_required / account_conflict / identity_incomplete).
    """
    try:
        payload = await _verify_apple_id_token(request.id_token)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc))

    # Identity comes from the VERIFIED token only: sub is durable identity; email
    # (present on first authorization; may be a private-relay address) is the verified
    # provider email. A client-claimed request.email is NEVER used as identity.
    return resolve_or_onboard_oauth(
        db,
        provider="apple",
        subject=payload.get("sub"),
        verified_email=payload.get("email"),
        display_name=request.full_name,
        date_of_birth=request.date_of_birth,
    )


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
