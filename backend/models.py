"""
SQLAlchemy database models for SportsHub
"""
from sqlalchemy import Boolean, Column, Integer, String, DateTime, Float, ForeignKey, Text, Enum as SQLEnum, JSON, TypeDecorator, Index
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base
import uuid as uuid_pkg
import enum


# Custom UUID type that works with SQLite
class UUID(TypeDecorator):
    """Platform-independent UUID type.

    Uses PostgreSQL's UUID type, otherwise uses
    String(36), storing as stringified hex values.
    """
    impl = String
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == 'postgresql':
            return dialect.type_descriptor(PG_UUID())
        else:
            return dialect.type_descriptor(String(36))

    def process_bind_param(self, value, dialect):
        if value is None:
            return value
        elif dialect.name == 'postgresql':
            return value
        else:
            if not isinstance(value, uuid_pkg.UUID):
                return str(value)
            else:
                return str(value)

    def process_result_value(self, value, dialect):
        if value is None:
            return value
        else:
            if not isinstance(value, uuid_pkg.UUID):
                value = uuid_pkg.UUID(value)
            return value


# Helper to generate UUID
def uuid():
    return uuid_pkg.uuid4()


# Enums
class UserRole(str, enum.Enum):
    USER = "user"
    ADMIN = "admin"


class AccountStatus(str, enum.Enum):
    ACTIVE = "active"
    SUSPENDED = "suspended"
    BANNED = "banned"
    SHADOW_BANNED = "shadow_banned"
    PENDING_VERIFICATION = "pending_verification"


class Sport(str, enum.Enum):
    BASKETBALL = "basketball"
    FOOTBALL = "football"
    SOCCER = "soccer"
    TENNIS = "tennis"


class FriendshipStatus(str, enum.Enum):
    PENDING = "pending"
    ACCEPTED = "accepted"
    BLOCKED = "blocked"
    DECLINED = "declined"


class ChallengeStatus(str, enum.Enum):
    PENDING = "pending"
    ACCEPTED = "accepted"
    DECLINED = "declined"
    COMPLETED = "completed"
    DISPUTED = "disputed"


class MatchType(str, enum.Enum):
    RANKED = "ranked"
    UNRANKED = "unranked"


class DisputeStatus(str, enum.Enum):
    PENDING = "pending"
    UNDER_REVIEW = "under_review"
    RESOLVED = "resolved"
    REJECTED = "rejected"


class EvidenceType(str, enum.Enum):
    IMAGE = "image"
    VIDEO = "video"
    SCREENSHOT = "screenshot"


class EvidenceStatus(str, enum.Enum):
    UPLOADED = "uploaded"
    UNDER_REVIEW = "under_review"
    VERIFIED = "verified"
    REJECTED = "rejected"


class AthleticLevel(str, enum.Enum):
    VARSITY = "varsity"
    JV = "jv"
    CLUB = "club"
    RECREATIONAL = "recreational"
    BEGINNER = "beginner"


# Models
class User(Base):
    __tablename__ = "users"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    email = Column(String(255), nullable=False, index=True)  # Removed unique constraint
    username = Column(String(50), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)
    display_name = Column(String(100))
    date_of_birth = Column(DateTime, nullable=False)
    avatar_seed = Column(String(100))
    bio = Column(Text)
    pronouns = Column(String(50))
    role = Column(SQLEnum(UserRole), default=UserRole.USER)
    account_status = Column(SQLEnum(AccountStatus), default=AccountStatus.ACTIVE)
    age_verified = Column(Boolean, default=False)
    email_verified = Column(Boolean, default=False)
    verification_token = Column(String(100))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    last_login = Column(DateTime(timezone=True))

    # Relationships
    sport_profiles = relationship("SportProfile", back_populates="user", cascade="all, delete-orphan")
    friendships_sent = relationship("Friendship", foreign_keys="Friendship.user_a_id", back_populates="user_a")
    friendships_received = relationship("Friendship", foreign_keys="Friendship.user_b_id", back_populates="user_b")
    # subscription = relationship("Subscription", back_populates="user", uselist=False, cascade="all, delete-orphan")  # Defined in models_premium.py


