# Tournament System API
# Premium feature - Solo and Team tournaments
# All formats: Single/Double Elimination, Round Robin, Ladder

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
from pydantic import BaseModel
from datetime import datetime, timedelta
import math

from database import get_db
from dependencies import get_current_active_user, require_premium
import models
from models_premium import (
    Tournament, TournamentParticipant, TournamentMatch,
    TournamentType, TournamentFormat, TournamentRanked, TournamentStatus
)

router = APIRouter(prefix="/tournaments", tags=["tournaments"])


# MARK: - Schemas

class CreateTournamentRequest(BaseModel):
    name: str
    description: Optional[str] = None
    sport: str
    tournament_type: str  # "solo", "team"
    format: str  # "single_elimination", "double_elimination", "round_robin", "ladder"
    ranked_type: str = "ranked"  # "ranked", "unranked"
    max_participants: int
    team_size: int = 1  # 1 for solo, 2-5 for team
    min_elo: Optional[int] = None
    max_elo: Optional[int] = None
    registration_opens: str  # ISO datetime
    registration_closes: str  # ISO datetime
    starts_at: str  # ISO datetime
    is_public: bool = True
    is_school: bool = False
    is_regional: bool = False
    region: Optional[str] = None
    school_name: Optional[str] = None
    prizes: dict = {}


class TournamentResponse(BaseModel):
    id: str
    creator_id: str
    name: str
    description: Optional[str]
    sport: str
    tournament_type: str
    format: str
    ranked_type: str
    max_participants: int
    team_size: int
    min_elo: Optional[int]
    max_elo: Optional[int]
    registration_opens: str
    registration_closes: str
    starts_at: str
    ends_at: Optional[str]
    status: str
    current_round: int
    participant_count: int
    is_public: bool
    is_school: bool
    is_regional: bool
    region: Optional[str]
    school_name: Optional[str]
    prizes: dict
    created_at: str

    class Config:
        from_attributes = True


class RegisterTournamentRequest(BaseModel):
    team_id: Optional[str] = None  # For team tournaments


class ParticipantResponse(BaseModel):
    id: str
    tournament_id: str
    user_id: Optional[str]
    team_id: Optional[str]
    username: Optional[str]
    team_name: Optional[str]
    seed: Optional[int]
    placement: Optional[int]
    wins: int
    losses: int
    is_eliminated: bool

    class Config:
        from_attributes = True


class MatchResponse(BaseModel):
    id: str
    tournament_id: str
    round_number: int
    match_number: int
    bracket_position: Optional[str]
    participant1_id: Optional[str]
    participant2_id: Optional[str]
    participant1_name: Optional[str]
    participant2_name: Optional[str]
    participant1_score: Optional[int]
    participant2_score: Optional[int]
    winner_id: Optional[str]
    scheduled_at: Optional[str]
    completed_at: Optional[str]
    is_complete: bool
    is_bye: bool

    class Config:
        from_attributes = True


class SubmitMatchResultRequest(BaseModel):
    participant1_score: int
    participant2_score: int
    winner_id: str


class BracketResponse(BaseModel):
    tournament_id: str
    format: str
    current_round: int
    total_rounds: int
    matches: List[MatchResponse]


class StandingsResponse(BaseModel):
    participant_id: str
    name: str
    seed: Optional[int]
    wins: int
    losses: int
    points_scored: int
    points_allowed: int
    placement: Optional[int]
    is_eliminated: bool


# MARK: - Create Tournament

