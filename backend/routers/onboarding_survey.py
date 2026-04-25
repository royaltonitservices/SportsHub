"""
Onboarding survey endpoints.

The survey collects sport-specific skill ratings, strengths, and weaknesses
during signup onboarding. This data feeds directly into the AI Coach context
so coaching is personalized from the first conversation.

Endpoints:
  POST /onboarding/survey  — submit (or update) survey
  GET  /onboarding/survey  — fetch existing survey (for AI Coach to load)
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import datetime
from database import get_db
from dependencies import get_current_user
import models
import schemas

router = APIRouter(prefix="/onboarding", tags=["onboarding"])


@router.post("/survey", status_code=status.HTTP_201_CREATED)
async def submit_survey(
    request: schemas.OnboardingSurveyRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Submit or update the onboarding survey.
    Idempotent — calling again updates the existing record in-place.
    Also marks user.survey_completed = True.
    """
    existing = (
        db.query(models.OnboardingSurvey)
        .filter(models.OnboardingSurvey.user_id == current_user.id)
        .first()
    )

    if existing:
        existing.main_sport = request.main_sport
        existing.skill_ratings = request.skill_ratings
        existing.strengths = request.strengths
        existing.weaknesses = request.weaknesses
        existing.goals = request.goals
        existing.onboarding_version = request.onboarding_version
        existing.updated_at = datetime.utcnow()
    else:
        survey = models.OnboardingSurvey(
            user_id=current_user.id,
            main_sport=request.main_sport,
            skill_ratings=request.skill_ratings,
            strengths=request.strengths,
            weaknesses=request.weaknesses,
            goals=request.goals,
            onboarding_version=request.onboarding_version,
        )
        db.add(survey)

    current_user.survey_completed = True
    current_user.onboarding_version = request.onboarding_version
    db.commit()

    return {"message": "Survey saved", "survey_completed": True}


@router.get("/survey", response_model=schemas.OnboardingSurveyResponse)
async def get_survey(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retrieve the user's onboarding survey.
    Called by AI Coach context loading to seed coaching with baseline skill data.
    """
    survey = (
        db.query(models.OnboardingSurvey)
        .filter(models.OnboardingSurvey.user_id == current_user.id)
        .first()
    )

    if not survey:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Survey not found. Complete onboarding to unlock personalized coaching.",
        )

    return survey
