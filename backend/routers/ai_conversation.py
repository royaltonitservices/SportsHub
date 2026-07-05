"""
Conversational AI Coach API
Premium feature - chat-style coaching interface
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel
from uuid import UUID
from datetime import datetime

from database import get_db
from dependencies import get_current_active_user, require_premium
import models
from ai_orchestrator import AIOrchestrator
from ai_rate_limit import ai_daily_limiter
from config import get_settings


router = APIRouter(prefix="/ai/coach", tags=["ai-coach"])


# MARK: - Schemas

class CoachMessageRequest(BaseModel):
    """User message to AI Coach"""
    message: str
    sport: str  # Sport context for conversation
    context: Optional[dict] = None  # iOS context: weak_points, available_time, wearable_data, goals
    conversation_history: Optional[List[dict]] = None  # Prior messages [{role, content}]


class CoachSource(BaseModel):
    """A curated source the coach actually retrieved for this answer.

    Only present when the orchestrator retrieved it from the internal knowledge
    base. An empty `sources` list means the answer is general guidance with no
    source-backed claim — clients must not fabricate a citation.
    """
    source_id: str
    title: str
    publisher: str
    url: Optional[str] = None


class CoachAction(BaseModel):
    """A typed suggested-action chip. The client routes by `type`, not by guessing
    from the label. Types: conversational_reply | explain_drill |
    open_drill_library | log_session."""
    label: str
    type: str = "conversational_reply"


class CoachMessageResponse(BaseModel):
    """AI Coach response — structured, assistant-style envelope.

    `suggested_actions` (plain strings) is retained for backward compatibility;
    `actions` carries the typed equivalent. All structured fields are optional so
    older clients keep decoding."""
    response: str
    suggested_actions: List[str] = []
    tone: str = "supportive"
    follow_up_questions: List[str] = []
    sources: List[CoachSource] = []
    # Structured pipeline metadata (additive; safe for older clients to ignore).
    actions: List[CoachAction] = []
    resolved_sport: Optional[str] = None
    intent: Optional[str] = None
    confidence: Optional[float] = None
    safety_level: Optional[str] = None
    is_degraded_fallback: bool = False
    needs_followup: bool = False
    timestamp: str


class ConversationHistoryItem(BaseModel):
    """Single message in conversation"""
    role: str  # "user" or "assistant"
    content: str
    timestamp: str


class ProactiveCheckinResponse(BaseModel):
    """Proactive AI Coach check-in"""
    message: Optional[str]
    has_message: bool


class DrillGenerationRequest(BaseModel):
    """Request for AI-generated drill"""
    sport: str
    focus_skill: Optional[str] = None
    difficulty: Optional[str] = None
    duration_minutes: int = 20


class DrillResponse(BaseModel):
    """AI-generated drill"""
    name: str
    description: str
    duration: int
    difficulty: str
    instructions: List[str]
    equipment_needed: List[str]
    tips: List[str]
    skill_focus: Optional[str] = None


class ChallengeGenerationRequest(BaseModel):
    """Request for AI-generated challenge"""
    sport: str
    challenge_type: str = "skill"  # skill, fitness, accuracy, speed


class ChallengeResponse(BaseModel):
    """AI-generated challenge"""
    title: str
    description: str
    goal: str
    difficulty: str
    estimated_time: int
    reward_points: int
    instructions: List[str]
    success_metric: str


class TrainingAnalysisRequest(BaseModel):
    """Training session to analyze"""
    sport: str
    session_data: dict  # drills_completed, duration, notes, etc.


class TrainingAnalysisResponse(BaseModel):
    """AI analysis of training session"""
    performance_rating: float
    insights: List[str]
    areas_to_improve: List[str]
    next_session_recommendations: List[str]


# MARK: - Conversational AI Coach (Premium)

@router.post("/message", response_model=CoachMessageResponse, dependencies=[Depends(require_premium)])
async def send_message_to_coach(
    request: CoachMessageRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Send message to AI Coach and get response (Premium feature).

    This is the main conversational interface - like texting your coach.
    The AI has full context: wearable data, training history, goals, recent matches.

    Example conversation:
    User: "I'm feeling really tired today"
    Coach: "I can see your recovery score is at 42/100. How many hours did you sleep last night?"

    User: "About 5 hours"
    Coach: "That explains it! Your body needs more rest. I'd recommend taking today easy -
           maybe just some light stretching or a recovery walk. Let's get you back to 100%
           for tomorrow's training. Sound good?"
    """
    try:
        sport = models.Sport(request.sport)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid sport: {request.sport}"
        )

    # ── AI Coach daily allowance (the ONLY quota; checked BEFORE any model call) ───
    # Premium users get N user-visible messages per UTC day. Message N+1 is rejected
    # here with zero model calls. The slot is reserved now and released only if the
    # request produces NO user-visible reply (so a full server error doesn't burn
    # quota). One accepted message counts once regardless of internal retries/repair.
    # (require_premium on this route already guarantees Premium entitlement.)
    uid = str(current_user.id)
    limit = get_settings().ai_daily_message_limit
    decision = ai_daily_limiter.reserve(uid, limit)
    if not decision.allowed:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="You've reached today's AI Coach limit. Your access resets tomorrow.",
            headers={"Retry-After": str(decision.retry_after_s or 3600)},
        )

    try:
        # Initialize AI orchestrator
        orchestrator = AIOrchestrator(db)

        # Use conversation history from iOS (client maintains history)
        conversation_history = request.conversation_history or []

        # Generate AI response with full context
        response = await orchestrator.generate_coach_response(
            user_id=current_user.id,
            sport=sport,
            user_message=request.message,
            conversation_history=conversation_history,
            ios_context=request.context
        )
    except Exception:
        # No user-visible reply was produced — release the reserved slot so this
        # failed turn does not permanently consume the daily allowance.
        ai_daily_limiter.release(uid)
        raise

    # Persist both sides of the exchange for cross-device history
    try:
        sport_enum = models.Sport(sport)
        db.add(models.CoachConversationMessage(
            user_id=current_user.id,
            sport=sport_enum,
            role="user",
            content=request.message,
        ))
        db.add(models.CoachConversationMessage(
            user_id=current_user.id,
            sport=sport_enum,
            role="assistant",
            content=response["response"],
        ))
        db.commit()
    except Exception:
        pass  # History persistence is non-critical; don't fail the response

    return CoachMessageResponse(
        response=response["response"],
        suggested_actions=response.get("suggested_actions", []),
        tone=response.get("tone", "supportive"),
        follow_up_questions=response.get("follow_up_questions", []),
        sources=[CoachSource(**s) for s in response.get("sources", [])],
        actions=[CoachAction(**a) for a in response.get("actions", [])],
        resolved_sport=response.get("resolved_sport"),
        intent=response.get("intent"),
        confidence=response.get("confidence"),
        safety_level=response.get("safety_level"),
        is_degraded_fallback=response.get("is_degraded_fallback", False),
        needs_followup=response.get("needs_followup", False),
        timestamp=datetime.utcnow().isoformat()
    )