class SportProfile(Base):
    __tablename__ = "sport_profiles"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    user_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    sport = Column(SQLEnum(Sport), nullable=False)
    rating = Column(Integer, default=1500)
    provisional_games = Column(Integer, default=0)
    is_provisional = Column(Boolean, default=True)
    rank_tier = Column(String(20), default="bronze")
    athletic_level = Column(SQLEnum(AthleticLevel), default=AthleticLevel.RECREATIONAL)
    games_played = Column(Integer, default=0)
    ranked_games_played = Column(Integer, default=0)
    wins = Column(Integer, default=0)
    losses = Column(Integer, default=0)
    best_streak = Column(Integer, default=0)
    current_streak = Column(Integer, default=0)
    progression_level = Column(Integer, default=1)
    last_played = Column(DateTime(timezone=True))

    # Trust and reliability tracking (Phase 3)
    matches_completed = Column(Integer, default=0)  # Matches that reached completion
    matches_disputed = Column(Integer, default=0)   # Matches that went to dispute
    disputes_won = Column(Integer, default=0)        # Admin ruled in player's favor
    disputes_lost = Column(Integer, default=0)       # Admin ruled against player
    trust_score = Column(Float, default=100.0)       # 0-100, starts at 100
    is_flagged = Column(Boolean, default=False)      # Flagged for admin review
    flagged_reason = Column(String(200))             # Why flagged
    flagged_at = Column(DateTime(timezone=True))

    # Phase 4: Advanced anti-exploitation tracking
    evidence_required_matches = Column(Integer, default=0)  # Matches requiring evidence
    evidence_submissions = Column(Integer, default=0)       # Times user submitted evidence
    one_sided_submissions = Column(Integer, default=0)      # Matches where only they submitted
    repeated_mismatches = Column(Integer, default=0)        # Consecutive score disagreements
    challenges_created = Column(Integer, default=0)         # Total challenges initiated
    challenges_declined_by_opponent = Column(Integer, default=0)  # Challenges declined
    no_shows = Column(Integer, default=0)                   # Accepted but never submitted result
    suspicion_score = Column(Float, default=0.0)            # 0-100, accumulates with patterns
    trust_tier = Column(String(20), default="standard")     # trusted, standard, caution, restricted
    last_restriction_applied = Column(DateTime(timezone=True))
    restriction_count = Column(Integer, default=0)          # Times restricted

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Relationships
    user = relationship("User", back_populates="sport_profiles")

    @property
    def completion_rate(self) -> float:
        """Calculate percentage of matches completed without dispute"""
        total = self.matches_completed + self.matches_disputed
        if total == 0:
            return 100.0
        return (self.matches_completed / total) * 100

    @property
    def dispute_rate(self) -> float:
        """Calculate percentage of matches that resulted in dispute"""
        total = self.matches_completed + self.matches_disputed
        if total == 0:
            return 0.0
        return (self.matches_disputed / total) * 100

    @property
    def no_show_rate(self) -> float:
        """Calculate percentage of accepted challenges where user never submitted"""
        total = self.games_played + self.no_shows
        if total == 0:
            return 0.0
        return (self.no_shows / total) * 100

    @property
    def evidence_compliance_rate(self) -> float:
        """When evidence required, how often did they provide it?"""
        if self.evidence_required_matches == 0:
            return 100.0
        return (self.evidence_submissions / self.evidence_required_matches) * 100

    def should_require_evidence(self) -> bool:
        """Phase 4: Determine if evidence should be required for this user"""
        # Require evidence if:
        # - High dispute rate (>30%)
        # - Recent repeated mismatches (>3 in row)
        # - Trust tier is caution or restricted
        # - Flagged for suspicious behavior
        if self.dispute_rate > 30.0:
            return True
        if self.repeated_mismatches >= 3:
            return True
        if self.trust_tier in ["caution", "restricted"]:
            return True
        if self.is_flagged:
            return True
        return False


