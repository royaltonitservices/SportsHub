"""
Friend system endpoints for requests, acceptance, and management
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_
from typing import List
from uuid import UUID
from datetime import datetime
from database import get_db
from dependencies import get_current_active_user
import models
import schemas

router = APIRouter(prefix="/friends", tags=["friends"])


@router.post("/request", response_model=schemas.FriendshipResponse, status_code=status.HTTP_201_CREATED)
async def send_friend_request(
    request: schemas.FriendRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Send a friend request to another user"""

    # Can't friend yourself
    if request.target_user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot send friend request to yourself"
        )

    # Check if target user exists
    target_user = db.query(models.User).filter(models.User.id == request.target_user_id).first()
    if not target_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    # Check if friendship already exists
    existing = db.query(models.Friendship).filter(
        or_(
            and_(
                models.Friendship.user_a_id == current_user.id,
                models.Friendship.user_b_id == request.target_user_id
            ),
            and_(
                models.Friendship.user_a_id == request.target_user_id,
                models.Friendship.user_b_id == current_user.id
            )
        )
    ).first()

    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Friendship already exists with status: {existing.status.value}"
        )

    # Create friend request
    friendship = models.Friendship(
        user_a_id=current_user.id,
        user_b_id=request.target_user_id,
        status=models.FriendshipStatus.PENDING,
        initiated_by=current_user.id
    )

    db.add(friendship)
    db.commit()
    db.refresh(friendship)

    return friendship


@router.post("/accept/{friendship_id}", response_model=schemas.FriendshipResponse)
async def accept_friend_request(
    friendship_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Accept a pending friend request"""

    friendship = db.query(models.Friendship).filter(
        models.Friendship.id == friendship_id
    ).first()

    if not friendship:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Friend request not found"
        )

    # Only the recipient can accept
    if friendship.user_b_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot accept this friend request"
        )

    if friendship.status != models.FriendshipStatus.PENDING:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Friend request is {friendship.status.value}"
        )

    friendship.status = models.FriendshipStatus.ACCEPTED
    friendship.accepted_at = datetime.utcnow()
    db.commit()
    db.refresh(friendship)

    return friendship


@router.post("/decline/{friendship_id}")
async def decline_friend_request(
    friendship_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Decline a pending friend request"""

    friendship = db.query(models.Friendship).filter(
        models.Friendship.id == friendship_id
    ).first()

    if not friendship:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Friend request not found"
        )

    if friendship.user_b_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot decline this friend request"
        )

    if friendship.status != models.FriendshipStatus.PENDING:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Friend request is {friendship.status.value}"
        )

    friendship.status = models.FriendshipStatus.DECLINED
    db.commit()

    return {"message": "Friend request declined"}


