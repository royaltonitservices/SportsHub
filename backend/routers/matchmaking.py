"""
Matchmaking and Elo rating endpoints
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_
from typing import List
from uuid import UUID
from datetime import datetime

from database import get_db
from dependencies import get_current_user
from elo_service import EloService
import models
import schemas

router = APIRouter(prefix="/matchmaking", tags=["matchmaking"])


@router.post("/find-opponents", response_model=List[schemas.UserProfile])
async def find_opponents(
    request: schemas.MatchmakingRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Find potential opponents for matchmaking based on Elo rating
    """
    # Get current user's sport profile
    user_profile = db.query(models.SportProfile).filter(
        and_(
            models.SportProfile.user_id == current_user.id,
            models.SportProfile.sport == request.sport
        )
    ).first()

    if not user_profile:
        # Create profile if it doesn't exist
        user_profile = models.SportProfile(
            user_id=current_user.id,
            sport=request.sport
        )
        db.add(user_profile)
        db.commit()
        db.refresh(user_profile)

    # Calculate matchmaking range
    min_rating, max_rating = EloService.find_matchmaking_range(
        user_profile.rating,
        user_profile.is_provisional
    )

    # Get blocked users
    blocked_user_ids = db.query(models.BlockedUser.blocked_id).filter(
        models.BlockedUser.blocker_id == current_user.id
    ).all()
    blocked_ids = [b[0] for b in blocked_user_ids]

    # Get users who blocked current user
    blockers = db.query(models.BlockedUser.blocker_id).filter(
        models.BlockedUser.blocked_id == current_user.id
    ).all()
    blocker_ids = [b[0] for b in blockers]

    # Combine all blocked IDs
    all_blocked = blocked_ids + blocker_ids

    # Find potential opponents
    query = db.query(models.SportProfile).filter(
        and_(
            models.SportProfile.sport == request.sport,
            models.SportProfile.rating >= min_rating,
            models.SportProfile.rating <= max_rating,
            models.SportProfile.user_id != current_user.id
        )
    )

    # Add blocked users filter if there are any
    if all_blocked:
        query = query.filter(~models.SportProfile.user_id.in_(all_blocked))

    # Phase 4: Apply trust-based filtering
    # Exclude restricted users from general matchmaking
    query = query.filter(models.SportProfile.trust_tier != "restricted")

    # Deprioritize high-risk users (caution tier)
    # Get all potential profiles first, then sort by trust tier
    all_potential_profiles = query.limit(40).all()

    # Sort profiles: trusted first, then standard, then caution (limited)
    def trust_priority(profile):
        tier_priority = {
            "trusted": 0,
            "standard": 1,
            "caution": 2
        }
        return (
            tier_priority.get(profile.trust_tier, 1),
            -profile.rating  # Within tier, prioritize by rating
        )

    sorted_profiles = sorted(all_potential_profiles, key=trust_priority)
    potential_profiles = sorted_profiles[:20]  # Limit to top 20 after sorting

    # Get user details
    opponent_ids = [p.user_id for p in potential_profiles]
    opponents = db.query(models.User).filter(
        models.User.id.in_(opponent_ids)
    ).all()

    return opponents


@router.post("/create-challenge", response_model=schemas.ChallengeResponse)
async def create_challenge(
    challenge_data: schemas.ChallengeCreate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Create a new challenge/match
    """
    # Check if opponent exists
    opponent = db.query(models.User).filter(
        models.User.id == challenge_data.opponent_id
    ).first()

    if not opponent:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Opponent not found"
        )

    # Check if users are blocked
    is_blocked = db.query(models.BlockedUser).filter(
        or_(
            and_(
                models.BlockedUser.blocker_id == current_user.id,
                models.BlockedUser.blocked_id == challenge_data.opponent_id
            ),
            and_(
                models.BlockedUser.blocker_id == challenge_data.opponent_id,
                models.BlockedUser.blocked_id == current_user.id
            )
        )
    ).first()

    if is_blocked:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot challenge this user"
        )

    # Create challenge
    new_challenge = models.Challenge(
        sport=challenge_data.sport,
        match_type=challenge_data.match_type,
        challenger_id=current_user.id,
        opponent_id=challenge_data.opponent_id,
        status=models.ChallengeStatus.PENDING
    )

    db.add(new_challenge)
    db.commit()
    db.refresh(new_challenge)

    return new_challenge


@router.post("/accept-challenge/{challenge_id}")
async def accept_challenge(
    challenge_id: UUID,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Accept a pending challenge
    """
    challenge = db.query(models.Challenge).filter(
        models.Challenge.id == challenge_id
    ).first()

    if not challenge:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Challenge not found"
        )

    if challenge.opponent_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to accept this challenge"
        )

    if challenge.status != models.ChallengeStatus.PENDING:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Challenge is not pending"
        )

    challenge.status = models.ChallengeStatus.ACCEPTED
    db.commit()

    return {"message": "Challenge accepted", "challenge_id": challenge_id}