class Friendship(Base):
    __tablename__ = "friendships"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    user_a_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    user_b_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    status = Column(SQLEnum(FriendshipStatus), nullable=False)
    initiated_by = Column(UUID(), ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    accepted_at = Column(DateTime(timezone=True))

    # Relationships
    user_a = relationship("User", foreign_keys=[user_a_id], back_populates="friendships_sent")
    user_b = relationship("User", foreign_keys=[user_b_id], back_populates="friendships_received")


class Message(Base):
    __tablename__ = "messages"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    sender_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    receiver_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"))  # Nullable for group messages
    group_id = Column(UUID(), ForeignKey("group_chats.id", ondelete="CASCADE"))  # For group messages
    content = Column(Text, nullable=False)
    safety_checked = Column(Boolean, default=False)
    moderation_status = Column(String(20), default="pending")
    sent_at = Column(DateTime(timezone=True), server_default=func.now())
    read_at = Column(DateTime(timezone=True))
    deleted_by_sender = Column(Boolean, default=False)
    deleted_by_receiver = Column(Boolean, default=False)


class Challenge(Base):
    __tablename__ = "challenges"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    sport = Column(SQLEnum(Sport), nullable=False)
    match_type = Column(SQLEnum(MatchType), default=MatchType.RANKED)
    challenger_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    opponent_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    status = Column(SQLEnum(ChallengeStatus), nullable=False)
    score_data = Column(JSON)
    impact_weight = Column(Float, default=1.0)
    winner_id = Column(UUID(), ForeignKey("users.id"))
    challenger_confirmed = Column(Boolean, default=False)
    opponent_confirmed = Column(Boolean, default=False)
    challenger_rating_before = Column(Integer)
    opponent_rating_before = Column(Integer)
    challenger_rating_after = Column(Integer)
    opponent_rating_after = Column(Integer)

    # Result submission tracking (Phase 3)
    challenger_submitted_score = Column(String(50))  # Format: "21-18" or null
    opponent_submitted_score = Column(String(50))  # Format: "21-18" or null
    challenger_submitted_at = Column(DateTime(timezone=True))
    opponent_submitted_at = Column(DateTime(timezone=True))

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    accepted_at = Column(DateTime(timezone=True))
    completed_at = Column(DateTime(timezone=True))


class Match(Base):
    """Match results for ELO tracking and leaderboards"""
    __tablename__ = "matches"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    sport = Column(SQLEnum(Sport), nullable=False)
    match_type = Column(SQLEnum(MatchType), default=MatchType.RANKED)
    player1_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    player2_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    status = Column(String(20), nullable=False)  # "pending", "completed", "disputed"
    player1_score = Column(Integer)
    player2_score = Column(Integer)
    winner_id = Column(UUID(), ForeignKey("users.id"))
    player1_elo_before = Column(Integer)
    player2_elo_before = Column(Integer)
    player1_elo_after = Column(Integer)
    player2_elo_after = Column(Integer)
    player1_elo_change = Column(Integer)
    player2_elo_change = Column(Integer)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    completed_at = Column(DateTime(timezone=True))


class Post(Base):
    __tablename__ = "posts"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    author_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    content = Column(Text, nullable=False)
    sport = Column(SQLEnum(Sport))
    safety_checked = Column(Boolean, default=False)
    moderation_status = Column(String(20), default="pending")
    likes_count = Column(Integer, default=0)
    comments_count = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Clip(Base):
    __tablename__ = "clips"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    author_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    sport = Column(SQLEnum(Sport), nullable=False)
    title = Column(String(200), nullable=False)
    description = Column(Text)
    video_url = Column(String(500))
    thumbnail_url = Column(String(500))
    thumbnail_gradient = Column(JSON)
    duration = Column(Integer)
    views_count = Column(Integer, default=0)
    likes_count = Column(Integer, default=0)
    safety_checked = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class ModerationFlag(Base):
    __tablename__ = "moderation_flags"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    content_type = Column(String(20))
    content_id = Column(UUID())
    reporter_id = Column(UUID(), ForeignKey("users.id"))
    reason = Column(String(100))
    status = Column(String(20), default="pending")
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class AdminAction(Base):
    __tablename__ = "admin_actions"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    admin_id = Column(UUID(), ForeignKey("users.id"), nullable=False)
    target_user_id = Column(UUID(), ForeignKey("users.id"))
    target_content_id = Column(UUID())
    action_type = Column(String(50), nullable=False)
    reason = Column(Text)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())


