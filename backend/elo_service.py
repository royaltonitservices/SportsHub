"""
Elo rating service for skill-based matchmaking
"""
import math
from typing import Tuple


class EloService:
    """Service for calculating Elo ratings"""

    # K-factor configurations
    K_FACTOR_PROVISIONAL = 40  # Higher K-factor for first 10 games
    K_FACTOR_REGULAR = 32      # Standard K-factor
    K_FACTOR_HIGH_RATING = 24  # Lower K-factor for players above 2000

    PROVISIONAL_GAMES_THRESHOLD = 10
    HIGH_RATING_THRESHOLD = 2000

    @staticmethod
    def expected_score(rating_a: int, rating_b: int) -> float:
        """
        Calculate expected score for player A
        Returns value between 0 and 1
        """
        return 1.0 / (1.0 + math.pow(10, (rating_b - rating_a) / 400.0))

    @staticmethod
    def get_k_factor(rating: int, is_provisional: bool) -> int:
        """
        Determine K-factor based on rating and provisional status
        """
        if is_provisional:
            return EloService.K_FACTOR_PROVISIONAL
        elif rating >= EloService.HIGH_RATING_THRESHOLD:
            return EloService.K_FACTOR_HIGH_RATING
        else:
            return EloService.K_FACTOR_REGULAR

    @staticmethod
    def calculate_new_ratings(
        winner_rating: int,
        loser_rating: int,
        winner_is_provisional: bool,
        loser_is_provisional: bool,
        impact_weight: float = 1.0
    ) -> Tuple[int, int]:
        """
        Calculate new ratings after a match

        Args:
            winner_rating: Current rating of the winner
            loser_rating: Current rating of the loser
            winner_is_provisional: Whether winner is in provisional period
            loser_is_provisional: Whether loser is in provisional period
            impact_weight: Match impact multiplier (from AI analysis)

        Returns:
            Tuple of (new_winner_rating, new_loser_rating)
        """
        # Calculate expected scores
        winner_expected = EloService.expected_score(winner_rating, loser_rating)
        loser_expected = 1.0 - winner_expected

        # Get K-factors
        winner_k = EloService.get_k_factor(winner_rating, winner_is_provisional)
        loser_k = EloService.get_k_factor(loser_rating, loser_is_provisional)

        # Apply impact weight
        winner_k = int(winner_k * impact_weight)
        loser_k = int(loser_k * impact_weight)

        # Calculate rating changes (winner gets 1.0, loser gets 0.0)
        winner_change = winner_k * (1.0 - winner_expected)
        loser_change = loser_k * (0.0 - loser_expected)

        # Calculate new ratings
        new_winner_rating = int(winner_rating + winner_change)
        new_loser_rating = int(loser_rating + loser_change)

        # Ensure ratings don't go below minimum
        new_winner_rating = max(new_winner_rating, 100)
        new_loser_rating = max(new_loser_rating, 100)

        return new_winner_rating, new_loser_rating

    @staticmethod
    def find_matchmaking_range(rating: int, is_provisional: bool) -> Tuple[int, int]:
        """
        Calculate acceptable rating range for matchmaking

        Args:
            rating: Player's current rating
            is_provisional: Whether player is in provisional period

        Returns:
            Tuple of (min_rating, max_rating) for matching
        """
        if is_provisional:
            # Wider range for provisional players
            range_size = 400
        else:
            # Standard range based on rating
            if rating < 1200:
                range_size = 300
            elif rating < 1600:
                range_size = 250
            elif rating < 2000:
                range_size = 200
            else:
                range_size = 150

        min_rating = max(100, rating - range_size)
        max_rating = rating + range_size

        return min_rating, max_rating

    @staticmethod
    def calculate_rank_tier(rating: int) -> str:
        """
        Determine rank tier based on rating

        Returns: bronze, silver, gold, platinum, diamond, master, grandmaster
        """
        if rating < 1000:
            return "bronze"
        elif rating < 1200:
            return "silver"
        elif rating < 1500:
            return "gold"
        elif rating < 1800:
            return "platinum"
        elif rating < 2100:
            return "diamond"
        elif rating < 2400:
            return "master"
        else:
            return "grandmaster"
