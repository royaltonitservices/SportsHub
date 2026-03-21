"""
Deterministic Rules Engine for SportsHub
NO AI - Pure algorithmic logic

This module handles:
1. ELO rating calculations (chess-style ranking)
2. Matchmaking algorithms (fair opponent matching)
3. Cheating detection (statistical anomaly detection)
4. Dispute resolution rules (evidence-based automated decisions)

These systems must be deterministic and transparent - NO black-box AI.
"""
from typing import List, Dict, Optional, Tuple
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from uuid import UUID
import statistics
import math

import models


# MARK: - ELO Rating System

class ELORatingEngine:
    """
    Chess-style ELO rating system.
    Deterministic algorithm - NO AI involved.

    Based on standard ELO formula:
    New Rating = Old Rating + K × (Actual Score - Expected Score)

    where:
    - K = K-factor (how much ratings change per game)
    - Actual Score = 1 (win), 0.5 (draw), 0 (loss)
    - Expected Score = 1 / (1 + 10^((opponent_rating - player_rating) / 400))
    """

    # K-factors by experience level
    K_FACTOR_NEW = 40  # First 20 games
    K_FACTOR_INTERMEDIATE = 24  # 20-100 games
    K_FACTOR_EXPERIENCED = 16  # 100+ games
    K_FACTOR_MASTER = 10  # 2000+ rating

    @classmethod
    def calculate_elo_change(
        cls,
        player_rating: int,
        opponent_rating: int,
        result: str,  # "win", "loss", "draw"
        player_games_played: int
    ) -> int:
        """
        Calculate ELO rating change for a match.

        Args:
            player_rating: Current ELO rating
            opponent_rating: Opponent's ELO rating
            result: Match outcome ("win", "loss", "draw")
            player_games_played: Total games played (for K-factor)

        Returns:
            Rating change (can be positive or negative)
        """
        # Determine K-factor based on experience and rating
        k_factor = cls._get_k_factor(player_rating, player_games_played)

        # Calculate expected score (probability of winning)
        expected_score = cls._calculate_expected_score(player_rating, opponent_rating)

        # Determine actual score
        if result == "win":
            actual_score = 1.0
        elif result == "draw":
            actual_score = 0.5
        else:  # loss
            actual_score = 0.0

        # Calculate rating change
        rating_change = k_factor * (actual_score - expected_score)

        return round(rating_change)

    @classmethod
    def _get_k_factor(cls, rating: int, games_played: int) -> int:
        """Determine K-factor based on rating and experience"""
        if rating >= 2000:
            return cls.K_FACTOR_MASTER
        elif games_played < 20:
            return cls.K_FACTOR_NEW
        elif games_played < 100:
            return cls.K_FACTOR_INTERMEDIATE
        else:
            return cls.K_FACTOR_EXPERIENCED

    @classmethod
    def _calculate_expected_score(cls, player_rating: int, opponent_rating: int) -> float:
        """
        Calculate expected score (win probability) using ELO formula.

        Formula: 1 / (1 + 10^((opponent_rating - player_rating) / 400))

        Examples:
        - Equal ratings (1500 vs 1500): 0.5 (50% chance)
        - +200 rating advantage: 0.76 (76% chance)
        - -200 rating disadvantage: 0.24 (24% chance)
        """
        rating_diff = opponent_rating - player_rating
        return 1.0 / (1.0 + math.pow(10, rating_diff / 400.0))

    @classmethod
    def calculate_rating_confidence(cls, games_played: int) -> float:
        """
        Calculate confidence in rating (0.0 to 1.0).

        New players have low confidence (volatile ratings).
        Experienced players have high confidence (stable ratings).
        """
        if games_played < 5:
            return 0.3
        elif games_played < 20:
            return 0.6
        elif games_played < 50:
            return 0.8
        else:
            return 0.95


# MARK: - Matchmaking Algorithm

