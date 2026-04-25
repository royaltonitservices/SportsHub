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

from database import get_db
import models
from auth import create_access_token, get_password_hash
from schemas import Token

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
    nonce: Optional[str] = None
    email: Optional[str] = None
    full_name: Optional[str] = None


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

def _find_or_create_oauth_user(
    db: Session,
    email: str,
    display_name: Optional[str],
    apple_sub: Optional[str] = None,
) -> models.User:
    """
    Look up a user by email.  If none exists, create one with a placeholder
    password (OAuth users never use password login).

    OAuth users are created with:
    - A generated unique username (based on email local-part)
    - date_of_birth set to Jan 1 1990 (placeholder — required field; cannot be
      obtained from OAuth provider)
    - age_verified = True  (provider has already verified identity)
    - email_verified = True
    """
    user = db.query(models.User).filter(models.User.email == email.lower()).first()
    if user:
        return user

    # Build a unique username from the email local-part
    base = email.split("@")[0].replace(".", "_").replace("+", "_")[:40]
    username = base
    counter = 1
    while db.query(models.User).filter(models.User.username == username).first():
        username = f"{base}{counter}"
        counter += 1

    user = models.User(
        email=email.lower(),
        username=username,
        display_name=display_name or username,
        password_hash=get_password_hash(f"oauth_{apple_sub or username}"),
        date_of_birth=datetime(1990, 1, 1),   # placeholder; OAuth users skip the age gate
        age_verified=True,
        email_verified=True,
        role=models.UserRole.USER,
        account_status=models.AccountStatus.ACTIVE,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


# ---------------------------------------------------------------------------
# Apple Sign-In endpoint
# ---------------------------------------------------------------------------

@router.post("/apple", response_model=Token)
async def apple_sign_in(request: OAuthLoginRequest, db: Session = Depends(get_db)):
    """
    Authenticate with Apple Sign-In.

    Verifies the Apple identity token (RS256 JWT) against Apple's public keys,
    then finds-or-creates a SportsHub account and returns a JWT.
    """
    try:
        payload = await _verify_apple_id_token(request.id_token)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
        )

    # Prefer email from the verified JWT payload; fall back to client-provided email.
    # Apple only sends email in the JWT on the first sign-in — subsequent logins omit it.
    email = payload.get("email") or request.email
    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "Email not available from Apple Sign-In. "
                "This can happen after the first sign-in. "
                "Please sign out of Apple ID settings and try again."
            ),
        )

    apple_sub = payload.get("sub")  # Apple's stable user identifier
    user = _find_or_create_oauth_user(
        db,
        email=email,
        display_name=request.full_name,
        apple_sub=apple_sub,
    )

    access_token = create_access_token(data={"sub": str(user.id)})
    return {"access_token": access_token, "token_type": "bearer"}


# ---------------------------------------------------------------------------
# Google Sign-In endpoint (stub — requires iOS Google SDK)
# ---------------------------------------------------------------------------

@router.post("/google", response_model=Token)
async def google_sign_in(request: OAuthLoginRequest, db: Session = Depends(get_db)):
    """
    Authenticate with Google Sign-In.

    Production: Verify via https://www.googleapis.com/oauth2/v3/tokeninfo.
    Current state: Requires iOS Google Sign-In SDK (not yet integrated).
    """
    # Verify with Google's tokeninfo endpoint when available
    GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_OAUTH_CLIENT_ID")

    if GOOGLE_CLIENT_ID:
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.get(
                    "https://www.googleapis.com/oauth2/v3/tokeninfo",
                    params={"id_token": request.id_token},
                )
                if resp.status_code != 200:
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Invalid Google ID token",
                    )
                token_info = resp.json()

            # Validate audience
            if token_info.get("aud") != GOOGLE_CLIENT_ID:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Google token audience mismatch",
                )

            email = token_info.get("email") or request.email
            if not email:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Email not available from Google Sign-In",
                )

            user = _find_or_create_oauth_user(
                db,
                email=email,
                display_name=token_info.get("name") or request.full_name,
            )
            access_token = create_access_token(data={"sub": str(user.id)})
            return {"access_token": access_token, "token_type": "bearer"}

        except HTTPException:
            raise
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Google Sign-In verification failed: {exc}",
            )
    else:
        # GOOGLE_OAUTH_CLIENT_ID not configured — fall back to trust-email mode (dev only)
        email = request.email
        if not email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Google Sign-In is not configured on this server",
            )
        user = _find_or_create_oauth_user(db, email=email, display_name=request.full_name)
        access_token = create_access_token(data={"sub": str(user.id)})
        return {"access_token": access_token, "token_type": "bearer"}
