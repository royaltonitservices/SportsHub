"""
Content moderation endpoints for reporting and flagging
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
from database import get_db
from dependencies import get_current_active_user, get_current_admin_user
import models
import schemas

router = APIRouter(prefix="/moderation", tags=["moderation"])


@router.post("/report", status_code=status.HTTP_201_CREATED)
async def report_content(
    content_type: str,
    content_id: UUID,
    reason: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Report content for moderation"""

    # Validate content type
    valid_types = ["post", "clip", "message", "user"]
    if content_type not in valid_types:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid content type. Must be one of: {valid_types}"
        )

    # Verify content exists
    if content_type == "post":
        content = db.query(models.Post).filter(models.Post.id == content_id).first()
    elif content_type == "clip":
        content = db.query(models.Clip).filter(models.Clip.id == content_id).first()
    elif content_type == "message":
        content = db.query(models.Message).filter(models.Message.id == content_id).first()
    elif content_type == "user":
        content = db.query(models.User).filter(models.User.id == content_id).first()

    if not content:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"{content_type.capitalize()} not found"
        )

    # Create moderation flag
    flag = models.ModerationFlag(
        content_type=content_type,
        content_id=content_id,
        reporter_id=current_user.id,
        reason=reason,
        status="pending"
    )

    db.add(flag)
    db.commit()

    return {"message": "Content reported for moderation"}


@router.get("/flags", response_model=List[schemas.ModerationFlagResponse])
async def get_moderation_flags(
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin_user),
    status_filter: Optional[str] = None,
    content_type: Optional[str] = None,
    limit: int = 100
):
    """Get all moderation flags (admin only)"""

    query = db.query(models.ModerationFlag)

    if status_filter:
        query = query.filter(models.ModerationFlag.status == status_filter)

    if content_type:
        query = query.filter(models.ModerationFlag.content_type == content_type)

    flags = query.order_by(models.ModerationFlag.created_at.desc()).limit(limit).all()

    return flags


@router.post("/flags/{flag_id}/resolve")
async def resolve_flag(
    flag_id: UUID,
    action: str,
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin_user)
):
    """Resolve a moderation flag (admin only)"""

    flag = db.query(models.ModerationFlag).filter(models.ModerationFlag.id == flag_id).first()

    if not flag:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Flag not found"
        )

    valid_actions = ["remove", "dismiss", "warn"]
    if action not in valid_actions:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid action. Must be one of: {valid_actions}"
        )

    # Update flag status
    flag.status = "resolved"
    db.commit()

    # Take action on content
    if action == "remove":
        if flag.content_type == "post":
            post = db.query(models.Post).filter(models.Post.id == flag.content_id).first()
            if post:
                post.moderation_status = "removed"
        elif flag.content_type == "clip":
            clip = db.query(models.Clip).filter(models.Clip.id == flag.content_id).first()
            if clip:
                db.delete(clip)
        elif flag.content_type == "message":
            message = db.query(models.Message).filter(models.Message.id == flag.content_id).first()
            if message:
                message.moderation_status = "removed"

    # Log admin action
    admin_action = models.AdminAction(
        admin_id=admin.id,
        target_content_id=flag.content_id,
        action_type=f"{action}_content",
        reason=f"Resolved flag: {flag.reason}"
    )
    db.add(admin_action)
    db.commit()

    return {"message": f"Flag resolved with action: {action}"}


@router.post("/flags/{flag_id}/dismiss")
async def dismiss_flag(
    flag_id: UUID,
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin_user)
):
    """Dismiss a moderation flag (admin only)"""

    flag = db.query(models.ModerationFlag).filter(models.ModerationFlag.id == flag_id).first()

    if not flag:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Flag not found"
        )

    flag.status = "dismissed"
    db.commit()

    # Log admin action
    admin_action = models.AdminAction(
        admin_id=admin.id,
        target_content_id=flag.content_id,
        action_type="dismiss_flag",
        reason=f"Dismissed report: {flag.reason}"
    )
    db.add(admin_action)
    db.commit()

    return {"message": "Flag dismissed"}
