"""
Video clips feed endpoints
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
from database import get_db
from dependencies import get_current_active_user
import models
import schemas

router = APIRouter(prefix="/clips", tags=["clips"])


def _build_clip_response(clip: models.Clip, liked_ids: set) -> dict:
    """Convert a Clip ORM object to a response dict with is_liked computed."""
    return {
        "id": clip.id,
        "author_id": clip.author_id,
        "user_id": clip.author_id,
        "username": clip.author.username if hasattr(clip, "author") and clip.author else "unknown",
        "sport": clip.sport,
        "title": clip.title,
        "description": getattr(clip, "description", None),
        "video_url": clip.video_url,
        "thumbnail_url": getattr(clip, "thumbnail_url", None),
        "duration": clip.duration,
        "views_count": clip.views_count,
        "likes_count": clip.likes_count,
        "created_at": clip.created_at,
        "is_liked": clip.id in liked_ids,
    }


def _get_liked_clip_ids(db: Session, user_id, clip_ids: list) -> set:
    """Return the set of clip_ids that the given user has liked, from a batch of clip_ids."""
    if not clip_ids:
        return set()
    rows = db.query(models.ClipLike.clip_id).filter(
        models.ClipLike.user_id == user_id,
        models.ClipLike.clip_id.in_(clip_ids),
    ).all()
    return {row.clip_id for row in rows}


@router.post("/create", response_model=schemas.ClipResponse, status_code=status.HTTP_201_CREATED)
async def create_clip(
    clip_data: schemas.ClipCreate,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Create a new clip"""

    clip = models.Clip(
        author_id=current_user.id,
        sport=clip_data.sport,
        title=clip_data.title,
        video_url=clip_data.video_url,
        duration=clip_data.duration,
        safety_checked=False  # Will be checked by AI moderation
    )

    db.add(clip)
    db.commit()
    db.refresh(clip)

    # Load author relationship for response
    clip.author = current_user

    return _build_clip_response(clip, set())


@router.get("/feed", response_model=List[schemas.ClipResponse])
async def get_clips_feed(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    sport: Optional[models.Sport] = None,
    skip: int = 0,
    limit: int = 20
):
    """Get clips feed with optional sport filter"""

    query = db.query(models.Clip).join(
        models.User, models.Clip.author_id == models.User.id
    )

    if sport:
        query = query.filter(models.Clip.sport == sport)

    clips = query.order_by(models.Clip.created_at.desc()).offset(skip).limit(limit).all()

    clip_ids = [c.id for c in clips]
    liked_ids = _get_liked_clip_ids(db, current_user.id, clip_ids)

    return [_build_clip_response(c, liked_ids) for c in clips]


@router.get("/{clip_id}", response_model=schemas.ClipResponse)
async def get_clip(
    clip_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get a specific clip"""

    clip = db.query(models.Clip).join(
        models.User, models.Clip.author_id == models.User.id
    ).filter(models.Clip.id == clip_id).first()

    if not clip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clip not found"
        )

    # Increment view count
    clip.views_count += 1
    db.commit()

    liked_ids = _get_liked_clip_ids(db, current_user.id, [clip_id])
    return _build_clip_response(clip, liked_ids)


@router.get("/user/{user_id}", response_model=List[schemas.ClipResponse])
async def get_user_clips(
    user_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    skip: int = 0,
    limit: int = 20
):
    """Get clips by a specific user"""

    clips = db.query(models.Clip).join(
        models.User, models.Clip.author_id == models.User.id
    ).filter(
        models.Clip.author_id == user_id
    ).order_by(models.Clip.created_at.desc()).offset(skip).limit(limit).all()

    clip_ids = [c.id for c in clips]
    liked_ids = _get_liked_clip_ids(db, current_user.id, clip_ids)

    return [_build_clip_response(c, liked_ids) for c in clips]


@router.get("/trending", response_model=List[schemas.ClipResponse])
async def get_trending_clips(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    sport: Optional[models.Sport] = None,
    limit: int = 20
):
    """Get trending clips sorted by views and likes"""

    query = db.query(models.Clip).join(
        models.User, models.Clip.author_id == models.User.id
    )

    if sport:
        query = query.filter(models.Clip.sport == sport)

    clips = query.order_by(
        (models.Clip.views_count + models.Clip.likes_count * 5).desc()
    ).limit(limit).all()

    clip_ids = [c.id for c in clips]
    liked_ids = _get_liked_clip_ids(db, current_user.id, clip_ids)

    return [_build_clip_response(c, liked_ids) for c in clips]


@router.post("/{clip_id}/like")
async def like_clip(
    clip_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Like a clip (idempotent — no-op if already liked)"""

    clip = db.query(models.Clip).filter(models.Clip.id == clip_id).first()

    if not clip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clip not found"
        )

    existing = db.query(models.ClipLike).filter(
        models.ClipLike.user_id == current_user.id,
        models.ClipLike.clip_id == clip_id,
    ).first()

    if not existing:
        db.add(models.ClipLike(user_id=current_user.id, clip_id=clip_id))
        clip.likes_count += 1
        db.commit()

    return {"message": "Clip liked"}


