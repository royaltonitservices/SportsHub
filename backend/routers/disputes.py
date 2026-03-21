"""
Dispute resolution system endpoints
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
from datetime import datetime

from database import get_db
from dependencies import get_current_user, require_admin
import models
import schemas

router = APIRouter(prefix="/disputes", tags=["disputes"])


@router.post("/create", response_model=schemas.DisputeResponse)
async def create_dispute(
    dispute_data: schemas.DisputeCreate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Create a dispute for a match result
    """
    # Get the challenge
    challenge = db.query(models.Challenge).filter(
        models.Challenge.id == dispute_data.challenge_id
    ).first()

    if not challenge:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Challenge not found"
        )

    # Verify user is part of the match
    if current_user.id not in [challenge.challenger_id, challenge.opponent_id]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to dispute this match"
        )

    # Check if match is completed
    if challenge.status != models.ChallengeStatus.COMPLETED:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Can only dispute completed matches"
        )

    # Check if dispute already exists
    existing_dispute = db.query(models.Dispute).filter(
        models.Dispute.challenge_id == dispute_data.challenge_id
    ).first()

    if existing_dispute:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Dispute already exists for this match"
        )

    # Create dispute
    new_dispute = models.Dispute(
        challenge_id=dispute_data.challenge_id,
        initiator_id=current_user.id,
        reason=dispute_data.reason,
        evidence=dispute_data.evidence,
        status=models.DisputeStatus.PENDING
    )

    # Update challenge status
    challenge.status = models.ChallengeStatus.DISPUTED

    db.add(new_dispute)
    db.commit()
    db.refresh(new_dispute)

    return new_dispute


@router.get("/my-disputes", response_model=List[schemas.DisputeResponse])
async def get_my_disputes(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get all disputes involving current user (Phase 3 - Trust System)

    Returns disputes where user is either:
    - The initiator, OR
    - Part of the challenged match (challenger or opponent)
    """
    # Get all disputes for matches involving this user
    from sqlalchemy import or_

    # Subquery to get challenges involving current user
    user_challenges = db.query(models.Challenge.id).filter(
        or_(
            models.Challenge.challenger_id == current_user.id,
            models.Challenge.opponent_id == current_user.id
        )
    ).subquery()

    # Get disputes for those challenges
    disputes = db.query(models.Dispute).filter(
        models.Dispute.challenge_id.in_(user_challenges)
    ).order_by(models.Dispute.created_at.desc()).all()

    return disputes


@router.get("/all", response_model=List[schemas.DisputeResponse])
async def get_all_disputes(
    status_filter: models.DisputeStatus = None,
    current_user: models.User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    Admin: Get all disputes with optional status filter
    """
    query = db.query(models.Dispute)

    if status_filter:
        query = query.filter(models.Dispute.status == status_filter)

    disputes = query.order_by(models.Dispute.created_at.desc()).all()

    return disputes


@router.post("/resolve/{dispute_id}")
async def resolve_dispute(
    dispute_id: UUID,
    resolution: str,  # "uphold" or "reverse"
    admin_notes: str,
    current_user: models.User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    Admin: Resolve a dispute
    """
    dispute = db.query(models.Dispute).filter(
        models.Dispute.id == dispute_id
    ).first()

    if not dispute:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Dispute not found"
        )

    if dispute.status != models.DisputeStatus.PENDING:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Dispute is not pending"
        )

    # Get the challenge
    challenge = db.query(models.Challenge).filter(
        models.Challenge.id == dispute.challenge_id
    ).first()

    if resolution == "reverse":
        # Reverse the match result
        # Get sport profiles
        challenger_profile = db.query(models.SportProfile).filter(
            models.SportProfile.user_id == challenge.challenger_id,
            models.SportProfile.sport == challenge.sport
        ).first()

        opponent_profile = db.query(models.SportProfile).filter(
            models.SportProfile.user_id == challenge.opponent_id,
            models.SportProfile.sport == challenge.sport
        ).first()

        # Reverse ratings if it was a ranked match
        if challenge.match_type == models.MatchType.RANKED:
            challenger_profile.rating = challenge.challenger_rating_before
            opponent_profile.rating = challenge.opponent_rating_before

            # Update rank tiers
            from elo_service import EloService
            challenger_profile.rank_tier = EloService.calculate_rank_tier(challenger_profile.rating)
            opponent_profile.rank_tier = EloService.calculate_rank_tier(opponent_profile.rating)

        # Reverse win/loss statistics
        old_winner_id = challenge.winner_id

        if old_winner_id == challenge.challenger_id:
            challenger_profile.wins -= 1
            opponent_profile.losses -= 1
        else:
            opponent_profile.wins -= 1
            challenger_profile.losses -= 1

        # Mark challenge as resolved (no winner)
        challenge.winner_id = None
        challenge.status = models.ChallengeStatus.COMPLETED

    elif resolution == "uphold":
        # Keep original result
        challenge.status = models.ChallengeStatus.COMPLETED
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid resolution type. Must be 'uphold' or 'reverse'"
        )

    # Update dispute
    dispute.status = models.DisputeStatus.RESOLVED
    dispute.admin_notes = admin_notes
    dispute.resolved_by = current_user.id
    dispute.resolved_at = datetime.utcnow()

    db.commit()

    return {"message": f"Dispute resolved: {resolution}", "dispute_id": dispute_id}


@router.post("/reject/{dispute_id}")
async def reject_dispute(
    dispute_id: UUID,
    admin_notes: str,
    current_user: models.User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    Admin: Reject a dispute
    """
    dispute = db.query(models.Dispute).filter(
        models.Dispute.id == dispute_id
    ).first()

    if not dispute:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Dispute not found"
        )

    # Update dispute
    dispute.status = models.DisputeStatus.REJECTED
    dispute.admin_notes = admin_notes
    dispute.resolved_by = current_user.id
    dispute.resolved_at = datetime.utcnow()

    # Get the challenge and restore completed status
    challenge = db.query(models.Challenge).filter(
        models.Challenge.id == dispute.challenge_id
    ).first()

    if challenge:
        challenge.status = models.ChallengeStatus.COMPLETED

    db.commit()

    return {"message": "Dispute rejected", "dispute_id": dispute_id}