class Dispute(Base):
    __tablename__ = "disputes"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    challenge_id = Column(UUID(), ForeignKey("challenges.id", ondelete="CASCADE"), nullable=False)
    initiator_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    reason = Column(Text, nullable=False)
    evidence = Column(JSON)
    status = Column(SQLEnum(DisputeStatus), default=DisputeStatus.PENDING)
    admin_notes = Column(Text)
    resolved_by = Column(UUID(), ForeignKey("users.id"))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    resolved_at = Column(DateTime(timezone=True))


class MatchEvidence(Base):
    """Phase 4: Evidence uploads for match verification and dispute resolution"""
    __tablename__ = "match_evidence"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    challenge_id = Column(UUID(), ForeignKey("challenges.id", ondelete="CASCADE"), nullable=False)
    submitter_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    evidence_type = Column(SQLEnum(EvidenceType), nullable=False)
    file_url = Column(String(500), nullable=False)  # S3 or CDN URL
    thumbnail_url = Column(String(500))  # For videos
    description = Column(Text)
    status = Column(SQLEnum(EvidenceStatus), default=EvidenceStatus.UPLOADED)
    is_required = Column(Boolean, default=False)  # Was this required or optional?
    reviewed_by = Column(UUID(), ForeignKey("users.id"))  # Admin who reviewed
    review_notes = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    reviewed_at = Column(DateTime(timezone=True))


class BlockedUser(Base):
    __tablename__ = "blocked_users"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    blocker_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    blocked_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Comment(Base):
    __tablename__ = "comments"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    post_id = Column(UUID(), ForeignKey("posts.id", ondelete="CASCADE"), nullable=False)
    author_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    content = Column(Text, nullable=False)
    parent_comment_id = Column(UUID(), ForeignKey("comments.id"))
    safety_checked = Column(Boolean, default=False)
    moderation_status = Column(String(20), default="pending")
    likes_count = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class UserBadge(Base):
    __tablename__ = "user_badges"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    user_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    badge_id = Column(String(100), nullable=False)
    sport = Column(SQLEnum(Sport), nullable=False)
    earned_at = Column(DateTime(timezone=True), server_default=func.now())
    progress = Column(Integer, default=0)


