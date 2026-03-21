# Premium subscription models for SportsHub
# Master Premium System - AI Coach + Smartwatch + Tournaments

from sqlalchemy import Column, String, Integer, Float, Boolean, DateTime, Text, ForeignKey, Enum as SQLEnum, JSON, func
from sqlalchemy.orm import relationship
from datetime import datetime
import uuid as uuid_pkg
import enum

from database import Base
from models import Sport, UUID, uuid


# MARK: - Premium Subscription

class SubscriptionTier(str, enum.Enum):
    FREE = "free"
    PREMIUM = "premium"


class SubscriptionStatus(str, enum.Enum):
    ACTIVE = "active"
    CANCELLED = "cancelled"
    EXPIRED = "expired"
    TRIAL = "trial"


class Subscription(Base):
    """Premium subscription records"""
    __tablename__ = "subscriptions"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    user_id = Column(UUID(), ForeignKey("users.id"), unique=True, nullable=False)
    tier = Column(SQLEnum(SubscriptionTier), default=SubscriptionTier.FREE, nullable=False)
    status = Column(SQLEnum(SubscriptionStatus), default=SubscriptionStatus.ACTIVE, nullable=False)

    # Payment info
    price_per_month = Column(Float, default=8.99)
    started_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True))
    cancelled_at = Column(DateTime(timezone=True))

    # Platform
    platform = Column(String(50))  # "apple", "google", "stripe"
    external_subscription_id = Column(String(255))

    # Features
    features = Column(JSON, default={
        "ai_coach": True,
        "smartwatch_sync": True,
        "tournaments": True,
        "advanced_analytics": True,
        "goals_system": True,
        "performance_predictions": True
    })

    # Relationships
    user = relationship("User", back_populates="subscription")


# MARK: - Sport Goals Survey

class SkillFocus(str, enum.Enum):
    # Basketball
    SHOOTING = "shooting"
    DRIBBLING = "dribbling"
    PASSING = "passing"
    DEFENSE = "defense"
    REBOUNDING = "rebounding"

    # Football
    THROWING = "throwing"
    CATCHING = "catching"
    RUNNING = "running"
    BLOCKING = "blocking"
    TACKLING = "tackling"

    # Soccer
    BALL_CONTROL = "ball_control"
    PASSING_SOCCER = "passing_soccer"
    SHOOTING_SOCCER = "shooting_soccer"
    DEFENDING = "defending"
    GOALKEEPING = "goalkeeping"

    # Tennis
    SERVE = "serve"
    FOREHAND = "forehand"
    BACKHAND = "backhand"
    VOLLEY = "volley"
    FOOTWORK = "footwork"

    # General
    ENDURANCE = "endurance"
    SPEED = "speed"
    STRENGTH = "strength"
    AGILITY = "agility"
    FLEXIBILITY = "flexibility"
    MENTAL_TOUGHNESS = "mental_toughness"
    STRATEGY = "strategy"
    RECOVERY = "recovery"


class SportGoals(Base):
    """Sport-specific goals survey responses (Premium only)"""
    __tablename__ = "sport_goals"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    user_id = Column(UUID(), ForeignKey("users.id"), nullable=False)
    sport = Column(SQLEnum(Sport), nullable=False)

    # Focus areas (stored as JSON arrays)
    skill_focus = Column(JSON, default=[])  # SkillFocus values
    physical_focus = Column(JSON, default=[])
    tactical_focus = Column(JSON, default=[])
    mental_focus = Column(JSON, default=[])

    # Custom goals
    custom_goals = Column(Text)

    # Priority levels (1-5)
    improvement_priority = Column(JSON, default={})  # {skill: priority_level}

    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=datetime.now)

    # Relationships
    user = relationship("User")


# MARK: - Smartwatch Sync

class WearableDevice(str, enum.Enum):
    APPLE_WATCH = "apple_watch"
    WEAR_OS = "wear_os"
    FITBIT = "fitbit"
    GARMIN = "garmin"
    WHOOP = "whoop"
    OURA = "oura"


