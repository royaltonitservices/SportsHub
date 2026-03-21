"""
AI services for SportsHub
Basic implementations that can be enhanced with actual ML models later
"""
import re
from typing import Tuple


class ProfanityFilter:
    """
    Basic profanity filter
    Can be replaced with actual AI model later
    """

    # Basic profanity list (censored for safety)
    PROFANITY_WORDS = {
        "badword1", "badword2", "badword3",  # Placeholder
        # In production, use comprehensive profanity lists or AI models
    }

    # Offensive patterns
    OFFENSIVE_PATTERNS = [
        r'\b(spam)\s+(spam)\b',  # Repeated spam
        r'([A-Z])\1{5,}',  # Excessive caps
        r'(.)\1{10,}',  # Character repetition
    ]

    @classmethod
    def check_content(cls, content: str) -> Tuple[bool, str]:
        """
        Check if content contains profanity or offensive material

        Returns:
            Tuple of (is_safe, reason)
        """
        content_lower = content.lower()

        # Check for profanity words
        for word in cls.PROFANITY_WORDS:
            if word in content_lower:
                return False, "Contains inappropriate language"

        # Check for offensive patterns
        for pattern in cls.OFFENSIVE_PATTERNS:
            if re.search(pattern, content, re.IGNORECASE):
                return False, "Contains spam or offensive patterns"

        # Check for excessive length
        if len(content) > 10000:
            return False, "Content too long"

        # All checks passed
        return True, "Content is safe"

    @classmethod
    def filter_content(cls, content: str) -> str:
        """
        Filter profanity from content by replacing with asterisks

        Returns:
            Filtered content
        """
        filtered = content
        content_lower = filtered.lower()

        for word in cls.PROFANITY_WORDS:
            if word in content_lower:
                # Case-insensitive replacement
                pattern = re.compile(re.escape(word), re.IGNORECASE)
                filtered = pattern.sub('*' * len(word), filtered)

        return filtered


class MatchImpactAI:
    """
    Determines the impact weight of a match for Elo calculations
    Basic rule-based system that can be replaced with ML model
    """

    @classmethod
    def calculate_impact(
        cls,
        winner_rating: int,
        loser_rating: int,
        winner_games: int,
        loser_games: int,
        score_data: dict = None
    ) -> float:
        """
        Calculate match impact weight (0.5 to 1.5)

        Higher impact for:
        - Close rating matches
        - Experienced players
        - Competitive scores

        Returns:
            Impact weight multiplier
        """
        impact = 1.0

        # Rating difference factor (closer = higher impact)
        rating_diff = abs(winner_rating - loser_rating)
        if rating_diff < 50:
            impact += 0.2  # Very close match
        elif rating_diff < 100:
            impact += 0.1  # Close match
        elif rating_diff > 400:
            impact -= 0.3  # Massive mismatch

        # Experience factor (both players experienced = higher impact)
        avg_games = (winner_games + loser_games) / 2
        if avg_games > 50:
            impact += 0.1
        elif avg_games < 5:
            impact -= 0.1  # Likely learning phase

        # Score competitiveness (if provided)
        if score_data:
            # Example: close scores increase impact
            # This would be sport-specific in production
            pass

        # Clamp between 0.5 and 1.5
        return max(0.5, min(1.5, impact))


class DrillGenerator:
    """
    AI drill generator
    Basic template system that can be enhanced with ML
    """

    DRILL_TEMPLATES = {
        "basketball": [
            {
                "name": "Ball Handling Circuit",
                "category": "technique",
                "difficulty": "beginner",
                "duration": 20,
                "description": "Practice dribbling patterns and ball control",
                "instructions": [
                    "Start with stationary dribbling",
                    "Progress to figure-8 dribbling",
                    "Finish with crossover moves"
                ]
            },
            {
                "name": "Shooting Form Reps",
                "category": "accuracy",
                "difficulty": "beginner",
                "duration": 25,
                "description": "Focus on proper shooting mechanics",
                "instructions": [
                    "Start close to basket",
                    "Focus on follow-through",
                    "Gradually increase distance"
                ]
            },
            {
                "name": "Defensive Slides",
                "category": "agility",
                "difficulty": "intermediate",
                "duration": 15,
                "description": "Improve lateral quickness and defensive stance",
                "instructions": [
                    "Maintain low defensive stance",
                    "Quick lateral slides",
                    "Mirror partner movements"
                ]
            },
        ],
        "football": [
            {
                "name": "Route Running",
                "category": "technique",
                "difficulty": "intermediate",
                "duration": 30,
                "description": "Practice precision route patterns",
                "instructions": [
                    "Focus on sharp cuts",
                    "Maintain speed through routes",
                    "Work on catching mechanics"
                ]
            },
        ],
        "soccer": [
            {
                "name": "Dribbling Cones",
                "category": "technique",
                "difficulty": "beginner",
                "duration": 20,
                "description": "Weave through cones with ball control",
                "instructions": [
                    "Set up cone pattern",
                    "Alternate feet",
                    "Increase speed gradually"
                ]
            },
        ],
        "tennis": [
            {
                "name": "Serve Practice",
                "category": "accuracy",
                "difficulty": "intermediate",
                "duration": 25,
                "description": "Develop consistent serving technique",
                "instructions": [
                    "Focus on toss placement",
                    "Practice swing motion",
                    "Target specific service boxes"
                ]
            },
        ]
    }

    @classmethod
    def generate_drills(
        cls,
        sport: str,
        user_level: str = "intermediate",
        focus_areas: list = None,
        duration_minutes: int = 30
    ) -> list:
        """
        Generate personalized drill recommendations

        Args:
            sport: Sport type
            user_level: User's skill level
            focus_areas: List of areas to focus on (e.g., ["accuracy", "speed"])
            duration_minutes: Total available time

        Returns:
            List of recommended drills
        """
        available_drills = cls.DRILL_TEMPLATES.get(sport.lower(), [])

        if not available_drills:
            return []

        # Filter by difficulty level
        suitable_drills = [
            d for d in available_drills
            if d["difficulty"] == user_level or d["difficulty"] == "beginner"
        ]

        # Filter by focus areas if specified
        if focus_areas:
            suitable_drills = [
                d for d in suitable_drills
                if d["category"] in focus_areas
            ]

        # Select drills that fit within time budget
        selected_drills = []
        remaining_time = duration_minutes

        for drill in suitable_drills:
            if drill["duration"] <= remaining_time:
                selected_drills.append(drill)
                remaining_time -= drill["duration"]

        return selected_drills or suitable_drills[:3]  # Return at least some drills