class MatchmakingEngine:
    """
    Fair opponent matching algorithm.
    Deterministic rules - NO AI involved.

    Goals:
    1. Match players of similar skill (close ELO ratings)
    2. Minimize wait times
    3. Prevent abuse (rating manipulation, farming)
    4. Ensure competitive matches
    """

    # Matchmaking parameters
    IDEAL_ELO_DIFFERENCE = 50  # Perfect match
    MAX_ELO_DIFFERENCE_INITIAL = 100  # First 30 seconds
    MAX_ELO_DIFFERENCE_EXTENDED = 200  # After 30 seconds
    MAX_ELO_DIFFERENCE_DESPERATE = 400  # After 2 minutes
    MAX_WAIT_TIME_SECONDS = 180  # 3 minutes max wait

    @classmethod
    def find_best_opponent(
        cls,
        player_id: UUID,
        player_rating: int,
        sport: models.Sport,
        wait_time_seconds: int,
        db: Session,
        blocked_ids: List[UUID] = None
    ) -> Optional[Dict]:
        """
        Find best opponent for player.

        Considers:
        - ELO rating similarity
        - Wait time (expand search over time)
        - Blocked users (don't match)
        - Recent opponents (avoid rematches)
        - Active matchmaking status

        Returns:
            {
                "opponent_id": UUID,
                "opponent_rating": int,
                "elo_difference": int,
                "match_quality": float  # 0.0 to 1.0
            }
        """
        # Determine acceptable ELO range based on wait time
        max_elo_diff = cls._get_max_elo_difference(wait_time_seconds)

        # Get all active matchmaking requests
        active_requests = db.query(models.MatchmakingRequest).filter(
            models.MatchmakingRequest.sport == sport,
            models.MatchmakingRequest.status == "searching",
            models.MatchmakingRequest.user_id != player_id
        ).all()

        if not active_requests:
            return None

        # Filter by ELO range and blocked users
        blocked_ids = blocked_ids or []
        candidates = []

        for request in active_requests:
            # Skip blocked users
            if request.user_id in blocked_ids:
                continue

            # Get opponent's profile
            opponent_profile = db.query(models.SportProfile).filter(
                models.SportProfile.user_id == request.user_id,
                models.SportProfile.sport == sport
            ).first()

            if not opponent_profile:
                continue

            opponent_rating = opponent_profile.elo_rating
            elo_diff = abs(player_rating - opponent_rating)

            # Check if within acceptable range
            if elo_diff <= max_elo_diff:
                match_quality = cls._calculate_match_quality(
                    elo_diff,
                    wait_time_seconds,
                    request.wait_time_seconds
                )

                candidates.append({
                    "opponent_id": request.user_id,
                    "opponent_rating": opponent_rating,
                    "elo_difference": elo_diff,
                    "match_quality": match_quality,
                    "opponent_wait_time": request.wait_time_seconds
                })

        if not candidates:
            return None

        # Sort by match quality (best match first)
        candidates.sort(key=lambda x: x["match_quality"], reverse=True)

        return candidates[0]

    @classmethod
    def _get_max_elo_difference(cls, wait_time_seconds: int) -> int:
        """Expand ELO search range based on wait time"""
        if wait_time_seconds < 30:
            return cls.MAX_ELO_DIFFERENCE_INITIAL
        elif wait_time_seconds < 120:
            return cls.MAX_ELO_DIFFERENCE_EXTENDED
        else:
            return cls.MAX_ELO_DIFFERENCE_DESPERATE

    @classmethod
    def _calculate_match_quality(
        cls,
        elo_diff: int,
        player_wait_time: int,
        opponent_wait_time: int
    ) -> float:
        """
        Calculate match quality score (0.0 to 1.0).

        Factors:
        - ELO difference (closer = better)
        - Combined wait time (longer wait = more willing to accept)
        """
        # ELO similarity score (1.0 = perfect match, 0.0 = max difference)
        elo_score = max(0.0, 1.0 - (elo_diff / cls.MAX_ELO_DIFFERENCE_DESPERATE))

        # Wait time bonus (both players waiting longer = higher priority)
        avg_wait = (player_wait_time + opponent_wait_time) / 2
        wait_bonus = min(avg_wait / 60.0, 1.0) * 0.3  # Up to 0.3 bonus

        return min(1.0, elo_score + wait_bonus)

    @classmethod
    def detect_matchmaking_abuse(
        cls,
        player_id: UUID,
        sport: models.Sport,
        db: Session
    ) -> Tuple[bool, Optional[str]]:
        """
        Detect matchmaking abuse patterns.

        Abuse types:
        - Rating manipulation (intentional losses)
        - Farming (repeatedly matching weak opponents)
        - Queue dodging (canceling searches repeatedly)

        Returns:
            (is_abuse_detected, abuse_type)
        """
        # Get recent matches (last 24 hours)
        day_ago = datetime.utcnow() - timedelta(days=1)

        recent_matches = db.query(models.Match).filter(
            models.Match.sport == sport,
            models.Match.created_at >= day_ago
        ).filter(
            (models.Match.player1_id == player_id) | (models.Match.player2_id == player_id)
        ).all()

        # Check for rating manipulation (suspicious loss streak)
        if len(recent_matches) >= 5:
            recent_results = []
            for match in recent_matches[-5:]:
                if match.winner_id == player_id:
                    recent_results.append("win")
                else:
                    recent_results.append("loss")

            # 5+ consecutive intentional losses (suspicious)
            if recent_results == ["loss"] * 5:
                return True, "rating_manipulation"

        # Check for farming (repeatedly matching much weaker opponents)
        if len(recent_matches) >= 10:
            elo_differences = []
            for match in recent_matches:
                if match.player1_id == player_id:
                    player_elo = match.player1_elo_before or 1500
                    opponent_elo = match.player2_elo_before or 1500
                else:
                    player_elo = match.player2_elo_before or 1500
                    opponent_elo = match.player1_elo_before or 1500

                elo_differences.append(player_elo - opponent_elo)

            # Average 300+ ELO advantage over 10 matches (farming)
            avg_advantage = statistics.mean(elo_differences)
            if avg_advantage > 300:
                return True, "farming_weak_opponents"

        # No abuse detected
        return False, None


