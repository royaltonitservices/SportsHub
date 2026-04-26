# Three Leaderboards System
# Premium Enhancement - Ranked, Challenges, Tournaments

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func, desc
from typing import List, Optional
from pydantic import BaseModel
from uuid import UUID

from database import get_db
from dependencies import get_current_active_user
import models
from models_premium import Tournament, TournamentParticipant

router = APIRouter(prefix="/leaderboards", tags=["leaderboards"])


# MARK: - Schemas

class RankedLeaderboardEntry(BaseModel):
    rank: int
    user_id: str
    username: str
    elo_rating: int
    wins: int
    losses: int
    win_rate: float
    streak: int

    class Config:
        from_attributes = True


class ChallengesLeaderboardEntry(BaseModel):
    rank: int
    user_id: str
    username: str
    total_wins: int
    total_matches: int
    win_rate: float
    sports_played: int

    class Config:
        from_attributes = True


class TournamentsLeaderboardEntry(BaseModel):
    rank: int
    user_id: str
    username: str
    tournaments_won: int
    total_tournaments: int
    avg_placement: float
    best_placement: int

    class Config:
        from_attributes = True


# MARK: - Ranked Leaderboard (ELO-based)

@router.get("/ranked/{sport}", response_model=List[RankedLeaderboardEntry])
async def get_ranked_leaderboard(
    sport: str,
    limit: int = 100,
    offset: int = 0,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Ranked Leaderboard - Sorted by ELO rating.

    Only includes users who completed placement matches (not provisional).
    Premium feature.
    """
    sport_enum = models.Sport(sport)

    # Get top players by ELO
    profiles = db.query(models.SportProfile).filter(
        models.SportProfile.sport == sport_enum,
        models.SportProfile.is_provisional == False
    ).order_by(desc(models.SportProfile.rating)).offset(offset).limit(limit).all()

    leaderboard = []
    for rank, profile in enumerate(profiles, start=offset + 1):
        user = db.query(models.User).filter(models.User.id == profile.user_id).first()

        if not user:
            continue

        # Calculate stats
        wins = db.query(models.Match).filter(
            models.Match.sport == sport_enum,
            models.Match.winner_id == profile.user_id,
            models.Match.status == "completed"
        ).count()

        total_matches = db.query(models.Match).filter(
            models.Match.sport == sport_enum,
            models.Match.status == "completed"
        ).filter(
            (models.Match.player1_id == profile.user_id) |
            (models.Match.player2_id == profile.user_id)
        ).count()

        losses = total_matches - wins
        win_rate = (wins / total_matches * 100) if total_matches > 0 else 0

        # Calculate streak
        streak = calculate_win_streak(profile.user_id, sport_enum, db)

        leaderboard.append(RankedLeaderboardEntry(
            rank=rank,
            user_id=str(user.id),
            username=user.username,
            elo_rating=profile.rating,
            wins=wins,
            losses=losses,
            win_rate=round(win_rate, 1),
            streak=streak
        ))

    return leaderboard


@router.get("/ranked/{sport}/my-rank")
async def get_my_ranked_position(
    sport: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get current user's rank in ranked leaderboard"""
    sport_enum = models.Sport(sport)

    profile = db.query(models.SportProfile).filter(
        models.SportProfile.user_id == current_user.id,
        models.SportProfile.sport == sport_enum
    ).first()

    if not profile or profile.is_provisional:
        return {
            "rank": None,
            "message": "Complete placement matches to get ranked"
        }

    # Count users with higher ELO
    higher_ranked = db.query(models.SportProfile).filter(
        models.SportProfile.sport == sport_enum,
        models.SportProfile.is_provisional == False,
        models.SportProfile.rating > profile.rating
    ).count()

    rank = higher_ranked + 1

    return {
        "rank": rank,
        "elo_rating": profile.rating,
        "sport": sport
    }


# MARK: - Challenges Leaderboard (Total Wins)

@router.get("/challenges", response_model=List[ChallengesLeaderboardEntry])
async def get_challenges_leaderboard(
    limit: int = 100,
    offset: int = 0,
    sport: Optional[str] = None,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Challenges Leaderboard - Sorted by total wins across all sports.

    Includes all match types: ranked, casual, challenges.
    Premium feature.
    """
    # Aggregate wins per user
    query = db.query(
        models.Match.winner_id.label('user_id'),
        func.count(models.Match.id).label('total_wins')
    ).filter(
        models.Match.status == "completed",
        models.Match.winner_id != None
    )

    if sport:
        query = query.filter(models.Match.sport == models.Sport(sport))

    wins_subquery = query.group_by(models.Match.winner_id).subquery()

    # Get total matches per user
    matches_query = db.query(
        models.User.id.label('user_id'),
        func.count(models.Match.id).label('total_matches')
    ).join(
        models.Match,
        (models.Match.player1_id == models.User.id) | (models.Match.player2_id == models.User.id)
    ).filter(
        models.Match.status == "completed"
    )

    if sport:
        matches_query = matches_query.filter(models.Match.sport == models.Sport(sport))

    matches_subquery = matches_query.group_by(models.User.id).subquery()

    # Join and sort
    leaderboard_query = db.query(
        models.User.id,
        models.User.username,
        wins_subquery.c.total_wins,
        matches_subquery.c.total_matches
    ).outerjoin(
        wins_subquery,
        models.User.id == wins_subquery.c.user_id
    ).outerjoin(
        matches_subquery,
        models.User.id == matches_subquery.c.user_id
    ).filter(
        wins_subquery.c.total_wins != None
    ).order_by(
        desc(wins_subquery.c.total_wins)
    ).offset(offset).limit(limit).all()

    leaderboard = []
    for rank, (user_id, username, total_wins, total_matches) in enumerate(leaderboard_query, start=offset + 1):
        # Count sports played
        sports_played = db.query(models.SportProfile).filter(
            models.SportProfile.user_id == user_id
        ).count()

        win_rate = (total_wins / total_matches * 100) if total_matches else 0

        leaderboard.append(ChallengesLeaderboardEntry(
            rank=rank,
            user_id=str(user_id),
            username=username,
            total_wins=total_wins or 0,
            total_matches=total_matches or 0,
            win_rate=round(win_rate, 1),
            sports_played=sports_played
        ))

    return leaderboard


# MARK: - Tournaments Leaderboard (Placements)

@router.get("/tournaments", response_model=List[TournamentsLeaderboardEntry])
async def get_tournaments_leaderboard(
    limit: int = 100,
    offset: int = 0,
    sport: Optional[str] = None,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Tournaments Leaderboard - Sorted by tournament wins and placements.

    Premium feature.
    """
    # Get all participants with their placements
    query = db.query(
        TournamentParticipant.user_id,
        func.count(TournamentParticipant.id).label('total_tournaments'),
        func.count(
            TournamentParticipant.id
        ).filter(TournamentParticipant.placement == 1).label('tournaments_won'),
        func.avg(TournamentParticipant.placement).label('avg_placement'),
        func.min(TournamentParticipant.placement).label('best_placement')
    ).filter(
        TournamentParticipant.user_id != None,
        TournamentParticipant.placement != None
    )

    if sport:
        query = query.join(Tournament).filter(Tournament.sport == models.Sport(sport))

    participants_data = query.group_by(TournamentParticipant.user_id).all()

    # Sort by tournaments won, then by average placement
    sorted_data = sorted(
        participants_data,
        key=lambda x: (-x.tournaments_won, x.avg_placement if x.avg_placement else 999)
    )

    leaderboard = []
    for rank, data in enumerate(sorted_data[offset:offset + limit], start=offset + 1):
        user = db.query(models.User).filter(models.User.id == data.user_id).first()

        if not user:
            continue

        leaderboard.append(TournamentsLeaderboardEntry(
            rank=rank,
            user_id=str(user.id),
            username=user.username,
            tournaments_won=data.tournaments_won or 0,
            total_tournaments=data.total_tournaments or 0,
            avg_placement=round(data.avg_placement, 1) if data.avg_placement else 0,
            best_placement=data.best_placement or 0
        ))

    return leaderboard


# MARK: - Helper Functions

def calculate_win_streak(user_id: UUID, sport: models.Sport, db: Session) -> int:
    """Calculate current win streak"""
    recent_matches = db.query(models.Match).filter(
        models.Match.sport == sport,
        models.Match.status == "completed"
    ).filter(
        (models.Match.player1_id == user_id) | (models.Match.player2_id == user_id)
    ).order_by(desc(models.Match.created_at)).limit(20).all()

    streak = 0
    for match in recent_matches:
        if match.winner_id == user_id:
            streak += 1
        else:
            break

    return streak
