"""
Authentication endpoints for login, signup, and token management
"""
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from collections import defaultdict
from database import get_db
from auth import verify_password, get_password_hash, create_access_token
from dependencies import get_current_user
from email_service import generate_verification_code, hash_code, send_verification_code_email, send_password_reset_email, VERIFICATION_CODE_TTL_MINUTES
from config import get_settings
import models
import schemas

router = APIRouter(prefix="/auth", tags=["authentication"])

# Admin credentials — loaded from environment via config (set ADMIN_EMAIL + ADMIN_PASSWORD in .env).
# Never hardcode real credentials here; this file is checked into version control.
_settings = get_settings()
ADMIN_EMAIL: str = _settings.admin_email
ADMIN_PASSWORD: str = _settings.admin_password

# ── Login rate limiting ────────────────────────────────────────────────────────────────────────────
# In-memory per-email attempt tracking. Resets on process restart — sufficient for dev and
# low-to-medium traffic. Replace with Redis-backed counter for high-concurrency production.
#
# Policy: 10 consecutive failed login attempts triggers a 5-minute lockout window.
# Successful login clears the counter immediately.
_LOGIN_MAX_ATTEMPTS: int = 10
_LOGIN_LOCKOUT_SECONDS: int = 300  # 5 minutes

_login_attempts: dict[str, list[datetime]] = defaultdict(list)  # email → timestamps of failed attempts


def _check_login_rate_limit(email: str) -> None:
    """Raise HTTP 429 if the email is in a lockout window."""
    now = datetime.utcnow()
    cutoff = now - timedelta(seconds=_LOGIN_LOCKOUT_SECONDS)
    recent = [t for t in _login_attempts[email] if t > cutoff]
    _login_attempts[email] = recent  # prune stale attempts in-place
    if len(recent) >= _LOGIN_MAX_ATTEMPTS:
        # Tell the client how long to wait based on when the first attempt in the window expires
        wait_secs = int((recent[0] + timedelta(seconds=_LOGIN_LOCKOUT_SECONDS) - now).total_seconds())
        wait_secs = max(wait_secs, 1)
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Too many failed login attempts. Try again in {wait_secs} second{'s' if wait_secs != 1 else ''}.",
            headers={"Retry-After": str(wait_secs)},
        )


def _record_failed_login(email: str) -> None:
    _login_attempts[email].append(datetime.utcnow())


def _clear_login_attempts(email: str) -> None:
    _login_attempts.pop(email, None)


def _ensure_admin_subscription(user: "models.User", db: "Session") -> None:
    """Create or repair a premium subscription for admin users at login time.

    Idempotent — safe to call on every admin login. Handles accounts that were
    created before the subscription auto-create logic existed in signup.
    """
    if user.role != models.UserRole.ADMIN:
        return

    from models_premium import Subscription, SubscriptionTier, SubscriptionStatus
    from datetime import timedelta

    existing = db.query(Subscription).filter(
        Subscription.user_id == user.id
    ).first()

    if existing is None:
        # First time — create the record
        sub = Subscription(
            user_id=user.id,
            tier=SubscriptionTier.PREMIUM,
            status=SubscriptionStatus.ACTIVE,
            price_per_month=0.00,
            expires_at=datetime.utcnow() + timedelta(days=36500),
            platform="admin_grant",
            features={
                "ai_coach": True,
                "smartwatch_sync": True,
                "tournaments": True,
                "advanced_analytics": True,
                "goals_system": True,
                "performance_predictions": True
            }
        )
        db.add(sub)
        db.commit()
    elif existing.tier != SubscriptionTier.PREMIUM or existing.status != SubscriptionStatus.ACTIVE:
        # Record exists but was downgraded — restore it
        existing.tier = SubscriptionTier.PREMIUM
        existing.status = SubscriptionStatus.ACTIVE
        existing.expires_at = datetime.utcnow() + timedelta(days=36500)
        db.commit()