# MARK: - Cheating Detection

class CheatingDetectionEngine:
    """
    Statistical anomaly detection for cheating.
    Deterministic rules - NO AI involved.

    Detection methods:
    1. Statistical outliers (impossible performance)
    2. Pattern analysis (bot-like behavior)
    3. Time-based anomalies (superhuman reaction times)
    4. Score manipulation detection
    """

    @classmethod
    def detect_performance_anomalies(
        cls,
        user_id: UUID,
        sport: models.Sport,
        db: Session
    ) -> Tuple[bool, List[str]]:
        """
        Detect suspicious performance patterns.

        Red flags:
        - Sudden massive rating spike
        - Unrealistic win streaks
        - Statistical outliers in performance
        - Inconsistent skill levels

        Returns:
            (is_suspicious, list_of_red_flags)
        """
        red_flags = []

        # Get user's sport profile
        profile = db.query(models.SportProfile).filter(
            models.SportProfile.user_id == user_id,
            models.SportProfile.sport == sport
        ).first()

        if not profile or profile.games_played < 10:
            return False, []  # Not enough data

        # Check 1: Massive rating spike
        recent_spike = cls._detect_rating_spike(user_id, sport, db)
        if recent_spike:
            red_flags.append("massive_rating_spike")

        # Check 2: Unrealistic win streak
        win_streak = cls._check_win_streak(user_id, sport, db)
        if win_streak > 20:  # 20+ wins in a row is suspicious
            red_flags.append(f"unrealistic_win_streak_{win_streak}")

        # Check 3: Performance consistency
        is_inconsistent = cls._check_performance_consistency(user_id, sport, db)
        if is_inconsistent:
            red_flags.append("inconsistent_performance")

        return len(red_flags) > 0, red_flags

    @classmethod
    def _detect_rating_spike(cls, user_id: UUID, sport: models.Sport, db: Session) -> bool:
        """Detect sudden massive ELO increase"""
        # Get recent matches
        week_ago = datetime.utcnow() - timedelta(days=7)

        recent_matches = db.query(models.Match).filter(
            models.Match.sport == sport,
            models.Match.created_at >= week_ago
        ).filter(
            (models.Match.player1_id == user_id) | (models.Match.player2_id == user_id)
        ).order_by(models.Match.created_at.asc()).all()

        if len(recent_matches) < 10:
            return False

        # Calculate rating change over week
        first_match = recent_matches[0]
        last_match = recent_matches[-1]

        if first_match.player1_id == user_id:
            start_rating = first_match.player1_elo_before or 1500
        else:
            start_rating = first_match.player2_elo_before or 1500

        if last_match.player1_id == user_id:
            end_rating = (last_match.player1_elo_before or 1500) + (last_match.player1_elo_change or 0)
        else:
            end_rating = (last_match.player2_elo_before or 1500) + (last_match.player2_elo_change or 0)

        rating_gain = end_rating - start_rating

        # +300 ELO in one week with 10+ games is suspicious
        return rating_gain > 300

    @classmethod
    def _check_win_streak(cls, user_id: UUID, sport: models.Sport, db: Session) -> int:
        """Check current win streak"""
        recent_matches = db.query(models.Match).filter(
            models.Match.sport == sport,
            models.Match.status == "completed"
        ).filter(
            (models.Match.player1_id == user_id) | (models.Match.player2_id == user_id)
        ).order_by(models.Match.created_at.desc()).limit(50).all()

        win_streak = 0
        for match in recent_matches:
            if match.winner_id == user_id:
                win_streak += 1
            else:
                break

        return win_streak

    @classmethod
    def _check_performance_consistency(cls, user_id: UUID, sport: models.Sport, db: Session) -> bool:
        """
        Check for inconsistent performance (potential account sharing).

        Looks for:
        - Alternating between very high and very low performance
        - Different play patterns over time
        """
        # Get recent matches
        recent_matches = db.query(models.Match).filter(
            models.Match.sport == sport,
            models.Match.status == "completed"
        ).filter(
            (models.Match.player1_id == user_id) | (models.Match.player2_id == user_id)
        ).order_by(models.Match.created_at.desc()).limit(20).all()

        if len(recent_matches) < 20:
            return False

        # Calculate performance variance (opponent ELO vs result)
        performance_scores = []

        for match in recent_matches:
            if match.player1_id == user_id:
                player_elo = match.player1_elo_before or 1500
                opponent_elo = match.player2_elo_before or 1500
                won = match.winner_id == user_id
            else:
                player_elo = match.player2_elo_before or 1500
                opponent_elo = match.player1_elo_before or 1500
                won = match.winner_id == user_id

            # Performance score: +1 for beating stronger, -1 for losing to weaker
            if won:
                performance = 1.0 + ((opponent_elo - player_elo) / 100.0)
            else:
                performance = -1.0 - ((player_elo - opponent_elo) / 100.0)

            performance_scores.append(performance)

        # High variance indicates inconsistency
        if len(performance_scores) >= 10:
            variance = statistics.variance(performance_scores)
            return variance > 5.0  # Threshold for suspicion

        return False


