"""
Global search functionality
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_
from typing import List, Dict, Any

from database import get_db
from dependencies import get_current_user
import models
import schemas

router = APIRouter(prefix="/search", tags=["search"])


@router.get("/", response_model=Dict[str, Any])
async def search(
    query: str,
    search_type: str = "all",
    limit: int = 20,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Global search across users, posts, and clips
    """
    if len(query) < 2:
        raise HTTPException(
            status_code=400,
            detail="Query must be at least 2 characters"
        )

    results = {}

    # Get blocked users to exclude from results
    blocked_ids = db.query(models.BlockedUser.blocked_id).filter(
        models.BlockedUser.blocker_id == current_user.id
    ).all()
    blocked_user_ids = [b[0] for b in blocked_ids]

    # Get users who blocked current user
    blockers = db.query(models.BlockedUser.blocker_id).filter(
        models.BlockedUser.blocked_id == current_user.id
    ).all()
    blocker_ids = [b[0] for b in blockers]

    all_blocked = blocked_user_ids + blocker_ids

    # Search users
    if search_type in ["all", "users"]:
        user_query = db.query(models.User).filter(
            or_(
                models.User.username.ilike(f"%{query}%"),
                models.User.display_name.ilike(f"%{query}%")
            )
        )

        if all_blocked:
            user_query = user_query.filter(~models.User.id.in_(all_blocked))

        users = user_query.limit(limit).all()
        results["users"] = [schemas.UserProfile.from_orm(u) for u in users]

    # Search posts
    if search_type in ["all", "posts"]:
        post_query = db.query(models.Post).filter(
            models.Post.content.ilike(f"%{query}%")
        )

        if all_blocked:
            post_query = post_query.filter(~models.Post.author_id.in_(all_blocked))

        posts = post_query.order_by(models.Post.created_at.desc()).limit(limit).all()
        results["posts"] = [schemas.PostResponse.from_orm(p) for p in posts]

    # Search clips
    if search_type in ["all", "clips"]:
        clip_query = db.query(models.Clip).filter(
            models.Clip.title.ilike(f"%{query}%")
        )

        if all_blocked:
            clip_query = clip_query.filter(~models.Clip.author_id.in_(all_blocked))

        clips = clip_query.order_by(models.Clip.created_at.desc()).limit(limit).all()
        results["clips"] = [schemas.ClipResponse.from_orm(c) for c in clips]

    return results


@router.get("/users/{username}", response_model=schemas.UserProfile)
async def search_user_by_username(
    username: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Find a specific user by exact username
    """
    user = db.query(models.User).filter(
        models.User.username == username
    ).first()

    if not user:
        raise HTTPException(
            status_code=404,
            detail="User not found"
        )

    # Check if blocked
    is_blocked = db.query(models.BlockedUser).filter(
        or_(
            and_(
                models.BlockedUser.blocker_id == current_user.id,
                models.BlockedUser.blocked_id == user.id
            ),
            and_(
                models.BlockedUser.blocker_id == user.id,
                models.BlockedUser.blocked_id == current_user.id
            )
        )
    ).first()

    if is_blocked:
        raise HTTPException(
            status_code=403,
            detail="User not accessible"
        )

    return user
