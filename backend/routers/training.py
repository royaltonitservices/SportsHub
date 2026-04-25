"""
Training API — drill catalog, session logging, and saved workouts.

Route prefix: /training

Public endpoints (all authenticated users):
  GET  /training/drills                  — Drill catalog for a sport
  GET  /training/drills/categories       — Category list for a sport
  POST /training/sessions                — Log a completed training session
  GET  /training/sessions                — Fetch user's session history
  GET  /training/sessions/{session_id}   — Single session detail
  POST /training/workouts                — Save a custom workout plan
  GET  /training/workouts                — Fetch saved workouts for a sport
  PUT  /training/workouts/{workout_id}   — Update a saved workout
  DELETE /training/workouts/{workout_id} — Delete a saved workout

Design notes:
- Drill catalog is server-side static content (curated, not user-generated).
  A database table for drills would be premature; the catalog is seeded here
  and can be migrated to a DB table when content management is needed.
- TrainingSession and SavedWorkout are fully DB-backed with user ownership.
- AI Coach context integration: sessions are accessible to ai_coach.py via
  get_recent_sessions_for_user() helper so the coach has training history.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel
from uuid import UUID
from datetime import datetime

from database import get_db
from dependencies import get_current_active_user
import models

router = APIRouter(prefix="/training", tags=["training"])


# ---------------------------------------------------------------------------
# MARK: - Drill Catalog (curated, sport-specific)
# ---------------------------------------------------------------------------

DRILL_CATALOG = {
    "basketball": [
        {
            "id": "bball-001", "name": "3-Point Shooting Circuit",
            "category": "shooting", "difficulty": "intermediate",
            "duration_minutes": 15, "equipment": ["ball", "hoop"],
            "description": "Move through 5 spots beyond the arc. Take 3 shots from each spot, focusing on consistent form and follow-through.",
            "focus_areas": ["shooting", "accuracy", "consistency"],
            "instructions": ["Set up at 5 spots around the arc", "Shoot 3 attempts per spot", "Focus on balanced base and high release", "Track makes/attempts per spot"]
        },
        {
            "id": "bball-002", "name": "Ball Handling Series",
            "category": "dribbling", "difficulty": "beginner",
            "duration_minutes": 10, "equipment": ["ball"],
            "description": "Stationary and moving dribble series: crossovers, behind-the-back, between-the-legs.",
            "focus_areas": ["dribbling", "ball handling", "control"],
            "instructions": ["Start stationary: 30s each — crossover, behind back, between legs", "Advance to walking dribble drills", "End with figure-8 dribble at pace"]
        },
        {
            "id": "bball-003", "name": "Defensive Slide Drill",
            "category": "defense", "difficulty": "intermediate",
            "duration_minutes": 12, "equipment": [],
            "description": "Lateral defensive slides from baseline to half court and back, staying low in defensive stance.",
            "focus_areas": ["defense", "footwork", "conditioning"],
            "instructions": ["Start in defensive stance at baseline", "Slide laterally to sideline", "Sprint back to start", "Repeat for 6 reps each direction"]
        },
        {
            "id": "bball-004", "name": "Mikan Drill",
            "category": "finishing", "difficulty": "beginner",
            "duration_minutes": 8, "equipment": ["ball", "hoop"],
            "description": "Alternating left/right hand layups under the basket to develop ambidextrous finishing.",
            "focus_areas": ["finishing", "layups", "coordination"],
            "instructions": ["Start under basket, ball in right hand", "Right hand layup, catch before ball hits floor", "Immediately go left hand layup", "Continue alternating for 2 minutes"]
        },
        {
            "id": "bball-005", "name": "Pick-and-Roll Reads",
            "category": "basketball_iq", "difficulty": "advanced",
            "duration_minutes": 20, "equipment": ["ball", "hoop", "cones"],
            "description": "Practice reading pick-and-roll coverage: go over screen, pull-up, pocket pass, or lob.",
            "focus_areas": ["basketball_iq", "decision_making", "passing"],
            "instructions": ["Set screen at elbow", "Ball handler reads defender position", "React to coverage: attack, pull up, or pass to roller", "Rotate and repeat"]
        },
        {
            "id": "bball-006", "name": "Free Throw Routine",
            "category": "shooting", "difficulty": "beginner",
            "duration_minutes": 10, "equipment": ["ball", "hoop"],
            "description": "Build a consistent free throw routine under simulated pressure.",
            "focus_areas": ["shooting", "mental toughness", "consistency"],
            "instructions": ["Establish your routine (bounces, breath, alignment)", "Shoot 10 attempts in sets of 2", "Track percentage", "Final 5: must make both to end the drill"]
        },
        {
            "id": "bball-007", "name": "Closeout and Contest Drill",
            "category": "defense", "difficulty": "intermediate",
            "duration_minutes": 12, "equipment": ["ball"],
            "description": "Start at the key, sprint to contest a shot at the perimeter, then recover.",
            "focus_areas": ["defense", "closeouts", "footwork"],
            "instructions": ["Start at the paint", "Coach holds ball at 3-pt line", "Sprint out, chop feet, contest without fouling", "Recover to start and repeat"]
        },
        {
            "id": "bball-008", "name": "Conditioning Sprint Ladders",
            "category": "conditioning", "difficulty": "hard",
            "duration_minutes": 15, "equipment": [],
            "description": "Full-court sprint ladders: baseline to free throw line, back; to half, back; to far free throw, back; full court.",
            "focus_areas": ["conditioning", "speed", "endurance"],
            "instructions": ["Baseline sprint to near free throw line — return", "Baseline sprint to half court — return", "Baseline sprint to far free throw — return", "Baseline full court — return", "Repeat 4 times with 45s rest between sets"]
        },
    ],

    "football": [
        {
            "id": "ftbl-001", "name": "Route Running Precision",
            "category": "receiving", "difficulty": "intermediate",
            "duration_minutes": 20, "equipment": ["cones", "ball"],
            "description": "Run crisp routes — out, in, post, corner — focusing on sharp cuts and separation.",
            "focus_areas": ["receiving", "route running", "separation"],
            "instructions": ["Set cones for route tree", "Run each route 3 times at full speed", "Emphasize plant-and-cut footwork", "Work in and out of breaks"]
        },
        {
            "id": "ftbl-002", "name": "Quick Release Mechanics",
            "category": "passing", "difficulty": "intermediate",
            "duration_minutes": 15, "equipment": ["ball", "targets"],
            "description": "Three-step and five-step drop mechanics, focusing on platform, hip rotation, and release point.",
            "focus_areas": ["passing", "mechanics", "speed"],
            "instructions": ["3-step drop: 5 reps to short targets", "5-step drop: 5 reps to intermediate routes", "Focus on getting feet set before throwing", "Record release time if possible"]
        },
        {
            "id": "ftbl-003", "name": "Agility Ladder Footwork",
            "category": "footwork", "difficulty": "beginner",
            "duration_minutes": 12, "equipment": ["agility_ladder"],
            "description": "Improve foot speed and coordination through ladder drills — in/out, lateral, ickey shuffle.",
            "focus_areas": ["footwork", "agility", "coordination"],
            "instructions": ["Two feet in each square — forward", "Lateral shuffle through ladder", "Ickey shuffle pattern x3", "High knees through ladder"]
        },
        {
            "id": "ftbl-004", "name": "Tackling Form Drill",
            "category": "defense", "difficulty": "intermediate",
            "duration_minutes": 10, "equipment": ["tackle_dummy"],
            "description": "Fundamentals of form tackling — breakdown position, drive through, wrap.",
            "focus_areas": ["defense", "tackling", "technique"],
            "instructions": ["Approach in breakdown stance", "Head up, eyes on numbers", "Drive through on contact", "Wrap and drive through"]
        },
        {
            "id": "ftbl-005", "name": "Plyometric Explosion Training",
            "category": "conditioning", "difficulty": "hard",
            "duration_minutes": 20, "equipment": ["cones"],
            "description": "Box jumps, broad jumps, and lateral bounds to build explosive first-step power.",
            "focus_areas": ["conditioning", "explosiveness", "power"],
            "instructions": ["5 box jumps — land softly", "5 broad jumps — max distance", "Lateral bounds 10m each direction — 4 reps", "60s rest between exercises"]
        },
    ],

    "soccer": [
        {
            "id": "socc-001", "name": "Finishing Drill — Low Crosses",
            "category": "shooting", "difficulty": "intermediate",
            "duration_minutes": 20, "equipment": ["ball", "goal", "cones"],
            "description": "Receive low crosses from wide and finish one-touch in the box.",
            "focus_areas": ["shooting", "finishing", "first_touch"],
            "instructions": ["Server on wide right, you start at near post", "Cross played low to near post area", "Finish first time", "Alternate sides every 5 reps"]
        },
        {
            "id": "socc-002", "name": "1v1 Cone Dribbling",
            "category": "dribbling", "difficulty": "beginner",
            "duration_minutes": 15, "equipment": ["ball", "cones"],
            "description": "Navigate a cone course at speed using close control, change of direction, and acceleration.",
            "focus_areas": ["dribbling", "close_control", "acceleration"],
            "instructions": ["Set 10 cones in zig-zag pattern", "Dribble through at 70% pace — full control", "Repeat at 90% — push pace", "Add moves: Cruyff, step-over at each gate"]
        },
        {
            "id": "socc-003", "name": "Pressing Trigger Reps",
            "category": "defense", "difficulty": "intermediate",
            "duration_minutes": 12, "equipment": ["ball", "cones"],
            "description": "Practice pressing triggers — reacting to a bad touch or back pass with immediate pressure.",
            "focus_areas": ["defense", "pressing", "intensity"],
            "instructions": ["Partner has ball 10m away", "On signal (ball bounces far) — explode to press", "Force to sideline or back pass", "Reset and repeat — 5 reps each"]
        },
        {
            "id": "socc-004", "name": "Long Ball Accuracy",
            "category": "passing", "difficulty": "intermediate",
            "duration_minutes": 15, "equipment": ["ball", "cones"],
            "description": "Switch the field and play long diagonal passes accurately at pace.",
            "focus_areas": ["passing", "long_ball", "technique"],
            "instructions": ["Set targets at 30m and 40m", "Strike 10 balls to each target", "Focus on shape and follow-through", "Track on-target percentage"]
        },
        {
            "id": "socc-005", "name": "Interval Conditioning",
            "category": "conditioning", "difficulty": "hard",
            "duration_minutes": 20, "equipment": ["cones"],
            "description": "Soccer-specific interval running: 40m sprints with 20m jog recovery, repeated.",
            "focus_areas": ["conditioning", "endurance", "speed"],
            "instructions": ["Sprint 40m at full pace", "Jog 20m back to start", "Repeat 8 times", "Rest 2 minutes, do second set"]
        },
        {
            "id": "socc-006", "name": "Penalty Kick Routine",
            "category": "shooting", "difficulty": "beginner",
            "duration_minutes": 10, "equipment": ["ball", "goal"],
            "description": "Build a repeatable penalty routine under pressure — placement, run-up, mental reset.",
            "focus_areas": ["shooting", "penalties", "mental_toughness"],
            "instructions": ["Decide your spot before placing ball", "Same run-up every time", "Look at goalkeeper, commit to location", "Take 10 penalties, track conversions"]
        },
    ],

    "tennis": [
        {
            "id": "tenn-001", "name": "Cross-Court Forehand Rally",
            "category": "groundstrokes", "difficulty": "intermediate",
            "duration_minutes": 20, "equipment": ["balls", "racket"],
            "description": "Sustain a cross-court forehand rally from the baseline, targeting the opponent's ad side.",
            "focus_areas": ["forehand", "consistency", "placement"],
            "instructions": ["Start position: deuce court baseline", "Rally cross-court to target zone", "Focus: recovery split-step after each shot", "Count rally length — target 8+ consistent"]
        },
        {
            "id": "tenn-002", "name": "Serve Placement Drill",
            "category": "serve", "difficulty": "intermediate",
            "duration_minutes": 15, "equipment": ["balls", "racket", "targets"],
            "description": "Hit targets in the T, body, and wide locations from both deuce and ad courts.",
            "focus_areas": ["serve", "placement", "consistency"],
            "instructions": ["10 serves to T from deuce court", "10 serves wide from deuce court", "10 serves T from ad court", "10 serves wide from ad court", "Track: in/out and hit target"]
        },
        {
            "id": "tenn-003", "name": "Net Approach and Volley",
            "category": "net_play", "difficulty": "intermediate",
            "duration_minutes": 15, "equipment": ["balls", "racket"],
            "description": "Approach on short ball, split step at service line, and finish with forehand or backhand volley.",
            "focus_areas": ["net_play", "volleys", "approach"],
            "instructions": ["Feed short ball to baseline player", "Attack with deep approach shot down the line", "Split step at service line", "Volley winner to open court"]
        },
        {
            "id": "tenn-004", "name": "Lateral Footwork Ladder",
            "category": "footwork", "difficulty": "beginner",
            "duration_minutes": 10, "equipment": ["agility_ladder"],
            "description": "Tennis-specific footwork patterns: side shuffle, crossover step, split step into stance.",
            "focus_areas": ["footwork", "movement", "recovery"],
            "instructions": ["Side shuffle through ladder — both directions", "Crossover step pattern", "Practice split step into ready position", "End: shadow swing off simulated feed"]
        },
        {
            "id": "tenn-005", "name": "Backhand Slice Consistency",
            "category": "groundstrokes", "difficulty": "intermediate",
            "duration_minutes": 12, "equipment": ["balls", "racket"],
            "description": "Hit 20 backhand slices that land in target zone with controlled depth and low bounce.",
            "focus_areas": ["backhand", "slice", "control"],
            "instructions": ["Contact point out front, racket face open", "Drive through ball from high to low", "Target: past service line, within 1m of baseline", "Count consecutive in-target shots"]
        },
        {
            "id": "tenn-006", "name": "Second Serve Spin Development",
            "category": "serve", "difficulty": "advanced",
            "duration_minutes": 20, "equipment": ["balls", "racket"],
            "description": "Develop a reliable kick or slice second serve with enough spin to hold at the net level.",
            "focus_areas": ["serve", "spin", "second_serve"],
            "instructions": ["Slow motion: focus on toss placement and brush angle", "50% effort to feel the spin", "Build to 75% — consistent kick", "20 second serves — track: in, kick, depth"]
        },
    ],
}

DRILL_CATEGORIES = {
    "basketball": ["shooting", "dribbling", "defense", "finishing", "basketball_iq", "conditioning"],
    "football": ["passing", "receiving", "defense", "footwork", "conditioning"],
    "soccer": ["shooting", "dribbling", "defense", "passing", "conditioning"],
    "tennis": ["groundstrokes", "serve", "net_play", "footwork"],
}


# ---------------------------------------------------------------------------
# MARK: - Request / Response Schemas
# ---------------------------------------------------------------------------

class DrillLogEntryRequest(BaseModel):
    drill_name: str
    drill_order: int = 0
    duration: int            # minutes
    effort: Optional[str] = None      # light / moderate / hard / maximal
    metric_type: Optional[str] = None
    metric_value: Optional[str] = None
    notes: Optional[str] = None


class LogSessionRequest(BaseModel):
    sport: str
    drills: List[DrillLogEntryRequest]
    notes: Optional[str] = None
    # AI analysis result (iOS calls analyzeTrainingSession separately and forwards result)
    ai_performance_rating: Optional[float] = None
    ai_insights: Optional[List[str]] = None
    ai_areas_to_improve: Optional[List[str]] = None
    ai_next_session_recs: Optional[List[str]] = None


class DrillLogEntryResponse(BaseModel):
    id: str
    drill_name: str
    drill_order: int
    duration: int
    effort: Optional[str]
    metric_type: Optional[str]
    metric_value: Optional[str]
    notes: Optional[str]


class SessionResponse(BaseModel):
    id: str
    sport: str
    total_duration: int
    notes: Optional[str]
    effort_rating: Optional[float]
    ai_performance_rating: Optional[float]
    ai_insights: Optional[List[str]]
    ai_areas_to_improve: Optional[List[str]]
    ai_next_session_recs: Optional[List[str]]
    drills: List[DrillLogEntryResponse]
    created_at: str


class SaveWorkoutRequest(BaseModel):
    sport: str
    name: str
    description: Optional[str] = None
    estimated_duration: Optional[int] = None
    difficulty: Optional[str] = None
    focus_areas: Optional[List[str]] = None
    drills: List[dict]       # same shape as DrillLogEntryRequest but as dicts for flexibility


class WorkoutResponse(BaseModel):
    id: str
    sport: str
    name: str
    description: Optional[str]
    estimated_duration: Optional[int]
    difficulty: Optional[str]
    focus_areas: List[str]
    drills: List[dict]
    times_used: int
    created_at: str


# ---------------------------------------------------------------------------
# MARK: - Helpers
# ---------------------------------------------------------------------------

def _session_to_response(session: models.TrainingSession) -> SessionResponse:
    drills = [
        DrillLogEntryResponse(
            id=str(d.id),
            drill_name=d.drill_name,
            drill_order=d.drill_order,
            duration=d.duration,
            effort=d.effort,
            metric_type=d.metric_type,
            metric_value=d.metric_value,
            notes=d.notes,
        )
        for d in session.drills
    ]
    return SessionResponse(
        id=str(session.id),
        sport=session.sport.value,
        total_duration=session.total_duration,
        notes=session.notes,
        effort_rating=session.effort_rating,
        ai_performance_rating=session.ai_performance_rating,
        ai_insights=session.ai_insights,
        ai_areas_to_improve=session.ai_areas_to_improve,
        ai_next_session_recs=session.ai_next_session_recs,
        drills=drills,
        created_at=session.created_at.isoformat() if session.created_at else datetime.utcnow().isoformat(),
    )


def _workout_to_response(workout: models.SavedWorkout) -> WorkoutResponse:
    return WorkoutResponse(
        id=str(workout.id),
        sport=workout.sport.value,
        name=workout.name,
        description=workout.description,
        estimated_duration=workout.estimated_duration,
        difficulty=workout.difficulty,
        focus_areas=workout.focus_areas or [],
        drills=workout.drills_json or [],
        times_used=workout.times_used or 0,
        created_at=workout.created_at.isoformat() if workout.created_at else datetime.utcnow().isoformat(),
    )


def get_recent_sessions_for_user(user_id, sport: models.Sport, db: Session, limit: int = 10):
    """
    Helper used by ai_coach router to pull training history into coach context.
    Returns list of session dicts with drill names and durations.
    """
    sessions = (
        db.query(models.TrainingSession)
        .filter(
            models.TrainingSession.user_id == user_id,
            models.TrainingSession.sport == sport,
        )
        .order_by(models.TrainingSession.created_at.desc())
        .limit(limit)
        .all()
    )
    return [
        {
            "date": s.created_at.isoformat() if s.created_at else None,
            "total_duration": s.total_duration,
            "drill_count": len(s.drills),
            "drills": [d.drill_name for d in s.drills],
            "ai_rating": s.ai_performance_rating,
        }
        for s in sessions
    ]


# ---------------------------------------------------------------------------
# MARK: - Endpoints
# ---------------------------------------------------------------------------

@router.get("/drills")
async def get_drills(
    sport: str,
    focus_area: Optional[str] = None,
    difficulty: Optional[str] = None,
    current_user: models.User = Depends(get_current_active_user),
):
    """
    Return curated drill catalog for a sport.
    Optionally filter by focus_area (e.g. 'shooting') or difficulty.
    """
    try:
        sport_enum = models.Sport(sport)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid sport: {sport}")

    drills = DRILL_CATALOG.get(sport_enum.value, [])

    if focus_area:
        drills = [d for d in drills if focus_area in d.get("focus_areas", [])]
    if difficulty:
        drills = [d for d in drills if d.get("difficulty") == difficulty]

    return drills


@router.get("/drills/categories")
async def get_drill_categories(
    sport: str,
    current_user: models.User = Depends(get_current_active_user),
):
    """Return category list for a sport."""
    try:
        sport_enum = models.Sport(sport)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid sport: {sport}")

    return {"sport": sport_enum.value, "categories": DRILL_CATEGORIES.get(sport_enum.value, [])}


@router.post("/sessions", response_model=SessionResponse)
async def log_training_session(
    request: LogSessionRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Persist a completed training session with all drill entries.
    Called by TrainingSessionView after the user taps 'Save Session'.
    """
    try:
        sport = models.Sport(request.sport)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid sport: {request.sport}")

    if not request.drills:
        raise HTTPException(status_code=400, detail="Session must include at least one drill")

    total_duration = sum(d.duration for d in request.drills)

    # Compute average effort rating (light=1, moderate=2, hard=3, maximal=4)
    effort_map = {"light": 1.0, "moderate": 2.0, "hard": 3.0, "maximal": 4.0}
    effort_values = [effort_map.get(d.effort or "", 2.0) for d in request.drills]
    avg_effort = sum(effort_values) / len(effort_values) if effort_values else None

    session = models.TrainingSession(
        user_id=current_user.id,
        sport=sport,
        total_duration=total_duration,
        notes=request.notes,
        effort_rating=avg_effort,
        ai_performance_rating=request.ai_performance_rating,
        ai_insights=request.ai_insights,
        ai_areas_to_improve=request.ai_areas_to_improve,
        ai_next_session_recs=request.ai_next_session_recs,
    )
    db.add(session)
    db.flush()

    for drill in request.drills:
        db_drill = models.TrainingSessionDrill(
            session_id=session.id,
            drill_name=drill.drill_name,
            drill_order=drill.drill_order,
            duration=drill.duration,
            effort=drill.effort,
            metric_type=drill.metric_type,
            metric_value=drill.metric_value,
            notes=drill.notes,
        )
        db.add(db_drill)

    db.commit()
    db.refresh(session)
    return _session_to_response(session)


