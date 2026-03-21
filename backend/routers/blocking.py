"""
User blocking system endpoints
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_
from typing import List
from uuid import UUID

from database import get_db
from dependencies import get_current_user
import models
import schemas

router = APIRouter(prefix="/blocking", tags=["blocking"])


@router.post("/block")
async def block_user(
    block_data: schemas.BlockUser,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Block a user
    """
    # Can't block yourself
    if block_data.blocked_user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot block yourself"
        )

    # Check if user exists
    blocked_user = db.query(models.User).filter(
        models.User.id == block_data.blocked_user_id
    ).first()

    if not blocked_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    # Check if already blocked
    existing_block = db.query(models.BlockedUser).filter(
        and_(
            models.BlockedUser.blocker_id == current_user.id,
            models.BlockedUser.blocked_id == block_data.blocked_user_id
        )
    ).first()

    if existing_block:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User already blocked"
        )

    # Create block
    new_block = models.BlockedUser(
        blocker_id=current_user.id,
        blocked_id=block_data.blocked_user_id
    )

    # Remove friendship if exists
    friendship = db.query(models.Friendship).filter(
        or_(
            and_(
                models.Friendship.user_a_id == current_user.id,
                models.Friendship.user_b_id == block_data.blocked_user_id
            ),
            and_(
                models.Friendship.user_a_id == block_data.blocked_user_id,
                models.Friendship.user_b_id == current_user.id
            )
        )
    ).first()

    if friendship:
        db.delete(friendship)

    db.add(new_block)
    db.commit()

    return {"message": "User blocked successfully"}


@router.post("/unblock/{blocked_user_id}")
async def unblock_user(
    blocked_user_id: UUID,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Unblock a user
    """
    block = db.query(models.BlockedUser).filter(
        and_(
            models.BlockedUser.blocker_id == current_user.id,
            models.BlockedUser.blocked_id == blocked_user_id
        )
    ).first()

    if not block:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Block not found"
        )

    db.delete(block)
    db.commit()

    return {"message": "User unblocked successfully"}


@router.get("/my-blocked-users", response_model=List[schemas.UserProfile])
async def get_blocked_users(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get list of users blocked by current user
    """
    blocked_ids = db.query(models.BlockedUser.blocked_id).filter(
        models.BlockedUser.blocker_id == current_user.id
    ).all()

    blocked_user_ids = [b[0] for b in blocked_ids]

    if not blocked_user_ids:
        return []

    blocked_users = db.query(models.User).filter(
        models.User.id.in_(blocked_user_ids)
    ).all()

    return blocked_users
