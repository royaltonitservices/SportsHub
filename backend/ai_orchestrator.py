"""
AI Orchestration Layer for SportsHub
External AI model integration (GPT-4.1) with context aggregation

This module provides:
- Conversational AI Coach (Premium feature)
- Drill generation (Regular AI - all users)
- Challenge generation (Regular AI - all users)
- Training analysis
- Context-aware AI responses

Architecture:
- External models (OpenAI GPT-4.1)
- Backend orchestration (this file)
- Deterministic rules (elo_service.py, ai_coach.py)
"""
from openai import OpenAI
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from uuid import UUID
import json

from config import get_settings
import models
from models_premium import BiometricData, SportGoals, Subscription, SmartwatchConnection


class AIOrchestrator:
    """
    Master AI orchestration service.

    Responsibilities:
    1. Context aggregation (user data, wearable signals, training history, goals)
    2. Prompt generation for different AI tasks
    3. External AI model calls (GPT-4.1)
    4. Response parsing and structuring
    5. Fallback to template-based systems when API fails
    """

    def __init__(self, db: Session):
        self.db = db
        self.settings = get_settings()
        self.client = OpenAI(api_key=self.settings.openai_api_key)

    # MARK: - Conversational AI Coach (Premium)

    async def generate_coach_response(
        self,
        user_id: UUID,
        sport: models.Sport,
        user_message: str,
        conversation_history: List[Dict[str, str]] = None
    ) -> Dict[str, str]:
        """
        Generate conversational AI Coach response (Premium feature).

        This is the main Premium AI feature - a conversational sports coach
        that feels like texting with a real mentor.

        Args:
            user_id: User UUID
            sport: Current sport context
            user_message: User's message to the coach
            conversation_history: Previous messages in conversation

        Returns:
            {
                "response": "Coach's response text",
                "suggested_actions": ["action1", "action2"],
                "tone": "supportive|motivating|concerned",
                "follow_up_questions": ["question1"]
            }
        """
        # Aggregate all context
        context = self._aggregate_user_context(user_id, sport)

        # Build conversational prompt
        system_prompt = self._build_coach_system_prompt(sport)
        messages = self._build_conversation_messages(
            system_prompt=system_prompt,
            context=context,
            user_message=user_message,
            history=conversation_history
        )

        try:
            # Call GPT-4.1
            response = self.client.chat.completions.create(
                model=self.settings.openai_model,
                messages=messages,
                max_tokens=self.settings.openai_max_tokens,
                temperature=self.settings.openai_temperature
            )

            coach_response = response.choices[0].message.content

            # Parse structured response
            parsed = self._parse_coach_response(coach_response)

            return parsed

        except Exception as e:
            print(f"[AI Orchestrator] GPT-4.1 call failed: {e}")
            # Fallback to template-based response
            return self._fallback_coach_response(user_message, context)

    async def generate_proactive_checkin(
        self,
        user_id: UUID,
        sport: models.Sport
    ) -> Optional[str]:
        """
        Generate proactive AI Coach check-in.

        Instead of "All caught up", the AI proactively asks:
        - "How are you feeling today?"
        - "Ready for today's training?"
        - "How did your match go yesterday?"

        Returns None if no proactive message is needed.
        """
        context = self._aggregate_user_context(user_id, sport)

        # Check if user needs proactive engagement
        should_engage, trigger = self._should_proactively_engage(context)

        if not should_engage:
            return None

        prompt = f"""You are a supportive sports coach. Based on this trigger: {trigger}

User context:
- Recent recovery score: {context.get('recovery_score')}
- Recent matches: {context.get('recent_match_count')} in last 7 days
- Last match: {context.get('last_match_result')}
- Goals: {context.get('goals_summary')}

Generate a brief, natural check-in message (1-2 sentences max).
Be conversational, supportive, and genuinely interested.
Start with "Hey" or similar casual greeting.

Examples:
- "Hey! How are you feeling after yesterday's match?"
- "Morning! Ready to tackle today's training?"
- "Hey! Noticed your recovery score is a bit low. How's your body feeling?"
"""

        try:
            response = self.client.chat.completions.create(
                model=self.settings.openai_model,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=100,
                temperature=0.8
            )

            return response.choices[0].message.content.strip()

        except:
            # Fallback templates
            fallback_messages = [
                "Hey! How are you feeling today?",
                "Ready for today's training?",
                "How's your energy level today?"
            ]
            return fallback_messages[0]

    # MARK: - Regular AI - Drill Generation (All Users)

    async def generate_personalized_drill(
        self,
        user_id: UUID,
        sport: models.Sport,
        focus_skill: Optional[str] = None,
        difficulty: Optional[str] = None,
        duration_minutes: int = 20
    ) -> Dict:
        """
        Generate personalized drill using AI (available to all users).

        This is Regular AI - not premium gated.
        Creates unique, sport-specific drills tailored to user's level.

        Returns:
            {
                "name": "Drill name",
                "description": "What this drill develops",
                "duration": 20,
                "difficulty": "intermediate",
                "instructions": ["Step 1", "Step 2", ...],
                "equipment_needed": ["ball", "cones"],
                "tips": ["Tip 1", "Tip 2"]
            }
        """
        context = self._aggregate_user_context(user_id, sport)

        # Get user's skill level
        sport_profile = self.db.query(models.SportProfile).filter(
            models.SportProfile.user_id == user_id,
            models.SportProfile.sport == sport
        ).first()

        user_level = self._determine_skill_level(sport_profile)

        prompt = f"""Generate a unique {sport.value} training drill.

User Profile:
- Skill level: {user_level}
- ELO rating: {sport_profile.elo_rating if sport_profile else 'N/A'}
- Games played: {sport_profile.games_played if sport_profile else 0}
- Focus skill: {focus_skill or 'general'}
- Requested difficulty: {difficulty or 'appropriate for level'}
- Duration: {duration_minutes} minutes

Requirements:
- Create a NEW, creative drill (not generic)
- Match the user's skill level
- Focus on {focus_skill if focus_skill else 'overall skill development'}
- Include clear, actionable steps
- Specify needed equipment
- Add coaching tips

Return as JSON:
{{
    "name": "Drill name",
    "description": "Brief description",
    "duration": {duration_minutes},
    "difficulty": "beginner|intermediate|advanced",
    "instructions": ["step 1", "step 2", ...],
    "equipment_needed": ["item1", "item2"],
    "tips": ["tip1", "tip2"],
    "skill_focus": "primary skill this develops"
}}
"""

        try:
            response = self.client.chat.completions.create(
                model=self.settings.openai_model,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=800,
                temperature=0.9  # Higher creativity for drill generation
            )

            drill_json = response.choices[0].message.content
            # Extract JSON from markdown code blocks if present
            if "```json" in drill_json:
                drill_json = drill_json.split("```json")[1].split("```")[0].strip()
            elif "```" in drill_json:
                drill_json = drill_json.split("```")[1].split("```")[0].strip()

            drill = json.loads(drill_json)
            return drill

        except Exception as e:
            print(f"[AI Orchestrator] Drill generation failed: {e}")
            # Fallback to template-based drill from ai_services.py
            from ai_services import DrillGenerator
            return DrillGenerator.generate_drills(
                sport=sport.value,
                user_level=user_level,
                focus_areas=[focus_skill] if focus_skill else None,
                duration_minutes=duration_minutes
            )[0] if DrillGenerator.generate_drills(sport.value, user_level) else {}

    async def generate_challenge(
        self,
        user_id: UUID,
        sport: models.Sport,
        challenge_type: str = "skill"  # skill, fitness, accuracy, speed
    ) -> Dict:
        """
        Generate AI-powered challenge (available to all users).

        Creates engaging, gamified challenges that push users to improve.

        Returns:
            {
                "title": "Challenge name",
                "description": "What to do",
                "goal": "Success criteria",
                "difficulty": "intermediate",
                "estimated_time": 30,
                "reward_points": 50,
                "instructions": ["step 1", "step 2"],
                "success_metric": "Score 8/10 shots from 3-point line"
            }
        """
        context = self._aggregate_user_context(user_id, sport)

        prompt = f"""Create an engaging {sport.value} challenge for a user.

Challenge Type: {challenge_type}
User Level: {context.get('skill_level', 'intermediate')}
Recent Performance: {context.get('win_rate', 0.5) * 100:.0f}% win rate

Create a challenge that:
- Is fun and gamified
- Pushes the user to improve
- Has clear success criteria
- Takes 20-45 minutes
- Is achievable but challenging

Return as JSON:
{{
    "title": "Catchy challenge name",
    "description": "What this challenge involves",
    "goal": "What success looks like",
    "difficulty": "beginner|intermediate|advanced",
    "estimated_time": 30,
    "reward_points": 50,
    "instructions": ["step 1", "step 2", ...],
    "success_metric": "Specific measurable goal"
}}
"""

        try:
            response = self.client.chat.completions.create(
                model=self.settings.openai_model,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=600,
                temperature=0.85
            )

            challenge_json = response.choices[0].message.content
            if "```json" in challenge_json:
                challenge_json = challenge_json.split("```json")[1].split("```")[0].strip()
            elif "```" in challenge_json:
                challenge_json = challenge_json.split("```")[1].split("```")[0].strip()

            return json.loads(challenge_json)

        except Exception as e:
            print(f"[AI Orchestrator] Challenge generation failed: {e}")
            return self._fallback_challenge(sport, challenge_type)

    # MARK: - Training Analysis (Premium)

    async def analyze_training_session(
        self,
        user_id: UUID,
        sport: models.Sport,
        session_data: Dict
    ) -> Dict:
        """
        Analyze training session using AI (Premium feature).

        Args:
            session_data: {
                "drills_completed": [...],
                "duration_minutes": 60,
                "perceived_difficulty": "hard",
                "notes": "Felt tired"
            }

        Returns:
            {
                "performance_rating": 7.5,
                "insights": ["You maintained good intensity", ...],
                "areas_to_improve": ["Rest more between sets"],
                "next_session_recommendations": [...]
            }
        """
        context = self._aggregate_user_context(user_id, sport)

        prompt = f"""Analyze this training session for a {sport.value} athlete.

Session Data:
{json.dumps(session_data, indent=2)}

Athlete Context:
- Recovery score: {context.get('recovery_score', 'N/A')}
- Recent win rate: {context.get('win_rate', 0.5) * 100:.0f}%
- Training volume (last 7 days): {context.get('recent_match_count', 0)} sessions

Provide:
1. Performance rating (0-10)
2. 2-3 positive insights
3. 1-2 areas to improve
4. Recommendations for next session

Be encouraging and constructive. Focus on progress, not criticism.

Return as JSON:
{{
    "performance_rating": 7.5,
    "insights": ["insight 1", "insight 2"],
    "areas_to_improve": ["area 1"],
    "next_session_recommendations": ["rec 1", "rec 2"]
}}
"""

        try:
            response = self.client.chat.completions.create(
                model=self.settings.openai_model,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=600,
                temperature=0.7
            )

            analysis_json = response.choices[0].message.content
            if "```json" in analysis_json:
                analysis_json = analysis_json.split("```json")[1].split("```")[0].strip()

            return json.loads(analysis_json)

        except:
            return {
                "performance_rating": 7.0,
                "insights": ["Good effort in training session"],
                "areas_to_improve": ["Continue building consistency"],
                "next_session_recommendations": ["Maintain current intensity"]
            }

    # MARK: - Context Aggregation

    def _aggregate_user_context(self, user_id: UUID, sport: models.Sport) -> Dict:
        """
        Aggregate all relevant user data for AI context.

        This is the "secret sauce" - collecting all signals:
        - User profile and sport stats
        - Wearable data (recovery, sleep, HRV)
        - Training history
        - Goals and priorities
        - Recent performance
        - Upcoming events
        """
        context = {}

        # 1. Sport Profile
        sport_profile = self.db.query(models.SportProfile).filter(
            models.SportProfile.user_id == user_id,
            models.SportProfile.sport == sport
        ).first()

        if sport_profile:
            context['elo_rating'] = sport_profile.elo_rating
            context['games_played'] = sport_profile.games_played
            context['wins'] = sport_profile.wins
            context['losses'] = sport_profile.losses
            context['win_rate'] = sport_profile.wins / max(sport_profile.games_played, 1)
            context['skill_level'] = self._determine_skill_level(sport_profile)

        # 2. Wearable Data
        today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        biometric = self.db.query(BiometricData).filter(
            BiometricData.user_id == user_id,
            BiometricData.date >= today
        ).first()

        if biometric:
            context['recovery_score'] = biometric.readiness_score
            context['sleep_quality'] = biometric.sleep_quality_score
            context['hrv'] = biometric.heart_rate_variability
            context['fatigue_level'] = biometric.fatigue_level
            context['sleep_duration'] = biometric.sleep_duration

        # 3. Goals
        goals = self.db.query(SportGoals).filter(
            SportGoals.user_id == user_id,
            SportGoals.sport == sport
        ).first()

        if goals:
            context['goals_summary'] = goals.goal_statement
            context['skill_focus'] = goals.skill_focus
            context['improvement_priority'] = goals.improvement_priority

        # 4. Recent Activity
        week_ago = datetime.now() - timedelta(days=7)
        recent_matches = self.db.query(models.Match).filter(
            models.Match.sport == sport,
            models.Match.created_at >= week_ago
        ).filter(
            (models.Match.player1_id == user_id) | (models.Match.player2_id == user_id)
        ).all()

        context['recent_match_count'] = len(recent_matches)

        if recent_matches:
            last_match = recent_matches[0]
            context['last_match_result'] = 'win' if last_match.winner_id == user_id else 'loss'
            context['last_match_date'] = last_match.created_at.isoformat()

        # 5. Premium Status
        subscription = self.db.query(Subscription).filter(
            Subscription.user_id == user_id,
            Subscription.status == "active"
        ).first()

        context['is_premium'] = subscription is not None

        return context

    def _build_coach_system_prompt(self, sport: models.Sport) -> str:
        """Build system prompt for conversational AI Coach"""
        return f"""You are an expert {sport.value} coach with years of experience.

Your personality:
- Supportive and encouraging (never critical or harsh)
- Motivating and energetic
- Knowledgeable about {sport.value} technique and strategy
- Genuinely interested in the athlete's progress
- Conversational and natural (like texting a mentor)

Communication style:
- Use "you" and "your" (personal)
- Keep responses 2-4 sentences unless asked for detail
- Ask follow-up questions to show interest
- Celebrate wins, support through losses
- Give actionable advice, not just theory

Topics you can discuss:
- Training and technique
- Match preparation and strategy
- Recovery and injury prevention
- Goal setting and progress
- Mental game and confidence
- Equipment and gear

IMPORTANT:
- Never be critical or discouraging
- If user is struggling, empathize then suggest solutions
- Focus on progress over perfection
- Acknowledge effort, not just results"""

    def _build_conversation_messages(
        self,
        system_prompt: str,
        context: Dict,
        user_message: str,
        history: Optional[List[Dict[str, str]]]
    ) -> List[Dict[str, str]]:
        """Build message array for GPT-4.1 API"""
        messages = [{"role": "system", "content": system_prompt}]

        # Add context as system message
        context_summary = self._format_context_for_prompt(context)
        messages.append({
            "role": "system",
            "content": f"Current athlete context:\n{context_summary}"
        })

        # Add conversation history
        if history:
            messages.extend(history[-10:])  # Last 10 messages for context

        # Add current user message
        messages.append({"role": "user", "content": user_message})

        return messages

    def _format_context_for_prompt(self, context: Dict) -> str:
        """Format context dictionary into readable string for prompt"""
        parts = []

        if 'elo_rating' in context:
            parts.append(f"ELO Rating: {context['elo_rating']}")
        if 'games_played' in context:
            parts.append(f"Games played: {context['games_played']}")
        if 'win_rate' in context:
            parts.append(f"Win rate: {context['win_rate'] * 100:.0f}%")
        if 'recovery_score' in context:
            parts.append(f"Recovery score: {context['recovery_score']:.0f}/100")
        if 'sleep_quality' in context:
            parts.append(f"Sleep quality: {context['sleep_quality']:.0f}/100")
        if 'recent_match_count' in context:
            parts.append(f"Matches this week: {context['recent_match_count']}")
        if 'last_match_result' in context:
            parts.append(f"Last match: {context['last_match_result']}")
        if 'goals_summary' in context:
            parts.append(f"Goal: {context['goals_summary']}")

        return "\n".join(parts) if parts else "Limited context available"

    def _parse_coach_response(self, response: str) -> Dict[str, any]:
        """Parse AI response into structured format"""
        return {
            "response": response,
            "suggested_actions": [],  # Could extract if AI formats them
            "tone": "supportive",
            "follow_up_questions": []
        }

    def _should_proactively_engage(self, context: Dict) -> Tuple[bool, str]:
        """Determine if AI should proactively check in"""
        # Low recovery
        if context.get('recovery_score', 100) < 40:
            return True, "low_recovery"

        # Recent match
        if context.get('last_match_date'):
            last_match = datetime.fromisoformat(context['last_match_date'])
            if (datetime.now() - last_match).days <= 1:
                return True, "recent_match"

        # High activity
        if context.get('recent_match_count', 0) > 10:
            return True, "high_volume"

        # No recent activity
        if context.get('recent_match_count', 0) == 0:
            return True, "inactive"

        return False, ""

    def _determine_skill_level(self, sport_profile: Optional[models.SportProfile]) -> str:
        """Determine skill level from ELO and games played"""
        if not sport_profile:
            return "beginner"

        if sport_profile.games_played < 5:
            return "beginner"
        elif sport_profile.elo_rating < 1200:
            return "beginner"
        elif sport_profile.elo_rating < 1600:
            return "intermediate"
        else:
            return "advanced"

    # MARK: - Fallback Responses

    def _fallback_coach_response(self, user_message: str, context: Dict) -> Dict:
        """Template-based fallback when API fails"""
        return {
            "response": "I'm here to help you improve! What would you like to work on today?",
            "suggested_actions": ["Practice fundamentals", "Review your goals"],
            "tone": "supportive",
            "follow_up_questions": ["What's your main focus right now?"]
        }

    def _fallback_challenge(self, sport: models.Sport, challenge_type: str) -> Dict:
        """Template-based challenge fallback"""
        challenges = {
            models.Sport.BASKETBALL: {
                "title": "Shooting Streak Challenge",
                "description": "Test your shooting consistency",
                "goal": "Make 15 shots in a row from free throw line",
                "difficulty": "intermediate",
                "estimated_time": 20,
                "reward_points": 50,
                "instructions": [
                    "Start at free throw line",
                    "Make 15 consecutive shots",
                    "Reset counter if you miss"
                ],
                "success_metric": "15 consecutive made shots"
            }
        }

        return challenges.get(sport, challenges[models.Sport.BASKETBALL])
