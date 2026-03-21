# AI Coach API Router
# Premium feature - Exposes AI Coach engine capabilities

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
from pydantic import BaseModel

from database import get_db
from dependencies import get_current_active_user, require_premium
import models
from ai_coach import AICoachService
from models_premium import AICoachInsight, PerformancePrediction

router = APIRouter(prefix="/ai-coach", tags=["ai-coach"])


# MARK: - Schemas

class InsightResponse(BaseModel):
    id: str
    insight_type: str
    priority: str
    title: str
    message: str
    details: Optional[dict]
    suggested_actions: List[str]
    drills_recommended: List[str]
    confidence: float
    is_read: bool
    is_dismissed: bool
    created_at: str
    expires_at: Optional[str]

    class Config:
        from_attributes = True


class PredictionResponse(BaseModel):
    id: str
    prediction_type: str
    performance_index: float
    readiness_score: float
    confidence: float
    factors: dict
    prediction_date: str

    class Config:
        from_attributes = True


class ReadinessScoreResponse(BaseModel):
    sport: str
    readiness_score: float
    status: str  # "excellent", "good", "fair", "poor"
    recommendation: str
    factors: dict


class TrainingPlanResponse(BaseModel):
    user_id: str
    sport: str
    start_date: str
    duration_days: int
    daily_plans: List[dict]
    weekly_focus: str
    progression_strategy: str


class DrillRecommendation(BaseModel):
    name: str
    intensity: str
    description: str
    duration_minutes: Optional[int]


# MARK: - Daily Insights