@router.get("/checkin", response_model=ProactiveCheckinResponse, dependencies=[Depends(require_premium)])
async def get_proactive_checkin(
    sport: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get proactive AI Coach check-in (Premium feature).

    Called when user opens the app. Instead of "All caught up", the AI proactively asks:
    - "How are you feeling today?"
    - "Ready for today's training?"
    - "How did your match go yesterday?"

    Returns None if no proactive message is needed.
    """
    try:
        sport_enum = models.Sport(sport)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid sport: {sport}"
        )

    orchestrator = AIOrchestrator(db)

    message = await orchestrator.generate_proactive_checkin(
        user_id=current_user.id,
        sport=sport_enum
    )

    return ProactiveCheckinResponse(
        message=message,
        has_message=message is not None
    )


# MARK: - Regular AI Features (All Users)

@router.post("/drill/generate", response_model=DrillResponse)
async def generate_drill(
    request: DrillGenerationRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Generate personalized AI drill (available to ALL users).

    This is Regular AI - not premium gated.
    Creates unique, sport-specific drills tailored to user's level.

    The AI considers:
    - User's skill level (ELO, games played)
    - Requested focus area
    - Appropriate difficulty
    - Equipment availability
    """
    try:
        sport = models.Sport(request.sport)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid sport: {request.sport}"
        )

    orchestrator = AIOrchestrator(db)

    drill = await orchestrator.generate_personalized_drill(
        user_id=current_user.id,
        sport=sport,
        focus_skill=request.focus_skill,
        difficulty=request.difficulty,
        duration_minutes=request.duration_minutes
    )

    return DrillResponse(**drill)


