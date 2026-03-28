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

    return clip


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

    return clips


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

    return clip


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

    return clips


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

    return clips


@router.post("/{clip_id}/like")
async def like_clip(
    clip_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Like a clip"""

    clip = db.query(models.Clip).filter(models.Clip.id == clip_id).first()

    if not clip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clip not found"
        )

    clip.likes_count += 1
    db.commit()

    return {"message": "Clip liked"}


@router.delete("/{clip_id}/like")
async def unlike_clip(
    clip_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Unlike a clip"""

    clip = db.query(models.Clip).filter(models.Clip.id == clip_id).first()

    if not clip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clip not found"
        )

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
            duration=0,  # TODO: Extract duration from video
            safety_checked=False
        )

        db.add(clip)
        db.commit()
        db.refresh(clip)

        # Load author relationship for response
        clip.author = current_user

        return clip

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to upload video: {str(e)}"
        )
