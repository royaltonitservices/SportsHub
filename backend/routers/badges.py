"""
Badge system endpoints
"""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID

from database import get_db
from dependencies import get_current_user
from badges_data import get_badges_for_sport, get_badge_by_id
import models
import schemas

router = APIRouter(prefix="/badges", tags=["badges"])


@router.get("/available/{sport}")
async def get_available_badges(
    sport: models.Sport,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get all available badges for a sport
    """
    badges = get_badges_for_sport(sport)

    # Get user's earned badges
    earned = db.query(models.UserBadge).filter(
        models.UserBadge.user_id == current_user.id,
        models.UserBadge.sport == sport
    ).all()

    earned_ids = {b.badge_id for b in earned}

    # Format response
    result = []
    for badge in badges:
        result.append({
            **badge,
            "earned": badge["id"] in earned_ids,
            "earned_at": next((b.earned_at for b in earned if b.badge_id == badge["id"]), None)
        })

    return result


@router.get("/my-badges")
async def get_my_badges(
    sport: models.Sport = None,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get user's earned badges
    """
    query = db.query(models.UserBadge).filter(
        models.UserBadge.user_id == current_user.id
    )

    if sport:
        query = query.filter(models.UserBadge.sport == sport)

    user_badges = query.all()

    # Enrich with badge details
    result = []
    for ub in user_badges:
        badge_data = get_badge_by_id(ub.badge_id)
        if badge_data:
            result.append({
                **badge_data,
                "earned_at": ub.earned_at,
                "sport": ub.sport.value
            })

    return result


@router.get("/stats")
async def get_badge_stats(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get badge statistics for user
    """
    from sqlalchemy import func

    stats = {}
    for sport in models.Sport:
        total_badges = len(get_badges_for_sport(sport))
        earned = db.query(func.count(models.UserBadge.id)).filter(
            models.UserBadge.user_id == current_user.id,
            models.UserBadge.sport == sport
        ).scalar()

        stats[sport.value] = {
            "total": total_badges,
            "earned": earned or 0,
            "percentage": round((earned or 0) / total_badges * 100, 1) if total_badges > 0 else 0
        }

    return stats
