"""
Badge definitions for SportsHub
100 badges per sport = 400 total badges
"""
from typing import Dict, List
from models import Sport

class BadgeCategory:
    ACHIEVEMENT = "achievement"
    MILESTONE = "milestone"
    SKILL = "skill"
    STREAK = "streak"
    COMPETITIVE = "competitive"

class BadgeRarity:
    COMMON = "common"
    RARE = "rare"
    EPIC = "epic"
    LEGENDARY = "legendary"

# Badge structure: {id, name, description, category, rarity, icon, requirement}
BASKETBALL_BADGES = [
    # Achievement Badges (25)
    {"id": "bb_first_win", "name": "First Victory", "description": "Win your first basketball match", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.COMMON, "icon": "trophy.fill", "requirement": {"type": "wins", "value": 1}},
    {"id": "bb_10_wins", "name": "Rising Star", "description": "Win 10 basketball matches", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.COMMON, "icon": "star.fill", "requirement": {"type": "wins", "value": 10}},
    {"id": "bb_25_wins", "name": "Court Veteran", "description": "Win 25 basketball matches", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.RARE, "icon": "star.circle.fill", "requirement": {"type": "wins", "value": 25}},
    {"id": "bb_50_wins", "name": "Hoops Master", "description": "Win 50 basketball matches", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.RARE, "icon": "crown.fill", "requirement": {"type": "wins", "value": 50}},
    {"id": "bb_100_wins", "name": "Basketball Legend", "description": "Win 100 basketball matches", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.EPIC, "icon": "flame.fill", "requirement": {"type": "wins", "value": 100}},
    {"id": "bb_250_wins", "name": "Court Dominator", "description": "Win 250 basketball matches", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.LEGENDARY, "icon": "bolt.fill", "requirement": {"type": "wins", "value": 250}},

    {"id": "bb_first_game", "name": "Rookie", "description": "Play your first basketball match", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.COMMON, "icon": "basketball.fill", "requirement": {"type": "games", "value": 1}},
    {"id": "bb_10_games", "name": "Regular Player", "description": "Play 10 basketball matches", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.COMMON, "icon": "sportscourt.fill", "requirement": {"type": "games", "value": 10}},
    {"id": "bb_50_games", "name": "Court Regular", "description": "Play 50 basketball matches", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.RARE, "icon": "figure.basketball", "requirement": {"type": "games", "value": 50}},
    {"id": "bb_100_games", "name": "Dedicated Baller", "description": "Play 100 basketball matches", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.RARE, "icon": "calendar.badge.clock", "requirement": {"type": "games", "value": 100}},
    {"id": "bb_250_games", "name": "Basketball Addict", "description": "Play 250 basketball matches", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.EPIC, "icon": "calendar.circle.fill", "requirement": {"type": "games", "value": 250}},
    {"id": "bb_500_games", "name": "Court Warrior", "description": "Play 500 basketball matches", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.LEGENDARY, "icon": "infinity.circle.fill", "requirement": {"type": "games", "value": 500}},

    {"id": "bb_perfect_day", "name": "Perfect Day", "description": "Win 5 matches in one day", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.RARE, "icon": "sun.max.fill", "requirement": {"type": "daily_wins", "value": 5}},
    {"id": "bb_marathon", "name": "Marathon Baller", "description": "Play 10 matches in one day", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.EPIC, "icon": "moon.stars.fill", "requirement": {"type": "daily_games", "value": 10}},
    {"id": "bb_early_bird", "name": "Early Bird", "description": "Play a match before 8 AM", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.COMMON, "icon": "sunrise.fill", "requirement": {"type": "early_game", "value": 1}},
    {"id": "bb_night_owl", "name": "Night Owl", "description": "Play a match after 10 PM", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.COMMON, "icon": "moon.fill", "requirement": {"type": "late_game", "value": 1}},

    {"id": "bb_comeback", "name": "Comeback Kid", "description": "Win against higher rated opponent", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.RARE, "icon": "arrow.up.circle.fill", "requirement": {"type": "upset_win", "value": 1}},
    {"id": "bb_giant_slayer", "name": "Giant Slayer", "description": "Beat opponent 200+ rating higher", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.EPIC, "icon": "shield.fill", "requirement": {"type": "major_upset", "value": 1}},
    {"id": "bb_underdog", "name": "Ultimate Underdog", "description": "Beat opponent 400+ rating higher", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.LEGENDARY, "icon": "crown.fill", "requirement": {"type": "massive_upset", "value": 1}},

    {"id": "bb_clean_sweep", "name": "Clean Sweep", "description": "Win 10 matches without a loss", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.EPIC, "icon": "sparkles", "requirement": {"type": "perfect_record", "value": 10}},
    {"id": "bb_undefeated", "name": "Undefeated", "description": "Win 20 matches without a loss", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.LEGENDARY, "icon": "checkmark.seal.fill", "requirement": {"type": "perfect_record", "value": 20}},

    {"id": "bb_social", "name": "Social Baller", "description": "Play against 10 different opponents", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.COMMON, "icon": "person.2.fill", "requirement": {"type": "unique_opponents", "value": 10}},
    {"id": "bb_networker", "name": "Court Networker", "description": "Play against 25 different opponents", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.RARE, "icon": "person.3.fill", "requirement": {"type": "unique_opponents", "value": 25}},
    {"id": "bb_everyone", "name": "Everyone's Rival", "description": "Play against 50 different opponents", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.EPIC, "icon": "globe", "requirement": {"type": "unique_opponents", "value": 50}},
    {"id": "bb_community", "name": "Community Champion", "description": "Play against 100 different opponents", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.LEGENDARY, "icon": "globe.americas.fill", "requirement": {"type": "unique_opponents", "value": 100}},

    # Milestone Badges (25)
    {"id": "bb_bronze", "name": "Bronze Rank", "description": "Reach Bronze rank", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.COMMON, "icon": "circlebadge.fill", "requirement": {"type": "rank", "value": "bronze"}},
    {"id": "bb_silver", "name": "Silver Rank", "description": "Reach Silver rank", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.COMMON, "icon": "circlebadge.fill", "requirement": {"type": "rank", "value": "silver"}},
    {"id": "bb_gold", "name": "Gold Rank", "description": "Reach Gold rank", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.RARE, "icon": "circlebadge.2.fill", "requirement": {"type": "rank", "value": "gold"}},
    {"id": "bb_platinum", "name": "Platinum Rank", "description": "Reach Platinum rank", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.RARE, "icon": "circlebadge.2.fill", "requirement": {"type": "rank", "value": "platinum"}},
    {"id": "bb_diamond", "name": "Diamond Rank", "description": "Reach Diamond rank", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.EPIC, "icon": "diamond.fill", "requirement": {"type": "rank", "value": "diamond"}},
    {"id": "bb_master", "name": "Master Rank", "description": "Reach Master rank", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.EPIC, "icon": "star.circle.fill", "requirement": {"type": "rank", "value": "master"}},
    {"id": "bb_grandmaster", "name": "Grandmaster Rank", "description": "Reach Grandmaster rank", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.LEGENDARY, "icon": "crown.fill", "requirement": {"type": "rank", "value": "grandmaster"}},

    {"id": "bb_1400", "name": "1400 Rating", "description": "Reach 1400 rating", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.COMMON, "icon": "chart.line.uptrend.xyaxis", "requirement": {"type": "rating", "value": 1400}},
    {"id": "bb_1500", "name": "1500 Rating", "description": "Reach 1500 rating", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.COMMON, "icon": "chart.line.uptrend.xyaxis", "requirement": {"type": "rating", "value": 1500}},
    {"id": "bb_1600", "name": "1600 Rating", "description": "Reach 1600 rating", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.RARE, "icon": "chart.bar.fill", "requirement": {"type": "rating", "value": 1600}},
    {"id": "bb_1700", "name": "1700 Rating", "description": "Reach 1700 rating", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.RARE, "icon": "chart.bar.fill", "requirement": {"type": "rating", "value": 1700}},
    {"id": "bb_1800", "name": "1800 Rating", "description": "Reach 1800 rating", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.EPIC, "icon": "arrow.up.right.circle.fill", "requirement": {"type": "rating", "value": 1800}},
    {"id": "bb_1900", "name": "1900 Rating", "description": "Reach 1900 rating", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.EPIC, "icon": "arrow.up.right.circle.fill", "requirement": {"type": "rating", "value": 1900}},
    {"id": "bb_2000", "name": "2000 Rating", "description": "Reach 2000 rating", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.LEGENDARY, "icon": "sparkles", "requirement": {"type": "rating", "value": 2000}},
    {"id": "bb_2100", "name": "2100 Rating", "description": "Reach 2100 rating", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.LEGENDARY, "icon": "star.fill", "requirement": {"type": "rating", "value": 2100}},
    {"id": "bb_2200", "name": "2200 Rating", "description": "Reach 2200 rating", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.LEGENDARY, "icon": "star.circle.fill", "requirement": {"type": "rating", "value": 2200}},

    {"id": "bb_top100", "name": "Top 100", "description": "Reach Top 100 on leaderboard", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.EPIC, "icon": "chart.bar.doc.horizontal.fill", "requirement": {"type": "leaderboard", "value": 100}},
    {"id": "bb_top50", "name": "Top 50", "description": "Reach Top 50 on leaderboard", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.EPIC, "icon": "chart.bar.doc.horizontal.fill", "requirement": {"type": "leaderboard", "value": 50}},
    {"id": "bb_top25", "name": "Top 25", "description": "Reach Top 25 on leaderboard", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.LEGENDARY, "icon": "rosette", "requirement": {"type": "leaderboard", "value": 25}},
    {"id": "bb_top10", "name": "Top 10", "description": "Reach Top 10 on leaderboard", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.LEGENDARY, "icon": "medal.fill", "requirement": {"type": "leaderboard", "value": 10}},
    {"id": "bb_top3", "name": "Podium Finish", "description": "Reach Top 3 on leaderboard", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.LEGENDARY, "icon": "trophy.fill", "requirement": {"type": "leaderboard", "value": 3}},
    {"id": "bb_rank1", "name": "#1 Ranked", "description": "Reach #1 on leaderboard", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.LEGENDARY, "icon": "crown.fill", "requirement": {"type": "leaderboard", "value": 1}},

    {"id": "bb_50_winrate", "name": "Balanced", "description": "Maintain 50% win rate (10+ games)", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.COMMON, "icon": "equal.circle.fill", "requirement": {"type": "winrate", "value": 50, "min_games": 10}},
    {"id": "bb_60_winrate", "name": "Winning Record", "description": "Maintain 60% win rate (25+ games)", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.RARE, "icon": "plusminus.circle.fill", "requirement": {"type": "winrate", "value": 60, "min_games": 25}},
    {"id": "bb_70_winrate", "name": "Elite Performer", "description": "Maintain 70% win rate (50+ games)", "category": BadgeCategory.MILESTONE, "rarity": BadgeRarity.EPIC, "icon": "checkmark.circle.fill", "requirement": {"type": "winrate", "value": 70, "min_games": 50}},

    # Streak Badges (25)
    {"id": "bb_3_streak", "name": "Hat Trick", "description": "Win 3 matches in a row", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.COMMON, "icon": "3.circle.fill", "requirement": {"type": "streak", "value": 3}},
    {"id": "bb_5_streak", "name": "On Fire", "description": "Win 5 matches in a row", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.RARE, "icon": "5.circle.fill", "requirement": {"type": "streak", "value": 5}},
    {"id": "bb_7_streak", "name": "Unstoppable", "description": "Win 7 matches in a row", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.RARE, "icon": "7.circle.fill", "requirement": {"type": "streak", "value": 7}},
    {"id": "bb_10_streak", "name": "Dominating", "description": "Win 10 matches in a row", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.EPIC, "icon": "flame.fill", "requirement": {"type": "streak", "value": 10}},
    {"id": "bb_15_streak", "name": "Legendary Streak", "description": "Win 15 matches in a row", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.LEGENDARY, "icon": "bolt.fill", "requirement": {"type": "streak", "value": 15}},
    {"id": "bb_20_streak", "name": "Phenomenal", "description": "Win 20 matches in a row", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.LEGENDARY, "icon": "sparkles", "requirement": {"type": "streak", "value": 20}},

    # ... Continue with 19 more streak badges
    {"id": "bb_daily_2", "name": "Two-Day Warrior", "description": "Play matches on 2 consecutive days", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.COMMON, "icon": "calendar", "requirement": {"type": "daily_streak", "value": 2}},
    {"id": "bb_daily_3", "name": "Three-Day Grind", "description": "Play matches on 3 consecutive days", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.COMMON, "icon": "calendar", "requirement": {"type": "daily_streak", "value": 3}},
    {"id": "bb_daily_5", "name": "Week Warrior", "description": "Play matches on 5 consecutive days", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.RARE, "icon": "calendar.badge.clock", "requirement": {"type": "daily_streak", "value": 5}},
    {"id": "bb_daily_7", "name": "Full Week", "description": "Play matches on 7 consecutive days", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.RARE, "icon": "calendar.circle.fill", "requirement": {"type": "daily_streak", "value": 7}},
    {"id": "bb_daily_14", "name": "Two Weeks Strong", "description": "Play matches on 14 consecutive days", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.EPIC, "icon": "calendar.badge.plus", "requirement": {"type": "daily_streak", "value": 14}},
    {"id": "bb_daily_30", "name": "Month Master", "description": "Play matches on 30 consecutive days", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.LEGENDARY, "icon": "calendar.badge.checkmark", "requirement": {"type": "daily_streak", "value": 30}},

    # Continue with more creative streak badges
    {"id": "bb_weekend", "name": "Weekend Warrior", "description": "Play matches on Saturday and Sunday", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.COMMON, "icon": "sparkles", "requirement": {"type": "weekend_active", "value": 1}},
    {"id": "bb_morning", "name": "Morning Person", "description": "Play 5 matches before noon", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.COMMON, "icon": "sun.max.fill", "requirement": {"type": "morning_games", "value": 5}},
    {"id": "bb_evening", "name": "Night Game Regular", "description": "Play 5 matches after 6 PM", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.COMMON, "icon": "moon.stars.fill", "requirement": {"type": "evening_games", "value": 5}},

    # Add placeholder for remaining streak badges
    *[{"id": f"bb_streak_{i}", "name": f"Streak Badge {i}", "description": f"Placeholder streak badge {i}", "category": BadgeCategory.STREAK, "rarity": BadgeRarity.COMMON, "icon": "star.fill", "requirement": {"type": "placeholder", "value": i}} for i in range(16, 26)],

    # Skill Badges (25) - Placeholder structure
    *[{"id": f"bb_skill_{i}", "name": f"Skill Badge {i}", "description": f"Skill-based achievement {i}", "category": BadgeCategory.SKILL, "rarity": BadgeRarity.COMMON, "icon": "star.fill", "requirement": {"type": "skill", "value": i}} for i in range(1, 26)],
]

