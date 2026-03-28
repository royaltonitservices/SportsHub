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

        # Make OpenAI client optional - gracefully degrade if no API key
        try:
            if self.settings.openai_api_key and not self.settings.openai_api_key.startswith("sk-proj"):
                self.client = OpenAI(api_key=self.settings.openai_api_key)
                self.has_openai = True
            else:
                self.client = None
                self.has_openai = False
                print("[AI Orchestrator] OpenAI API key not configured - using template-based coaching")
        except Exception as e:
            self.client = None
            self.has_openai = False
            print(f"[AI Orchestrator] OpenAI initialization failed: {e} - using template-based coaching")

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
        # PRIORITY FIX 2: Update persistent coaching context from user message
        self._update_coach_context(user_id, sport, user_message)

        # Aggregate all context (includes saved coaching context now)
        context = self._aggregate_user_context(user_id, sport)

        # Load saved coaching context
        saved_context = self._load_coach_context_into_dict(user_id, sport)
        context.update(saved_context)

        # Build conversational prompt
        system_prompt = self._build_coach_system_prompt(sport)
        messages = self._build_conversation_messages(
            system_prompt=system_prompt,
            context=context,
            user_message=user_message,
            history=conversation_history
        )

        # Use OpenAI if available, otherwise use intelligent templates
        if self.has_openai and self.client:
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
                return self._fallback_coach_response(user_message, context, sport)
        else:
            # No OpenAI available - use intelligent template-based coaching
            return self._fallback_coach_response(user_message, context, sport)

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

    # MARK: - Coaching Context Management (PRIORITY FIX 2: Persistent Memory)

    def _get_or_create_coach_context(self, user_id: UUID, sport: models.Sport):
        """Get existing coaching context or create new one"""
        context = self.db.query(models.CoachContext).filter(
            models.CoachContext.user_id == user_id,
            models.CoachContext.sport == sport
        ).first()

        if not context:
            context = models.CoachContext(
                user_id=user_id,
                sport=sport,
                weak_points=[],
                goals=[],
                recent_recommendations=[],
                mentioned_skills=[]
            )
            self.db.add(context)
            self.db.commit()
            self.db.refresh(context)

        return context

    def _update_coach_context(self, user_id: UUID, sport: models.Sport, user_message: str):
        """Extract and save coaching context from user message"""
        context = self._get_or_create_coach_context(user_id, sport)
        msg_lower = user_message.lower()

        # Extract weak points
        weak_point_keywords = ['weak', 'struggle', 'bad at', 'need help with', 'not good at']
        if any(keyword in msg_lower for keyword in weak_point_keywords):
            # Try to extract the specific skill
            skills = self._get_sport_skills(sport)
            for skill in skills:
                if skill.lower() in msg_lower:
                    weak_points = json.loads(context.weak_points) if isinstance(context.weak_points, str) else context.weak_points
                    if skill.lower() not in [wp.lower() for wp in weak_points]:
                        weak_points.append(skill.lower())
                        context.weak_points = json.dumps(weak_points[-10:])  # Keep last 10

        # Extract goals
        goal_keywords = ['goal', 'want to', 'trying to', 'hoping to', 'working toward']
        if any(keyword in msg_lower for keyword in goal_keywords):
            goals = json.loads(context.goals) if isinstance(context.goals, str) else context.goals
            # Store the full goal statement (cleaned)
            goal_text = user_message.strip()
            if goal_text not in goals:
                goals.append(goal_text)
                context.goals = json.dumps(goals[-5:])  # Keep last 5 goals

        # Extract time preference
        time_match = None
        for num in ['5', '10', '15', '20', '30', '45', '60']:
            if num in user_message and 'minute' in msg_lower:
                time_match = int(num)
                break
        if time_match:
            context.preferred_training_duration = time_match

        # Update last interaction time
        context.last_interaction = datetime.now()
        context.updated_at = datetime.now()

        self.db.commit()
        return context

    def _save_recommendation(self, user_id: UUID, sport: models.Sport, recommendation: str):
        """Save a recommendation to avoid repeating it"""
        context = self._get_or_create_coach_context(user_id, sport)
        recent = json.loads(context.recent_recommendations) if isinstance(context.recent_recommendations, str) else context.recent_recommendations
        recent.append({
            'recommendation': recommendation[:200],  # Truncate
            'timestamp': datetime.now().isoformat()
        })
        context.recent_recommendations = json.dumps(recent[-5:])  # Keep last 5
        self.db.commit()

    def _load_coach_context_into_dict(self, user_id: UUID, sport: models.Sport) -> Dict:
        """Load saved coaching context into context dict for AI prompts"""
        coach_context = self._get_or_create_coach_context(user_id, sport)

        return {
            'saved_weak_points': json.loads(coach_context.weak_points) if isinstance(coach_context.weak_points, str) else coach_context.weak_points,
            'saved_goals': json.loads(coach_context.goals) if isinstance(coach_context.goals, str) else coach_context.goals,
            'preferred_duration': coach_context.preferred_training_duration,
            'training_focus': coach_context.training_focus,
            'recent_recommendations': json.loads(coach_context.recent_recommendations) if isinstance(coach_context.recent_recommendations, str) else coach_context.recent_recommendations
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
            context['elo_rating'] = sport_profile.rating
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
        elif sport_profile.rating < 1200:
            return "beginner"
        elif sport_profile.rating < 1600:
            return "intermediate"
        else:
            return "advanced"

    # MARK: - Fallback Responses

    def _fallback_coach_response(self, user_message: str, context: Dict, sport: models.Sport) -> Dict:
        """Intelligent template-based coaching when OpenAI unavailable"""
        msg_lower = user_message.lower()

        # Workout request - provide STRUCTURED, time-based workout plans
        if any(word in msg_lower for word in ['workout', 'train', 'practice', 'drill', 'exercise']):
            # Extract time duration
            time_match = None
            for num in ['5', '10', '15', '20', '30', '45', '60']:
                if num in user_message:
                    time_match = int(num)
                    break

            # Default to 20 minutes if not specified
            if not time_match:
                time_match = 20

            # Generate structured workout based on time and recovery
            recovery_score = context.get('recovery_score', 75)
            structured_workout = self._generate_structured_workout(
                sport=sport,
                duration_minutes=time_match,
                recovery_score=recovery_score,
                skill_level=context.get('skill_level', 'intermediate')
            )

            response = f"Here's your structured {time_match}-minute {sport.value} workout:\n\n"
            response += structured_workout
            response += f"\n\n💡 Tip: Focus on form over speed. You've got this!"

            return {
                "response": response,
                "suggested_actions": ["Open Train section", "Log this session"],
                "tone": "motivating",
                "follow_up_questions": ["How did the workout feel?"]
            }

        # Improvement/weakness focus
        if any(word in msg_lower for word in ['improve', 'better', 'weak', 'struggle', 'help with']):
            weak_point = self._extract_skill(msg_lower, sport)
            if weak_point:
                drills = self._get_skill_drills(sport, weak_point)
                response = f"Let's work on your {weak_point}! Here's what I recommend:\n\n"
                response += "\n".join(f"{i+1}. {drill}" for i, drill in enumerate(drills[:3]))
                response += f"\n\nFocus on quality over quantity - consistency is key!"
            else:
                response = f"I'd love to help you improve! What specific skill would you like to work on? Your main areas in {sport.value} could be:\n\n"
                response += "\n".join(f"• {skill}" for skill in self._get_sport_skills(sport)[:4])

            return {
                "response": response,
                "suggested_actions": ["View training drills", "Set a goal"],
                "tone": "supportive",
                "follow_up_questions": ["What feels most challenging for you?"]
            }

        # Recovery/tiredness
        if any(word in msg_lower for word in ['tired', 'sore', 'rest', 'recovery', 'fatigue']):
            recovery_score = context.get('recovery_score')
            if recovery_score and recovery_score < 50:
                response = "I noticed your recovery score is low. Your body's telling you something important! Consider:\n\n"
                response += "• Active recovery (light movement, stretching)\n"
                response += "• Extra sleep tonight\n"
                response += "• Proper hydration and nutrition\n\n"
                response += "Taking care of recovery is just as important as training hard."
            else:
                response = "It's smart to listen to your body! Here's what you can do:\n\n"
                response += "• Take a rest day if you need it\n"
                response += "• Try light active recovery\n"
                response += "• Focus on mobility work\n\n"
                response += "Recovery is when your body actually gets stronger!"

            return {
                "response": response,
                "suggested_actions": ["View recovery tips", "Track sleep"],
                "tone": "concerned",
                "follow_up_questions": ["How are you sleeping lately?"]
            }

        # Match prep
        if any(word in msg_lower for word in ['match', 'game', 'compete', 'tournament', 'opponent']):
            response = f"Let's get you ready! Here's your {sport.value} match prep:\n\n"
            response += "• Warm up thoroughly (15-20 mins)\n"
            response += "• Review your game plan and strategy\n"
            response += "• Focus on your strengths\n"
            response += "• Stay confident - you've put in the work!\n\n"
            response += "How are you feeling about your match?"

            return {
                "response": response,
                "suggested_actions": ["View pre-match routine", "Check opponent stats"],
                "tone": "motivating",
                "follow_up_questions": ["When is your match?"]
            }

        # General/greeting
        win_rate = context.get('win_rate', 0)
        recent_matches = context.get('recent_match_count', 0)
        last_result = context.get('last_match_result')

        if recent_matches > 0 and last_result == 'win':
            response = f"Great to hear from you! I saw you won your last match - nice work! What would you like to focus on today?"
        elif recent_matches > 0 and last_result == 'loss':
            response = f"Hey! Every match is a learning opportunity. What would you like to work on to come back stronger?"
        elif win_rate > 0.6:
            response = f"You're on a roll with a {win_rate*100:.0f}% win rate! What's next on your training agenda?"
        else:
            response = f"Ready to level up your {sport.value} game? I'm here to help! What would you like to work on?"

        return {
            "response": response,
            "suggested_actions": ["Get a workout", "Review my progress", "Set new goals"],
            "tone": "supportive",
            "follow_up_questions": ["What's your main focus this week?"]
        }

    def _get_sport_workouts(self, sport: models.Sport) -> List[str]:
        """Get sport-specific workout drills"""
        workouts = {
            models.Sport.BASKETBALL: [
                "Ball handling: 5 mins of figure-8s, between legs, behind back",
                "Shooting: 25 free throws, then 20 mid-range jumpers from 5 spots",
                "Conditioning: 10 suicide runs at game speed",
                "Defense: Defensive slides across court, 3 sets of 30 seconds"
            ],
            models.Sport.SOCCER: [
                "Dribbling: Cone weaving drill, both feet, increase speed gradually",
                "Passing: Wall passes for accuracy, 50 reps each foot",
                "Shooting: 20 shots from edge of box, focus on placement",
                "Conditioning: 10 x 40-yard sprints with 30 sec rest"
            ],
            models.Sport.TENNIS: [
                "Footwork: Ladder drills and cone sprints, 10 minutes",
                "Groundstrokes: 50 forehand, 50 backhand from baseline",
                "Serves: 30 first serves focusing on placement",
                "Volleys: 10 minutes at net, quick reactions"
            ],
            models.Sport.FOOTBALL: [
                "Throwing: 30 passes at various distances and angles",
                "Route running: 20 reps of different routes (slant, post, corner)",
                "Conditioning: 10 x 40-yard sprints with 45 sec rest",
                "Agility: Cone drills and ladder work, 15 minutes"
            ]
        }
        return workouts.get(sport, workouts[models.Sport.BASKETBALL])

    def _get_sport_skills(self, sport: models.Sport) -> List[str]:
        """Get main skills for a sport"""
        skills = {
            models.Sport.BASKETBALL: ["Shooting", "Ball handling", "Defense", "Passing"],
            models.Sport.SOCCER: ["Dribbling", "Passing", "Shooting", "Defense"],
            models.Sport.TENNIS: ["Serve", "Forehand", "Backhand", "Footwork"],
            models.Sport.FOOTBALL: ["Throwing", "Catching", "Route running", "Blocking"]
        }
        return skills.get(sport, skills[models.Sport.BASKETBALL])

    def _extract_skill(self, message: str, sport: models.Sport) -> Optional[str]:
        """Extract mentioned skill from message"""
        skills = self._get_sport_skills(sport)
        for skill in skills:
            if skill.lower() in message:
                return skill.lower()
        return None

    def _get_skill_drills(self, sport: models.Sport, skill: str) -> List[str]:
        """Get drills for specific skill"""
        basketball_drills = {
            "shooting": [
                "Form shooting from 5 feet (50 reps)",
                "Free throws (50 makes)",
                "Catch-and-shoot from 5 spots (10 each)",
                "Off-dribble pull-ups (20 reps)"
            ],
            "ball handling": [
                "Stationary dribbling (2 balls, 5 mins)",
                "Figure-8 dribbles through legs (3 mins)",
                "Full court dribbling with moves (5 trips)",
                "Change of pace/direction drills (10 mins)"
            ],
            "defense": [
                "Defensive slides (6 sets across court)",
                "Closeout drills (20 reps)",
                "1-on-1 positioning (practice with partner)",
                "Help and recover drills (10 mins)"
            ]
        }

        soccer_drills = {
            "dribbling": [
                "Cone weaving (both feet, 10 reps)",
                "Speed dribbling with cuts (5 lengths)",
                "1v1 moves against cone (20 reps)",
                "Tight space control (5x5 yard box, 5 mins)"
            ],
            "passing": [
                "Wall passes for accuracy (100 reps)",
                "Long passing (20 each foot)",
                "Through balls to target (20 attempts)",
                "One-touch passing triangles (10 mins)"
            ]
        }

        if sport == models.Sport.BASKETBALL:
            return basketball_drills.get(skill, basketball_drills["shooting"])
        elif sport == models.Sport.SOCCER:
            return soccer_drills.get(skill, soccer_drills["dribbling"])
        else:
            return ["Practice fundamentals with focus", "Watch technique videos", "Work with a coach if possible"]

    def _generate_structured_workout(
        self,
        sport: models.Sport,
        duration_minutes: int,
        recovery_score: float,
        skill_level: str
    ) -> str:
        """
        Generate a structured, time-allocated workout plan.
        This provides REAL value when live AI is unavailable.
        """
        # Adjust intensity based on recovery
        if recovery_score < 50:
            intensity = "light"
            intensity_note = "📊 Your recovery is low - taking it easier today"
        elif recovery_score < 70:
            intensity = "moderate"
            intensity_note = "📊 Moderate intensity based on your recovery"
        else:
            intensity = "full"
            intensity_note = "📊 Full intensity - your recovery looks good!"

        # Sport-specific structured workouts
        if sport == models.Sport.BASKETBALL:
            return self._basketball_structured_workout(duration_minutes, intensity, intensity_note, skill_level)
        elif sport == models.Sport.SOCCER:
            return self._soccer_structured_workout(duration_minutes, intensity, intensity_note, skill_level)
        elif sport == models.Sport.TENNIS:
            return self._tennis_structured_workout(duration_minutes, intensity, intensity_note, skill_level)
        elif sport == models.Sport.FOOTBALL:
            return self._football_structured_workout(duration_minutes, intensity, intensity_note, skill_level)
        else:
            return self._basketball_structured_workout(duration_minutes, intensity, intensity_note, skill_level)

    def _basketball_structured_workout(self, duration: int, intensity: str, note: str, level: str) -> str:
        """Structured basketball workout with time allocation"""
        if duration <= 15:
            return f"""{note}

**Warm-up** (3 min)
- Light jogging and dynamic stretches
- Arm circles and leg swings

**Ball Handling** (6 min)
- Figure-8 dribbles: 2 min
- Between-legs crossovers: 2 min
- Behind-back dribbles: 2 min

**Shooting** (5 min)
- Form shooting close range: 3 min
- Free throws: 2 min

**Cool-down** (1 min)
- Static stretching"""

        elif duration <= 30:
            warmup = int(duration * 0.15)
            skill1 = int(duration * 0.30)
            skill2 = int(duration * 0.30)
            conditioning = int(duration * 0.15)
            cooldown = duration - (warmup + skill1 + skill2 + conditioning)

            if intensity == "light":
                return f"""{note}

**Warm-up** ({warmup} min)
- Light movement and stretching

**Ball Handling** ({skill1} min)
- Stationary dribbling drills
- Controlled figure-8s
- Crossover practice

**Shooting** ({skill2} min)
- Form shooting from 5 feet
- Mid-range spot shooting
- Free throw practice

**Light Conditioning** ({conditioning} min)
- Half-court walk/jog
- Easy defensive slides

**Cool-down** ({cooldown} min)
- Stretching and breathing"""
            else:
                return f"""{note}

**Warm-up** ({warmup} min)
- Dynamic stretching and light jogging

**Ball Handling** ({skill1} min)
- Full-court dribbling with moves
- Speed dribbling
- Combo moves (crossover → behind-back)

**Shooting** ({skill2} min)
- Catch-and-shoot from 5 spots
- Off-dribble pull-ups
- Game-speed shooting

**Conditioning** ({conditioning} min)
- Suicide runs (3-4 sets)
- Defensive slide drills

**Cool-down** ({cooldown} min)
- Static stretching"""

        else:  # 30+ minutes
            warmup = 5
            skill1 = int(duration * 0.25)
            skill2 = int(duration * 0.25)
            skill3 = int(duration * 0.20)
            conditioning = int(duration * 0.15)
            cooldown = duration - (warmup + skill1 + skill2 + skill3 + conditioning)

            return f"""{note}

**Warm-up** ({warmup} min)
- Full dynamic warm-up routine

**Ball Handling** ({skill1} min)
- Two-ball dribbling drills
- Full-court combo moves
- Weak-hand focus

**Shooting** ({skill2} min)
- Form shooting progression
- Game-situation shooting
- Free throws under fatigue

**Finishing** ({skill3} min)
- Layup variations (reverse, euro-step)
- Contact finishing drills
- Weak-hand finishing

**Conditioning** ({conditioning} min)
- Full-court sprints
- Defensive slides
- Jump training

**Cool-down** ({cooldown} min)
- Complete stretching routine"""

    def _soccer_structured_workout(self, duration: int, intensity: str, note: str, level: str) -> str:
        """Structured soccer workout"""
        if duration <= 20:
            return f"""{note}

**Warm-up** (3 min)
- Light jogging and leg swings

**Ball Control** (8 min)
- Juggling practice: 3 min
- Dribbling through cones: 5 min

**Passing** (7 min)
- Wall passes for accuracy: 5 min
- Long passing: 2 min

**Cool-down** (2 min)
- Stretching"""
        else:
            warmup = int(duration * 0.15)
            skill1 = int(duration * 0.30)
            skill2 = int(duration * 0.25)
            shooting = int(duration * 0.20)
            cooldown = duration - (warmup + skill1 + skill2 + shooting)

            return f"""{note}

**Warm-up** ({warmup} min)
- Dynamic stretching and light jogging

**Dribbling & Control** ({skill1} min)
- Cone weaving (both feet)
- Speed dribbling with cuts
- Close control in tight space

**Passing** ({skill2} min)
- Short passing accuracy
- Through balls to targets
- One-touch combinations

**Shooting** ({shooting} min)
- Shots from edge of box
- Finishing practice
- Placement over power

**Cool-down** ({cooldown} min)
- Static stretching"""

    def _tennis_structured_workout(self, duration: int, intensity: str, note: str, level: str) -> str:
        """Structured tennis workout"""
        if duration <= 20:
            return f"""{note}

**Warm-up** (3 min)
- Light movement and arm circles

**Serve Practice** (8 min)
- Toss consistency: 3 min
- Target practice: 5 min

**Groundstrokes** (7 min)
- Forehand repetition: 4 min
- Backhand consistency: 3 min

**Cool-down** (2 min)
- Arm and shoulder stretches"""
        else:
            warmup = int(duration * 0.15)
            serve = int(duration * 0.25)
            groundstrokes = int(duration * 0.35)
            footwork = int(duration * 0.15)
            cooldown = duration - (warmup + serve + groundstrokes + footwork)

            return f"""{note}

**Warm-up** ({warmup} min)
- Dynamic stretching and shadow swings

**Serve Practice** ({serve} min)
- First serve placement
- Second serve consistency
- Power serve development

**Groundstrokes** ({groundstrokes} min)
- Forehand cross-court: {int(groundstrokes * 0.4)} min
- Backhand consistency: {int(groundstrokes * 0.4)} min
- Approach shots: {int(groundstrokes * 0.2)} min

**Footwork** ({footwork} min)
- Ladder drills
- Split-step practice
- Court movement patterns

**Cool-down** ({cooldown} min)
- Complete stretching routine"""

    def _football_structured_workout(self, duration: int, intensity: str, note: str, level: str) -> str:
        """Structured football workout"""
        if duration <= 20:
            return f"""{note}

**Warm-up** (3 min)
- Light jogging and arm swings

**Route Running** (8 min)
- Basic route practice
- Sharp cuts and breaks

**Catching** (7 min)
- Hand-eye coordination drills
- Catch-and-tuck practice

**Cool-down** (2 min)
- Stretching"""
        else:
            warmup = int(duration * 0.15)
            routes = int(duration * 0.30)
            catching = int(duration * 0.25)
            agility = int(duration * 0.20)
            cooldown = duration - (warmup + routes + catching + agility)

            return f"""{note}

**Warm-up** ({warmup} min)
- Dynamic stretching and mobility

**Route Running** ({routes} min)
- Slant, post, corner routes
- Precision cuts and breaks
- Full-speed releases

**Catching** ({catching} min)
- Hands drills
- Over-shoulder catches
- Contested catches

**Agility** ({agility} min)
- Cone drills
- Ladder work
- Change of direction

**Cool-down** ({cooldown} min)
- Complete stretching"""

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