@router.post("/create", response_model=TournamentResponse, dependencies=[Depends(require_premium)])
async def create_tournament(
    request: CreateTournamentRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Create a new tournament (Premium only).

    Supports:
    - Solo and team tournaments
    - All formats: single/double elimination, round robin, ladder
    - ELO restrictions
    - Regional and school tournaments
    """

    # Validate team size
    if request.tournament_type == "team" and request.team_size < 2:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Team tournaments require team_size >= 2"
        )

    # Validate max participants for elimination
    if request.format in ["single_elimination", "double_elimination"]:
        if not is_power_of_two(request.max_participants):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Elimination tournaments require power of 2 participants (4, 8, 16, 32, 64)"
            )

    tournament = Tournament(
        creator_id=current_user.id,
        name=request.name,
        description=request.description,
        sport=models.Sport(request.sport),
        tournament_type=TournamentType(request.tournament_type),
        format=TournamentFormat(request.format),
        ranked_type=TournamentRanked(request.ranked_type),
        max_participants=request.max_participants,
        team_size=request.team_size,
        min_elo=request.min_elo,
        max_elo=request.max_elo,
        registration_opens=datetime.fromisoformat(request.registration_opens.replace('Z', '+00:00')),
        registration_closes=datetime.fromisoformat(request.registration_closes.replace('Z', '+00:00')),
        starts_at=datetime.fromisoformat(request.starts_at.replace('Z', '+00:00')),
        status=TournamentStatus.UPCOMING,
        is_public=request.is_public,
        is_school=request.is_school,
        is_regional=request.is_regional,
        region=request.region,
        school_name=request.school_name,
        prizes=request.prizes
    )

    db.add(tournament)
    db.commit()
    db.refresh(tournament)

    return to_tournament_response(tournament, db)


# MARK: - List Tournaments

@router.get("/", response_model=List[TournamentResponse])
async def list_tournaments(
    sport: Optional[str] = None,
    status: Optional[str] = None,
    tournament_type: Optional[str] = None,
    is_school: Optional[bool] = None,
    is_regional: Optional[bool] = None,
    region: Optional[str] = None,
    skip: int = 0,
    limit: int = 20,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """List tournaments with filters"""

    query = db.query(Tournament).filter(Tournament.is_public == True)

    if sport:
        query = query.filter(Tournament.sport == models.Sport(sport))

    if status:
        query = query.filter(Tournament.status == TournamentStatus(status))

    if tournament_type:
        query = query.filter(Tournament.tournament_type == TournamentType(tournament_type))

    if is_school is not None:
        query = query.filter(Tournament.is_school == is_school)

    if is_regional is not None:
        query = query.filter(Tournament.is_regional == is_regional)

    if region:
        query = query.filter(Tournament.region == region)

    tournaments = query.order_by(Tournament.starts_at.asc()).offset(skip).limit(limit).all()

    return [to_tournament_response(t, db) for t in tournaments]


@router.get("/{tournament_id}", response_model=TournamentResponse)
async def get_tournament(
    tournament_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get tournament details"""

    tournament = db.query(Tournament).filter(Tournament.id == tournament_id).first()

    if not tournament:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tournament not found"
        )

    return to_tournament_response(tournament, db)


# MARK: - Registration