class SmartwatchConnection(Base):
    """Smartwatch device connections"""
    __tablename__ = "smartwatch_connections"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    user_id = Column(UUID(), ForeignKey("users.id"), unique=True, nullable=False)

    device_type = Column(SQLEnum(WearableDevice), nullable=False)
    device_name = Column(String(100))
    device_id = Column(String(255))

    # Connection status
    is_connected = Column(Boolean, default=True)
    last_sync = Column(DateTime(timezone=True))
    sync_frequency = Column(Integer, default=3600)  # seconds

    # Permissions
    permissions = Column(JSON, default={
        "heart_rate": True,
        "hrv": True,
        "sleep": True,
        "activity": True,
        "workouts": True
    })

    # Auth
    access_token = Column(Text)
    refresh_token = Column(Text)
    token_expires_at = Column(DateTime(timezone=True))

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User")


class BiometricData(Base):
    """Daily biometric data from smartwatch"""
    __tablename__ = "biometric_data"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    user_id = Column(UUID(), ForeignKey("users.id"), nullable=False)
    date = Column(DateTime(timezone=True), nullable=False)

    # Heart metrics
    resting_heart_rate = Column(Integer)  # bpm
    avg_heart_rate = Column(Integer)
    max_heart_rate = Column(Integer)
    heart_rate_variability = Column(Integer)  # ms

    # Sleep metrics
    sleep_duration = Column(Integer)  # minutes
    deep_sleep = Column(Integer)  # minutes
    rem_sleep = Column(Integer)  # minutes
    light_sleep = Column(Integer)  # minutes
    sleep_quality_score = Column(Float)  # 0-100

    # Activity metrics
    steps = Column(Integer)
    active_calories = Column(Integer)
    total_calories = Column(Integer)
    exercise_minutes = Column(Integer)

    # Recovery & strain
    recovery_score = Column(Float)  # 0-100 (Whoop-style)
    training_strain = Column(Float)  # 0-21 (Whoop-style)
    day_strain = Column(Float)

    # Calculated by AI
    readiness_score = Column(Float)  # 0-100
    fatigue_level = Column(String(20))  # "low", "medium", "high", "very_high"
    performance_prediction = Column(Float)  # -10 to +10 (% expected change)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User")


# MARK: - Tournament System

class TournamentType(str, enum.Enum):
    SOLO = "solo"
    TEAM = "team"


class TournamentFormat(str, enum.Enum):
    SINGLE_ELIMINATION = "single_elimination"
    DOUBLE_ELIMINATION = "double_elimination"
    ROUND_ROBIN = "round_robin"
    LADDER = "ladder"


class TournamentRanked(str, enum.Enum):
    RANKED = "ranked"
    UNRANKED = "unranked"


class TournamentStatus(str, enum.Enum):
    UPCOMING = "upcoming"
    REGISTRATION_OPEN = "registration_open"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class Tournament(Base):
    """Tournament events (Premium feature)"""
    __tablename__ = "tournaments"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    creator_id = Column(UUID(), ForeignKey("users.id"), nullable=False)

    # Basic info
    name = Column(String(200), nullable=False)
    description = Column(Text)
    sport = Column(SQLEnum(Sport), nullable=False)

    # Tournament settings
    tournament_type = Column(SQLEnum(TournamentType), nullable=False)
    format = Column(SQLEnum(TournamentFormat), nullable=False)
    ranked_type = Column(SQLEnum(TournamentRanked), default=TournamentRanked.RANKED)

    # Participants
    max_participants = Column(Integer, nullable=False)
    team_size = Column(Integer, default=1)  # 1 for solo, 2-5 for team
    min_elo = Column(Integer)
    max_elo = Column(Integer)

    # Schedule
    registration_opens = Column(DateTime(timezone=True), nullable=False)
    registration_closes = Column(DateTime(timezone=True), nullable=False)
    starts_at = Column(DateTime(timezone=True), nullable=False)
    ends_at = Column(DateTime(timezone=True))

    # Status
    status = Column(SQLEnum(TournamentStatus), default=TournamentStatus.UPCOMING)
    current_round = Column(Integer, default=0)

    # Prize/rewards
    prizes = Column(JSON, default={})
    badges_awarded = Column(JSON, default=[])

    # Settings
    is_public = Column(Boolean, default=True)
    is_school = Column(Boolean, default=False)
    is_regional = Column(Boolean, default=False)
    region = Column(String(100))
    school_name = Column(String(200))

    # Generated bracket
    bracket = Column(JSON)  # Tournament bracket structure

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    creator = relationship("User", foreign_keys=[creator_id])
    participants = relationship("TournamentParticipant", back_populates="tournament")
    matches = relationship("TournamentMatch", back_populates="tournament")


