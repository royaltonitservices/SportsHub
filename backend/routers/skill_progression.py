"""
Skill Progression sync endpoints.

Stores per-user, per-sport skill snapshots so the SkillProgressionEngine can
sync its local state to the backend, enabling cross-device continuity.

Routes:
  GET  /skill-progression/{sport}  — fetch the current snapshot (404 if none)
  PUT  /skill-progression/{sport}  — upsert full snapshot (replaces previous)
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime

from database import get_db
from dependencies import get_current_active_user
import models

router = APIRouter(prefix="/skill-progression", tags=["skill-progression"])


# ---------------------------------------------------------------------------
# MARK: - Pydantic schemas (local to this router)
# ---------------------------------------------------------------------------

class SkillScorePayload(BaseModel):
    category: str
    score: float
    trend: str
    last_updated: Optional[str] = None
    data_points: int = 0


class SkillSnapshotRequest(BaseModel):
    skills: List[SkillScorePayload]


class SkillSnapshotResponse(BaseModel):
    sport: str
    skills: List[SkillScorePayload]
    updated_at: Optional[datetime] = None


# ---------------------------------------------------------------------------
# MARK: - Endpoints
# ---------------------------------------------------------------------------

@router.get("/{sport}", response_model=SkillSnapshotResponse)
async def get_skill_snapshot(
    sport: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Return the stored skill snapshot for this user+sport, or 404 if none."""
    try:
        sport_enum = models.Sport(sport.lower())
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unknown sport: {sport}"
        )

    snapshot = db.query(models.SkillSnapshot).filter(
        models.SkillSnapshot.user_id == current_user.id,
        models.SkillSnapshot.sport == sport_enum
    ).first()

    if not snapshot:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No skill snapshot found for this sport"
        )

    skills = [SkillScorePayload(**item) for item in (snapshot.skills_json or [])]
    return SkillSnapshotResponse(sport=sport_enum.value, skills=skills, updated_at=snapshot.updated_at)


@router.put("/{sport}", response_model=SkillSnapshotResponse)
async def upsert_skill_snapshot(
    sport: str,
    body: SkillSnapshotRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Upsert the full skill snapshot for this user+sport."""
    try:
        sport_enum = models.Sport(sport.lower())
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unknown sport: {sport}"
        )

    skills_data = [s.model_dump() for s in body.skills]

    snapshot = db.query(models.SkillSnapshot).filter(
        models.SkillSnapshot.user_id == current_user.id,
        models.SkillSnapshot.sport == sport_enum
    ).first()

    if snapshot:
        snapshot.skills_json = skills_data
        snapshot.updated_at = datetime.utcnow()
    else:
        snapshot = models.SkillSnapshot(
            user_id=current_user.id,
            sport=sport_enum,
            skills_json=skills_data,
            updated_at=datetime.utcnow()
        )
        db.add(snapshot)

    db.commit()
    db.refresh(snapshot)

    skills = [SkillScorePayload(**item) for item in (snapshot.skills_json or [])]
    return SkillSnapshotResponse(sport=sport_enum.value, skills=skills, updated_at=snapshot.updated_at)
