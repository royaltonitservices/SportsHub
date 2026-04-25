"""
Phase 4: Evidence upload and management for match verification

POST /evidence/upload          — multipart; returns upload_id (server-generated URL)
POST /evidence/upload/{id}     — associate an upload_id with a challenge (legacy file_url deprecated)
GET  /evidence/match/{id}      — list evidence for a match
GET  /evidence/required/{id}   — check whether evidence is required
POST /evidence/review/{id}     — admin: review submitted evidence
"""
import os
import logging
import uuid as uuid_pkg
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form
from sqlalchemy.orm import Session
from sqlalchemy import and_
from typing import List, Optional
from uuid import UUID
from datetime import datetime

from database import get_db
from dependencies import get_current_user, require_admin
import models
import schemas

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/evidence", tags=["evidence"])

# ---------------------------------------------------------------------------
# Upload constants
# ---------------------------------------------------------------------------
EVIDENCE_UPLOAD_DIR = "./uploads/evidence"
ALLOWED_MIME_TYPES = {
    "image/jpeg": ".jpg",
    "image/png":  ".png",
    "image/webp": ".webp",
    "image/gif":  ".gif",
    "video/mp4":  ".mp4",
    "video/quicktime": ".mov",
}
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50 MB


# ---------------------------------------------------------------------------
# POST /evidence/upload  — real multipart endpoint
# ---------------------------------------------------------------------------
@router.post("/upload", response_model=schemas.EvidenceFileUploadResponse)
async def upload_evidence_file(
    file: UploadFile = File(...),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Accept actual file bytes from the client, validate, persist to disk,
    create an UploadRecord, and return a server-generated upload_id + canonical URL.

    The client then passes upload_id to POST /evidence/upload/{challenge_id}
    to associate the upload with a specific match.
    """
    # Validate content type
    content_type = file.content_type or ""
    if content_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported file type '{content_type}'. Allowed: {', '.join(ALLOWED_MIME_TYPES)}",
        )

    ext = ALLOWED_MIME_TYPES[content_type]
    file_id = str(uuid_pkg.uuid4())
    filename = f"{file_id}{ext}"
    storage_path = os.path.join(EVIDENCE_UPLOAD_DIR, filename)

    # Read file bytes and enforce size limit
    contents = await file.read()
    if len(contents) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File is empty",
        )
    if len(contents) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File exceeds maximum size of {MAX_FILE_SIZE // (1024 * 1024)} MB",
        )

    # Write to disk
    os.makedirs(EVIDENCE_UPLOAD_DIR, exist_ok=True)
    with open(storage_path, "wb") as f:
        f.write(contents)

    canonical_url = f"/cdn/evidence/{filename}"

    # Create DB record — provides ownership proof and deduplication
    record = models.UploadRecord(
        owner_id=current_user.id,
        storage_path=storage_path,
        canonical_url=canonical_url,
        mime_type=content_type,
        original_filename=file.filename or filename,
        size_bytes=len(contents),
    )
    db.add(record)
    db.commit()
    db.refresh(record)

    return schemas.EvidenceFileUploadResponse(
        upload_id=str(record.id),
        file_url=canonical_url,
        mime_type=content_type,
        size_bytes=len(contents),
    )


# ---------------------------------------------------------------------------
# POST /evidence/upload/{challenge_id}  — associate upload with a challenge
# ---------------------------------------------------------------------------
@router.post("/upload/{challenge_id}")
async def associate_evidence(
    challenge_id: UUID,
    evidence_type: str,                     # "image", "video", "screenshot"
    description: Optional[str] = None,
    upload_id: Optional[str] = None,        # Preferred: ID from POST /evidence/upload
    file_url: str = "",                     # Deprecated: client-supplied URL
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Associate an uploaded file (identified by upload_id) with a specific challenge.

    upload_id (preferred): UUID returned by POST /evidence/upload.
    file_url  (deprecated): legacy query-param path; emits a warning log.
    """
    # Get the challenge
    challenge = db.query(models.Challenge).filter(
        models.Challenge.id == challenge_id
    ).first()

    if not challenge:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Challenge not found",
        )

    # Verify user is part of the match
    if current_user.id not in [challenge.challenger_id, challenge.opponent_id]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to submit evidence for this match",
        )

    # Validate evidence type
    try:
        evidence_enum = models.EvidenceType(evidence_type)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid evidence type. Must be: image, video, or screenshot",
        )

    # Resolve the file URL
    if upload_id:
        # Preferred path: validate upload ownership via UploadRecord
        record = db.query(models.UploadRecord).filter(
            models.UploadRecord.id == upload_id
        ).first()
        if not record:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Upload record not found. Upload the file first via POST /evidence/upload.",
            )
        if str(record.owner_id) != str(current_user.id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Upload does not belong to the current user",
            )
        resolved_url = record.canonical_url
    elif file_url:
        # Deprecated path: client-supplied URL — accept but warn
        logger.warning(
            "[DEPRECATED] /evidence/upload/%s called with file_url query param by user %s. "
            "Migrate to POST /evidence/upload (multipart) + upload_id.",
            challenge_id,
            current_user.id,
        )
        resolved_url = file_url
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Provide upload_id (from POST /evidence/upload) or file_url (deprecated).",
        )

    # Check if evidence submission is required for this user
    sport_profile = db.query(models.SportProfile).filter(
        and_(
            models.SportProfile.user_id == current_user.id,
            models.SportProfile.sport == challenge.sport,
        )
    ).first()

    is_required = sport_profile.should_require_evidence() if sport_profile else False

    # Create evidence record
    evidence = models.MatchEvidence(
        challenge_id=challenge_id,
        submitter_id=current_user.id,
        evidence_type=evidence_enum,
        file_url=resolved_url,
        description=description,
        is_required=is_required,
    )
    db.add(evidence)

    if sport_profile:
        sport_profile.evidence_submissions += 1

    db.commit()
    db.refresh(evidence)

    return {
        "message": "Evidence associated successfully",
        "evidence_id": str(evidence.id),
        "was_required": is_required,
        "status": "uploaded",
    }


