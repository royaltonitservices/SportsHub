"""
Tournament system endpoints
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
from datetime import datetime
from database import get_db
from dependencies import get_current_active_user
import models
import models_premium
import schemas

router = APIRouter(prefix="/tournaments", tags=["tournaments"])


def _get_registered_tournament_ids(db: Session, user_id, tournament_ids: list) -> set:
    """Return the set of tournament_ids the user is registered for, from a batch."""
    if not tournament_ids:
        return set()
    rows = db.query(models_premium.TournamentParticipant.tournament_id).filter(
        models_premium.TournamentParticipant.user_id == user_id,
        models_premium.TournamentParticipant.tournament_id.in_(tournament_ids),
    ).all()
    return {row.tournament_id for row in rows}


def _build_tournament_response(tournament: models_premium.Tournament, registered_ids: set) -> dict:
    """Convert a Tournament ORM object to a response dict with is_registered computed."""
    return {
        "id": tournament.id,
        "creator_id": tournament.creator_id,
        "creator_username": tournament.creator.username if tournament.creator else "unknown",
        "name": tournament.name,
        "sport": tournament.sport,
        "description": tournament.description,
        "format": tournament.format,
        "status": tournament.status,
        "max_participants": tournament.max_participants,
        "current_participants": tournament.current_participants,
        "is_premium_only": tournament.is_premium_only,
        "registration_opens": getattr(tournament, "registration_opens", None),
        "registration_closes": tournament.registration_closes,
        "start_date": tournament.start_date,
        "end_date": tournament.end_date,
        "location": tournament.location,
        "is_online": tournament.is_online,
        "entry_fee": tournament.entry_fee,
        "prize_description": tournament.prize_description,
        "created_at": tournament.created_at,
        "is_registered": tournament.id in registered_ids,
    }


@router.post("/create", response_model=schemas.TournamentResponse, status_code=status.HTTP_201_CREATED)
async def create_tournament(
    tournament_data: schemas.TournamentCreate,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Create a new tournament.

    Any user can create a tournament.
    """

    tournament = models_premium.Tournament(
        creator_id=current_user.id,
        name=tournament_data.name,
        sport=tournament_data.sport,
        description=tournament_data.description,
        format=tournament_data.format,
        max_participants=tournament_data.max_participants,
        is_premium_only=tournament_data.is_premium_only,
        start_date=tournament_data.start_date,
        registration_closes=tournament_data.registration_closes,
        location=tournament_data.location,
        is_online=tournament_data.is_online,
        entry_fee=tournament_data.entry_fee,
        prize_description=tournament_data.prize_description,
        status=models_premium.TournamentStatus.REGISTRATION_OPEN
    )

    db.add(tournament)
    db.commit()
    db.refresh(tournament)

    # Load creator relationship for response
    tournament.creator = current_user

    return _build_tournament_response(tournament, set())


@router.get("/discover", response_model=List[schemas.TournamentResponse])
async def discover_tournaments(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    sport: Optional[models.Sport] = None,
    status_filter: Optional[models_premium.TournamentStatus] = None,
    skip: int = 0,
    limit: int = 20
):
    """
    Discover available tournaments.

    All users can see tournaments.
    """

    query = db.query(models_premium.Tournament).join(
        models.User, models_premium.Tournament.creator_id == models.User.id
    ).filter(
        models_premium.Tournament.status != models_premium.TournamentStatus.CANCELLED
    )

    if sport:
        query = query.filter(models_premium.Tournament.sport == sport)

    if status_filter:
        query = query.filter(models_premium.Tournament.status == status_filter)

    tournaments = query.order_by(models_premium.Tournament.starts_at.asc()).offset(skip).limit(limit).all()

    tournament_ids = [t.id for t in tournaments]
    registered_ids = _get_registered_tournament_ids(db, current_user.id, tournament_ids)

    return [_build_tournament_response(t, registered_ids) for t in tournaments]


