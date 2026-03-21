"""
Phase 4: Evidence upload and management for match verification
"""
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.orm import Session
from sqlalchemy import and_
from typing import List, Optional
from uuid import UUID
from datetime import datetime

from database import get_db
from dependencies import get_current_user, require_admin
import models
import schemas

router = APIRouter(prefix="/evidence", tags=["evidence"])


@router.post("/upload/{challenge_id}")
async def upload_evidence(
    challenge_id: UUID,
    evidence_type: str,  # "image", "video", "screenshot"
    description: Optional[str] = None,
    file_url: str = "",  # In production, this would come from actual file upload
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Upload evidence for a match (Phase 4)

    In production, this would handle actual file upload to S3/CDN.
    For now, we simulate with file_url parameter.
    """
    # Get the challenge
    challenge = db.query(models.Challenge).filter(
        models.Challenge.id == challenge_id
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
            detail="Not authorized to submit evidence for this match"
        )

    # Check if evidence type is valid
    try:
        evidence_enum = models.EvidenceType(evidence_type)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid evidence type. Must be: image, video, or screenshot"
        )

    # Get user's sport profile to check if evidence was required
    sport_profile = db.query(models.SportProfile).filter(
        and_(
            models.SportProfile.user_id == current_user.id,
            models.SportProfile.sport == challenge.sport
        )
    ).first()

    is_required = sport_profile.should_require_evidence() if sport_profile else False

    # Create evidence record
    evidence = models.MatchEvidence(
        challenge_id=challenge_id,
        submitter_id=current_user.id,
        evidence_type=evidence_enum,
        file_url=file_url or f"https://cdn.sportshub.com/evidence/{challenge_id}/{current_user.id}.jpg",
        description=description,
        is_required=is_required
    )

    db.add(evidence)

    # Update user's evidence submission count
    if sport_profile:
        sport_profile.evidence_submissions += 1

    db.commit()
    db.refresh(evidence)

    return {
        "message": "Evidence uploaded successfully",
        "evidence_id": str(evidence.id),
        "was_required": is_required,
        "status": "uploaded"
    }


@router.get("/match/{challenge_id}", response_model=List[schemas.EvidenceResponse])
async def get_match_evidence(
    challenge_id: UUID,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get all evidence submitted for a specific match
    """
    # Get the challenge
    challenge = db.query(models.Challenge).filter(
        models.Challenge.id == challenge_id
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
            detail="Not authorized to view evidence for this match"
        )

    # Get all evidence for this challenge
    evidence_list = db.query(models.MatchEvidence).filter(
        models.MatchEvidence.challenge_id == challenge_id
    ).order_by(models.MatchEvidence.created_at.desc()).all()

    return evidence_list


@router.get("/required/{challenge_id}")
async def check_evidence_required(
    challenge_id: UUID,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Check if evidence is required for this match (Phase 4)

    Returns guidance on whether evidence should be submitted
    """
    challenge = db.query(models.Challenge).filter(
        models.Challenge.id == challenge_id
    ).first()

    if not challenge:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Challenge not found"
        )

    # Get both players' sport profiles
    challenger_profile = db.query(models.SportProfile).filter(
        and_(
            models.SportProfile.user_id == challenge.challenger_id,
            models.SportProfile.sport == challenge.sport
        )
    ).first()

    opponent_profile = db.query(models.SportProfile).filter(
        and_(
            models.SportProfile.user_id == challenge.opponent_id,
            models.SportProfile.sport == challenge.sport
        )
    ).first()

    # Determine requirement level
    current_user_is_challenger = current_user.id == challenge.challenger_id
    user_profile = challenger_profile if current_user_is_challenger else opponent_profile
    opponent_profile_check = opponent_profile if current_user_is_challenger else challenger_profile

    user_should_submit = user_profile.should_require_evidence() if user_profile else False
    opponent_should_submit = opponent_profile_check.should_require_evidence() if opponent_profile_check else False

    # Check if match is disputed
    is_disputed = challenge.status == models.ChallengeStatus.DISPUTED

    # Determine requirement tier
    if is_disputed:
        requirement = "required"
        reason = "Match is under dispute - evidence required to help resolve"
    elif user_should_submit and opponent_should_submit:
        requirement = "required"
        reason = "Both players have elevated trust requirements"
    elif user_should_submit:
        requirement = "required"
        reason = "Your recent match history requires evidence submission"
    elif opponent_should_submit:
        requirement = "recommended"
        reason = "Opponent has elevated trust requirements - evidence recommended for protection"
    else:
        requirement = "optional"
        reason = "Evidence is optional but can speed up any future disputes"

    return {
        "challenge_id": str(challenge_id),
        "requirement": requirement,  # "optional", "recommended", "required"
        "reason": reason,
        "is_disputed": is_disputed,
        "user_trust_tier": user_profile.trust_tier if user_profile else "standard",
        "opponent_trust_tier": opponent_profile_check.trust_tier if opponent_profile_check else "standard"
    }


@router.post("/review/{evidence_id}")
async def review_evidence(
    evidence_id: UUID,
    status: str,  # "verified" or "rejected"
    review_notes: str,
    current_user: models.User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    Admin: Review submitted evidence
    """
    evidence = db.query(models.MatchEvidence).filter(
        models.MatchEvidence.id == evidence_id
    ).first()

    if not evidence:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Evidence not found"
        )

    # Update evidence status
    try:
        evidence.status = models.EvidenceStatus(status)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid status. Must be 'verified' or 'rejected'"
        )

    evidence.reviewed_by = current_user.id
    evidence.review_notes = review_notes
    evidence.reviewed_at = datetime.utcnow()

    db.commit()

    return {
        "message": f"Evidence {status}",
        "evidence_id": str(evidence_id)
    }