@router.post("/signup", response_model=schemas.Token, status_code=status.HTTP_201_CREATED)
async def signup(user_data: schemas.UserSignup, db: Session = Depends(get_db)):
    """Register a new user account"""

    try:
        # Check if username already exists (email can be reused)
        existing_username = db.query(models.User).filter(models.User.username == user_data.username).first()
        if existing_username:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already taken"
            )

        # Verify age (must be 13+)
        # Make date_of_birth timezone-naive for comparison
        dob = user_data.date_of_birth.replace(tzinfo=None) if user_data.date_of_birth.tzinfo else user_data.date_of_birth
        age = (datetime.now() - dob).days / 365.25
        if age < 13:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Must be at least 13 years old"
            )

        # Check if admin credentials (2-key system: BOTH email AND password must match)
        is_admin = (user_data.email == ADMIN_EMAIL and user_data.password == ADMIN_PASSWORD)
        user_role = models.UserRole.ADMIN if is_admin else models.UserRole.USER

        # Admin accounts are fully activated; all others start pending verification
        initial_status = models.AccountStatus.ACTIVE if is_admin else models.AccountStatus.PENDING_VERIFICATION

        # Create user first — we need the UUID to build the salted hash
        new_user = models.User(
            email=user_data.email,
            username=user_data.username,
            password_hash=get_password_hash(user_data.password),
            display_name=user_data.display_name,
            date_of_birth=user_data.date_of_birth,
            age_verified=True,
            avatar_seed=user_data.username,
            account_status=initial_status,
            role=user_role,
            email_verified=is_admin,
            survey_completed=is_admin,
        )

        db.add(new_user)
        db.commit()
        db.refresh(new_user)  # Populates new_user.id

        # Now generate the salted code hash using the real UUID
        initial_code = None
        if not is_admin:
            initial_code = generate_verification_code()
            new_user.verification_code_hash = hash_code(initial_code, str(new_user.id))
            new_user.verification_code_expires_at = datetime.utcnow() + timedelta(minutes=VERIFICATION_CODE_TTL_MINUTES)
            new_user.verification_code_attempts = 0
            new_user.verification_code_used = False
            new_user.verification_last_sent_at = datetime.utcnow()
            db.commit()

        # Create default sport profiles for all sports
        for sport in models.Sport:
            sport_profile = models.SportProfile(
                user_id=new_user.id,
                sport=sport
            )
            db.add(sport_profile)

        # Create premium subscription for admin accounts
        if is_admin:
            from models_premium import Subscription
            from datetime import timedelta

            premium_subscription = Subscription(
                user_id=new_user.id,
                tier="premium",
                status="active",
                price_per_month=0.00,  # Free for admin
                started_at=datetime.utcnow(),
                expires_at=datetime.utcnow() + timedelta(days=36500),  # 100 years
                platform="admin_grant"
            )
            db.add(premium_subscription)

        db.commit()

        # Send verification code email (non-blocking — failure doesn't abort signup)
        if not is_admin and initial_code:
            try:
                send_verification_code_email(new_user.email, initial_code)
            except Exception as e:
                print(f"[WARN] Verification code email failed at signup: {e}")

        # Create access token (works for PENDING_VERIFICATION accounts too,
        # allowing the client to call /auth/send-code and /auth/verify-code)
        access_token = create_access_token(data={"sub": str(new_user.id)})

        return {"access_token": access_token, "token_type": "bearer"}

    except HTTPException:
        # Re-raise validation errors
        raise
    except Exception as e:
        # Log and handle database/system errors
        print(f"[ERROR] Signup failed - {type(e).__name__}: {str(e)}")
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Service temporarily unavailable. Please try again later."
        )


@router.post("/login", response_model=schemas.Token)
async def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db)
):
    """Login with email (sent as 'username') and password."""

    email = form_data.username

    # Rate limit: raises HTTP 429 if email is in a lockout window
    _check_login_rate_limit(email)

    # Find user by email (username field in OAuth2 form is used for email)
    user = db.query(models.User).filter(models.User.email == email).first()

    if not user or not verify_password(form_data.password, user.password_hash):
        _record_failed_login(email)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Allow PENDING_VERIFICATION accounts to log in (so they can complete verification)
    # Block only truly inactive accounts: SUSPENDED, BANNED, SHADOW_BANNED
    blocked_statuses = {
        models.AccountStatus.SUSPENDED,
        models.AccountStatus.BANNED,
        models.AccountStatus.SHADOW_BANNED,
    }
    if user.account_status in blocked_statuses:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Account is {user.account_status.value}"
        )

    # Successful auth — clear any accumulated failed-attempt counter
    _clear_login_attempts(email)

    # Update last login
    user.last_login = datetime.utcnow()
    db.commit()

    # Ensure admin users always have a premium subscription record
    _ensure_admin_subscription(user, db)

    # Create access token
    access_token = create_access_token(data={"sub": str(user.id)})

    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/login/json", response_model=schemas.Token)