@router.get("/{tournament_id}", response_model=schemas.TournamentResponse)
async def get_tournament(
    tournament_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get tournament details"""

    tournament = db.query(models_premium.Tournament).join(
        models.User, models_premium.Tournament.creator_id == models.User.id
    ).filter(models_premium.Tournament.id == tournament_id).first()

    if not tournament:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tournament not found"
        )

    registered_ids = _get_registered_tournament_ids(db, current_user.id, [tournament_id])
    return _build_tournament_response(tournament, registered_ids)


@router.post("/{tournament_id}/join", status_code=status.HTTP_201_CREATED)
async def join_tournament(
    tournament_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Join a tournament.

    IMPORTANT: Non-premium users CAN join tournaments.
    This is accessible to all users.
    """

    tournament = db.query(models_premium.Tournament).filter(models_premium.Tournament.id == tournament_id).first()

    if not tournament:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tournament not found"
        )

    # Check if tournament is open for registration
    if tournament.status != models_premium.TournamentStatus.REGISTRATION_OPEN:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Tournament registration is not open"
        )

    # Check if already registered
    existing_participant = db.query(models_premium.TournamentParticipant).filter(
        models_premium.TournamentParticipant.tournament_id == tournament_id,
        models_premium.TournamentParticipant.user_id == current_user.id
    ).first()

    if existing_participant:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Already registered for this tournament"
        )

    # Check capacity
    if tournament.max_participants and tournament.current_participants >= tournament.max_participants:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Tournament is full"
        )

    # Create participant entry
    participant = models_premium.TournamentParticipant(
        tournament_id=tournament_id,
        user_id=current_user.id,
        status="registered"
    )

    tournament.current_participants += 1

    db.add(participant)
    db.commit()

    return {"message": "Successfully joined tournament", "tournament_id": str(tournament_id)}


@router.delete("/{tournament_id}/leave")
async def leave_tournament(
    tournament_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Leave a tournament (before it starts)"""

    tournament = db.query(models_premium.Tournament).filter(models_premium.Tournament.id == tournament_id).first()

    if not tournament:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tournament not found"
        )

    # Can only leave if tournament hasn't started
    if tournament.status not in [models_premium.TournamentStatus.UPCOMING, models_premium.TournamentStatus.REGISTRATION_OPEN]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot leave tournament after it has started"
        )

    participant = db.query(models_premium.TournamentParticipant).filter(
        models_premium.TournamentParticipant.tournament_id == tournament_id,
        models_premium.TournamentParticipant.user_id == current_user.id
    ).first()

    if not participant:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Not registered for this tournament"
        )

    tournament.current_participants -= 1
    db.delete(participant)
    db.commit()

    return {"message": "Successfully left tournament"}


@router.get("/{tournament_id}/participants", response_model=List[schemas.TournamentParticipantResponse])
async def get_tournament_participants(
    tournament_id: UUID,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get list of tournament participants"""

    tournament = db.query(models_premium.Tournament).filter(models_premium.Tournament.id == tournament_id).first()

    if not tournament:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tournament not found"
        )

    participants = db.query(models_premium.TournamentParticipant).join(
        models.User, models_premium.TournamentParticipant.user_id == models.User.id
    ).filter(
        models_premium.TournamentParticipant.tournament_id == tournament_id
    ).order_by(models_premium.TournamentParticipant.registered_at.asc()).all()

    return participants


@router.get("/my-tournaments", response_model=List[schemas.TournamentResponse])
async def get_my_tournaments(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get tournaments I'm participating in or created"""

    # Tournaments created by user
    created_tournaments = db.query(models_premium.Tournament).join(
        models.User, models_premium.Tournament.creator_id == models.User.id
    ).filter(
        models_premium.Tournament.creator_id == current_user.id
    ).all()

    # Tournaments user is participating in
    participant_tournament_ids = db.query(models_premium.TournamentParticipant.tournament_id).filter(
        models_premium.TournamentParticipant.user_id == current_user.id
    ).all()

    participant_tournament_ids = [str(t_id[0]) for t_id in participant_tournament_ids]

    participating_tournaments = db.query(models_premium.Tournament).join(
        models.User, models_premium.Tournament.creator_id == models.User.id
    ).filter(
        models_premium.Tournament.id.in_(participant_tournament_ids)
    ).all()

    # Combine and deduplicate
    all_tournaments = {str(t.id): t for t in created_tournaments + participating_tournaments}
    unique_tournaments = list(all_tournaments.values())

    tournament_ids = [t.id for t in unique_tournaments]
    registered_ids = _get_registered_tournament_ids(db, current_user.id, tournament_ids)

    return [_build_tournament_response(t, registered_ids) for t in unique_tournaments]
