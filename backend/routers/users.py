"""
User profile and management endpoints
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
from database import get_db
from dependencies import get_current_active_user
import models
import schemas

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=schemas.UserProfile)
async def get_current_user_profile(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get current user's profile"""
    return current_user


@router.get("/{user_id}", response_model=schemas.UserResponse)
async def get_user_by_id(
    user_id: UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
):
    """Get user profile by ID"""
    user = db.query(models.User).filter(models.User.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    return user


@router.get("/username/{username}", response_model=schemas.UserResponse)
async def get_user_by_username(
    username: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
):
    """Get user profile by username"""
    user = db.query(models.User).filter(models.User.username == username).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    return user


@router.get("/", response_model=List[schemas.UserResponse])
async def search_users(
    query: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user),
    limit: int = 20
):
    """Search users by username or display name"""
    users = db.query(models.User).filter(
        (models.User.username.ilike(f"%{query}%")) |
        (models.User.display_name.ilike(f"%{query}%"))
    ).filter(
        models.User.account_status == models.AccountStatus.ACTIVE
    ).limit(limit).all()

    return users


@router.get("/check-username/{username}")
async def check_username_availability(
    username: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
):
    """Check if a username is available"""
    # Check if username exists
    existing_user = db.query(models.User).filter(
        models.User.username == username
    ).first()

    return {"available": existing_user is None}


@router.put("/me/username")
async def update_username(
    username_data: schemas.UpdateUsername,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Update current user's username"""
    new_username = username_data.new_username.strip()

    # Validate username format
    if len(new_username) < 3:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username must be at least 3 characters long"
        )

    if len(new_username) > 20:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username must be 20 characters or less"
        )

    # Check if username is alphanumeric with underscores only
    import re
    if not re.match(r'^[a-zA-Z0-9_]+$', new_username):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username can only contain letters, numbers, and underscores"
        )

    # Check if username is already taken
    existing_user = db.query(models.User).filter(
        models.User.username == new_username
    ).first()

    if existing_user and existing_user.id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Username is already taken"
        )

    # Update username
    current_user.username = new_username
    db.commit()

    return {"message": "Username updated successfully", "new_username": new_username}


@router.put("/me/display-name")
async def update_display_name(
    display_name_data: schemas.UpdateDisplayName,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Update current user's display name"""
    new_display_name = display_name_data.new_display_name.strip()

    # Validate display name
    if len(new_display_name) < 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Display name cannot be empty"
        )

    if len(new_display_name) > 100:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Display name must be 100 characters or less"
        )

    # Update display name
    current_user.display_name = new_display_name
    db.commit()

    return {"message": "Display name updated successfully", "new_display_name": new_display_name}


@router.put("/update-athletic-level")
async def update_athletic_level(
    update_data: schemas.UpdateAthleticLevel,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Update athletic level for a specific sport"""
    from sqlalchemy import and_

    # Get or create sport profile
    profile = db.query(models.SportProfile).filter(
        and_(
            models.SportProfile.user_id == current_user.id,
            models.SportProfile.sport == update_data.sport
        )
    ).first()

    if not profile:
        # Create new profile
        profile = models.SportProfile(
            user_id=current_user.id,
            sport=update_data.sport,
            athletic_level=update_data.athletic_level
        )
        db.add(profile)
    else:
        profile.athletic_level = update_data.athletic_level

    db.commit()
    db.refresh(profile)

    return {"message": "Athletic level updated", "profile": profile}


@router.put("/update-pronouns")
async def update_pronouns(
    pronouns: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Update user pronouns"""
    current_user.pronouns = pronouns
    db.commit()

    return {"message": "Pronouns updated", "pronouns": pronouns}


@router.get("/me/subscription", response_model=schemas.SubscriptionStatusResponse)
async def get_subscription_status(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get current user's Premium subscription status.

    This endpoint is critical for iOS Premium state synchronization.
    Returns subscription details including tier, status, and features.
    """
    from models_premium import Subscription
    from datetime import datetime

    # Query subscription
    subscription = db.query(Subscription).filter(
        Subscription.user_id == current_user.id
    ).first()

    if not subscription:
        # No subscription record = free tier
        return schemas.SubscriptionStatusResponse(
            has_premium=False,
            tier="free",
            status=None,
            expires_at=None,
            features={}
        )

    # Check if subscription is active and valid
    is_active = (
        subscription.status == "active" and
        subscription.tier == "premium" and
        (subscription.expires_at is None or subscription.expires_at > datetime.utcnow())
    )

    return schemas.SubscriptionStatusResponse(
        has_premium=is_active,
        tier=subscription.tier.value if hasattr(subscription.tier, 'value') else str(subscription.tier),
        status=subscription.status.value if hasattr(subscription.status, 'value') else str(subscription.status),
        expires_at=subscription.expires_at,
        features=subscription.features if subscription.features else {}
    )
