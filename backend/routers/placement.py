# Placement Matches System
# Premium Enhancement - First 5 matches for initial rating calibration

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
from pydantic import BaseModel
from datetime import datetime

from database import get_db
from dependencies import get_current_active_user
import models

router = APIRouter(prefix="/placement", tags=["placement"])


# MARK: - Schemas

class PlacementStatusResponse(BaseModel):
    sport: str
    is_placement_complete: bool
    matches_played: int
    matches_remaining: int
    estimated_elo: Optional[int]
    placement_matches: List[dict]

    class Config:
        from_attributes = True


class PlacementMatchResult(BaseModel):
    match_id: str
    opponent_elo: int
    user_won: bool
    score_differential: int


# MARK: - Endpoints

@router.get("/{sport}/status", response_model=PlacementStatusResponse)
async def get_placement_status(
    sport: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get placement match status for a sport.

    Premium users must complete 5 placement matches before getting official ELO rating.
    """
    sport_enum = models.Sport(sport)

    # Get user's sport profile
    profile = db.query(models.SportProfile).filter(
        models.SportProfile.user_id == current_user.id,
        models.SportProfile.sport == sport_enum
    ).first()

    if not profile:
        # Create new profile
        profile = models.SportProfile(
            user_id=current_user.id,
            sport=sport_enum,
            elo_rating=1500,  # Starting ELO
            is_provisional=True
        )
        db.add(profile)
        db.commit()
        db.refresh(profile)

    # Get placement matches (first 5 matches)
    placement_matches = db.query(models.Match).filter(
        models.Match.sport == sport_enum,
        models.Match.status == "completed"
    ).filter(
        (models.Match.player1_id == current_user.id) |
        (models.Match.player2_id == current_user.id)
    ).order_by(models.Match.created_at.asc()).limit(5).all()

    matches_played = len(placement_matches)
    is_complete = matches_played >= 5

    # Calculate estimated ELO based on placement results
    estimated_elo = calculate_placement_elo(placement_matches, current_user.id, profile.elo_rating)

    # Format match history
    match_history = []
    for match in placement_matches:
        is_player1 = match.player1_id == current_user.id
        opponent_id = match.player2_id if is_player1 else match.player1_id
        opponent = db.query(models.User).filter(models.User.id == opponent_id).first()

        user_won = match.winner_id == current_user.id

        match_history.append({
            "match_id": str(match.id),
            "opponent": opponent.username if opponent else "Unknown",
            "result": "Win" if user_won else "Loss",
            "score": f"{match.player1_score}-{match.player2_score}" if is_player1 else f"{match.player2_score}-{match.player1_score}",
            "elo_change": match.player1_elo_change if is_player1 else match.player2_elo_change,
            "date": match.created_at.isoformat()
        })

    return PlacementStatusResponse(
        sport=sport,
        is_placement_complete=is_complete,
        matches_played=matches_played,
        matches_remaining=max(0, 5 - matches_played),
        estimated_elo=estimated_elo if matches_played > 0 else None,
        placement_matches=match_history
    )


@router.post("/{sport}/complete")
async def complete_placement(
    sport: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Complete placement matches and set official ELO.

    Called automatically after 5th match or manually by user.
    """
    sport_enum = models.Sport(sport)

    # Get user's sport profile
    profile = db.query(models.SportProfile).filter(
        models.SportProfile.user_id == current_user.id,
        models.SportProfile.sport == sport_enum
    ).first()

    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Sport profile not found"
        )

    # Check if already completed
    if not profile.is_provisional:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Placement already completed"
        )

    # Get placement matches
    placement_matches = db.query(models.Match).filter(
        models.Match.sport == sport_enum,
        models.Match.status == "completed"
    ).filter(
        (models.Match.player1_id == current_user.id) |
        (models.Match.player2_id == current_user.id)
    ).order_by(models.Match.created_at.asc()).limit(5).all()

    if len(placement_matches) < 5:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Need {5 - len(placement_matches)} more placement matches"
        )

    # Calculate final placement ELO
    final_elo = calculate_placement_elo(placement_matches, current_user.id, profile.elo_rating)

    # Update profile
    profile.elo_rating = final_elo
    profile.is_provisional = False

    db.commit()

    return {
        "message": "Placement completed",
        "final_elo": final_elo,
        "matches_played": len(placement_matches)
    }


# MARK: - Helper Functions

def calculate_placement_elo(matches: List[models.Match], user_id: UUID, starting_elo: int) -> int:
    """
    Calculate ELO based on placement match results.

    Uses win rate and opponent strength to estimate appropriate starting rating.
    """
    if not matches:
        return starting_elo

    wins = 0
    total_opponent_elo = 0

    for match in matches:
        is_player1 = match.player1_id == user_id

        # Count wins
        if match.winner_id == user_id:
            wins += 1

        # Get opponent ELO
        if is_player1:
            opponent_elo = match.player2_elo_before or 1500
        else:
            opponent_elo = match.player1_elo_before or 1500

        total_opponent_elo += opponent_elo

    # Calculate average opponent strength
    avg_opponent_elo = total_opponent_elo / len(matches)

    # Calculate win rate
    win_rate = wins / len(matches)

    # Estimate ELO based on performance
    # Win rate 0% vs 1500 avg → ~1200
    # Win rate 50% vs 1500 avg → ~1500
    # Win rate 100% vs 1500 avg → ~1800

    elo_adjustment = (win_rate - 0.5) * 600  # -300 to +300
    estimated_elo = int(avg_opponent_elo + elo_adjustment)

    # Clamp to reasonable range
    return max(800, min(2200, estimated_elo))