# ---------------------------------------------------------------------------
# GET /evidence/match/{challenge_id}
# ---------------------------------------------------------------------------
@router.get("/match/{challenge_id}", response_model=List[schemas.EvidenceResponse])
async def get_match_evidence(
    challenge_id: UUID,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get all evidence submitted for a specific match."""
    challenge = db.query(models.Challenge).filter(
        models.Challenge.id == challenge_id
    ).first()

    if not challenge:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Challenge not found",
        )

    if current_user.id not in [challenge.challenger_id, challenge.opponent_id]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to view evidence for this match",
        )

    evidence_list = db.query(models.MatchEvidence).filter(
        models.MatchEvidence.challenge_id == challenge_id
    ).order_by(models.MatchEvidence.created_at.desc()).all()

    return evidence_list


# ---------------------------------------------------------------------------
# GET /evidence/required/{challenge_id}
# ---------------------------------------------------------------------------
@router.get("/required/{challenge_id}")
async def check_evidence_required(
    challenge_id: UUID,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Check if evidence is required for this match."""
    challenge = db.query(models.Challenge).filter(
        models.Challenge.id == challenge_id
    ).first()

    if not challenge:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Challenge not found",
        )

    challenger_profile = db.query(models.SportProfile).filter(
        and_(
            models.SportProfile.user_id == challenge.challenger_id,
            models.SportProfile.sport == challenge.sport,
        )
    ).first()

    opponent_profile = db.query(models.SportProfile).filter(
        and_(
            models.SportProfile.user_id == challenge.opponent_id,
            models.SportProfile.sport == challenge.sport,
        )
    ).first()

    current_user_is_challenger = current_user.id == challenge.challenger_id
    user_profile = challenger_profile if current_user_is_challenger else opponent_profile
    opponent_profile_check = opponent_profile if current_user_is_challenger else challenger_profile

    user_should_submit = user_profile.should_require_evidence() if user_profile else False
    opponent_should_submit = opponent_profile_check.should_require_evidence() if opponent_profile_check else False

    is_disputed = challenge.status == models.ChallengeStatus.DISPUTED

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
        "requirement": requirement,
        "reason": reason,
        "is_disputed": is_disputed,
        "user_trust_tier": user_profile.trust_tier if user_profile else "standard",
        "opponent_trust_tier": opponent_profile_check.trust_tier if opponent_profile_check else "standard",
    }


# ---------------------------------------------------------------------------
# POST /evidence/review/{evidence_id}  — admin only
# ---------------------------------------------------------------------------
@router.post("/review/{evidence_id}")
async def review_evidence(
    evidence_id: UUID,
    review_status: str,    # "verified" or "rejected"
    review_notes: str,
    current_user: models.User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Admin: review submitted evidence."""
    evidence = db.query(models.MatchEvidence).filter(
        models.MatchEvidence.id == evidence_id
    ).first()

    if not evidence:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Evidence not found",
        )

    try:
        evidence.status = models.EvidenceStatus(review_status)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid status. Must be 'verified' or 'rejected'",
        )

    evidence.reviewed_by = current_user.id
    evidence.review_notes = review_notes
    evidence.reviewed_at = datetime.utcnow()

    db.commit()

    return {
        "message": f"Evidence {review_status}",
        "evidence_id": str(evidence_id),
    }
