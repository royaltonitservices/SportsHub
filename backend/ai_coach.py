# AI Performance Coach Engine
# Master Premium Feature - 3,000+ LOC
# Analyzes: Match data, Tournament data, Smartwatch data, Goals Survey data
# Generates: Training plans, Match readiness, Recovery warnings, Drill recommendations

from sqlalchemy.orm import Session
from typing import List, Dict, Optional, Tuple
from datetime import datetime, timedelta
from uuid import UUID
import statistics
import math

import models
from models_premium import (
    BiometricData, SportGoals, Tournament, TournamentParticipant,
    AICoachInsight, PerformancePrediction, SmartwatchConnection
)


# MARK: - AI Coach Service

class AICoachService:
    """
    Master AI Performance Coach

    Analyzes all available data to provide:
    - Training recommendations
    - Match readiness scores
    - Recovery warnings
    - Performance predictions
    - Skill development paths
    - Fatigue management
    """

    def __init__(self, db: Session):
        self.db = db

    # MARK: - Main Analysis Entry Points

    def generate_daily_insights(self, user_id: UUID, sport: models.Sport) -> List[AICoachInsight]:
        """
        Generate daily insights for user.

        Called every morning or when user opens app.
        Analyzes all data to create actionable insights.
        """
        insights = []

        # 1. Check recovery status
        recovery_insight = self._analyze_recovery(user_id)
        if recovery_insight:
            insights.append(recovery_insight)

        # 2. Check recent performance trends
        performance_insight = self._analyze_performance_trend(user_id, sport)
        if performance_insight:
            insights.append(performance_insight)

        # 3. Check if overtraining
        overtraining_insight = self._check_overtraining(user_id, sport)
        if overtraining_insight:
            insights.append(overtraining_insight)

        # 4. Check goal progress
        goal_insight = self._analyze_goal_progress(user_id, sport)
        if goal_insight:
            insights.append(goal_insight)

        # 5. Tournament preparation
        tournament_insight = self._check_upcoming_tournaments(user_id, sport)
        if tournament_insight:
            insights.append(tournament_insight)

        # 6. Skill development suggestions
        skill_insight = self._suggest_skill_development(user_id, sport)
        if skill_insight:
            insights.append(skill_insight)

        # Save to database
        for insight in insights:
            self.db.add(insight)

        self.db.commit()

        return insights

    def generate_match_readiness_score(self, user_id: UUID, sport: models.Sport) -> float:
        """
        Calculate match readiness score (0-100).

        Factors:
        - Recovery score (smartwatch)
        - Recent performance
        - Sleep quality
        - Training load
        - Mental readiness
        """
        scores = []
        weights = []

        # 1. Recovery score (40% weight)
        recovery_score = self._get_recovery_score(user_id)
        if recovery_score:
            scores.append(recovery_score)
            weights.append(0.4)

        # 2. Recent performance (30% weight)
        recent_performance = self._get_recent_performance_score(user_id, sport)
        if recent_performance:
            scores.append(recent_performance)
            weights.append(0.3)

        # 3. Sleep quality (20% weight)
        sleep_score = self._get_sleep_quality_score(user_id)
        if sleep_score:
            scores.append(sleep_score)
            weights.append(0.2)

        # 4. Mental readiness (10% weight)
        mental_score = self._estimate_mental_readiness(user_id, sport)
        if mental_score:
            scores.append(mental_score)
            weights.append(0.1)

        if not scores:
            return 70.0  # Default moderate readiness

        # Weighted average
        total_weight = sum(weights)
        weighted_sum = sum(s * w for s, w in zip(scores, weights))
        readiness = weighted_sum / total_weight

        return max(0, min(100, readiness))

    def predict_match_performance(self, user_id: UUID, sport: models.Sport, opponent_elo: int) -> PerformancePrediction:
        """
        Predict performance for upcoming match.

        Returns prediction with:
        - Performance index (-10 to +10)
        - Confidence (0-1)
        - Contributing factors
        """
        user_profile = self.db.query(models.SportProfile).filter(
            models.SportProfile.user_id == user_id,
            models.SportProfile.sport == sport
        ).first()

        if not user_profile:
            return self._create_default_prediction(user_id, sport)

        # Get all factors
        recovery_factor = self._calculate_recovery_factor(user_id)
        recent_performance_factor = self._calculate_recent_performance_factor(user_id, sport)
        training_load_factor = self._calculate_training_load_factor(user_id, sport)
        sleep_factor = self._calculate_sleep_factor(user_id)
        stress_factor = self._calculate_stress_factor(user_id, sport)
        elo_factor = self._calculate_elo_factor(user_profile.elo_rating, opponent_elo)

        # Calculate performance index
        factors = {
            "recovery": recovery_factor,
            "recent_performance": recent_performance_factor,
            "training_load": training_load_factor,
            "sleep_quality": sleep_factor,
            "stress_level": stress_factor,
            "elo_difference": elo_factor
        }

        performance_index = sum(factors.values())

        # Calculate readiness score
        readiness = self.generate_match_readiness_score(user_id, sport)

        # Calculate confidence (based on data availability)
        confidence = self._calculate_prediction_confidence(user_id)

        # Create prediction
        prediction = PerformancePrediction(
            user_id=user_id,
            sport=sport,
            prediction_date=datetime.now(),
            prediction_type="match",
            performance_index=performance_index,
            readiness_score=readiness,
            confidence=confidence,
            factors=factors
        )

        self.db.add(prediction)
        self.db.commit()

        return prediction

    def generate_training_plan(self, user_id: UUID, sport: models.Sport, duration_days: int = 7) -> Dict:
        """
        Generate personalized training plan.

        Based on:
        - Goals survey
        - Current skill level
        - Recovery status
        - Upcoming matches/tournaments
        """
        # Get user's goals
        goals = self.db.query(SportGoals).filter(
            SportGoals.user_id == user_id,
            SportGoals.sport == sport
        ).first()

        # Get recovery status
        recovery_score = self._get_recovery_score(user_id)

        # Get upcoming events
        upcoming_tournaments = self._get_upcoming_tournaments(user_id, sport)

        # Generate daily plan
        daily_plans = []

        for day in range(duration_days):
            date = datetime.now() + timedelta(days=day)

            # Determine intensity based on recovery and schedule
            intensity = self._determine_training_intensity(
                day_number=day,
                recovery_score=recovery_score,
                upcoming_tournaments=upcoming_tournaments
            )

            # Generate drills based on goals
            drills = self._select_drills_for_goals(goals, sport, intensity)

            # Create daily plan
            daily_plan = {
                "date": date.isoformat(),
                "intensity": intensity,
                "focus_areas": self._get_priority_focus_areas(goals),
                "drills": drills,
                "duration_minutes": self._calculate_session_duration(intensity),
                "notes": self._generate_daily_notes(day, recovery_score, upcoming_tournaments)
            }

            daily_plans.append(daily_plan)

        training_plan = {
            "user_id": str(user_id),
            "sport": sport.value,
            "start_date": datetime.now().isoformat(),
            "duration_days": duration_days,
            "daily_plans": daily_plans,
            "weekly_focus": self._get_weekly_focus(goals),
            "progression_strategy": self._get_progression_strategy(goals)
        }

        return training_plan

    def recommend_drills(self, user_id: UUID, sport: models.Sport, limit: int = 5) -> List[Dict]:
        """
        Recommend specific drills for user.

        Based on:
        - Goals survey
        - Recent performance weaknesses
        - Skill level
        """
        # Get goals
        goals = self.db.query(SportGoals).filter(
            SportGoals.user_id == user_id,
            SportGoals.sport == sport
        ).first()

        # Analyze recent matches for weaknesses
        weaknesses = self._identify_skill_weaknesses(user_id, sport)

        # Get all drills for sport
        all_drills = self._get_sport_drills(sport)

        # Score drills
        scored_drills = []
        for drill in all_drills:
            score = self._score_drill_relevance(drill, goals, weaknesses)
            scored_drills.append((drill, score))

        # Sort by score and return top drills
        scored_drills.sort(key=lambda x: x[1], reverse=True)

        return [drill for drill, score in scored_drills[:limit]]

    # MARK: - Recovery Analysis

    def _analyze_recovery(self, user_id: UUID) -> Optional[AICoachInsight]:
        """Analyze recovery status and generate insight"""
        today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)

        biometric = self.db.query(BiometricData).filter(
            BiometricData.user_id == user_id,
            BiometricData.date >= today
        ).first()

        if not biometric:
            return None

        if not biometric.readiness_score:
            return None

        # Generate insight based on readiness
        if biometric.readiness_score < 30:
            return AICoachInsight(
                user_id=user_id,
                insight_type="recovery",
                priority="urgent",
                title="Critical Recovery Alert",
                message=f"Your recovery score is very low ({biometric.readiness_score:.0f}/100). "
                        f"Your body needs rest to prevent injury and burnout.",
                details={
                    "readiness_score": biometric.readiness_score,
                    "fatigue_level": biometric.fatigue_level,
                    "hrv": biometric.heart_rate_variability,
                    "sleep_quality": biometric.sleep_quality_score
                },
                suggested_actions=[
                    "Take a rest day - no intense training",
                    "Get 8+ hours of quality sleep tonight",
                    "Light stretching or yoga only",
                    "Stay hydrated and focus on nutrition"
                ],
                confidence=0.9,
                is_actionable=True
            )
        elif biometric.readiness_score < 50:
            return AICoachInsight(
                user_id=user_id,
                insight_type="recovery",
                priority="high",
                title="Low Recovery - Active Recovery Recommended",
                message=f"Your recovery score is below optimal ({biometric.readiness_score:.0f}/100). "
                        f"Consider light training or active recovery today.",
                suggested_actions=[
                    "Light cardio (50-60% max HR)",
                    "Skill work without intensity",
                    "Focus on technique drills",
                    "Ensure good sleep tonight"
                ],
                confidence=0.85
            )
        elif biometric.readiness_score >= 80:
            return AICoachInsight(
                user_id=user_id,
                insight_type="recovery",
                priority="medium",
                title="Excellent Recovery - Perfect for Intensity",
                message=f"Your recovery score is excellent ({biometric.readiness_score:.0f}/100). "
                        f"This is a great day for high-intensity training or competition.",
                suggested_actions=[
                    "High-intensity interval training",
                    "Practice game scenarios",
                    "Competition or ranked matches",
                    "Push your limits today"
                ],
                confidence=0.9
            )

        return None

    def _get_recovery_score(self, user_id: UUID) -> Optional[float]:
        """Get latest recovery score from smartwatch data"""
        today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)

        biometric = self.db.query(BiometricData).filter(
            BiometricData.user_id == user_id,
            BiometricData.date >= today
        ).first()

        if biometric and biometric.readiness_score:
            return biometric.readiness_score

        return None

    def _calculate_recovery_factor(self, user_id: UUID) -> float:
        """Calculate recovery contribution to performance (-10 to +10)"""
        recovery_score = self._get_recovery_score(user_id)

        if not recovery_score:
            return 0.0

        # Convert 0-100 to -10 to +10
        # 50 = baseline (0)
        # 100 = +10
        # 0 = -10
        return (recovery_score - 50) / 5.0

    # MARK: - Performance Analysis

    def _analyze_performance_trend(self, user_id: UUID, sport: models.Sport) -> Optional[AICoachInsight]:
        """Analyze recent performance trend"""
        # Get last 10 matches
        recent_matches = self.db.query(models.Match).filter(
            models.Match.sport == sport
        ).filter(
            (models.Match.player1_id == user_id) | (models.Match.player2_id == user_id)
        ).filter(
            models.Match.status == "completed"
        ).order_by(models.Match.created_at.desc()).limit(10).all()

        if len(recent_matches) < 3:
            return None

        # Calculate win rate
        wins = sum(1 for m in recent_matches if self._did_user_win(m, user_id))
        win_rate = wins / len(recent_matches)

        # Get ELO changes
        elo_changes = []
        for match in recent_matches:
            if match.player1_id == user_id and match.player1_elo_change:
                elo_changes.append(match.player1_elo_change)
            elif match.player2_id == user_id and match.player2_elo_change:
                elo_changes.append(match.player2_elo_change)

        avg_elo_change = statistics.mean(elo_changes) if elo_changes else 0

        # Generate insight based on trend
        if win_rate >= 0.7 and avg_elo_change > 5:
            return AICoachInsight(
                user_id=user_id,
                sport=sport,
                insight_type="training",
                priority="medium",
                title="Strong Performance Streak!",
                message=f"You've won {wins} of your last {len(recent_matches)} matches. "
                        f"Your ELO is rising (+{avg_elo_change:.0f} average). Keep up the momentum!",
                suggested_actions=[
                    "Challenge higher-ranked opponents",
                    "Enter a tournament to showcase skills",
                    "Maintain current training intensity",
                    "Share your progress with friends"
                ],
                confidence=0.8
            )
        elif win_rate <= 0.3 and avg_elo_change < -5:
            weaknesses = self._identify_skill_weaknesses(user_id, sport)

            return AICoachInsight(
                user_id=user_id,
                sport=sport,
                insight_type="training",
                priority="high",
                title="Performance Dip - Time to Adjust",
                message=f"You've won only {wins} of your last {len(recent_matches)} matches. "
                        f"Let's work on your weaknesses and rebuild confidence.",
                details={"weaknesses": weaknesses, "elo_change": avg_elo_change},
                suggested_actions=[
                    "Focus on fundamentals training",
                    "Practice specific weak areas",
                    "Play casual matches to rebuild confidence",
                    "Review goals and adjust training plan"
                ],
                drills_recommended=self._get_drills_for_weaknesses(weaknesses, sport),
                confidence=0.85
            )

        return None

    def _get_recent_performance_score(self, user_id: UUID, sport: models.Sport) -> Optional[float]:
        """Calculate recent performance score (0-100)"""
        recent_matches = self.db.query(models.Match).filter(
            models.Match.sport == sport
        ).filter(
            (models.Match.player1_id == user_id) | (models.Match.player2_id == user_id)
        ).filter(
            models.Match.status == "completed"
        ).order_by(models.Match.created_at.desc()).limit(5).all()

        if not recent_matches:
            return None

        wins = sum(1 for m in recent_matches if self._did_user_win(m, user_id))
        win_rate = wins / len(recent_matches)

        # Convert win rate to 0-100 score
        # 0% wins = 30
        # 50% wins = 65
        # 100% wins = 100
        return 30 + (win_rate * 70)

    def _calculate_recent_performance_factor(self, user_id: UUID, sport: models.Sport) -> float:
        """Calculate recent performance contribution (-10 to +10)"""
        performance_score = self._get_recent_performance_score(user_id, sport)

        if not performance_score:
            return 0.0

        # Convert to -10 to +10
        return (performance_score - 50) / 5.0

    def _did_user_win(self, match: models.Match, user_id: UUID) -> bool:
        """Check if user won the match"""
        if match.winner_id == user_id:
            return True
        return False

    # MARK: - Overtraining Detection

    def _check_overtraining(self, user_id: UUID, sport: models.Sport) -> Optional[AICoachInsight]:
        """Check for signs of overtraining"""
        # Get matches in last 7 days
        week_ago = datetime.now() - timedelta(days=7)

        recent_matches = self.db.query(models.Match).filter(
            models.Match.sport == sport,
            models.Match.created_at >= week_ago
        ).filter(
            (models.Match.player1_id == user_id) | (models.Match.player2_id == user_id)
        ).all()

        matches_this_week = len(recent_matches)

        # Get biometric data
        biometric_data = self.db.query(BiometricData).filter(
            BiometricData.user_id == user_id,
            BiometricData.date >= week_ago
        ).all()

        # Check for overtraining signs
        high_volume = matches_this_week > 15  # More than 2 matches per day
        low_recovery = any(b.readiness_score and b.readiness_score < 40 for b in biometric_data if b.readiness_score)
        declining_hrv = self._check_declining_hrv(biometric_data)
        poor_sleep = sum(1 for b in biometric_data if b.sleep_quality_score and b.sleep_quality_score < 60) >= 3

        overtraining_indicators = sum([high_volume, low_recovery, declining_hrv, poor_sleep])

        if overtraining_indicators >= 2:
            return AICoachInsight(
                user_id=user_id,
                sport=sport,
                insight_type="recovery",
                priority="urgent",
                title="⚠️ Overtraining Warning",
                message=f"You've played {matches_this_week} matches this week with declining recovery metrics. "
                        f"Your body needs rest to prevent burnout and injury.",
                details={
                    "matches_this_week": matches_this_week,
                    "indicators": {
                        "high_volume": high_volume,
                        "low_recovery": low_recovery,
                        "declining_hrv": declining_hrv,
                        "poor_sleep": poor_sleep
                    }
                },
                suggested_actions=[
                    "Take 2-3 days complete rest",
                    "Focus on sleep quality (8+ hours)",
                    "Light stretching and mobility work only",
                    "Reduce match frequency next week",
                    "Consider massage or active recovery"
                ],
                confidence=0.85,
                is_actionable=True,
                expires_at=datetime.now() + timedelta(days=3)
            )

        return None

    def _check_declining_hrv(self, biometric_data: List[BiometricData]) -> bool:
        """Check if HRV is declining"""
        hrv_values = [b.heart_rate_variability for b in biometric_data if b.heart_rate_variability]

        if len(hrv_values) < 3:
            return False

        # Check if trend is declining
        recent_avg = statistics.mean(hrv_values[-3:])
        overall_avg = statistics.mean(hrv_values)

        return recent_avg < overall_avg * 0.85  # 15% decline

    def _calculate_training_load_factor(self, user_id: UUID, sport: models.Sport) -> float:
        """Calculate training load impact (-10 to +10)"""
        week_ago = datetime.now() - timedelta(days=7)

        recent_matches = self.db.query(models.Match).filter(
            models.Match.sport == sport,
            models.Match.created_at >= week_ago
        ).filter(
            (models.Match.player1_id == user_id) | (models.Match.player2_id == user_id)
        ).count()

        # Optimal: 7-10 matches per week = 0
        # Too few: < 5 = negative
        # Too many: > 15 = negative
        if recent_matches < 5:
            return -2.0  # Detraining
        elif recent_matches > 15:
            return -3.0  # Overtraining
        elif 7 <= recent_matches <= 10:
            return 2.0  # Optimal
        else:
            return 0.0

    # MARK: - Goal Progress Analysis

    def _analyze_goal_progress(self, user_id: UUID, sport: models.Sport) -> Optional[AICoachInsight]:
        """Analyze progress toward goals"""
        goals = self.db.query(SportGoals).filter(
            SportGoals.user_id == user_id,
            SportGoals.sport == sport
        ).first()

        if not goals:
            return AICoachInsight(
                user_id=user_id,
                sport=sport,
                insight_type="training",
                priority="medium",
                title="Set Your Goals",
                message="Complete the goals survey to get personalized training recommendations!",
                suggested_actions=[
                    "Complete goals survey in settings",
                    "Identify your focus areas",
                    "Set improvement priorities"
                ],
                confidence=1.0
            )

        # Check if goals were recently updated
        if goals.updated_at and (datetime.now() - goals.updated_at).days < 7:
            return None  # Don't nag about new goals

        # Analyze progress on priority skills
        if goals.improvement_priority:
            top_priority_skill = max(goals.improvement_priority, key=goals.improvement_priority.get)
            priority_level = goals.improvement_priority[top_priority_skill]

            # Check recent training focus
            recent_drills = self._get_recent_drill_focus(user_id, sport)

            if top_priority_skill not in recent_drills:
                return AICoachInsight(
                    user_id=user_id,
                    sport=sport,
                    insight_type="training",
                    priority="medium",
                    title=f"Focus on {top_priority_skill.replace('_', ' ').title()}",
                    message=f"You marked {top_priority_skill} as a priority (level {priority_level}/5), "
                            f"but haven't practiced it recently.",
                    suggested_actions=[
                        f"Practice {top_priority_skill} drills today",
                        "Track your progress",
                        "Review technique videos"
                    ],
                    drills_recommended=self._get_drills_for_skill(top_priority_skill, sport),
                    confidence=0.8
                )

        return None

    def _get_recent_drill_focus(self, user_id: UUID, sport: models.Sport) -> List[str]:
        """Get skills user has practiced recently"""
        # This would integrate with drill tracking system
        # For now, return empty list
        return []

    def _get_priority_focus_areas(self, goals: Optional[SportGoals]) -> List[str]:
        """Get priority focus areas from goals"""
        if not goals:
            return []

        focus_areas = []

        if goals.skill_focus:
            focus_areas.extend(goals.skill_focus[:3])

        if goals.physical_focus:
            focus_areas.extend(goals.physical_focus[:2])

        return focus_areas[:5]

    # MARK: - Tournament Analysis

    def _check_upcoming_tournaments(self, user_id: UUID, sport: models.Sport) -> Optional[AICoachInsight]:
        """Check for upcoming tournaments and provide prep advice"""
        tournaments = self._get_upcoming_tournaments(user_id, sport)

        if not tournaments:
            return None

        nearest_tournament = tournaments[0]
        days_until = (nearest_tournament.starts_at - datetime.now()).days

        if days_until <= 3:
            recovery_score = self._get_recovery_score(user_id)

            message = f"Tournament '{nearest_tournament.name}' starts in {days_until} days. "

            if recovery_score and recovery_score < 60:
                message += "Your recovery is below optimal - prioritize rest and light training."
                priority = "high"
                actions = [
                    "Reduce training intensity",
                    "Focus on sleep and nutrition",
                    "Light skill work only",
                    "Mental preparation and visualization"
                ]
            else:
                message += "Your recovery is good - maintain current preparation."
                priority = "medium"
                actions = [
                    "Practice match scenarios",
                    "Review opponent strategies",
                    "Maintain sleep schedule",
                    "Prepare equipment and logistics"
                ]

            return AICoachInsight(
                user_id=user_id,
                sport=sport,
                insight_type="match_prep",
                priority=priority,
                title=f"Tournament Prep: {days_until} Days to Go",
                message=message,
                details={
                    "tournament_id": str(nearest_tournament.id),
                    "tournament_name": nearest_tournament.name,
                    "days_until": days_until,
                    "recovery_score": recovery_score
                },
                suggested_actions=actions,
                confidence=0.85,
                expires_at=nearest_tournament.starts_at
            )

        return None

    def _get_upcoming_tournaments(self, user_id: UUID, sport: models.Sport) -> List[Tournament]:
        """Get user's upcoming tournaments"""
        participants = self.db.query(TournamentParticipant).filter(
            TournamentParticipant.user_id == user_id
        ).all()

        tournament_ids = [p.tournament_id for p in participants]

        tournaments = self.db.query(Tournament).filter(
            Tournament.id.in_(tournament_ids),
            Tournament.sport == sport,
            Tournament.starts_at > datetime.now()
        ).order_by(Tournament.starts_at.asc()).all()

        return tournaments

    # MARK: - Skill Development

    def _suggest_skill_development(self, user_id: UUID, sport: models.Sport) -> Optional[AICoachInsight]:
        """Suggest next skill to develop"""
        weaknesses = self._identify_skill_weaknesses(user_id, sport)

        if not weaknesses:
            return None

        # Get top weakness
        top_weakness = weaknesses[0]

        drills = self._get_drills_for_skill(top_weakness["skill"], sport)

        return AICoachInsight(
            user_id=user_id,
            sport=sport,
            insight_type="training",
            priority="medium",
            title=f"Improve Your {top_weakness['skill'].replace('_', ' ').title()}",
            message=f"Analysis shows {top_weakness['skill']} is a development opportunity. "
                    f"Focusing here could significantly improve your game.",
            details=top_weakness,
            drills_recommended=[d["name"] for d in drills[:3]],
            suggested_actions=[
                f"Practice {top_weakness['skill']} drills 3x this week",
                "Record a session to review technique",
                "Ask for feedback from higher-ranked players"
            ],
            confidence=0.75
        )

    def _identify_skill_weaknesses(self, user_id: UUID, sport: models.Sport) -> List[Dict]:
        """Identify skill weaknesses from match data"""
        # This would analyze match statistics
        # For now, return placeholder
        return [
            {"skill": "shooting", "confidence": 0.65, "reason": "Lower accuracy in close matches"},
            {"skill": "defense", "confidence": 0.60, "reason": "Higher points allowed vs stronger opponents"}
        ]

    def _get_drills_for_weaknesses(self, weaknesses: List[Dict], sport: models.Sport) -> List[str]:
        """Get drill names for weaknesses"""
        drill_names = []

        for weakness in weaknesses[:2]:
            drills = self._get_drills_for_skill(weakness["skill"], sport)
            drill_names.extend([d["name"] for d in drills[:2]])

        return drill_names

    def _get_drills_for_skill(self, skill: str, sport: models.Sport) -> List[Dict]:
        """Get drills for specific skill"""
        # Master drill database - would be much larger in production
        drills_db = {
            models.Sport.BASKETBALL: {
                "shooting": [
                    {"name": "Form Shooting (10 min)", "intensity": "low", "description": "Close-range form work"},
                    {"name": "Spot Shooting (15 min)", "intensity": "medium", "description": "5 spots around arc"},
                    {"name": "Game Situation Shooting (20 min)", "intensity": "high", "description": "Off screens, cuts, dribble"}
                ],
                "dribbling": [
                    {"name": "Stationary Ball Handling (10 min)", "intensity": "low", "description": "Pound dribbles, figure 8"},
                    {"name": "Two Ball Dribbling (15 min)", "intensity": "medium", "description": "Coordination work"},
                    {"name": "Full Court Dribbling (20 min)", "intensity": "high", "description": "Game speed moves"}
                ],
                "defense": [
                    {"name": "Defensive Slides (10 min)", "intensity": "medium", "description": "Lateral movement"},
                    {"name": "Closeout Drills (15 min)", "intensity": "high", "description": "Sprint and contest"},
                    {"name": "1v1 Defense (20 min)", "intensity": "high", "description": "Live defense practice"}
                ]
            },
            models.Sport.FOOTBALL: {
                "throwing": [
                    {"name": "Target Practice (15 min)", "intensity": "low", "description": "Accuracy work"},
                    {"name": "Route Timing (20 min)", "intensity": "medium", "description": "Timing with receivers"},
                    {"name": "Game Simulation (30 min)", "intensity": "high", "description": "Full plays"}
                ],
                "catching": [
                    {"name": "Hands Drills (10 min)", "intensity": "low", "description": "Ball security"},
                    {"name": "Route Running (20 min)", "intensity": "medium", "description": "Catch in stride"},
                    {"name": "Contested Catches (15 min)", "intensity": "high", "description": "With defender"}
                ]
            },
            models.Sport.SOCCER: {
                "ball_control": [
                    {"name": "Cone Dribbling (15 min)", "intensity": "low", "description": "Touch and control"},
                    {"name": "Juggling (10 min)", "intensity": "low", "description": "Touch consistency"},
                    {"name": "Tight Space Control (20 min)", "intensity": "medium", "description": "Pressure situations"}
                ],
                "passing": [
                    {"name": "Wall Passing (10 min)", "intensity": "low", "description": "Accuracy and first touch"},
                    {"name": "Partner Passing (20 min)", "intensity": "medium", "description": "Various distances"},
                    {"name": "Game Speed Passing (25 min)", "intensity": "high", "description": "Under pressure"}
                ]
            },
            models.Sport.TENNIS: {
                "serve": [
                    {"name": "Service Motion (15 min)", "intensity": "low", "description": "Form and consistency"},
                    {"name": "Target Serving (20 min)", "intensity": "medium", "description": "Placement work"},
                    {"name": "Game Situation Serves (25 min)", "intensity": "high", "description": "First and second serves"}
                ],
                "forehand": [
                    {"name": "Forehand Form (15 min)", "intensity": "low", "description": "Technique focus"},
                    {"name": "Rally Forehand (20 min)", "intensity": "medium", "description": "Consistency work"},
                    {"name": "Aggressive Forehand (25 min)", "intensity": "high", "description": "Power and placement"}
                ]
            }
        }

        sport_drills = drills_db.get(sport, {})
        return sport_drills.get(skill, [])

    def _select_drills_for_goals(self, goals: Optional[SportGoals], sport: models.Sport, intensity: str) -> List[Dict]:
        """Select drills based on goals and intensity"""
        if not goals or not goals.skill_focus:
            return []

        drills = []

        for skill in goals.skill_focus[:3]:
            skill_drills = self._get_drills_for_skill(skill, sport)

            # Filter by intensity
            matching_drills = [d for d in skill_drills if d["intensity"] == intensity]

            if matching_drills:
                drills.append(matching_drills[0])

        return drills

    def _get_sport_drills(self, sport: models.Sport) -> List[Dict]:
        """Get all drills for a sport"""
        all_drills = []

        skills = ["shooting", "dribbling", "defense", "passing", "ball_control"]

        for skill in skills:
            all_drills.extend(self._get_drills_for_skill(skill, sport))

        return all_drills

    def _score_drill_relevance(self, drill: Dict, goals: Optional[SportGoals], weaknesses: List[Dict]) -> float:
        """Score how relevant a drill is for user"""
        score = 0.0

        # Match with goals
        if goals and goals.skill_focus:
            for skill in goals.skill_focus:
                if skill in drill.get("name", "").lower():
                    score += 3.0

        # Match with weaknesses
        for weakness in weaknesses:
            if weakness["skill"] in drill.get("name", "").lower():
                score += weakness["confidence"] * 5.0

        return score

    # MARK: - Sleep Analysis

    def _get_sleep_quality_score(self, user_id: UUID) -> Optional[float]:
        """Get sleep quality score (0-100)"""
        # Get last 3 nights
        three_days_ago = datetime.now() - timedelta(days=3)

        biometric_data = self.db.query(BiometricData).filter(
            BiometricData.user_id == user_id,
            BiometricData.date >= three_days_ago
        ).all()

        sleep_scores = [b.sleep_quality_score for b in biometric_data if b.sleep_quality_score]

        if not sleep_scores:
            return None

        return statistics.mean(sleep_scores)

    def _calculate_sleep_factor(self, user_id: UUID) -> float:
        """Calculate sleep contribution (-10 to +10)"""
        sleep_score = self._get_sleep_quality_score(user_id)

        if not sleep_score:
            return 0.0

        return (sleep_score - 50) / 5.0

    # MARK: - Mental Readiness

    def _estimate_mental_readiness(self, user_id: UUID, sport: models.Sport) -> Optional[float]:
        """Estimate mental readiness (0-100)"""
        # Based on recent performance and confidence
        recent_performance = self._get_recent_performance_score(user_id, sport)

        if not recent_performance:
            return None

        # Higher recent performance = higher mental readiness
        return recent_performance

    def _calculate_stress_factor(self, user_id: UUID, sport: models.Sport) -> float:
        """Calculate stress level impact (-10 to +10)"""
        # Based on match frequency and performance pressure
        week_ago = datetime.now() - timedelta(days=7)

        recent_matches = self.db.query(models.Match).filter(
            models.Match.sport == sport,
            models.Match.created_at >= week_ago
        ).filter(
            (models.Match.player1_id == user_id) | (models.Match.player2_id == user_id)
        ).count()

        # Moderate activity = low stress
        # Too much or too little = higher stress
        if 5 <= recent_matches <= 12:
            return 1.0  # Low stress
        elif recent_matches > 20:
            return -3.0  # High stress from overload
        else:
            return -1.0  # Mild stress from inactivity

    # MARK: - ELO Analysis

    def _calculate_elo_factor(self, user_elo: int, opponent_elo: int) -> float:
        """Calculate ELO difference impact (-10 to +10)"""
        elo_diff = user_elo - opponent_elo

        # +200 ELO = +4 performance bonus
        # -200 ELO = -4 performance penalty
        return elo_diff / 50.0

    # MARK: - Training Plan Generation

    def _determine_training_intensity(
        self,
        day_number: int,
        recovery_score: Optional[float],
        upcoming_tournaments: List[Tournament]
    ) -> str:
        """Determine training intensity for the day"""
        # Check for tournament proximity
        if upcoming_tournaments:
            days_to_tournament = (upcoming_tournaments[0].starts_at - datetime.now()).days

            # Taper before tournament
            if days_to_tournament <= 2:
                return "low"
            elif days_to_tournament <= 5:
                return "medium"

        # Check recovery
        if recovery_score:
            if recovery_score < 40:
                return "low"
            elif recovery_score > 80:
                return "high"

        # Weekly pattern: Hard-Easy-Medium-Hard-Easy-Medium-Rest
        pattern = ["high", "low", "medium", "high", "low", "medium", "low"]
        return pattern[day_number % 7]

    def _calculate_session_duration(self, intensity: str) -> int:
        """Calculate training session duration in minutes"""
        durations = {
            "low": 45,
            "medium": 75,
            "high": 90
        }
        return durations.get(intensity, 60)

    def _generate_daily_notes(
        self,
        day_number: int,
        recovery_score: Optional[float],
        upcoming_tournaments: List[Tournament]
    ) -> str:
        """Generate notes for daily training"""
        notes = []

        if upcoming_tournaments:
            days_to_tournament = (upcoming_tournaments[0].starts_at - datetime.now()).days
            if days_to_tournament <= 7:
                notes.append(f"Tournament in {days_to_tournament} days - focus on match readiness")

        if recovery_score:
            if recovery_score < 50:
                notes.append("Recovery below optimal - listen to your body")
            elif recovery_score > 85:
                notes.append("Great recovery - push yourself today")

        if day_number % 7 == 6:
            notes.append("Active recovery or rest day")

        return " | ".join(notes) if notes else "Standard training day"

    def _get_weekly_focus(self, goals: Optional[SportGoals]) -> str:
        """Get weekly focus area"""
        if not goals or not goals.skill_focus:
            return "General skill development"

        return f"Primary: {goals.skill_focus[0].replace('_', ' ').title()}"

    def _get_progression_strategy(self, goals: Optional[SportGoals]) -> str:
        """Get progression strategy"""
        return "Progressive overload - increase difficulty weekly while monitoring recovery"

    # MARK: - Prediction Helpers

    def _calculate_prediction_confidence(self, user_id: UUID) -> float:
        """Calculate confidence in prediction (0-1)"""
        # Based on data availability
        confidence = 0.5  # Base confidence

        # Boost for smartwatch data
        connection = self.db.query(SmartwatchConnection).filter(
            SmartwatchConnection.user_id == user_id
        ).first()

        if connection and connection.is_connected:
            confidence += 0.2

        # Boost for match history
        match_count = self.db.query(models.Match).filter(
            (models.Match.player1_id == user_id) | (models.Match.player2_id == user_id)
        ).count()

        if match_count > 10:
            confidence += 0.15
        if match_count > 50:
            confidence += 0.10

        # Boost for goals data
        goals_count = self.db.query(SportGoals).filter(
            SportGoals.user_id == user_id
        ).count()

        if goals_count > 0:
            confidence += 0.05

        return min(1.0, confidence)

    def _create_default_prediction(self, user_id: UUID, sport: models.Sport) -> PerformancePrediction:
        """Create default prediction with limited data"""
        return PerformancePrediction(
            user_id=user_id,
            sport=sport,
            prediction_date=datetime.now(),
            prediction_type="match",
            performance_index=0.0,
            readiness_score=70.0,
            confidence=0.3,
            factors={
                "recovery": 0.0,
                "recent_performance": 0.0,
                "training_load": 0.0,
                "sleep_quality": 0.0,
                "stress_level": 0.0
            }
        )