@router.get("/sessions", response_model=List[SessionResponse])
async def get_training_history(
    sport: Optional[str] = None,
    limit: int = 20,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Fetch user's training session history.
    Optionally filter by sport. Returns newest first.
    """
    query = db.query(models.TrainingSession).filter(
        models.TrainingSession.user_id == current_user.id
    )

    if sport:
        try:
            sport_enum = models.Sport(sport)
            query = query.filter(models.TrainingSession.sport == sport_enum)
        except ValueError:
            raise HTTPException(status_code=400, detail=f"Invalid sport: {sport}")

    sessions = query.order_by(models.TrainingSession.created_at.desc()).limit(limit).all()
    return [_session_to_response(s) for s in sessions]


@router.get("/sessions/{session_id}", response_model=SessionResponse)
async def get_session_detail(
    session_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Fetch a single training session by ID (must be owned by current user)."""
    session = db.query(models.TrainingSession).filter(
        models.TrainingSession.id == session_id,
        models.TrainingSession.user_id == current_user.id,
    ).first()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    return _session_to_response(session)


@router.post("/workouts", response_model=WorkoutResponse)
async def save_workout(
    request: SaveWorkoutRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Save a custom workout plan for reuse."""
    try:
        sport = models.Sport(request.sport)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid sport: {request.sport}")

    workout = models.SavedWorkout(
        user_id=current_user.id,
        sport=sport,
        name=request.name,
        description=request.description,
        estimated_duration=request.estimated_duration,
        difficulty=request.difficulty,
        focus_areas=request.focus_areas or [],
        drills_json=request.drills,
    )
    db.add(workout)
    db.commit()
    db.refresh(workout)
    return _workout_to_response(workout)


@router.get("/workouts", response_model=List[WorkoutResponse])
async def get_saved_workouts(
    sport: Optional[str] = None,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Fetch user's saved workout plans, optionally filtered by sport."""
    query = db.query(models.SavedWorkout).filter(
        models.SavedWorkout.user_id == current_user.id
    )

    if sport:
        try:
            sport_enum = models.Sport(sport)
            query = query.filter(models.SavedWorkout.sport == sport_enum)
        except ValueError:
            raise HTTPException(status_code=400, detail=f"Invalid sport: {sport}")

    workouts = query.order_by(models.SavedWorkout.created_at.desc()).all()
    return [_workout_to_response(w) for w in workouts]


@router.put("/workouts/{workout_id}", response_model=WorkoutResponse)
async def update_workout(
    workout_id: UUID,
    request: SaveWorkoutRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Update a saved workout plan (must be owned by current user)."""
    workout = db.query(models.SavedWorkout).filter(
        models.SavedWorkout.id == workout_id,
        models.SavedWorkout.user_id == current_user.id,
    ).first()

    if not workout:
        raise HTTPException(status_code=404, detail="Workout not found")

    workout.name = request.name
    workout.description = request.description
    workout.estimated_duration = request.estimated_duration
    workout.difficulty = request.difficulty
    workout.focus_areas = request.focus_areas or []
    workout.drills_json = request.drills

    db.commit()
    db.refresh(workout)
    return _workout_to_response(workout)


@router.delete("/workouts/{workout_id}")
async def delete_workout(
    workout_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Delete a saved workout plan."""
    workout = db.query(models.SavedWorkout).filter(
        models.SavedWorkout.id == workout_id,
        models.SavedWorkout.user_id == current_user.id,
    ).first()

    if not workout:
        raise HTTPException(status_code=404, detail="Workout not found")

    db.delete(workout)
    db.commit()
    return {"message": "Workout deleted"}
