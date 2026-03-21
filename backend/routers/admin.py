"""
Admin panel endpoints for user management and platform oversight
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
from datetime import datetime
from database import get_db
from dependencies import get_current_admin_user
import models
import schemas

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/users", response_model=List[schemas.AdminUserList])
async def get_all_users(
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin_user),
    skip: int = 0,
    limit: int = 100,
    account_status: Optional[models.AccountStatus] = None
):
    """Get list of all users (admin only)"""

    query = db.query(models.User)

    if account_status:
        query = query.filter(models.User.account_status == account_status)

    users = query.offset(skip).limit(limit).all()

    return users


@router.get("/users/{user_id}", response_model=schemas.UserProfile)
async def get_user_details(
    user_id: UUID,
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin_user)
):
    """Get detailed user information (admin only)"""

    user = db.query(models.User).filter(models.User.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    return user


@router.post("/users/{user_id}/suspend")
async def suspend_user(
    user_id: UUID,
    reason: str,
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin_user)
):
    """Suspend a user account (admin only)"""

    user = db.query(models.User).filter(models.User.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    if user.role == models.UserRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot suspend admin users"
        )

    user.account_status = models.AccountStatus.SUSPENDED

    # Log admin action
    action = models.AdminAction(
        admin_id=admin.id,
        target_user_id=user_id,
        action_type="suspend_user",
        reason=reason
    )
    db.add(action)

    db.commit()

    return {"message": f"User {user.username} suspended"}


@router.post("/users/{user_id}/ban")
async def ban_user(
    user_id: UUID,
    reason: str,
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin_user)
):
    """Permanently ban a user account (admin only)"""

    user = db.query(models.User).filter(models.User.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    if user.role == models.UserRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot ban admin users"
        )

    user.account_status = models.AccountStatus.BANNED

    # Log admin action
    action = models.AdminAction(
        admin_id=admin.id,
        target_user_id=user_id,
        action_type="ban_user",
        reason=reason
    )
    db.add(action)

    db.commit()

    return {"message": f"User {user.username} banned"}


@router.post("/users/{user_id}/shadow-ban")
async def shadow_ban_user(
    user_id: UUID,
    reason: str,
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin_user)
):
    """Shadow ban a user (admin only)"""

    user = db.query(models.User).filter(models.User.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    if user.role == models.UserRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot shadow ban admin users"
        )

    user.account_status = models.AccountStatus.SHADOW_BANNED

    # Log admin action
    action = models.AdminAction(
        admin_id=admin.id,
        target_user_id=user_id,
        action_type="shadow_ban_user",
        reason=reason
    )
    db.add(action)

    db.commit()

    return {"message": f"User {user.username} shadow banned"}


@router.post("/users/{user_id}/reactivate")
async def reactivate_user(
    user_id: UUID,
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin_user)
):
    """Reactivate a suspended/banned user (admin only)"""

    user = db.query(models.User).filter(models.User.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    user.account_status = models.AccountStatus.ACTIVE

    # Log admin action
    action = models.AdminAction(
        admin_id=admin.id,
        target_user_id=user_id,
        action_type="reactivate_user",
        reason="Account reactivated by admin"
    )
    db.add(action)

    db.commit()

    return {"message": f"User {user.username} reactivated"}


@router.get("/actions", response_model=List[dict])
async def get_admin_actions(
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin_user),
    limit: int = 100
):
    """Get recent admin actions (admin only)"""

    actions = db.query(models.AdminAction).order_by(
        models.AdminAction.timestamp.desc()
    ).limit(limit).all()

    # Include admin username in response
    result = []
    for action in actions:
        admin_user = db.query(models.User).filter(models.User.id == action.admin_id).first()
        result.append({
            "id": str(action.id),
            "admin_username": admin_user.username if admin_user else "Unknown",
            "target_user_id": str(action.target_user_id) if action.target_user_id else None,
            "action_type": action.action_type,
            "reason": action.reason,
            "timestamp": action.timestamp
        })

    return result


@router.get("/stats")
async def get_platform_stats(
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_current_admin_user)
):
    """Get platform statistics (admin only)"""

    total_users = db.query(models.User).count()
    active_users = db.query(models.User).filter(
        models.User.account_status == models.AccountStatus.ACTIVE
    ).count()
    suspended_users = db.query(models.User).filter(
        models.User.account_status == models.AccountStatus.SUSPENDED
    ).count()
    banned_users = db.query(models.User).filter(
        models.User.account_status == models.AccountStatus.BANNED
    ).count()

    total_posts = db.query(models.Post).count()
    total_clips = db.query(models.Clip).count()
    total_messages = db.query(models.Message).count()
    total_challenges = db.query(models.Challenge).count()

    pending_flags = db.query(models.ModerationFlag).filter(
        models.ModerationFlag.status == "pending"
    ).count()

    return {
        "users": {
            "total": total_users,
            "active": active_users,
            "suspended": suspended_users,
            "banned": banned_users
        },
        "content": {
            "posts": total_posts,
            "clips": total_clips,
            "messages": total_messages,
            "challenges": total_challenges
        },
        "moderation": {
            "pending_flags": pending_flags
        }
    }
