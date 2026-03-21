"""
Sport profile management endpoints
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from database import get_db
from dependencies import get_current_active_user
import models
import schemas

router = APIRouter(prefix="/sports", tags=["sports"])


@router.get("/profiles", response_model=List[schemas.SportProfileResponse])
async def get_my_sport_profiles(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get all sport profiles for current user"""
    profiles = db.query(models.SportProfile).filter(
        models.SportProfile.user_id == current_user.id
    ).all()

    return profiles


@router.get("/profiles/{sport}", response_model=schemas.SportProfileResponse)
async def get_my_sport_profile(
    sport: models.Sport,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get specific sport profile for current user"""
    profile = db.query(models.SportProfile).filter(
        models.SportProfile.user_id == current_user.id,
        models.SportProfile.sport == sport
    ).first()

    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Sport profile for {sport.value} not found"
        )

    return profile


@router.get("/profiles/user/{user_id}", response_model=List[schemas.SportProfileResponse])
async def get_user_sport_profiles(
    user_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
):
    """Get all sport profiles for a specific user"""
    profiles = db.query(models.SportProfile).filter(
        models.SportProfile.user_id == user_id
    ).all()

    return profiles
