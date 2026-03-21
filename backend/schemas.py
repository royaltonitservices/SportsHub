"""
Pydantic schemas for request/response validation
"""
from pydantic import BaseModel, EmailStr, Field, model_validator
from typing import Optional, List
from datetime import datetime
from uuid import UUID
import models


# Auth Schemas
class UserSignup(BaseModel):
    email: EmailStr
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=6)
    display_name: str = Field(..., max_length=100)
    date_of_birth: datetime


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class TokenData(BaseModel):
    user_id: Optional[UUID] = None


# User Schemas
class UserBase(BaseModel):
    email: EmailStr
    username: str
    display_name: str


class UserResponse(UserBase):
    id: UUID
    role: models.UserRole
    account_status: models.AccountStatus
    age_verified: bool
    created_at: datetime
    full_name: Optional[str] = None
    is_admin: bool = False

    class Config:
        from_attributes = True

    @model_validator(mode='before')
    @classmethod
    def compute_fields(cls, data):
        if hasattr(data, '__dict__'):
            # Converting from ORM object
            obj = data
            return {
                'id': obj.id,
                'email': obj.email,
                'username': obj.username,
                'display_name': obj.display_name,
                'role': obj.role,
                'account_status': obj.account_status,
                'age_verified': obj.age_verified,
                'created_at': obj.created_at,
                'full_name': obj.display_name,
                'is_admin': obj.role == models.UserRole.ADMIN
            }
        return data


class UserProfile(UserResponse):
    bio: Optional[str] = None
    avatar_seed: Optional[str] = None
    pronouns: Optional[str] = None


# Sport Profile Schemas
class SportProfileResponse(BaseModel):
    id: UUID
    sport: models.Sport
    rating: int
    provisional_games: int
    is_provisional: bool
    rank_tier: str
    athletic_level: models.AthleticLevel
    games_played: int
    ranked_games_played: int
    wins: int
    losses: int
    best_streak: int
    current_streak: int

    class Config:
        from_attributes = True


class UpdateAthleticLevel(BaseModel):
    sport: models.Sport
    athletic_level: models.AthleticLevel


# Friend Schemas
class FriendRequest(BaseModel):
    target_user_id: UUID


class FriendshipResponse(BaseModel):
    id: UUID
    user_a_id: UUID
    user_b_id: UUID
    status: models.FriendshipStatus
    created_at: datetime

    class Config:
        from_attributes = True


class FriendStatusResponse(BaseModel):
    status: str  # "none", "pending", "accepted", "blocked", "declined"
    is_friend: bool
    is_pending: bool
    is_blocked: bool
    initiated_by_me: bool


# Message Schemas
class MessageCreate(BaseModel):
    receiver_id: UUID
    content: str = Field(..., max_length=1000)


class MessageResponse(BaseModel):
    id: UUID
    sender_id: UUID
    receiver_id: UUID
    content: str
    sent_at: datetime
    read_at: Optional[datetime]

    class Config:
        from_attributes = True


# Challenge Schemas
class ChallengeCreate(BaseModel):
    sport: models.Sport
    match_type: models.MatchType
    opponent_id: UUID


class ChallengeResponse(BaseModel):
    id: UUID
    sport: models.Sport
    match_type: models.MatchType
    challenger_id: UUID
    opponent_id: UUID
    status: models.ChallengeStatus
    challenger_confirmed: bool
    opponent_confirmed: bool
    created_at: datetime

    class Config:
        from_attributes = True


class SubmitMatchResult(BaseModel):
    challenge_id: UUID
    winner_id: UUID
    score_data: Optional[dict] = None


class DisputeCreate(BaseModel):
    challenge_id: UUID
    reason: str
    evidence: Optional[dict] = None


class DisputeResponse(BaseModel):
    id: UUID
    challenge_id: UUID
    initiator_id: UUID
    reason: str
    status: models.DisputeStatus
    admin_notes: Optional[str]
    created_at: datetime
    resolved_at: Optional[datetime]

    class Config:
        from_attributes = True


# Post Schemas
class PostCreate(BaseModel):
    content: str = Field(..., max_length=500)
    sport: Optional[models.Sport] = None


class PostResponse(BaseModel):
    id: UUID
    author_id: UUID
    content: str
    sport: Optional[models.Sport]
    likes_count: int
    comments_count: int
    created_at: datetime

    class Config:
        from_attributes = True


# Clip Schemas
class ClipCreate(BaseModel):
    sport: models.Sport
    title: str = Field(..., max_length=200)
    video_url: Optional[str] = None
    duration: int


class ClipResponse(BaseModel):
    id: UUID
    author_id: UUID
    sport: models.Sport
    title: str
    duration: int
    views_count: int
    likes_count: int
    created_at: datetime

    class Config:
        from_attributes = True


# Admin Schemas
class AdminUserList(BaseModel):
    id: UUID
    username: str
    email: str
    account_status: models.AccountStatus
    created_at: datetime
    last_login: Optional[datetime]

    class Config:
        from_attributes = True


class AdminActionCreate(BaseModel):
    target_user_id: Optional[UUID] = None
    action_type: str
    reason: str


class ModerationFlagResponse(BaseModel):
    id: UUID
    content_type: str
    content_id: UUID
    reporter_id: UUID
    reason: str
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


