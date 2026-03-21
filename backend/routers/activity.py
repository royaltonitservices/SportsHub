"""
Activity feed endpoints
"""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_, desc
from typing import List
from datetime import datetime, timedelta

from database import get_db
from dependencies import get_current_user
import models

router = APIRouter(prefix="/activity", tags=["activity"])


@router.get("/feed")
async def get_activity_feed(
    limit: int = 50,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get personalized activity feed
    Shows matches, friend activities, rating changes, etc.
    """
    # Get friend IDs
    friendships = db.query(models.Friendship).filter(
        and_(
            or_(
                models.Friendship.user_a_id == current_user.id,
                models.Friendship.user_b_id == current_user.id
            ),
            models.Friendship.status == models.FriendshipStatus.ACCEPTED
        )
    ).all()

    friend_ids = set()
    for f in friendships:
        friend_ids.add(f.user_a_id if f.user_a_id != current_user.id else f.user_b_id)
    friend_ids.add(current_user.id)  # Include own activity

    # Get recent matches involving friends
    recent_time = datetime.utcnow() - timedelta(days=7)
    challenges = db.query(models.Challenge).filter(
        and_(
            or_(
                models.Challenge.challenger_id.in_(friend_ids),
                models.Challenge.opponent_id.in_(friend_ids)
            ),
            models.Challenge.status == models.ChallengeStatus.COMPLETED,
            models.Challenge.completed_at >= recent_time
        )
    ).order_by(desc(models.Challenge.completed_at)).limit(limit).all()

    # Get user details
    user_ids = set()
    for c in challenges:
        user_ids.add(c.challenger_id)
        user_ids.add(c.opponent_id)

    users = db.query(models.User).filter(models.User.id.in_(user_ids)).all()
    user_dict = {u.id: u for u in users}

    # Format activity items
    activities = []
    for challenge in challenges:
        challenger = user_dict.get(challenge.challenger_id)
        opponent = user_dict.get(challenge.opponent_id)

        if not challenger or not opponent:
            continue

        winner = user_dict.get(challenge.winner_id) if challenge.winner_id else None

        activity = {
            "type": "match_completed",
            "timestamp": challenge.completed_at,
            "challenge_id": challenge.id,
            "sport": challenge.sport.value,
            "match_type": challenge.match_type.value if challenge.match_type else "ranked",
            "challenger": {
                "id": challenger.id,
                "username": challenger.username,
                "display_name": challenger.display_name
            },
            "opponent": {
                "id": opponent.id,
                "username": opponent.username,
                "display_name": opponent.display_name
            },
            "winner": {
                "id": winner.id,
                "username": winner.username,
                "display_name": winner.display_name
            } if winner else None,
            "rating_change": {
                "challenger": challenge.challenger_rating_after - challenge.challenger_rating_before if challenge.challenger_rating_after and challenge.challenger_rating_before else 0,
                "opponent": challenge.opponent_rating_after - challenge.opponent_rating_before if challenge.opponent_rating_after and challenge.opponent_rating_before else 0
            } if challenge.match_type == models.MatchType.RANKED else None
        }

        activities.append(activity)

    return activities


@router.get("/recent-matches")
async def get_recent_matches(
    sport: models.Sport = None,
    limit: int = 20,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get user's recent match history
    """
    query = db.query(models.Challenge).filter(
        and_(
            or_(
                models.Challenge.challenger_id == current_user.id,
                models.Challenge.opponent_id == current_user.id
            ),
            models.Challenge.status == models.ChallengeStatus.COMPLETED
        )
    )

    if sport:
        query = query.filter(models.Challenge.sport == sport)

    matches = query.order_by(desc(models.Challenge.completed_at)).limit(limit).all()

    return matches
