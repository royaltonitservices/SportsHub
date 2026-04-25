"""
API endpoints for Highlights (Stories feature)
"""
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_
from datetime import datetime, timedelta
from typing import List
import models
import schemas
import os
import uuid as uuid_pkg
from database import get_db
from dependencies import get_current_active_user

router = APIRouter(prefix="/highlights", tags=["highlights"])


@router.post("/upload")
async def upload_highlight_media(
    media: UploadFile = File(...),
    current_user: models.User = Depends(get_current_active_user)
):
    """Upload media for a highlight (image up to 50MB, or short video)"""
    MAX_SIZE = 50 * 1024 * 1024
    content = await media.read()

    if len(content) > MAX_SIZE:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Media must be under 50MB"
        )

    allowed_types = {
        "image/jpeg", "image/jpg", "image/png", "image/webp",
        "video/mp4", "video/quicktime"
    }
    if media.content_type not in allowed_types:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only JPEG, PNG, WebP images and MP4/MOV videos are supported"
        )

    ext = media.filename.rsplit(".", 1)[-1].lower() if "." in (media.filename or "") else "jpg"
    filename = f"{uuid_pkg.uuid4()}.{ext}"
    save_path = os.path.join("./uploads/highlights", filename)

    with open(save_path, "wb") as f:
        f.write(content)

    return {"media_url": f"/cdn/highlights/{filename}"}


@router.post("/create", response_model=schemas.HighlightResponse)
async def create_highlight(
    highlight_data: schemas.HighlightCreate,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Create a new highlight that expires after 24 hours
    """
    # Set expiration to 24 hours from now
    expires_at = datetime.utcnow() + timedelta(hours=24)

    highlight = models.Highlight(
        user_id=current_user.id,
        media_url=highlight_data.media_url,
        thumbnail_url=highlight_data.thumbnail_url,
        caption=highlight_data.caption,
        sport=highlight_data.sport,
        expires_at=expires_at,
        views_count=0
    )

    db.add(highlight)
    db.commit()
    db.refresh(highlight)

    return schemas.HighlightResponse.from_orm(highlight)


@router.get("/feed", response_model=List[schemas.HighlightFeedItem])
async def get_highlights_feed(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get highlights from friends and users the current user follows.
    Only returns non-expired highlights.
    """
    # Get list of friends
    friendships = db.query(models.Friendship).filter(
        and_(
            or_(
                models.Friendship.user_a_id == current_user.id,
                models.Friendship.user_b_id == current_user.id
            ),
            models.Friendship.status == models.FriendshipStatus.ACCEPTED
        )
    ).all()

    friend_ids = []
    for friendship in friendships:
        if friendship.user_a_id == current_user.id:
            friend_ids.append(friendship.user_b_id)
        else:
            friend_ids.append(friendship.user_a_id)

    # Add current user to see their own highlights
    friend_ids.append(current_user.id)

    # Get non-expired highlights from friends
    now = datetime.utcnow()
    highlights = db.query(models.Highlight).filter(
        and_(
            models.Highlight.user_id.in_(friend_ids),
            models.Highlight.expires_at > now
        )
    ).order_by(models.Highlight.created_at.desc()).all()

    # Group by user and check if current user has viewed
    feed_items = []
    user_highlights = {}

    for highlight in highlights:
        if highlight.user_id not in user_highlights:
            user = db.query(models.User).filter(models.User.id == highlight.user_id).first()
            user_highlights[highlight.user_id] = {
                'user': user,
                'highlights': [],
                'has_unviewed': False
            }

        # Check if current user has viewed this highlight
        view = db.query(models.HighlightView).filter(
            and_(
                models.HighlightView.highlight_id == highlight.id,
                models.HighlightView.viewer_id == current_user.id
            )
        ).first()

        has_viewed = view is not None
        if not has_viewed:
            user_highlights[highlight.user_id]['has_unviewed'] = True

        user_highlights[highlight.user_id]['highlights'].append({
            'highlight': highlight,
            'has_viewed': has_viewed
        })

    # Convert to response format
    for user_id, data in user_highlights.items():
        feed_items.append(schemas.HighlightFeedItem(
            user_id=str(user_id),
            username=data['user'].username,
            display_name=data['user'].display_name,
            avatar_seed=data['user'].avatar_seed,
            has_unviewed=data['has_unviewed'],
            highlight_count=len(data['highlights']),
            latest_thumbnail=data['highlights'][0]['highlight'].thumbnail_url if data['highlights'] else None
        ))

    return feed_items


@router.get("/{highlight_id}", response_model=schemas.HighlightResponse)
async def view_highlight(
    highlight_id: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    View a single highlight and record the view
    """
    highlight = db.query(models.Highlight).filter(models.Highlight.id == highlight_id).first()

    if not highlight:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Highlight not found"
        )

    # Check if expired
    if highlight.expires_at < datetime.utcnow():
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="Highlight has expired"
        )

    # Record view if not already viewed
    existing_view = db.query(models.HighlightView).filter(
        and_(
            models.HighlightView.highlight_id == highlight_id,
            models.HighlightView.viewer_id == current_user.id
        )
    ).first()

    if not existing_view:
        view = models.HighlightView(
            highlight_id=highlight_id,
            viewer_id=current_user.id
        )
        db.add(view)

        # Increment views count
        highlight.views_count += 1
        db.commit()

    db.refresh(highlight)
    return schemas.HighlightResponse.from_orm(highlight)


@router.get("/user/{user_id}", response_model=List[schemas.HighlightResponse])
async def get_user_highlights(
    user_id: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get all non-expired highlights for a specific user
    """
    now = datetime.utcnow()
    highlights = db.query(models.Highlight).filter(
        and_(
            models.Highlight.user_id == user_id,
            models.Highlight.expires_at > now
        )
    ).order_by(models.Highlight.created_at.desc()).all()

    return [schemas.HighlightResponse.from_orm(h) for h in highlights]


@router.delete("/{highlight_id}")
async def delete_highlight(
    highlight_id: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Delete own highlight
    """
    highlight = db.query(models.Highlight).filter(models.Highlight.id == highlight_id).first()

    if not highlight:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Highlight not found"
        )

    # Only owner can delete
    if highlight.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot delete another user's highlight"
        )

    db.delete(highlight)
    db.commit()

    return {"message": "Highlight deleted successfully"}


@router.get("/stats/{highlight_id}")
async def get_highlight_stats(
    highlight_id: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get view statistics for a highlight (owner only)
    """
    highlight = db.query(models.Highlight).filter(models.Highlight.id == highlight_id).first()

    if not highlight:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Highlight not found"
        )

    # Only owner can see stats
    if highlight.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot view stats for another user's highlight"
        )

    # Get viewers
    views = db.query(models.HighlightView).filter(
        models.HighlightView.highlight_id == highlight_id
    ).all()

    viewers = []
    for view in views:
        user = db.query(models.User).filter(models.User.id == view.viewer_id).first()
        if user:
            viewers.append({
                'user_id': str(user.id),
                'username': user.username,
                'display_name': user.display_name,
                'viewed_at': view.viewed_at.isoformat()
            })

    return {
        'highlight_id': str(highlight_id),
        'views_count': highlight.views_count,
        'viewers': viewers
    }