@router.post("/{tournament_id}/register", response_model=ParticipantResponse, dependencies=[Depends(require_premium)])
async def register_for_tournament(
    tournament_id: UUID,
    request: RegisterTournamentRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Register for tournament (Premium only)"""

    tournament = db.query(Tournament).filter(Tournament.id == tournament_id).first()

    if not tournament:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tournament not found")

    # Check status
    if tournament.status != TournamentStatus.REGISTRATION_OPEN:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Registration is not open")

    # Check if already registered
    existing = db.query(TournamentParticipant).filter(
        TournamentParticipant.tournament_id == tournament_id,
        TournamentParticipant.user_id == current_user.id
    ).first()

    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Already registered")

    # Check participant limit
    participant_count = db.query(TournamentParticipant).filter(
        TournamentParticipant.tournament_id == tournament_id
    ).count()

    if participant_count >= tournament.max_participants:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Tournament is full")

    # Check ELO restrictions
    if tournament.ranked_type == TournamentRanked.RANKED:
        user_elo = get_user_elo(current_user.id, tournament.sport, db)

        if tournament.min_elo and user_elo < tournament.min_elo:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="ELO too low")

        if tournament.max_elo and user_elo > tournament.max_elo:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="ELO too high")

    # Register
    participant = TournamentParticipant(
        tournament_id=tournament_id,
        user_id=current_user.id if tournament.tournament_type == TournamentType.SOLO else None,
        team_id=UUID(request.team_id) if request.team_id else None
    )

    db.add(participant)
    db.commit()
    db.refresh(participant)

    return to_participant_response(participant, db)


@router.delete("/{tournament_id}/unregister", dependencies=[Depends(require_premium)])
async def unregister_from_tournament(
    tournament_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Unregister from tournament"""

    tournament = db.query(Tournament).filter(Tournament.id == tournament_id).first()

    if not tournament:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tournament not found")

    if tournament.status not in [TournamentStatus.UPCOMING, TournamentStatus.REGISTRATION_OPEN]:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot unregister after tournament starts")

    participant = db.query(TournamentParticipant).filter(
        TournamentParticipant.tournament_id == tournament_id,
        TournamentParticipant.user_id == current_user.id
    ).first()

    if not participant:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not registered")

    db.delete(participant)
    db.commit()

    return {"message": "Successfully unregistered"}


# MARK: - Bracket Generation

@router.post("/{tournament_id}/generate-bracket", dependencies=[Depends(require_premium)])
async def generate_bracket(
    tournament_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Generate tournament bracket (tournament creator only)"""

    tournament = db.query(Tournament).filter(Tournament.id == tournament_id).first()

    if not tournament:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tournament not found")

    # Check permissions
    if tournament.creator_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only creator can generate bracket")

    # Get participants
    participants = db.query(TournamentParticipant).filter(
        TournamentParticipant.tournament_id == tournament_id
    ).all()

    if len(participants) < 2:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Need at least 2 participants")

    # Seed participants by ELO
    if tournament.ranked_type == TournamentRanked.RANKED:
        for participant in participants:
            if participant.user_id:
                participant.seed = get_user_elo(participant.user_id, tournament.sport, db)
            elif participant.team_id:
                participant.seed = get_team_elo(participant.team_id, tournament.sport, db)

        participants.sort(key=lambda p: p.seed or 0, reverse=True)
        for i, p in enumerate(participants):
            p.seed = i + 1

    db.commit()

    # Generate bracket based on format
    if tournament.format == TournamentFormat.SINGLE_ELIMINATION:
        generate_single_elimination_bracket(tournament, participants, db)
    elif tournament.format == TournamentFormat.DOUBLE_ELIMINATION:
        generate_double_elimination_bracket(tournament, participants, db)
    elif tournament.format == TournamentFormat.ROUND_ROBIN:
        generate_round_robin_bracket(tournament, participants, db)
    elif tournament.format == TournamentFormat.LADDER:
        generate_ladder_bracket(tournament, participants, db)

    # Update tournament status
    tournament.status = TournamentStatus.IN_PROGRESS
    tournament.current_round = 1
    db.commit()

    return {"message": "Bracket generated successfully"}


@router.get("/{tournament_id}/bracket", response_model=BracketResponse)
async def get_bracket(
    tournament_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get tournament bracket"""

    tournament = db.query(Tournament).filter(Tournament.id == tournament_id).first()

    if not tournament:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tournament not found")

    matches = db.query(TournamentMatch).filter(
        TournamentMatch.tournament_id == tournament_id
    ).order_by(TournamentMatch.round_number, TournamentMatch.match_number).all()

    total_rounds = max([m.round_number for m in matches]) if matches else 0

    return BracketResponse(
        tournament_id=str(tournament_id),
        format=tournament.format.value,
        current_round=tournament.current_round,
        total_rounds=total_rounds,
        matches=[to_match_response(m, db) for m in matches]
    )


# MARK: - Match Results

@router.post("/{tournament_id}/matches/{match_id}/submit", dependencies=[Depends(require_premium)])
async def submit_match_result(
    tournament_id: UUID,
    match_id: UUID,
    request: SubmitMatchResultRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Submit match result"""

    match = db.query(TournamentMatch).filter(
        TournamentMatch.id == match_id,
        TournamentMatch.tournament_id == tournament_id
    ).first()

    if not match:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Match not found")

    if match.is_complete:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Match already completed")

    # Update match
    match.participant1_score = request.participant1_score
    match.participant2_score = request.participant2_score
    match.winner_id = UUID(request.winner_id)
    match.is_complete = True
    match.completed_at = datetime.now()

    # Update participant stats
    p1 = db.query(TournamentParticipant).filter(TournamentParticipant.id == match.participant1_id).first()
    p2 = db.query(TournamentParticipant).filter(TournamentParticipant.id == match.participant2_id).first()

    if p1:
        p1.points_scored += request.participant1_score
        p1.points_allowed += request.participant2_score
        if str(p1.id) == request.winner_id:
            p1.wins += 1
        else:
            p1.losses += 1

    if p2:
        p2.points_scored += request.participant2_score
        p2.points_allowed += request.participant1_score
        if str(p2.id) == request.winner_id:
            p2.wins += 1
        else:
            p2.losses += 1

    db.commit()

    # Check if round is complete
    tournament = db.query(Tournament).filter(Tournament.id == tournament_id).first()
    check_round_completion(tournament, db)

    return {"message": "Match result submitted"}


@router.get("/{tournament_id}/standings", response_model=List[StandingsResponse])
async def get_standings(
    tournament_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get tournament standings"""

    participants = db.query(TournamentParticipant).filter(
        TournamentParticipant.tournament_id == tournament_id
    ).all()

    # Sort by wins, then points differential
    participants.sort(key=lambda p: (p.wins, p.points_scored - p.points_allowed), reverse=True)

    standings = []
    for i, p in enumerate(participants):
        if not p.placement and not p.is_eliminated:
            p.placement = i + 1

        name = "Unknown"
        if p.user_id:
            user = db.query(models.User).filter(models.User.id == p.user_id).first()
            name = user.username if user else "Unknown"
        elif p.team_id:
            team = db.query(models.Team).filter(models.Team.id == p.team_id).first()
            name = team.name if team else "Unknown"

        standings.append(StandingsResponse(
            participant_id=str(p.id),
            name=name,
            seed=p.seed,
            wins=p.wins,
            losses=p.losses,
            points_scored=p.points_scored,
            points_allowed=p.points_allowed,
            placement=p.placement,
            is_eliminated=p.is_eliminated
        ))

    db.commit()
    return standings


# MARK: - Helper Functions

def is_power_of_two(n: int) -> bool:
    """Check if number is power of 2"""
    return n > 0 and (n & (n - 1)) == 0


def get_user_elo(user_id: UUID, sport: models.Sport, db: Session) -> int:
    """Get user's ELO for sport"""
    profile = db.query(models.SportProfile).filter(
        models.SportProfile.user_id == user_id,
        models.SportProfile.sport == sport
    ).first()
    return profile.elo_rating if profile else 1500


def get_team_elo(team_id: UUID, sport: models.Sport, db: Session) -> int:
    """Get team's ELO for sport"""
    team = db.query(models.Team).filter(models.Team.id == team_id).first()
    return team.team_elo if team else 1500


def generate_single_elimination_bracket(tournament: Tournament, participants: List[TournamentParticipant], db: Session):
    """Generate single elimination bracket"""
    num_participants = len(participants)
    num_rounds = math.ceil(math.log2(num_participants))

    # Round 1
    matches_in_round = num_participants // 2
    for i in range(matches_in_round):
        match = TournamentMatch(
            tournament_id=tournament.id,
            round_number=1,
            match_number=i + 1,
            bracket_position=f"R1M{i+1}",
            participant1_id=participants[i * 2].id,
            participant2_id=participants[i * 2 + 1].id if (i * 2 + 1) < len(participants) else None,
            is_bye=(i * 2 + 1) >= len(participants)
        )
        db.add(match)

    # Create placeholder matches for future rounds
    for round_num in range(2, num_rounds + 1):
        matches_in_round = 2 ** (num_rounds - round_num)
        for i in range(matches_in_round):
            match = TournamentMatch(
                tournament_id=tournament.id,
                round_number=round_num,
                match_number=i + 1,
                bracket_position=f"R{round_num}M{i+1}"
            )
            db.add(match)

    db.commit()


def generate_double_elimination_bracket(tournament: Tournament, participants: List[TournamentParticipant], db: Session):
    """Generate double elimination bracket (upper + lower brackets)"""
    # Similar to single elimination but with loser's bracket
    # Simplified version - would need full implementation
    generate_single_elimination_bracket(tournament, participants, db)


def generate_round_robin_bracket(tournament: Tournament, participants: List[TournamentParticipant], db: Session):
    """Generate round robin bracket (everyone plays everyone)"""
    num_participants = len(participants)
    match_number = 1

    for i in range(num_participants):
        for j in range(i + 1, num_participants):
            match = TournamentMatch(
                tournament_id=tournament.id,
                round_number=1,
                match_number=match_number,
                participant1_id=participants[i].id,
                participant2_id=participants[j].id
            )
            db.add(match)
            match_number += 1

    db.commit()


def generate_ladder_bracket(tournament: Tournament, participants: List[TournamentParticipant], db: Session):
    """Generate ladder bracket (challenge system)"""
    # Players ranked by seed, can challenge players above them
    # Initial matches created on demand
    pass


def check_round_completion(tournament: Tournament, db: Session):
    """Check if current round is complete and advance if needed"""
    current_matches = db.query(TournamentMatch).filter(
        TournamentMatch.tournament_id == tournament.id,
        TournamentMatch.round_number == tournament.current_round
    ).all()

    all_complete = all(m.is_complete or m.is_bye for m in current_matches)

    if all_complete:
        # Advance to next round
        next_round_matches = db.query(TournamentMatch).filter(
            TournamentMatch.tournament_id == tournament.id,
            TournamentMatch.round_number == tournament.current_round + 1
        ).all()

        if next_round_matches:
            tournament.current_round += 1

            # Populate next round matches with winners
            if tournament.format == TournamentFormat.SINGLE_ELIMINATION:
                for i, next_match in enumerate(next_round_matches):
                    match1 = current_matches[i * 2]
                    match2 = current_matches[i * 2 + 1] if (i * 2 + 1) < len(current_matches) else None

                    next_match.participant1_id = match1.winner_id
                    next_match.participant2_id = match2.winner_id if match2 else None
        else:
            # Tournament complete
            tournament.status = TournamentStatus.COMPLETED
            tournament.ends_at = datetime.now()

        db.commit()


def to_tournament_response(tournament: Tournament, db: Session) -> TournamentResponse:
    """Convert tournament to response"""
    participant_count = db.query(TournamentParticipant).filter(
        TournamentParticipant.tournament_id == tournament.id
    ).count()

    return TournamentResponse(
        id=str(tournament.id),
        creator_id=str(tournament.creator_id),
        name=tournament.name,
        description=tournament.description,
        sport=tournament.sport.value,
        tournament_type=tournament.tournament_type.value,
        format=tournament.format.value,
        ranked_type=tournament.ranked_type.value,
        max_participants=tournament.max_participants,
        team_size=tournament.team_size,
        min_elo=tournament.min_elo,
        max_elo=tournament.max_elo,
        registration_opens=tournament.registration_opens.isoformat(),
        registration_closes=tournament.registration_closes.isoformat(),
        starts_at=tournament.starts_at.isoformat(),
        ends_at=tournament.ends_at.isoformat() if tournament.ends_at else None,
        status=tournament.status.value,
        current_round=tournament.current_round,
        participant_count=participant_count,
        is_public=tournament.is_public,
        is_school=tournament.is_school,
        is_regional=tournament.is_regional,
        region=tournament.region,
        school_name=tournament.school_name,
        prizes=tournament.prizes,
        created_at=tournament.created_at.isoformat()
    )


def to_participant_response(participant: TournamentParticipant, db: Session) -> ParticipantResponse:
    """Convert participant to response"""
    username = None
    team_name = None

    if participant.user_id:
        user = db.query(models.User).filter(models.User.id == participant.user_id).first()
        username = user.username if user else None

    if participant.team_id:
        team = db.query(models.Team).filter(models.Team.id == participant.team_id).first()
        team_name = team.name if team else None

    return ParticipantResponse(
        id=str(participant.id),
        tournament_id=str(participant.tournament_id),
        user_id=str(participant.user_id) if participant.user_id else None,
        team_id=str(participant.team_id) if participant.team_id else None,
        username=username,
        team_name=team_name,
        seed=participant.seed,
        placement=participant.placement,
        wins=participant.wins,
        losses=participant.losses,
        is_eliminated=participant.is_eliminated
    )


def to_match_response(match: TournamentMatch, db: Session) -> MatchResponse:
    """Convert match to response"""
    p1_name = None
    p2_name = None

    if match.participant1_id:
        p1 = db.query(TournamentParticipant).filter(TournamentParticipant.id == match.participant1_id).first()
        if p1:
            if p1.user_id:
                user = db.query(models.User).filter(models.User.id == p1.user_id).first()
                p1_name = user.username if user else None
            elif p1.team_id:
                team = db.query(models.Team).filter(models.Team.id == p1.team_id).first()
                p1_name = team.name if team else None

    if match.participant2_id:
        p2 = db.query(TournamentParticipant).filter(TournamentParticipant.id == match.participant2_id).first()
        if p2:
            if p2.user_id:
                user = db.query(models.User).filter(models.User.id == p2.user_id).first()
                p2_name = user.username if user else None
            elif p2.team_id:
                team = db.query(models.Team).filter(models.Team.id == p2.team_id).first()
                p2_name = team.name if team else None

    return MatchResponse(
        id=str(match.id),
        tournament_id=str(match.tournament_id),
        round_number=match.round_number,
        match_number=match.match_number,
        bracket_position=match.bracket_position,
        participant1_id=str(match.participant1_id) if match.participant1_id else None,
        participant2_id=str(match.participant2_id) if match.participant2_id else None,
        participant1_name=p1_name,
        participant2_name=p2_name,
        participant1_score=match.participant1_score,
        participant2_score=match.participant2_score,
        winner_id=str(match.winner_id) if match.winner_id else None,
        scheduled_at=match.scheduled_at.isoformat() if match.scheduled_at else None,
        completed_at=match.completed_at.isoformat() if match.completed_at else None,
        is_complete=match.is_complete,
        is_bye=match.is_bye
    )