async def login_json(user_login: schemas.UserLogin, db: Session = Depends(get_db)):
    """Login with JSON body (for mobile apps)."""

    email = user_login.email

    # Rate limit: raises HTTP 429 if email is in a lockout window
    _check_login_rate_limit(email)

    user = db.query(models.User).filter(models.User.email == email).first()

    if not user or not verify_password(user_login.password, user.password_hash):
        _record_failed_login(email)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password"
        )

    # Allow PENDING_VERIFICATION accounts to log in (so they can complete verification)
    blocked_statuses = {
        models.AccountStatus.SUSPENDED,
        models.AccountStatus.BANNED,
        models.AccountStatus.SHADOW_BANNED,
    }
    if user.account_status in blocked_statuses:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Account is {user.account_status.value}"
        )

    # Successful auth — clear any accumulated failed-attempt counter
    _clear_login_attempts(email)

    user.last_login = datetime.utcnow()
    db.commit()

    # Ensure admin users always have a premium subscription record
    _ensure_admin_subscription(user, db)

    access_token = create_access_token(data={"sub": str(user.id)})

    return {"access_token": access_token, "token_type": "bearer"}


# Email Verification Endpoints
@router.post("/send-verification")
async def send_verification_email_endpoint(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Send email verification link to user"""
    from auth import generate_verification_token, send_verification_email

    # Check if already verified
    if current_user.email_verified:
        return {"message": "Email already verified"}

    # Generate new token
    token = generate_verification_token()
    current_user.verification_token = token
    db.commit()

    # Send email
    send_verification_email(current_user.email, token)

    return {"message": "Verification email sent"}


@router.post("/verify-email")
async def verify_email(
    token: str,
    db: Session = Depends(get_db)
):
    """Verify email address with token"""
    # Find user with this token
    user = db.query(models.User).filter(models.User.verification_token == token).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired verification token"
        )

    # Mark as verified
    user.email_verified = True
    user.verification_token = None  # Clear token after use
    db.commit()

    return {"message": "Email verified successfully"}


@router.get("/verification-status")
async def get_verification_status(
    current_user: models.User = Depends(get_current_user)
):
    """Check if current user's email is verified"""
    return {
        "email_verified": current_user.email_verified,
        "email": current_user.email
    }


# ── Password Reset ─────────────────────────────────────────────────────────────────────────────────

class ForgotPasswordRequest(BaseModel):
    email: str


class ResetPasswordRequest(BaseModel):
    email: str
    code: str
    new_password: str = Field(..., min_length=6)


@router.post("/forgot-password")
async def forgot_password(
    request: ForgotPasswordRequest,
    db: Session = Depends(get_db)
):
    """
    Send a 6-digit password reset code to the given email.
    Always returns 200 to prevent email enumeration.
    """
    user = db.query(models.User).filter(models.User.email == request.email.lower().strip()).first()

    if user:
        now = datetime.utcnow()

        # Rate-limit: don't resend within 60 seconds
        if user.reset_code_expires_at:
            resend_cooldown = user.reset_code_expires_at - timedelta(
                minutes=VERIFICATION_CODE_TTL_MINUTES - 1
            )
            if now < resend_cooldown:
                # Still within cooldown — return success silently (don't leak timing)
                return {"message": "If an account exists for that email, a reset code has been sent."}

        code = generate_verification_code()
        user.reset_code_hash = hash_code(code, str(user.id))
        user.reset_code_expires_at = now + timedelta(minutes=VERIFICATION_CODE_TTL_MINUTES)
        user.reset_code_used = False
        db.commit()

        send_password_reset_email(user.email, code)

    # Always return success to prevent email enumeration
    return {"message": "If an account exists for that email, a reset code has been sent."}


@router.post("/reset-password")
async def reset_password(
    request: ResetPasswordRequest,
    db: Session = Depends(get_db)
):
    """
    Verify the 6-digit reset code and update the user's password.
    """
    INVALID_MSG = "Invalid or expired reset code."

    user = db.query(models.User).filter(models.User.email == request.email.lower().strip()).first()

    if not user:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=INVALID_MSG)

    # Check code exists, not already used, and not expired
    if not user.reset_code_hash or user.reset_code_used:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=INVALID_MSG)

    if user.reset_code_expires_at and datetime.utcnow() > user.reset_code_expires_at:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=INVALID_MSG)

    # Verify the code
    expected_hash = hash_code(request.code.strip(), str(user.id))
    if expected_hash != user.reset_code_hash:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=INVALID_MSG)

    # Mark code as used and update password
    user.reset_code_used = True
    user.password_hash = get_password_hash(request.new_password)
    db.commit()

    return {"message": "Password updated successfully."}