class TournamentParticipant(Base):
    """Tournament participant registration"""
    __tablename__ = "tournament_participants"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    tournament_id = Column(UUID(), ForeignKey("tournaments.id"), nullable=False)
    user_id = Column(UUID(), ForeignKey("users.id"))
    team_id = Column(UUID(), ForeignKey("teams.id"))

    # Registration
    registered_at = Column(DateTime(timezone=True), server_default=func.now())
    seed = Column(Integer)  # Tournament seeding

    # Performance
    placement = Column(Integer)  # Final placement
    wins = Column(Integer, default=0)
    losses = Column(Integer, default=0)
    points_scored = Column(Integer, default=0)
    points_allowed = Column(Integer, default=0)

    # Status
    is_eliminated = Column(Boolean, default=False)
    eliminated_round = Column(Integer)

    tournament = relationship("Tournament", back_populates="participants")
    user = relationship("User")
    team = relationship("Team")


class TournamentMatch(Base):
    """Individual matches within tournament"""
    __tablename__ = "tournament_matches"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    tournament_id = Column(UUID(), ForeignKey("tournaments.id"), nullable=False)

    # Match info
    round_number = Column(Integer, nullable=False)
    match_number = Column(Integer, nullable=False)
    bracket_position = Column(String(50))  # "upper_1", "lower_2", etc

    # Participants (user or team)
    participant1_id = Column(UUID(), ForeignKey("tournament_participants.id"))
    participant2_id = Column(UUID(), ForeignKey("tournament_participants.id"))

    # Results
    participant1_score = Column(Integer)
    participant2_score = Column(Integer)
    winner_id = Column(UUID(), ForeignKey("tournament_participants.id"))

    # Schedule
    scheduled_at = Column(DateTime(timezone=True))
    completed_at = Column(DateTime(timezone=True))

    # Status
    is_complete = Column(Boolean, default=False)
    is_bye = Column(Boolean, default=False)

    tournament = relationship("Tournament", back_populates="matches")


# MARK: - AI Coach Data

class AICoachInsight(Base):
    """AI-generated insights and recommendations"""
    __tablename__ = "ai_coach_insights"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    user_id = Column(UUID(), ForeignKey("users.id"), nullable=False)
    sport = Column(SQLEnum(Sport))

    # Insight type
    insight_type = Column(String(50), nullable=False)  # "training", "recovery", "match_prep", etc
    priority = Column(String(20), default="medium")  # "low", "medium", "high", "urgent"

    # Content
    title = Column(String(200), nullable=False)
    message = Column(Text, nullable=False)
    details = Column(JSON)

    # Action items
    suggested_actions = Column(JSON, default=[])
    drills_recommended = Column(JSON, default=[])

    # Context
    based_on = Column(JSON)  # What data drove this insight
    confidence = Column(Float)  # AI confidence 0-1

    # Status
    is_read = Column(Boolean, default=False)
    is_dismissed = Column(Boolean, default=False)
    is_actionable = Column(Boolean, default=True)

    # Expiry
    expires_at = Column(DateTime(timezone=True))

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User")


class PerformancePrediction(Base):
    """AI performance predictions"""
    __tablename__ = "performance_predictions"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    user_id = Column(UUID(), ForeignKey("users.id"), nullable=False)
    sport = Column(SQLEnum(Sport), nullable=False)

    # Prediction
    prediction_date = Column(DateTime(timezone=True), nullable=False)
    prediction_type = Column(String(50))  # "match", "tournament", "weekly"

    # Scores
    performance_index = Column(Float)  # -10 to +10
    readiness_score = Column(Float)  # 0-100
    confidence = Column(Float)  # 0-1

    # Factors
    factors = Column(JSON, default={
        "recovery": 0,
        "recent_performance": 0,
        "training_load": 0,
        "sleep_quality": 0,
        "stress_level": 0
    })

    # Actual outcome (filled in later)
    actual_performance = Column(Float)
    actual_outcome = Column(String(50))
    prediction_accuracy = Column(Float)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User")