class Team(Base):
    __tablename__ = "teams"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    name = Column(String(100), nullable=False)
    sport = Column(SQLEnum(Sport), nullable=False)
    captain_id = Column(UUID(), ForeignKey("users.id"), nullable=False)
    rating = Column(Integer, default=1500)
    games_played = Column(Integer, default=0)
    wins = Column(Integer, default=0)
    losses = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class TeamMember(Base):
    __tablename__ = "team_members"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    team_id = Column(UUID(), ForeignKey("teams.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    joined_at = Column(DateTime(timezone=True), server_default=func.now())


class TeamChallenge(Base):
    __tablename__ = "team_challenges"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    sport = Column(SQLEnum(Sport), nullable=False)
    team1_id = Column(UUID(), ForeignKey("teams.id"), nullable=False)
    team2_id = Column(UUID(), ForeignKey("teams.id"), nullable=False)
    match_type = Column(SQLEnum(MatchType), default=MatchType.RANKED)
    status = Column(SQLEnum(ChallengeStatus), nullable=False)
    winner_team_id = Column(UUID(), ForeignKey("teams.id"))
    team1_rating_before = Column(Integer)
    team2_rating_before = Column(Integer)
    team1_rating_after = Column(Integer)
    team2_rating_after = Column(Integer)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    completed_at = Column(DateTime(timezone=True))


# Group Messaging Models
class GroupChat(Base):
    __tablename__ = "group_chats"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    name = Column(String(100), nullable=False)
    description = Column(Text)
    creator_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    avatar_seed = Column(String(50))  # For consistent group avatars
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())


class GroupChatMember(Base):
    __tablename__ = "group_chat_members"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    group_id = Column(UUID(), ForeignKey("group_chats.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    role = Column(String(20), default="member")  # admin, member
    joined_at = Column(DateTime(timezone=True), server_default=func.now())
    last_read_at = Column(DateTime(timezone=True))


# Highlights/Stories Models
class Highlight(Base):
    __tablename__ = "highlights"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    user_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    media_url = Column(String(500), nullable=False)
    thumbnail_url = Column(String(500))
    caption = Column(Text)
    sport = Column(SQLEnum(Sport))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=False)  # 24 hours from creation
    views_count = Column(Integer, default=0)


class HighlightView(Base):
    __tablename__ = "highlight_views"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    highlight_id = Column(UUID(), ForeignKey("highlights.id", ondelete="CASCADE"), nullable=False)
    viewer_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    viewed_at = Column(DateTime(timezone=True), server_default=func.now())


# Tennis Court Models
class TennisCourt(Base):
    """Real tennis court locations for venue-specific matchmaking"""
    __tablename__ = "tennis_courts"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    name = Column(String(200), nullable=False)
    address = Column(String(500), nullable=False)
    city = Column(String(100), nullable=False)
    state = Column(String(50), nullable=False)
    postal_code = Column(String(20))
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)

    # Venue access information
    venue_type = Column(String(50), nullable=False)  # public, private_club, recreation_center, school, hotel
    requires_reservation = Column(Boolean, default=False)
    requires_membership = Column(Boolean, default=False)
    hourly_rate = Column(Float)  # Nullable - free courts have None
    currency = Column(String(10), default="USD")

    # Court details
    surface_type = Column(String(50))  # hard, clay, grass, carpet
    num_courts = Column(Integer, default=1)
    has_lights = Column(Boolean, default=False)
    indoor = Column(Boolean, default=False)

    # Contact and availability
    phone = Column(String(50))
    website = Column(String(500))
    hours_of_operation = Column(Text)  # JSON or text describing hours

    # Metadata
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    is_verified = Column(Boolean, default=False)  # Admin-verified court
    added_by = Column(UUID(), ForeignKey("users.id"))  # User who added (community-sourced)


# AI Coach Context Storage - PRIORITY FIX 2: Persistent Memory
class CoachContext(Base):
    """
    Stores persistent coaching context so AI Coach remembers the athlete.
    This is the key to making coaching feel real, not stateless.
    """
    __tablename__ = "coach_context"

    id = Column(UUID(), primary_key=True, default=uuid_pkg.uuid4)
    user_id = Column(UUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    sport = Column(SQLEnum(Sport), nullable=False)

    # Weak points the athlete has mentioned
    weak_points = Column(JSON, default=list)  # ["left hand", "shooting consistency", etc.]

    # Goals the athlete is working toward
    goals = Column(JSON, default=list)  # ["improve athleticism", "make varsity team", etc.]

    # Training preferences
    preferred_training_duration = Column(Integer)  # minutes
    preferred_training_time = Column(String(50))  # "morning", "afternoon", "evening"
    training_frequency = Column(String(50))  # "daily", "3x/week", etc.

    # Recent coaching advice given (to avoid repetition)
    recent_recommendations = Column(JSON, default=list)  # Last 5 workout/drill recommendations

    # Context from conversations
    mentioned_skills = Column(JSON, default=list)  # Skills user has discussed
    training_focus = Column(String(200))  # Current focus area
    notes = Column(Text)  # Free-form coach notes

    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    last_interaction = Column(DateTime(timezone=True), server_default=func.now())

    # Indexes for fast lookup
    __table_args__ = (
        Index('idx_coach_context_user_sport', 'user_id', 'sport'),
    )