@router.delete("/{clip_id}/like")
async def unlike_clip(
    clip_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Unlike a clip (idempotent — no-op if not liked)"""

    clip = db.query(models.Clip).filter(models.Clip.id == clip_id).first()

    if not clip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clip not found"
        )

    existing = db.query(models.ClipLike).filter(
        models.ClipLike.user_id == current_user.id,
        models.ClipLike.clip_id == clip_id,
    ).first()

    if existing:
        db.delete(existing)
        if clip.likes_count > 0:
            clip.likes_count -= 1
        db.commit()

    return {"message": "Clip unliked"}


@router.delete("/{clip_id}")
async def delete_clip(
    clip_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Delete a clip (only author can delete)"""

    clip = db.query(models.Clip).filter(models.Clip.id == clip_id).first()

    if not clip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clip not found"
        )

    if clip.author_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Can only delete your own clips"
        )

    db.delete(clip)
    db.commit()

    return {"message": "Clip deleted"}


# Video upload endpoint
from fastapi import File, UploadFile, Form
from video_cdn import video_cdn


@router.post("/upload", response_model=schemas.ClipResponse, status_code=status.HTTP_201_CREATED)
async def upload_clip(
    video: UploadFile = File(...),
    title: str = Form(...),
    sport: str = Form(...),
    description: Optional[str] = Form(None),
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Upload video clip with file.

    Accepts multipart/form-data with:
    - video: Video file (MP4, MOV)
    - title: Clip title
    - sport: Sport category
    - description: Optional description
    """

    # Validate file size (max 500 MB)
    MAX_SIZE = 500 * 1024 * 1024  # 500 MB
    content = await video.read()

    if len(content) > MAX_SIZE:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Video file too large. Maximum size is 500MB"
        )

    # Validate file type
    allowed_types = ["video/mp4", "video/quicktime", "video/x-msvideo"]
    if video.content_type not in allowed_types:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Invalid video format. Supported: MP4, MOV"
        )

    try:
        # Upload to CDN
        video_url, video_id, thumbnail_url = await video_cdn.upload_video(
            file_content=content,
            filename=video.filename,
            user_id=str(current_user.id)
        )

        # Create clip record
        clip = models.Clip(
            author_id=current_user.id,
            sport=models.Sport(sport),
            title=title,
            description=description,
            video_url=video_url,
            thumbnail_url=thumbnail_url,
            duration=0,  # Duration extraction requires ffprobe — tracked as future work
            safety_checked=False
        )

        db.add(clip)
        db.commit()
        db.refresh(clip)

        # Load author relationship for response
        clip.author = current_user

        return _build_clip_response(clip, set())

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to upload video: {str(e)}"
        )