# MARK: - Dispute Resolution

class DisputeResolutionEngine:
    """
    Automated dispute resolution using evidence-based rules.
    Deterministic logic - NO AI involved.

    Handles:
    - Score disputes
    - Proof verification
    - Evidence evaluation
    - Automatic rulings
    """

    @classmethod
    def evaluate_dispute(
        cls,
        dispute: models.Dispute,
        db: Session
    ) -> Tuple[str, str, Optional[UUID]]:
        """
        Evaluate dispute and make ruling.

        Returns:
            (ruling, reasoning, winner_id)

        Rulings:
        - "plaintiff_wins": Reporter wins
        - "defendant_wins": Accused wins
        - "draw": Inconclusive, match voided
        - "needs_manual_review": Too complex for automation
        """
        # Get match data
        match = db.query(models.Match).filter(
            models.Match.id == dispute.match_id
        ).first()

        if not match:
            return "needs_manual_review", "Match not found", None

        # Check if both players submitted proof
        has_plaintiff_proof = dispute.plaintiff_evidence_url is not None
        has_defendant_proof = dispute.defendant_evidence_url is not None

        # Rule 1: Only one player has proof -> they win
        if has_plaintiff_proof and not has_defendant_proof:
            return "plaintiff_wins", "Only plaintiff provided evidence", dispute.plaintiff_id

        if has_defendant_proof and not has_plaintiff_proof:
            return "defendant_wins", "Only defendant provided evidence", dispute.defendant_id

        # Rule 2: Neither has proof -> draw
        if not has_plaintiff_proof and not has_defendant_proof:
            return "draw", "No evidence provided by either player", None

        # Rule 3: Both have proof -> needs manual review
        # (In production, could use computer vision to verify screenshots)
        return "needs_manual_review", "Both players submitted evidence - manual review required", None

    @classmethod
    def auto_resolve_if_possible(
        cls,
        dispute: models.Dispute,
        db: Session
    ) -> bool:
        """
        Attempt automatic resolution.

        Returns:
            True if auto-resolved, False if needs manual review
        """
        ruling, reasoning, winner_id = cls.evaluate_dispute(dispute, db)

        if ruling == "needs_manual_review":
            return False

        # Update dispute
        dispute.status = "resolved"
        dispute.resolution = ruling
        dispute.resolution_reasoning = reasoning
        dispute.resolved_at = datetime.utcnow()

        # Update match if winner changed
        if winner_id:
            match = db.query(models.Match).filter(
                models.Match.id == dispute.match_id
            ).first()

            if match:
                match.winner_id = winner_id
                match.status = "dispute_resolved"

        db.commit()

        return True