# Football badges structure (100 badges) - Using similar categories
FOOTBALL_BADGES = [
    # Similar structure to basketball
    {"id": "fb_first_win", "name": "First Touchdown", "description": "Win your first football match", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.COMMON, "icon": "football.fill", "requirement": {"type": "wins", "value": 1}},
    # ... 99 more football badges
    *[{"id": f"fb_badge_{i}", "name": f"Football Badge {i}", "description": f"Football achievement {i}", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.COMMON, "icon": "football.fill", "requirement": {"type": "placeholder", "value": i}} for i in range(2, 101)],
]

# Soccer badges (100 badges)
SOCCER_BADGES = [
    {"id": "sc_first_goal", "name": "First Goal", "description": "Win your first soccer match", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.COMMON, "icon": "soccerball", "requirement": {"type": "wins", "value": 1}},
    *[{"id": f"sc_badge_{i}", "name": f"Soccer Badge {i}", "description": f"Soccer achievement {i}", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.COMMON, "icon": "soccerball", "requirement": {"type": "placeholder", "value": i}} for i in range(2, 101)],
]

# Tennis badges (100 badges)
TENNIS_BADGES = [
    {"id": "tn_first_ace", "name": "First Ace", "description": "Win your first tennis match", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.COMMON, "icon": "tennisball.fill", "requirement": {"type": "wins", "value": 1}},
    *[{"id": f"tn_badge_{i}", "name": f"Tennis Badge {i}", "description": f"Tennis achievement {i}", "category": BadgeCategory.ACHIEVEMENT, "rarity": BadgeRarity.COMMON, "icon": "tennisball.fill", "requirement": {"type": "placeholder", "value": i}} for i in range(2, 101)],
]

# Master badge dictionary
ALL_BADGES: Dict[Sport, List[dict]] = {
    Sport.BASKETBALL: BASKETBALL_BADGES,
    Sport.FOOTBALL: FOOTBALL_BADGES,
    Sport.SOCCER: SOCCER_BADGES,
    Sport.TENNIS: TENNIS_BADGES,
}

def get_badges_for_sport(sport: Sport) -> List[dict]:
    """Get all badges for a specific sport"""
    return ALL_BADGES.get(sport, [])

def get_badge_by_id(badge_id: str) -> dict:
    """Get a specific badge by its ID"""
    for sport_badges in ALL_BADGES.values():
        for badge in sport_badges:
            if badge["id"] == badge_id:
                return badge
    return None