# Comment Schemas
class CommentCreate(BaseModel):
    post_id: UUID
    content: str = Field(..., max_length=500)
    parent_comment_id: Optional[UUID] = None


class CommentResponse(BaseModel):
    id: UUID
    post_id: UUID
    author_id: UUID
    content: str
    parent_comment_id: Optional[UUID]
    likes_count: int
    created_at: datetime

    class Config:
        from_attributes = True


# Block Schemas
class BlockUser(BaseModel):
    blocked_user_id: UUID


# Search Schema
class SearchQuery(BaseModel):
    query: str = Field(..., min_length=2)
    search_type: Optional[str] = "all"  # all, users, posts, clips


# Leaderboard Schema
class LeaderboardEntry(BaseModel):
    user_id: UUID
    username: str
    display_name: str
    rating: int
    rank_tier: str
    games_played: int
    wins: int
    losses: int
    win_rate: float

    class Config:
        from_attributes = True


class MatchmakingRequest(BaseModel):
    sport: models.Sport
    match_type: models.MatchType


class MatchmakingResult(BaseModel):
    available_opponents: List[UserProfile]
    your_rating: int
    rating_range: tuple


# Highlights Schemas
class HighlightCreate(BaseModel):
    media_url: str
    thumbnail_url: Optional[str] = None
    caption: Optional[str] = None
    sport: Optional[models.Sport] = None


class HighlightResponse(BaseModel):
    id: UUID
    user_id: UUID
    media_url: str
    thumbnail_url: Optional[str]
    caption: Optional[str]
    sport: Optional[models.Sport]
    created_at: datetime
    expires_at: datetime
    views_count: int

    class Config:
        from_attributes = True


class HighlightFeedItem(BaseModel):
    user_id: str
    username: str
    display_name: Optional[str]
    avatar_seed: Optional[str]
    has_unviewed: bool
    highlight_count: int
    latest_thumbnail: Optional[str]


# Group Chat Schemas
class GroupChatCreate(BaseModel):
    name: str
    description: Optional[str] = None
    member_ids: List[str]  # List of user IDs to add to the group


class GroupChatResponse(BaseModel):
    id: UUID
    name: str
    description: Optional[str]
    creator_id: UUID
    avatar_seed: Optional[str]
    created_at: datetime
    member_count: int
    last_message: Optional[str]
    last_message_at: Optional[datetime]
    unread_count: int

    class Config:
        from_attributes = True


class GroupMessageCreate(BaseModel):
    content: str


class GroupMessageResponse(BaseModel):
    id: UUID
    group_id: UUID
    sender_id: UUID
    sender_name: str
    content: str
    sent_at: datetime

    class Config:
        from_attributes = True


# Phase 4: Evidence Schemas
class EvidenceUpload(BaseModel):
    evidence_type: str  # "image", "video", "screenshot"
    file_url: str
    description: Optional[str] = None


class EvidenceResponse(BaseModel):
    id: UUID
    challenge_id: UUID
    submitter_id: UUID
    evidence_type: str
    file_url: str
    thumbnail_url: Optional[str]
    description: Optional[str]
    status: str  # "uploaded", "under_review", "verified", "rejected"
    is_required: bool
    review_notes: Optional[str]
    created_at: datetime
    reviewed_at: Optional[datetime]

    class Config:
        from_attributes = True


# Tennis Court Schemas
class TennisCourtCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    address: str = Field(..., min_length=1, max_length=500)
    city: str = Field(..., min_length=1, max_length=100)
    state: str = Field(..., min_length=1, max_length=50)
    postal_code: Optional[str] = Field(None, max_length=20)
    latitude: float = Field(..., ge=-90.0, le=90.0)
    longitude: float = Field(..., ge=-180.0, le=180.0)

    # Venue access information
    venue_type: str = Field(..., description="public, private_club, recreation_center, school, hotel")
    requires_reservation: bool = False
    requires_membership: bool = False
    hourly_rate: Optional[float] = Field(None, ge=0.0, description="Hourly rate (null for free courts)")
    currency: str = Field(default="USD", max_length=10)

    # Court details
    surface_type: Optional[str] = Field(None, description="hard, clay, grass, carpet")
    num_courts: int = Field(default=1, ge=1)
    has_lights: bool = False
    indoor: bool = False

    # Contact and availability
    phone: Optional[str] = Field(None, max_length=50)
    website: Optional[str] = Field(None, max_length=500)
    hours_of_operation: Optional[str] = None


class TennisCourtResponse(BaseModel):
    id: UUID
    name: str
    address: str
    city: str
    state: str
    postal_code: Optional[str]
    latitude: float
    longitude: float

    # Venue access information
    venue_type: str
    requires_reservation: bool
    requires_membership: bool
    hourly_rate: Optional[float]
    currency: str

    # Court details
    surface_type: Optional[str]
    num_courts: int
    has_lights: bool
    indoor: bool

    # Contact and availability
    phone: Optional[str]
    website: Optional[str]
    hours_of_operation: Optional[str]

    # Metadata
    created_at: datetime
    is_verified: bool
    added_by: Optional[UUID]

    # Optional distance field (populated by nearby search)
    distance_miles: Optional[float] = None

    class Config:
        from_attributes = True
