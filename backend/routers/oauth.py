# OAuth authentication endpoints for Google and Apple Sign-In

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
import httpx
import jwt
from datetime import datetime, timedelta

from database import get_db
from models import User
from auth import create_access_token, get_password_hash
from schemas import Token

router = APIRouter(prefix="/auth/oauth", tags=["OAuth"])


# Request/Response Models
class OAuthLoginRequest(BaseModel):
    provider: str  # "apple" or "google"
    id_token: str
    nonce: Optional[str] = None
    email: Optional[str] = None
    full_name: Optional[str] = None


# Apple Sign-In
@router.post("/apple", response_model=Token)
async def apple_sign_in(request: OAuthLoginRequest, db: Session = Depends(get_db)):
    """
    Authenticate with Apple Sign-In.

    Flow:
    1. Verify Apple ID token
    2. Extract user info
    3. Create user if doesn't exist
    4. Return JWT token
    """

    try:
        # TODO: In production, verify the ID token with Apple
        # For now, we'll decode it without verification (development only)
        # decoded = jwt.decode(request.id_token, options={"verify_signature": False})

        # For demo purposes, use provided email or create from token
        if not request.email:
            raise HTTPException(status_code=400, detail="Email is required for Apple Sign-In")

        # Check if user exists
        user = db.query(User).filter(User.email == request.email).first()

        if not user:
            # Create new user from Apple Sign-In
            # Generate username from email
            username = request.email.split("@")[0]
            base_username = username
            counter = 1

            # Ensure unique username
            while db.query(User).filter(User.username == username).first():
                username = f"{base_username}{counter}"
                counter += 1

            user = User(
                email=request.email,
                username=username,
                full_name=request.full_name or username,
                hashed_password=get_password_hash("oauth_" + request.id_token[:20]),  # Placeholder password
                is_admin=False
            )
            db.add(user)
            db.commit()
            db.refresh(user)

        # Create access token
        access_token = create_access_token(data={"sub": user.email})

        return {"access_token": access_token, "token_type": "bearer"}

    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Apple Sign-In failed: {str(e)}")


# Google Sign-In
@router.post("/google", response_model=Token)
async def google_sign_in(request: OAuthLoginRequest, db: Session = Depends(get_db)):
    """
    Authenticate with Google Sign-In.

    Flow:
    1. Verify Google ID token with Google servers
    2. Extract user info
    3. Create user if doesn't exist
    4. Return JWT token
    """

    try:
        # Verify Google token
        # In production, verify with Google:
        # https://www.googleapis.com/oauth2/v3/tokeninfo?id_token={id_token}

        # For demo, use provided email
        if not request.email:
            # In production, would get this from verified token
            raise HTTPException(status_code=400, detail="Email is required")

        # Check if user exists
        user = db.query(User).filter(User.email == request.email).first()

        if not user:
            # Create new user from Google Sign-In
            username = request.email.split("@")[0]
            base_username = username
            counter = 1

            # Ensure unique username
            while db.query(User).filter(User.username == username).first():
                username = f"{base_username}{counter}"
                counter += 1

            user = User(
                email=request.email,
                username=username,
                full_name=request.full_name or username,
                hashed_password=get_password_hash("oauth_" + request.id_token[:20]),
                is_admin=False
            )
            db.add(user)
            db.commit()
            db.refresh(user)

        # Create access token
        access_token = create_access_token(data={"sub": user.email})

        return {"access_token": access_token, "token_type": "bearer"}

    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Google Sign-In failed: {str(e)}")


# Helper function for production: Verify Apple ID token
async def verify_apple_token(id_token: str, nonce: str = None) -> dict:
    """
    Verify Apple ID token with Apple servers.

    In production:
    1. Fetch Apple's public keys
    2. Verify token signature
    3. Validate nonce
    4. Return user info
    """
    # TODO: Implement full verification
    # See: https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api/verifying_a_user

    pass


# Helper function for production: Verify Google ID token
async def verify_google_token(id_token: str) -> dict:
    """
    Verify Google ID token with Google servers.

    In production:
    1. Call Google's tokeninfo endpoint
    2. Verify audience matches your client ID
    3. Return user info
    """

    # Example production code:
    # async with httpx.AsyncClient() as client:
    #     response = await client.get(
    #         f"https://www.googleapis.com/oauth2/v3/tokeninfo?id_token={id_token}"
    #     )
    #     if response.status_code != 200:
    #         raise HTTPException(status_code=401, detail="Invalid Google token")
    #     return response.json()

    pass