@router.post("/submit-result")
async def submit_match_result(
    result: schemas.SubmitMatchResult,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Submit match result with enhanced validation and dispute detection (Phase 3)

    Flow:
    1. First player submits result
    2. Second player submits result
    3. If results match → process match completion
    4. If results DON'T match → create dispute, flag high-dispute users
    """
    challenge = db.query(models.Challenge).filter(
        models.Challenge.id == result.challenge_id
    ).first()

    if not challenge:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Challenge not found"
        )

    # Verify user is part of the match
    if current_user.id not in [challenge.challenger_id, challenge.opponent_id]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to submit result for this match"
        )

    # Verify match is accepted
    if challenge.status != models.ChallengeStatus.ACCEPTED:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Match must be accepted before submitting results"
        )

    # Store individual submission with timestamp
    is_challenger = current_user.id == challenge.challenger_id

    if is_challenger:
        challenge.challenger_submitted_score = result.score_data
        challenge.challenger_submitted_at = datetime.utcnow()
    else:
        challenge.opponent_submitted_score = result.score_data
        challenge.opponent_submitted_at = datetime.utcnow()

    # Check if both players have submitted
    both_submitted = (challenge.challenger_submitted_score is not None and
                     challenge.opponent_submitted_score is not None)

    if not both_submitted:
        # First submission - just store and wait
        db.commit()
        return {
            "message": "Result submitted, waiting for opponent confirmation",
            "status": "waiting"
        }

    # Both submitted - check if they match
    scores_match = (challenge.challenger_submitted_score == challenge.opponent_submitted_score)

    if not scores_match:
        # MISMATCH DETECTED - Create dispute
        challenge.status = models.ChallengeStatus.DISPUTED

        # Create dispute record
        dispute = models.Dispute(
            challenge_id=challenge.id,
            initiator_id=current_user.id,  # Last submitter triggered the dispute
            reason="Score mismatch: Challenger submitted '{}', Opponent submitted '{}'".format(
                challenge.challenger_submitted_score or "N/A",
                challenge.opponent_submitted_score or "N/A"
            ),
            status=models.DisputeStatus.PENDING
        )
        db.add(dispute)

        # Get sport profiles for trust tracking
        challenger_profile = db.query(models.SportProfile).filter(
            and_(
                models.SportProfile.user_id == challenge.challenger_id,
                models.SportProfile.sport == challenge.sport
            )
        ).first()

        opponent_profile = db.query(models.SportProfile).filter(
            and_(
                models.SportProfile.user_id == challenge.opponent_id,
                models.SportProfile.sport == challenge.sport
            )
        ).first()

        # Increment dispute counters
        challenger_profile.matches_disputed += 1
        opponent_profile.matches_disputed += 1

        # Calculate and update trust scores
        challenger_profile.trust_score = max(0, challenger_profile.trust_score - 5.0)
        opponent_profile.trust_score = max(0, opponent_profile.trust_score - 5.0)

        # Flag users with high dispute rates (>30%)
        DISPUTE_THRESHOLD = 30.0

        if challenger_profile.dispute_rate > DISPUTE_THRESHOLD and not challenger_profile.is_flagged:
            challenger_profile.is_flagged = True
            challenger_profile.flagged_reason = f"High dispute rate: {challenger_profile.dispute_rate:.1f}%"
            challenger_profile.flagged_at = datetime.utcnow()

        if opponent_profile.dispute_rate > DISPUTE_THRESHOLD and not opponent_profile.is_flagged:
            opponent_profile.is_flagged = True
            opponent_profile.flagged_reason = f"High dispute rate: {opponent_profile.dispute_rate:.1f}%"
            opponent_profile.flagged_at = datetime.utcnow()

        db.commit()

        return {
            "message": "Results don't match - dispute created",
            "status": "disputed",
            "dispute_id": str(dispute.id),
            "challenger_submitted": challenge.challenger_submitted_score,
            "opponent_submitted": challenge.opponent_submitted_score
        }

    # RESULTS MATCH - Process completion
    # Store result for both players
    challenge.winner_id = result.winner_id
    challenge.score_data = result.score_data
    challenge.challenger_confirmed = True
    challenge.opponent_confirmed = True

    # If both players confirmed, process the match
    if challenge.challenger_confirmed and challenge.opponent_confirmed:
        # Get sport profiles
        challenger_profile = db.query(models.SportProfile).filter(
            and_(
                models.SportProfile.user_id == challenge.challenger_id,
                models.SportProfile.sport == challenge.sport
            )
        ).first()

        opponent_profile = db.query(models.SportProfile).filter(
            and_(
                models.SportProfile.user_id == challenge.opponent_id,
                models.SportProfile.sport == challenge.sport
            )
        ).first()

        # Store ratings before match
        challenge.challenger_rating_before = challenger_profile.rating
        challenge.opponent_rating_before = opponent_profile.rating

        # Calculate new ratings (for ranked matches)
        if challenge.match_type == models.MatchType.RANKED:
            if challenge.winner_id == challenge.challenger_id:
                new_challenger_rating, new_opponent_rating = EloService.calculate_new_ratings(
                    challenger_profile.rating,
                    opponent_profile.rating,
                    challenger_profile.is_provisional,
                    opponent_profile.is_provisional,
                    challenge.impact_weight
                )
            else:
                new_opponent_rating, new_challenger_rating = EloService.calculate_new_ratings(
                    opponent_profile.rating,
                    challenger_profile.rating,
                    opponent_profile.is_provisional,
                    challenger_profile.is_provisional,
                    challenge.impact_weight
                )

            # Update ratings
            challenger_profile.rating = new_challenger_rating
            opponent_profile.rating = new_opponent_rating

            # Store ratings after match
            challenge.challenger_rating_after = new_challenger_rating
            challenge.opponent_rating_after = new_opponent_rating

            # Update rank tiers
            challenger_profile.rank_tier = EloService.calculate_rank_tier(new_challenger_rating)
            opponent_profile.rank_tier = EloService.calculate_rank_tier(new_opponent_rating)

            # Update provisional status
            challenger_profile.provisional_games += 1
            opponent_profile.provisional_games += 1

            if challenger_profile.provisional_games >= EloService.PROVISIONAL_GAMES_THRESHOLD:
                challenger_profile.is_provisional = False

            if opponent_profile.provisional_games >= EloService.PROVISIONAL_GAMES_THRESHOLD:
                opponent_profile.is_provisional = False

            # Update ranked games count
            challenger_profile.ranked_games_played += 1
            opponent_profile.ranked_games_played += 1

        # Update match statistics
        challenger_profile.games_played += 1
        opponent_profile.games_played += 1

        if challenge.winner_id == challenge.challenger_id:
            challenger_profile.wins += 1
            opponent_profile.losses += 1
            challenger_profile.current_streak += 1
            opponent_profile.current_streak = 0
        else:
            opponent_profile.wins += 1
            challenger_profile.losses += 1
            opponent_profile.current_streak += 1
            challenger_profile.current_streak = 0

        # Update best streaks
        if challenger_profile.current_streak > challenger_profile.best_streak:
            challenger_profile.best_streak = challenger_profile.current_streak

        if opponent_profile.current_streak > opponent_profile.best_streak:
            opponent_profile.best_streak = opponent_profile.current_streak

        # Update last played
        challenger_profile.last_played = datetime.utcnow()
        opponent_profile.last_played = datetime.utcnow()

        # Update trust tracking (Phase 3)
        challenger_profile.matches_completed += 1
        opponent_profile.matches_completed += 1

        # Reward trust for successful completion (small boost)
        challenger_profile.trust_score = min(100.0, challenger_profile.trust_score + 0.5)
        opponent_profile.trust_score = min(100.0, opponent_profile.trust_score + 0.5)

        # Mark challenge as completed
        challenge.status = models.ChallengeStatus.COMPLETED
        challenge.completed_at = datetime.utcnow()

        db.commit()

        return {
            "message": "Match completed and ratings updated",
            "status": "completed",
            "challenger_rating_change": challenge.challenger_rating_after - challenge.challenger_rating_before if challenge.match_type == models.MatchType.RANKED else 0,
            "opponent_rating_change": challenge.opponent_rating_after - challenge.opponent_rating_before if challenge.match_type == models.MatchType.RANKED else 0,
            "trust_updated": True
        }

    # Should not reach here
    db.commit()
    return {"message": "Result submitted, waiting for opponent confirmation", "status": "waiting"}


@router.get("/leaderboard/{sport}", response_model=List[schemas.LeaderboardEntry])
async def get_leaderboard(
    sport: models.Sport,
    limit: int = 100,
    db: Session = Depends(get_db)
):
    """
    Get leaderboard for a specific sport
    """
    profiles = db.query(models.SportProfile).filter(
        and_(
            models.SportProfile.sport == sport,
            models.SportProfile.ranked_games_played >= 5  # Minimum games for leaderboard
        )
    ).order_by(models.SportProfile.rating.desc()).limit(limit).all()

    # Get user details
    user_ids = [p.user_id for p in profiles]
    users = db.query(models.User).filter(models.User.id.in_(user_ids)).all()
    user_dict = {u.id: u for u in users}

    # Build leaderboard entries
    leaderboard = []
    for profile in profiles:
        user = user_dict.get(profile.user_id)
        if user:
            win_rate = (profile.wins / profile.games_played * 100) if profile.games_played > 0 else 0
            leaderboard.append(schemas.LeaderboardEntry(
                user_id=user.id,
                username=user.username,
                display_name=user.display_name,
                rating=profile.rating,
                rank_tier=profile.rank_tier,
                games_played=profile.games_played,
                wins=profile.wins,
                losses=profile.losses,
                win_rate=round(win_rate, 1)
            ))

    return leaderboard


@router.get("/my-challenges", response_model=List[schemas.ChallengeResponse])
async def get_my_challenges(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get all challenges for current user
    """
    challenges = db.query(models.Challenge).filter(
        or_(
            models.Challenge.challenger_id == current_user.id,
            models.Challenge.opponent_id == current_user.id
        )
    ).order_by(models.Challenge.created_at.desc()).all()

    return challenges
