"""
Challenge system endpoints for competitive matches
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_
from typing import List, Optional
from uuid import UUID
from datetime import datetime
from database import get_db
from dependencies import get_current_active_user
import models
import schemas

router = APIRouter(prefix="/challenges", tags=["challenges"])


def are_friends(user_a_id: UUID, user_b_id: UUID, db: Session) -> bool:
    """Check if two users are friends"""
    friendship = db.query(models.Friendship).filter(
        or_(
            and_(
                models.Friendship.user_a_id == user_a_id,
                models.Friendship.user_b_id == user_b_id
            ),
            and_(
                models.Friendship.user_a_id == user_b_id,
                models.Friendship.user_b_id == user_a_id
            )
        ),
        models.Friendship.status == models.FriendshipStatus.ACCEPTED
    ).first()
    return friendship is not None


@router.post("/create", response_model=schemas.ChallengeResponse, status_code=status.HTTP_201_CREATED)
async def create_challenge(
    challenge_data: schemas.ChallengeCreate,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Create a new challenge"""

    # Can't challenge yourself
    if challenge_data.opponent_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot challenge yourself"
        )

    # Check if opponent exists
    opponent = db.query(models.User).filter(models.User.id == challenge_data.opponent_id).first()
    if not opponent:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Opponent not found"
        )

    # Verify friendship
    if not are_friends(current_user.id, challenge_data.opponent_id, db):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Can only challenge friends"
        )

    # Check if both users have profiles for this sport
    challenger_profile = db.query(models.SportProfile).filter(
        models.SportProfile.user_id == current_user.id,
        models.SportProfile.sport == challenge_data.sport
    ).first()

    opponent_profile = db.query(models.SportProfile).filter(
        models.SportProfile.user_id == challenge_data.opponent_id,
        models.SportProfile.sport == challenge_data.sport
    ).first()

    if not challenger_profile or not opponent_profile:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Both users must have profiles for {challenge_data.sport.value}"
        )

    # Create challenge
    challenge = models.Challenge(
        sport=challenge_data.sport,
        challenger_id=current_user.id,
        opponent_id=challenge_data.opponent_id,
        status=models.ChallengeStatus.PENDING
    )

    db.add(challenge)
    db.commit()
    db.refresh(challenge)

    return challenge


@router.post("/{challenge_id}/accept", response_model=schemas.ChallengeResponse)
async def accept_challenge(
    challenge_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Accept a pending challenge"""

    challenge = db.query(models.Challenge).filter(models.Challenge.id == challenge_id).first()

    if not challenge:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Challenge not found"
        )

    # Only opponent can accept
    if challenge.opponent_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the opponent can accept this challenge"
        )

    if challenge.status != models.ChallengeStatus.PENDING:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Challenge is {challenge.status.value}"
        )

    challenge.status = models.ChallengeStatus.ACCEPTED
    db.commit()
    db.refresh(challenge)

    return challenge


@router.post("/{challenge_id}/decline")
async def decline_challenge(
    challenge_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Decline a pending challenge"""

    challenge = db.query(models.Challenge).filter(models.Challenge.id == challenge_id).first()

    if not challenge:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Challenge not found"
        )

    if challenge.opponent_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the opponent can decline this challenge"
        )

    if challenge.status != models.ChallengeStatus.PENDING:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Challenge is {challenge.status.value}"
        )

    challenge.status = models.ChallengeStatus.DECLINED
    db.commit()

    return {"message": "Challenge declined"}


@router.post("/{challenge_id}/complete")
async def complete_challenge(
    challenge_id: UUID,
    winner_id: UUID,
    score_data: Optional[dict] = None,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Complete a challenge and record the result"""

    challenge = db.query(models.Challenge).filter(models.Challenge.id == challenge_id).first()

    if not challenge:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Challenge not found"
        )

    # Only participants can complete
    if current_user.id not in [challenge.challenger_id, challenge.opponent_id]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only participants can complete this challenge"
        )

    if challenge.status != models.ChallengeStatus.ACCEPTED:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Challenge must be accepted before completing"
        )

    # Verify winner is one of the participants
    if winner_id not in [challenge.challenger_id, challenge.opponent_id]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Winner must be one of the participants"
        )

    # Update challenge
    challenge.status = models.ChallengeStatus.COMPLETED
    challenge.winner_id = winner_id
    challenge.score_data = score_data
    challenge.completed_at = datetime.utcnow()

    # Update sport profiles
    winner_profile = db.query(models.SportProfile).filter(
        models.SportProfile.user_id == winner_id,
        models.SportProfile.sport == challenge.sport
    ).first()

    loser_id = challenge.opponent_id if winner_id == challenge.challenger_id else challenge.challenger_id
    loser_profile = db.query(models.SportProfile).filter(
        models.SportProfile.user_id == loser_id,
        models.SportProfile.sport == challenge.sport
    ).first()

    if winner_profile and loser_profile:
        # Update winner stats
        winner_profile.games_played += 1
        winner_profile.wins += 1
        winner_profile.current_streak += 1
        if winner_profile.current_streak > winner_profile.best_streak:
            winner_profile.best_streak = winner_profile.current_streak
        winner_profile.last_played = datetime.utcnow()

        # Update loser stats
        loser_profile.games_played += 1
        loser_profile.losses += 1
        loser_profile.current_streak = 0
        loser_profile.last_played = datetime.utcnow()

    db.commit()

    return {"message": "Challenge completed", "winner_id": str(winner_id)}


@router.get("/my-challenges", response_model=List[schemas.ChallengeResponse])
async def get_my_challenges(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    status_filter: Optional[models.ChallengeStatus] = None
):
    """Get all challenges for current user"""

    query = db.query(models.Challenge).filter(
        or_(
            models.Challenge.challenger_id == current_user.id,
            models.Challenge.opponent_id == current_user.id
        )
    )

    if status_filter:
        query = query.filter(models.Challenge.status == status_filter)

    challenges = query.order_by(models.Challenge.created_at.desc()).all()

    return challenges


@router.get("/{challenge_id}", response_model=schemas.ChallengeResponse)
async def get_challenge(
    challenge_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get challenge details"""

    challenge = db.query(models.Challenge).filter(models.Challenge.id == challenge_id).first()

    if not challenge:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Challenge not found"
        )

    return challenge
