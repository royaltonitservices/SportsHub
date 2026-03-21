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