@router.get("/insights", response_model=List[InsightResponse], dependencies=[Depends(require_premium)])
async def get_daily_insights(
    sport: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get daily AI-generated insights (Premium only).

    Analyzes:
    - Recovery status
    - Performance trends
    - Overtraining risk
    - Goal progress
    - Upcoming tournaments
    - Skill development opportunities
    """
    ai_coach = AICoachService(db)

    # Generate fresh insights
    insights = ai_coach.generate_daily_insights(
        user_id=current_user.id,
        sport=models.Sport(sport)
    )

    return [to_insight_response(i) for i in insights]


@router.get("/insights/unread", response_model=List[InsightResponse], dependencies=[Depends(require_premium)])
async def get_unread_insights(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get unread insights"""
    insights = db.query(AICoachInsight).filter(
        AICoachInsight.user_id == current_user.id,
        AICoachInsight.is_read == False,
        AICoachInsight.is_dismissed == False
    ).order_by(AICoachInsight.created_at.desc()).all()

    return [to_insight_response(i) for i in insights]


@router.post("/insights/{insight_id}/read", dependencies=[Depends(require_premium)])
async def mark_insight_read(
    insight_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Mark insight as read"""
    insight = db.query(AICoachInsight).filter(
        AICoachInsight.id == insight_id,
        AICoachInsight.user_id == current_user.id
    ).first()

    if not insight:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Insight not found")

    insight.is_read = True
    db.commit()

    return {"message": "Insight marked as read"}


@router.post("/insights/{insight_id}/dismiss", dependencies=[Depends(require_premium)])
async def dismiss_insight(
    insight_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Dismiss insight"""
    insight = db.query(AICoachInsight).filter(
        AICoachInsight.id == insight_id,
        AICoachInsight.user_id == current_user.id
    ).first()

    if not insight:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Insight not found")

    insight.is_dismissed = True
    db.commit()

    return {"message": "Insight dismissed"}


# MARK: - Match Readiness

@router.get("/readiness", response_model=ReadinessScoreResponse, dependencies=[Depends(require_premium)])
async def get_match_readiness(
    sport: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get current match readiness score (Premium only).

    Factors:
    - Recovery score (smartwatch)
    - Recent performance
    - Sleep quality
    - Training load
    - Mental readiness
    """
    ai_coach = AICoachService(db)

    readiness_score = ai_coach.generate_match_readiness_score(
        user_id=current_user.id,
        sport=models.Sport(sport)
    )

    # Determine status
    if readiness_score >= 85:
        status = "excellent"
        recommendation = "Perfect day for competition or high-intensity training!"
    elif readiness_score >= 70:
        status = "good"
        recommendation = "Good condition for matches and moderate training."
    elif readiness_score >= 50:
        status = "fair"
        recommendation = "Consider lighter training or active recovery."
    else:
        status = "poor"
        recommendation = "Rest day recommended. Focus on recovery."

    # Get contributing factors
    recovery = ai_coach._get_recovery_score(current_user.id) or 50
    performance = ai_coach._get_recent_performance_score(current_user.id, models.Sport(sport)) or 50
    sleep = ai_coach._get_sleep_quality_score(current_user.id) or 50

    return ReadinessScoreResponse(
        sport=sport,
        readiness_score=readiness_score,
        status=status,
        recommendation=recommendation,
        factors={
            "recovery": recovery,
            "recent_performance": performance,
            "sleep_quality": sleep
        }
    )


# MARK: - Performance Prediction

@router.get("/predict", response_model=PredictionResponse, dependencies=[Depends(require_premium)])
async def predict_performance(
    sport: str,
    opponent_elo: int,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Predict performance for upcoming match (Premium only).

    Returns:
    - Performance index (-10 to +10)
    - Readiness score (0-100)
    - Confidence level (0-1)
    - Contributing factors
    """
    ai_coach = AICoachService(db)

    prediction = ai_coach.predict_match_performance(
        user_id=current_user.id,
        sport=models.Sport(sport),
        opponent_elo=opponent_elo
    )

    return to_prediction_response(prediction)


@router.get("/predictions/history", response_model=List[PredictionResponse], dependencies=[Depends(require_premium)])
async def get_prediction_history(
    sport: Optional[str] = None,
    limit: int = 10,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get prediction history"""
    query = db.query(PerformancePrediction).filter(
        PerformancePrediction.user_id == current_user.id
    )

    if sport:
        query = query.filter(PerformancePrediction.sport == models.Sport(sport))

    predictions = query.order_by(PerformancePrediction.created_at.desc()).limit(limit).all()

    return [to_prediction_response(p) for p in predictions]


# MARK: - Training Plans

@router.get("/training-plan", response_model=TrainingPlanResponse, dependencies=[Depends(require_premium)])
async def get_training_plan(
    sport: str,
    duration_days: int = 7,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Generate personalized training plan (Premium only).

    Based on:
    - Goals survey
    - Current skill level
    - Recovery status
    - Upcoming matches/tournaments
    """
    ai_coach = AICoachService(db)

    training_plan = ai_coach.generate_training_plan(
        user_id=current_user.id,
        sport=models.Sport(sport),
        duration_days=duration_days
    )

    return TrainingPlanResponse(**training_plan)


# MARK: - Drill Recommendations

@router.get("/drills", response_model=List[DrillRecommendation], dependencies=[Depends(require_premium)])
async def get_recommended_drills(
    sport: str,
    limit: int = 5,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get recommended drills (Premium only).

    Based on:
    - Goals survey
    - Recent performance weaknesses
    - Skill level
    """
    ai_coach = AICoachService(db)

    drills = ai_coach.recommend_drills(
        user_id=current_user.id,
        sport=models.Sport(sport),
        limit=limit
    )

    return [DrillRecommendation(**drill) for drill in drills]


# MARK: - Helper Functions

def to_insight_response(insight: AICoachInsight) -> InsightResponse:
    """Convert AICoachInsight to response"""
    return InsightResponse(
        id=str(insight.id),
        insight_type=insight.insight_type,
        priority=insight.priority,
        title=insight.title,
        message=insight.message,
        details=insight.details or {},
        suggested_actions=insight.suggested_actions or [],
        drills_recommended=insight.drills_recommended or [],
        confidence=insight.confidence or 0.0,
        is_read=insight.is_read,
        is_dismissed=insight.is_dismissed,
        created_at=insight.created_at.isoformat(),
        expires_at=insight.expires_at.isoformat() if insight.expires_at else None
    )


def to_prediction_response(prediction: PerformancePrediction) -> PredictionResponse:
    """Convert PerformancePrediction to response"""
    return PredictionResponse(
        id=str(prediction.id),
        prediction_type=prediction.prediction_type,
        performance_index=prediction.performance_index or 0.0,
        readiness_score=prediction.readiness_score or 0.0,
        confidence=prediction.confidence or 0.0,
        factors=prediction.factors or {},
        prediction_date=prediction.prediction_date.isoformat()
    )
