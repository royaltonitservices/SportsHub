"""
Social posts feed endpoints
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
from database import get_db
from dependencies import get_current_active_user
import models
import schemas

router = APIRouter(prefix="/posts", tags=["posts"])


def _build_post_response(post: models.Post, liked_ids: set) -> dict:
    """Convert a Post ORM object to a response dict with is_liked computed."""
    return {
        "id": post.id,
        "author_id": post.author_id,
        "user_id": post.author_id,
        "username": post.author.username if hasattr(post, "author") and post.author else "unknown",
        "content": post.content,
        "sport": post.sport,
        "likes_count": post.likes_count,
        "comments_count": post.comments_count,
        "created_at": post.created_at,
        "is_liked": post.id in liked_ids,
    }


def _get_liked_post_ids(db: Session, user_id, post_ids: list) -> set:
    """Return the set of post_ids that the given user has liked, from a batch of post_ids."""
    if not post_ids:
        return set()
    rows = db.query(models.PostLike.post_id).filter(
        models.PostLike.user_id == user_id,
        models.PostLike.post_id.in_(post_ids),
    ).all()
    return {row.post_id for row in rows}


@router.post("/create", response_model=schemas.PostResponse, status_code=status.HTTP_201_CREATED)
async def create_post(
    post_data: schemas.PostCreate,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Create a new post"""

    post = models.Post(
        author_id=current_user.id,
        content=post_data.content,
        sport=post_data.sport,
        safety_checked=False,  # Will be checked by AI moderation
        moderation_status="pending"
    )

    db.add(post)
    db.commit()
    db.refresh(post)

    # Load author relationship for response
    post.author = current_user

    return _build_post_response(post, set())


@router.get("/feed", response_model=List[schemas.PostResponse])
async def get_feed(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    sport: Optional[models.Sport] = None,
    skip: int = 0,
    limit: int = 20
):
    """Get posts feed with optional sport filter"""

    query = db.query(models.Post).join(
        models.User, models.Post.author_id == models.User.id
    ).filter(
        models.Post.moderation_status != "removed"
    )

    if sport:
        query = query.filter(models.Post.sport == sport)

    posts = query.order_by(models.Post.created_at.desc()).offset(skip).limit(limit).all()

    post_ids = [p.id for p in posts]
    liked_ids = _get_liked_post_ids(db, current_user.id, post_ids)

    return [_build_post_response(p, liked_ids) for p in posts]


@router.get("/{post_id}", response_model=schemas.PostResponse)
async def get_post(
    post_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get a specific post"""

    post = db.query(models.Post).join(
        models.User, models.Post.author_id == models.User.id
    ).filter(models.Post.id == post_id).first()

    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )

    liked_ids = _get_liked_post_ids(db, current_user.id, [post_id])
    return _build_post_response(post, liked_ids)


@router.get("/user/{user_id}", response_model=List[schemas.PostResponse])
async def get_user_posts(
    user_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    skip: int = 0,
    limit: int = 20
):
    """Get posts by a specific user"""

    posts = db.query(models.Post).join(
        models.User, models.Post.author_id == models.User.id
    ).filter(
        models.Post.author_id == user_id,
        models.Post.moderation_status != "removed"
    ).order_by(models.Post.created_at.desc()).offset(skip).limit(limit).all()

    post_ids = [p.id for p in posts]
    liked_ids = _get_liked_post_ids(db, current_user.id, post_ids)

    return [_build_post_response(p, liked_ids) for p in posts]


@router.post("/{post_id}/like")
async def like_post(
    post_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Like a post (idempotent — no-op if already liked)"""

    post = db.query(models.Post).filter(models.Post.id == post_id).first()

    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )

    existing = db.query(models.PostLike).filter(
        models.PostLike.user_id == current_user.id,
        models.PostLike.post_id == post_id,
    ).first()

    if not existing:
        db.add(models.PostLike(user_id=current_user.id, post_id=post_id))
        post.likes_count += 1
        db.commit()

    return {"message": "Post liked"}


@router.delete("/{post_id}/like")
async def unlike_post(
    post_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Unlike a post (idempotent — no-op if not liked)"""

    post = db.query(models.Post).filter(models.Post.id == post_id).first()

    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )

    existing = db.query(models.PostLike).filter(
        models.PostLike.user_id == current_user.id,
        models.PostLike.post_id == post_id,
    ).first()

    if existing:
        db.delete(existing)
        if post.likes_count > 0:
            post.likes_count -= 1
        db.commit()

    return {"message": "Post unliked"}


@router.delete("/{post_id}")
async def delete_post(
    post_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Delete a post (only author can delete)"""

    post = db.query(models.Post).filter(models.Post.id == post_id).first()

    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found"
        )

    if post.author_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Can only delete your own posts"
        )

    db.delete(post)
    db.commit()

    return {"message": "Post deleted"}
