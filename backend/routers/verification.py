"""
Email verification endpoints using 6-digit one-time codes.

Security model:
  - Codes are SHA-256(code + user_id + deploy_salt) — raw code never stored
  - 10-minute TTL enforced server-side
  - 5 attempt maximum (attempt count incremented BEFORE checking, prevents timing leaks)
  - 60-second resend cooldown
  - Single-use enforcement via verification_code_used flag
  - On success: account activated, all code fields cleared, fresh JWT returned

Flow:
  1. POST /auth/send-code     — authenticated user requests a code
  2. POST /auth/verify-code   — submit the code, receive fresh JWT on success
  3. POST /auth/resend-code   — resend with same rate-limiting as send-code
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from database import get_db
from auth import create_access_token
from dependencies import get_current_user
from email_service import (
    generate_verification_code,
    hash_code,
    send_verification_code_email,
    VERIFICATION_CODE_TTL_MINUTES,
)
import models
import schemas

router = APIRouter(prefix="/auth", tags=["verification"])

MAX_ATTEMPTS = 5
RESEND_COOLDOWN_SECONDS = 60


def _mask_email(email: str) -> str:
    """Return a partially masked email for safe display (e.g. jo***@gmail.com)."""
    parts = email.split("@")
    if len(parts) != 2:
        return email
    name, domain = parts
    visible = name[:2] if len(name) >= 2 else name[0]
    masked = visible + "*" * max(0, len(name) - 2)
    return f"{masked}@{domain}"


def _enforce_cooldown(user: models.User) -> None:
    """Raise 429 if the user is still within the resend cooldown window."""
    if user.verification_last_sent_at:
        elapsed = (datetime.utcnow() - user.verification_last_sent_at).total_seconds()
        if elapsed < RESEND_COOLDOWN_SECONDS:
            wait = int(RESEND_COOLDOWN_SECONDS - elapsed)
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"Please wait {wait} second{'s' if wait != 1 else ''} before requesting a new code.",
            )


def _issue_new_code(user: models.User, db: Session) -> str:
    """
    Generate a new code, hash it with the user's ID as salt, and persist
    the hash + metadata. Returns the raw code (caller is responsible for
    emailing it — do not log or store it).
    """
    code = generate_verification_code()
    user.verification_code_hash = hash_code(code, str(user.id))
    user.verification_code_expires_at = datetime.utcnow() + timedelta(minutes=VERIFICATION_CODE_TTL_MINUTES)
    user.verification_code_attempts = 0
    user.verification_code_used = False  # Reset single-use flag for the new code
    user.verification_last_sent_at = datetime.utcnow()
    db.commit()
    return code


@router.post("/send-code", response_model=schemas.SendCodeResponse)
async def send_verification_code(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Send a 6-digit verification code to the authenticated user's email.
    Idempotent if already verified — returns success without sending another code.
    """
    if current_user.email_verified:
        return {"message": "Email already verified", "email": _mask_email(current_user.email)}

    _enforce_cooldown(current_user)
    code = _issue_new_code(current_user, db)
    send_verification_code_email(current_user.email, code)

    return {
        "message": "Verification code sent",
        "email": _mask_email(current_user.email),
    }


@router.post("/resend-code", response_model=schemas.SendCodeResponse)
async def resend_verification_code(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Resend a verification code. Subject to the same 60-second cooldown as send-code.
    Issues a fresh code — the old code is immediately invalidated.
    """
    if current_user.email_verified:
        return {"message": "Email already verified", "email": _mask_email(current_user.email)}

    _enforce_cooldown(current_user)
    code = _issue_new_code(current_user, db)
    send_verification_code_email(current_user.email, code)

    return {
        "message": "New verification code sent",
        "email": _mask_email(current_user.email),
    }


@router.post("/verify-code", response_model=schemas.Token)
async def verify_code(
    request: schemas.VerifyCodeRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Verify the 6-digit code.

    On success:
      - email_verified = True
      - account_status = ACTIVE
      - All code fields cleared (single-use enforcement)
      - Fresh JWT returned (caller MUST store and replace the signup token)

    Security guarantees:
      - Attempt count incremented BEFORE code comparison (prevents timing-based enumeration)
      - Code hash uses per-user salt — invalid across different users even for same digits
      - verification_code_used flag prevents replay even if attempts counter is bypassed
      - Expired codes are rejected even if hash would match
    """
    # Already verified — return a fresh token so the client can proceed
    if current_user.email_verified:
        token = create_access_token(data={"sub": str(current_user.id)})
        return {"access_token": token, "token_type": "bearer"}

    attempts = current_user.verification_code_attempts or 0

    # Check attempt limit first — prevents brute force even on valid-TTL codes
    if attempts >= MAX_ATTEMPTS:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many failed attempts. Please request a new code.",
        )

    # Check TTL
    if (
        not current_user.verification_code_expires_at
        or datetime.utcnow() > current_user.verification_code_expires_at
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Verification code has expired. Please request a new one.",
        )

    # Check single-use flag
    if current_user.verification_code_used:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This code has already been used. Please request a new one.",
        )

    # Increment attempts BEFORE checking hash — prevents timing-based enumeration
    current_user.verification_code_attempts = attempts + 1
    db.commit()

    # Verify hash — code is salted with user ID so it cannot be replayed for other accounts
    expected_hash = hash_code(request.code, str(current_user.id))
    if not current_user.verification_code_hash or expected_hash != current_user.verification_code_hash:
        remaining = max(0, MAX_ATTEMPTS - current_user.verification_code_attempts)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid code. {remaining} attempt{'s' if remaining != 1 else ''} remaining."
            if remaining > 0
            else "Invalid code. No attempts remaining — please request a new code.",
        )

    # SUCCESS — mark verified, activate account, clear all code fields
    current_user.email_verified = True
    current_user.account_status = models.AccountStatus.ACTIVE
    current_user.verification_code_hash = None
    current_user.verification_code_expires_at = None
    current_user.verification_code_attempts = 0
    current_user.verification_code_used = True  # Marks this code as consumed
    db.commit()

    token = create_access_token(data={"sub": str(current_user.id)})
    return {"access_token": token, "token_type": "bearer"}