@router.delete("/{friendship_id}")
async def remove_friend(
    friendship_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Remove a friend (unfriend)"""

    friendship = db.query(models.Friendship).filter(
        models.Friendship.id == friendship_id
    ).first()

    if not friendship:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Friendship not found"
        )

    # Either user can remove the friendship
    if friendship.user_a_id != current_user.id and friendship.user_b_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot remove this friendship"
        )

    db.delete(friendship)
    db.commit()

    return {"message": "Friendship removed"}


@router.get("/list", response_model=List[schemas.FriendshipResponse])
async def get_my_friends(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get all accepted friendships for current user"""

    friendships = db.query(models.Friendship).filter(
        or_(
            models.Friendship.user_a_id == current_user.id,
            models.Friendship.user_b_id == current_user.id
        ),
        models.Friendship.status == models.FriendshipStatus.ACCEPTED
    ).all()

    return friendships


@router.get("/requests/pending", response_model=List[schemas.FriendshipResponse])
async def get_pending_requests(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get all pending friend requests (sent and received)"""

    requests = db.query(models.Friendship).filter(
        or_(
            models.Friendship.user_a_id == current_user.id,
            models.Friendship.user_b_id == current_user.id
        ),
        models.Friendship.status == models.FriendshipStatus.PENDING
    ).all()

    return requests


@router.get("/requests/received", response_model=List[schemas.FriendshipResponse])
async def get_received_requests(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get pending friend requests received by current user"""

    requests = db.query(models.Friendship).filter(
        models.Friendship.user_b_id == current_user.id,
        models.Friendship.status == models.FriendshipStatus.PENDING
    ).all()

    return requests


@router.post("/block/{user_id}", response_model=schemas.FriendshipResponse)
async def block_user(
    user_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Block a user (prevents all interactions)"""

    # Can't block yourself
    if user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot block yourself"
        )

    # Check if target user exists
    target_user = db.query(models.User).filter(models.User.id == user_id).first()
    if not target_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    # Check if relationship already exists
    existing = db.query(models.Friendship).filter(
        or_(
            and_(
                models.Friendship.user_a_id == current_user.id,
                models.Friendship.user_b_id == user_id
            ),
            and_(
                models.Friendship.user_a_id == user_id,
                models.Friendship.user_b_id == current_user.id
            )
        )
    ).first()

    if existing:
        # Update existing relationship to blocked
        existing.status = models.FriendshipStatus.BLOCKED
        existing.initiated_by = current_user.id  # Track who blocked
        db.commit()
        db.refresh(existing)
        return existing
    else:
        # Create new blocked relationship
        block = models.Friendship(
            user_a_id=current_user.id,
            user_b_id=user_id,
            status=models.FriendshipStatus.BLOCKED,
            initiated_by=current_user.id
        )
        db.add(block)
        db.commit()
        db.refresh(block)
        return block


@router.delete("/unblock/{user_id}")
async def unblock_user(
    user_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Unblock a previously blocked user"""

    # Find the block relationship
    block = db.query(models.Friendship).filter(
        or_(
            and_(
                models.Friendship.user_a_id == current_user.id,
                models.Friendship.user_b_id == user_id
            ),
            and_(
                models.Friendship.user_a_id == user_id,
                models.Friendship.user_b_id == current_user.id
            )
        ),
        models.Friendship.status == models.FriendshipStatus.BLOCKED
    ).first()

    if not block:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User is not blocked"
        )

    # Only the blocker can unblock
    if block.initiated_by != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot unblock this user"
        )

    # Remove the block relationship entirely
    db.delete(block)
    db.commit()

    return {"message": "User unblocked"}


@router.get("/blocked", response_model=List[schemas.FriendshipResponse])
async def get_blocked_users(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get all users blocked by current user"""

    blocks = db.query(models.Friendship).filter(
        or_(
            models.Friendship.user_a_id == current_user.id,
            models.Friendship.user_b_id == current_user.id
        ),
        models.Friendship.status == models.FriendshipStatus.BLOCKED,
        models.Friendship.initiated_by == current_user.id
    ).all()

    return blocks


@router.get("/status/{user_id}", response_model=schemas.FriendStatusResponse)
async def get_friend_status(
    user_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Check friendship status with a specific user"""

    friendship = db.query(models.Friendship).filter(
        or_(
            and_(
                models.Friendship.user_a_id == current_user.id,
                models.Friendship.user_b_id == user_id
            ),
            and_(
                models.Friendship.user_a_id == user_id,
                models.Friendship.user_b_id == current_user.id
            )
        )
    ).first()

    if not friendship:
        return schemas.FriendStatusResponse(
            status="none",
            is_friend=False,
            is_pending=False,
            is_blocked=False,
            initiated_by_me=False
        )

    return schemas.FriendStatusResponse(
        status=friendship.status.value,
        is_friend=friendship.status == models.FriendshipStatus.ACCEPTED,
        is_pending=friendship.status == models.FriendshipStatus.PENDING,
        is_blocked=friendship.status == models.FriendshipStatus.BLOCKED,
        initiated_by_me=friendship.initiated_by == current_user.id
    )
