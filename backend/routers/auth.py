"""
Authentication endpoints for login, signup, and token management
"""
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from database import get_db
from auth import verify_password, get_password_hash, create_access_token
from dependencies import get_current_user
import models
import schemas

router = APIRouter(prefix="/auth", tags=["authentication"])

# Admin credentials - 2-key system (BOTH must match)
ADMIN_EMAIL = "aarushkhanna11@gmail.com"
ADMIN_PASSWORD = "$81Admin"


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

        # Create new user
        new_user = models.User(
            email=user_data.email,
            username=user_data.username,
            password_hash=get_password_hash(user_data.password),
            display_name=user_data.display_name,
            date_of_birth=user_data.date_of_birth,
            age_verified=True,
            avatar_seed=user_data.username,  # Use username as seed for avatar
            account_status=models.AccountStatus.ACTIVE,
            role=user_role  # Set role based on credentials
        )

        db.add(new_user)
        db.commit()
        db.refresh(new_user)

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

        # Create access token
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
    """
    Login with email and password

    Note: Admin access requires BOTH correct email (aarushkhanna11@gmail.com)
    AND correct password ($81Admin) - 2-key system
    """

    # Find user by email (username field in OAuth2 form is used for email)
    user = db.query(models.User).filter(models.User.email == form_data.username).first()

    if not user or not verify_password(form_data.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Check account status
    if user.account_status != models.AccountStatus.ACTIVE:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Account is {user.account_status.value}"
        )

    # Update last login
    user.last_login = datetime.utcnow()
    db.commit()

    # Create access token
    access_token = create_access_token(data={"sub": str(user.id)})

    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/login/json", response_model=schemas.Token)
async def login_json(user_login: schemas.UserLogin, db: Session = Depends(get_db)):
    """
    Login with JSON body (for mobile apps)

    Note: Admin access requires BOTH correct email (aarushkhanna11@gmail.com)
    AND correct password ($81Admin) - 2-key system
    """

    user = db.query(models.User).filter(models.User.email == user_login.email).first()

    if not user or not verify_password(user_login.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password"
        )

    if user.account_status != models.AccountStatus.ACTIVE:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Account is {user.account_status.value}"
        )

    user.last_login = datetime.utcnow()
    db.commit()

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
