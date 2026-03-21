# Sport-Specific Goals Survey API
# Premium feature for personalized training

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
from pydantic import BaseModel

from database import get_db
from dependencies import get_current_active_user, require_premium
import models
from models_premium import SportGoals, SkillFocus

router = APIRouter(prefix="/goals", tags=["goals"])


# MARK: - Schemas

class GoalsSurveyRequest(BaseModel):
    sport: str
    skill_focus: List[str]
    physical_focus: List[str]
    tactical_focus: List[str]
    mental_focus: List[str]
    custom_goals: Optional[str] = None
    improvement_priority: dict = {}


class GoalsResponse(BaseModel):
    id: str
    sport: str
    skill_focus: List[str]
    physical_focus: List[str]
    tactical_focus: List[str]
    mental_focus: List[str]
    custom_goals: Optional[str]
    improvement_priority: dict
    created_at: str
    updated_at: Optional[str]

    class Config:
        from_attributes = True


class SkillOptionsResponse(BaseModel):
    """Available skills for each sport"""
    basketball: List[str]
    football: List[str]
    soccer: List[str]
    tennis: List[str]
    general: List[str]


# MARK: - Endpoints

@router.get("/skill-options", response_model=SkillOptionsResponse)
async def get_skill_options():
    """Get available skill focus options for all sports"""

    return {
        "basketball": [
            "shooting", "dribbling", "passing", "defense", "rebounding",
            "three_point", "free_throw", "layups", "post_moves", "screens"
        ],
        "football": [
            "throwing", "catching", "running", "blocking", "tackling",
            "route_running", "coverage", "pass_rush", "field_awareness"
        ],
        "soccer": [
            "ball_control", "passing_soccer", "shooting_soccer", "defending",
            "goalkeeping", "crossing", "headers", "dribbling_soccer", "positioning"
        ],
        "tennis": [
            "serve", "forehand", "backhand", "volley", "footwork",
            "overhead", "slice", "topspin", "court_positioning"
        ],
        "general": [
            "endurance", "speed", "strength", "agility", "flexibility",
            "mental_toughness", "strategy", "recovery", "conditioning"
        ]
    }


@router.post("/survey", response_model=GoalsResponse, dependencies=[Depends(require_premium)])
async def submit_goals_survey(
    survey: GoalsSurveyRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Submit or update sport-specific goals survey.

    Premium feature only.
    AI Coach uses this to personalize training.
    """

    # Check if goals already exist for this sport
    existing = db.query(SportGoals).filter(
        SportGoals.user_id == current_user.id,
        SportGoals.sport == models.Sport(survey.sport)
    ).first()

    if existing:
        # Update existing
        existing.skill_focus = survey.skill_focus
        existing.physical_focus = survey.physical_focus
        existing.tactical_focus = survey.tactical_focus
        existing.mental_focus = survey.mental_focus
        existing.custom_goals = survey.custom_goals
        existing.improvement_priority = survey.improvement_priority

        db.commit()
        db.refresh(existing)

        return GoalsResponse(
            id=str(existing.id),
            sport=existing.sport.value,
            skill_focus=existing.skill_focus,
            physical_focus=existing.physical_focus,
            tactical_focus=existing.tactical_focus,
            mental_focus=existing.mental_focus,
            custom_goals=existing.custom_goals,
            improvement_priority=existing.improvement_priority,
            created_at=existing.created_at.isoformat(),
            updated_at=existing.updated_at.isoformat() if existing.updated_at else None
        )

    # Create new
    goals = SportGoals(
        user_id=current_user.id,
        sport=models.Sport(survey.sport),
        skill_focus=survey.skill_focus,
        physical_focus=survey.physical_focus,
        tactical_focus=survey.tactical_focus,
        mental_focus=survey.mental_focus,
        custom_goals=survey.custom_goals,
        improvement_priority=survey.improvement_priority
    )

    db.add(goals)
    db.commit()
    db.refresh(goals)

    return GoalsResponse(
        id=str(goals.id),
        sport=goals.sport.value,
        skill_focus=goals.skill_focus,
        physical_focus=goals.physical_focus,
        tactical_focus=goals.tactical_focus,
        mental_focus=goals.mental_focus,
        custom_goals=goals.custom_goals,
        improvement_priority=goals.improvement_priority,
        created_at=goals.created_at.isoformat(),
        updated_at=None
    )


@router.get("/survey/{sport}", response_model=GoalsResponse, dependencies=[Depends(require_premium)])
async def get_goals_survey(
    sport: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get goals survey for specific sport"""

    goals = db.query(SportGoals).filter(
        SportGoals.user_id == current_user.id,
        SportGoals.sport == models.Sport(sport)
    ).first()

    if not goals:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No goals survey found for {sport}"
        )

    return GoalsResponse(
        id=str(goals.id),
        sport=goals.sport.value,
        skill_focus=goals.skill_focus,
        physical_focus=goals.physical_focus,
        tactical_focus=goals.tactical_focus,
        mental_focus=goals.mental_focus,
        custom_goals=goals.custom_goals,
        improvement_priority=goals.improvement_priority,
        created_at=goals.created_at.isoformat(),
        updated_at=goals.updated_at.isoformat() if goals.updated_at else None
    )


@router.get("/all", response_model=List[GoalsResponse], dependencies=[Depends(require_premium)])
async def get_all_goals(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get all goals surveys for current user"""

    goals_list = db.query(SportGoals).filter(
        SportGoals.user_id == current_user.id
    ).all()

    return [
        GoalsResponse(
            id=str(g.id),
            sport=g.sport.value,
            skill_focus=g.skill_focus,
            physical_focus=g.physical_focus,
            tactical_focus=g.tactical_focus,
            mental_focus=g.mental_focus,
            custom_goals=g.custom_goals,
            improvement_priority=g.improvement_priority,
            created_at=g.created_at.isoformat(),
            updated_at=g.updated_at.isoformat() if g.updated_at else None
        )
        for g in goals_list
    ]


@router.delete("/survey/{sport}", dependencies=[Depends(require_premium)])
async def delete_goals_survey(
    sport: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Delete goals survey for specific sport"""

    goals = db.query(SportGoals).filter(
        SportGoals.user_id == current_user.id,
        SportGoals.sport == models.Sport(sport)
    ).first()

    if not goals:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No goals survey found for {sport}"
        )

    db.delete(goals)
    db.commit()

    return {"message": f"Goals survey for {sport} deleted successfully"}