@router.post("/challenge/generate", response_model=ChallengeResponse)
async def generate_challenge(
    request: ChallengeGenerationRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Generate AI-powered challenge (available to ALL users).

    Creates engaging, gamified challenges that push users to improve.
    Considers user's current level and recent performance.

    Challenge types:
    - skill: Technique and form challenges
    - fitness: Endurance and conditioning
    - accuracy: Precision-based goals
    - speed: Agility and quickness
    """
    try:
        sport = models.Sport(request.sport)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid sport: {request.sport}"
        )

    orchestrator = AIOrchestrator(db)

    challenge = await orchestrator.generate_challenge(
        user_id=current_user.id,
        sport=sport,
        challenge_type=request.challenge_type
    )

    return ChallengeResponse(**challenge)


@router.post("/analyze", response_model=TrainingAnalysisResponse, dependencies=[Depends(require_premium)])
async def analyze_training_session(
    request: TrainingAnalysisRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Analyze training session using AI (Premium feature).

    The AI reviews your session and provides:
    - Performance rating (0-10)
    - Positive insights and wins
    - Areas to improve
    - Recommendations for next session

    Always encouraging and constructive - focuses on progress, not criticism.
    """
    try:
        sport = models.Sport(request.sport)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid sport: {request.sport}"
        )

    orchestrator = AIOrchestrator(db)

    analysis = await orchestrator.analyze_training_session(
        user_id=current_user.id,
        sport=sport,
        session_data=request.session_data
    )

    return TrainingAnalysisResponse(**analysis)


# MARK: - Conversation Management

@router.get("/history", response_model=List[ConversationHistoryItem], dependencies=[Depends(require_premium)])
async def get_conversation_history(
    sport: str,
    limit: int = 50,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get conversation history with AI Coach (Premium feature).

    Returns recent messages for context and continuity.
    """
    try:
        sport_enum = models.Sport(sport)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid sport: {sport}"
        )

    messages = db.query(models.CoachConversationMessage).filter(
        models.CoachConversationMessage.user_id == current_user.id,
        models.CoachConversationMessage.sport == sport_enum,
    ).order_by(models.CoachConversationMessage.created_at.asc()).limit(limit).all()

    return [
        ConversationHistoryItem(
            role=m.role,
            content=m.content,
            timestamp=m.created_at.isoformat(),
        )
        for m in messages
    ]


@router.delete("/history", dependencies=[Depends(require_premium)])
async def clear_conversation_history(
    sport: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Clear conversation history with AI Coach (Premium feature).

    Starts fresh conversation - useful for changing topics or resetting context.
    """
    try:
        sport_enum = models.Sport(sport)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid sport: {sport}"
        )

    db.query(models.CoachConversationMessage).filter(
        models.CoachConversationMessage.user_id == current_user.id,
        models.CoachConversationMessage.sport == sport_enum,
    ).delete(synchronize_session=False)
    db.commit()

    return {"message": "Conversation history cleared"}
