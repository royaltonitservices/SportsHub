"""
Team formation and team matches
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import and_, func
from typing import List
from uuid import UUID
from datetime import datetime
from pydantic import BaseModel

from database import get_db
from dependencies import get_current_user
from elo_service import EloService
import models

router = APIRouter(prefix="/teams", tags=["teams"])


class CreateTeamRequest(BaseModel):
    name: str
    sport: str


@router.get("/open")
async def list_open_teams(
    sport: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """List teams for a sport that others can join (not captained by current user)"""
    try:
        sport_enum = models.Sport(sport)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid sport: {sport}")

    teams = db.query(models.Team).filter(
        and_(
            models.Team.sport == sport_enum,
            models.Team.captain_id != current_user.id
        )
    ).limit(20).all()

    result = []
    for team in teams:
        member_count = db.query(func.count(models.TeamMember.user_id)).filter(
            models.TeamMember.team_id == team.id
        ).scalar() or 0
        captain = db.query(models.User).filter(models.User.id == team.captain_id).first()
        result.append({
            "id": str(team.id),
            "name": team.name,
            "sport": team.sport.value,
            "captain_id": str(team.captain_id),
            "captain_username": captain.username if captain else "Unknown",
            "rating": team.rating,
            "games_played": team.games_played,
            "wins": team.wins,
            "losses": team.losses,
            "member_count": member_count
        })

    return result


@router.post("/create")
async def create_team(
    request: CreateTeamRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Create a new team
    """
    try:
        sport = models.Sport(request.sport)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid sport: {request.sport}")
    name = request.name
    # Check if user is already captain of a team for this sport
    existing = db.query(models.Team).filter(
        and_(
            models.Team.captain_id == current_user.id,
            models.Team.sport == sport
        )
    ).first()

    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You are already captain of a team for this sport"
        )

    # Create team
    new_team = models.Team(
        name=name,
        sport=sport,
        captain_id=current_user.id
    )

    db.add(new_team)
    db.flush()

    # Add creator as first member
    member = models.TeamMember(
        team_id=new_team.id,
        user_id=current_user.id
    )

    db.add(member)
    db.commit()
    db.refresh(new_team)

    return new_team


@router.post("/{team_id}/add-member")
async def add_team_member(
    team_id: UUID,
    user_id: UUID,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Add a member to the team (captain only)
    """
    team = db.query(models.Team).filter(models.Team.id == team_id).first()

    if not team:
        raise HTTPException(status_code=404, detail="Team not found")

    if team.captain_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only team captain can add members")

    # Check team size (max 3 for 3v3)
    current_members = db.query(models.TeamMember).filter(
        models.TeamMember.team_id == team_id
    ).count()

    if current_members >= 3:
        raise HTTPException(status_code=400, detail="Team is full (max 3 members)")

    # Check if user already in team
    existing = db.query(models.TeamMember).filter(
        and_(
            models.TeamMember.team_id == team_id,
            models.TeamMember.user_id == user_id
        )
    ).first()

    if existing:
        raise HTTPException(status_code=400, detail="User already in team")

    # Add member
    member = models.TeamMember(
        team_id=team_id,
        user_id=user_id
    )

    db.add(member)
    db.commit()

    return {"message": "Member added successfully"}


@router.get("/my-teams")
async def get_my_teams(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get teams user is part of
    """
    memberships = db.query(models.TeamMember).filter(
        models.TeamMember.user_id == current_user.id
    ).all()

    team_ids = [m.team_id for m in memberships]

    teams = db.query(models.Team).filter(
        models.Team.id.in_(team_ids)
    ).all()

    return teams


@router.get("/{team_id}/members")
async def get_team_members(
    team_id: UUID,
    db: Session = Depends(get_db)
):
    """
    Get all members of a team
    """
    members = db.query(models.TeamMember).filter(
        models.TeamMember.team_id == team_id
    ).all()

    user_ids = [m.user_id for m in members]
    users = db.query(models.User).filter(models.User.id.in_(user_ids)).all()

    return users


@router.post("/challenge")
async def create_team_challenge(
    team1_id: UUID,
    team2_id: UUID,
    sport: models.Sport,
    match_type: models.MatchType,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Create a team vs team challenge
    """
    # Verify user is captain of team1
    team1 = db.query(models.Team).filter(models.Team.id == team1_id).first()
    if not team1 or team1.captain_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")

    # Verify team2 exists
    team2 = db.query(models.Team).filter(models.Team.id == team2_id).first()
    if not team2:
        raise HTTPException(status_code=404, detail="Opponent team not found")

    # Create challenge
    challenge = models.TeamChallenge(
        sport=sport,
        team1_id=team1_id,
        team2_id=team2_id,
        match_type=match_type,
        status=models.ChallengeStatus.PENDING,
        team1_rating_before=team1.rating,
        team2_rating_before=team2.rating
    )

    db.add(challenge)
    db.commit()
    db.refresh(challenge)

    return challenge


@router.post("/challenge/{challenge_id}/complete")
async def complete_team_challenge(
    challenge_id: UUID,
    winner_team_id: UUID,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Complete a team challenge and update ratings
    """
    challenge = db.query(models.TeamChallenge).filter(
        models.TeamChallenge.id == challenge_id
    ).first()

    if not challenge:
        raise HTTPException(status_code=404, detail="Challenge not found")

    # Get teams
    team1 = db.query(models.Team).filter(models.Team.id == challenge.team1_id).first()
    team2 = db.query(models.Team).filter(models.Team.id == challenge.team2_id).first()

    # Verify user is captain of one of the teams
    if current_user.id not in [team1.captain_id, team2.captain_id]:
        raise HTTPException(status_code=403, detail="Not authorized")

    # Update challenge
    challenge.winner_team_id = winner_team_id
    challenge.status = models.ChallengeStatus.COMPLETED
    challenge.completed_at = datetime.utcnow()

    # Calculate new ratings for ranked matches
    if challenge.match_type == models.MatchType.RANKED:
        if winner_team_id == team1.id:
            new_team1_rating, new_team2_rating = EloService.calculate_new_ratings(
                team1.rating, team2.rating, False, False
            )
        else:
            new_team2_rating, new_team1_rating = EloService.calculate_new_ratings(
                team2.rating, team1.rating, False, False
            )

        team1.rating = new_team1_rating
        team2.rating = new_team2_rating

        challenge.team1_rating_after = new_team1_rating
        challenge.team2_rating_after = new_team2_rating

    # Update team stats
    team1.games_played += 1
    team2.games_played += 1

    if winner_team_id == team1.id:
        team1.wins += 1
        team2.losses += 1
    else:
        team2.wins += 1
        team1.losses += 1

    db.commit()

    return {
        "message": "Team match completed",
        "team1_rating_change": new_team1_rating - team1.rating if challenge.match_type == models.MatchType.RANKED else 0,
        "team2_rating_change": new_team2_rating - team2.rating if challenge.match_type == models.MatchType.RANKED else 0
    }
