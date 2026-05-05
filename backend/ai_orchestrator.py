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
import re

from config import get_settings
import models
from models_premium import BiometricData, SportGoals, Subscription, SmartwatchConnection

# MARK: - Coaching Philosophy
# Single source of truth for coaching identity — injected into every GPT system prompt.
# The iOS equivalent lives in CoachingPhilosophy.swift (CoachingPhilosophyConstants).
# Both must stay in sync when the philosophy is updated.
COACHING_PHILOSOPHY = """
COACHING PHILOSOPHY (NON-NEGOTIABLE — applies to every response):
1. ATHLETE-FIRST: Long-term development and safety above all short-term performance goals.
2. SPECIFICITY: Named drills with exact sets, reps, and durations — never generic categories.
3. PROGRESSIVE OVERLOAD: Every session escalates from the last; reference prior training history.
4. SPORT-SPECIFIC MASTERY: Every drill and skill reference MUST belong to the active sport. Zero exceptions.
5. HONESTY-FIRST: Don't pad responses with hollow encouragement. Acknowledge strengths only when the athlete has shared a specific success; otherwise go directly to the plan.
6. NO DEAD ENDS: Every response closes with a clear next action the athlete can take today.
7. SAFETY ABOVE ALL: Injury or overtraining signals override ALL other coaching directives immediately.
"""

# Per-sport team context constraints injected into the GPT system prompt.
# The iOS equivalent lives in SportConstraint in CoachingPhilosophy.swift.
SPORT_CONSTRAINTS = {
    models.Sport.BASKETBALL: (
        "Basketball: solo skill work and 1v1 drills are fully appropriate. "
        "Connect individual skills to team application (pick-and-roll, help defense, spacing) where relevant."
    ),
    models.Sport.FOOTBALL: (
        "FOOTBALL CONSTRAINT — CRITICAL ZERO TOLERANCE:\n"
        "Football is a TEAM sport. NEVER generate solo 1-on-1 match drills or frame any training as individual competition.\n"
        "EVERY drill must include a team context element: route running with QB timing, formation reads, "
        "blocking assignments, coverage recognition, or scout team roles.\n"
        "FORBIDDEN: 'you vs one other player in a match' framing, isolation drills from individual sports.\n"
        "REQUIRED: Name the team role, formation, or scheme for every drill."
    ),
    models.Sport.SOCCER: (
        "Soccer: solo ball work and 1v1 dribbling drills are appropriate. "
        "Connect individual skills to team patterns (combinations, pressing shape, transition) where relevant."
    ),
    models.Sport.TENNIS: (
        "Tennis is an individual sport. Both solo drilling (shadow swings, ball machine, feeding drills) "
        "and 1v1 match-play scenarios are fully appropriate and expected."
    ),
}

# Sport-specific skill keyword aliases → canonical drill key in _get_skill_drills().
# Checked by _extract_skill() before direct skill name matching so common natural-language
# phrasings resolve to the correct drill bucket even when the message doesn't match exactly.
# Ordered longest-first within each sport to prevent partial matches (e.g., "throwing
# mechanics" matches before "throw").
_SPORT_SKILL_ALIASES: dict = {
    "basketball": [
        ("left hand",  "ball handling"), ("weak hand",   "ball handling"),
        ("right hand", "ball handling"), ("off hand",    "ball handling"),
        ("handles",    "ball handling"), ("dribble",     "ball handling"),
        ("layup",      "finishing"),     ("layups",      "finishing"),
        ("finish",     "finishing"),     ("shoot",       "shooting"),
    ],
    "football": [
        ("throwing mechanics", "throwing"), ("throwing accuracy", "throwing"),
        ("route running",      "route running"),
        ("routes",   "route running"), ("route",  "route running"),
        ("throw",    "throwing"),
        ("catching", "catching"),      ("catch",  "catching"),
        ("agility",  "speed"),         ("explosive", "speed"), ("faster", "speed"),
        ("footwork", "footwork"),      ("conditioning", "conditioning"),
        ("endurance","conditioning"),
    ],
    "soccer": [
        ("first touch",    "first touch"), ("weak foot",    "first touch"),
        ("weaker foot",    "first touch"), ("off foot",     "first touch"),
        ("shooting accuracy", "finishing"),("shooting",     "finishing"),
        ("shoot",          "finishing"),   ("finish",       "finishing"),
        ("dribble",        "dribbling"),   ("passing",      "passing"),
        ("pass",           "passing"),
    ],
    "tennis": [
        ("serve toss",   "serve"),  ("second serve", "serve"),
        ("first serve",  "serve"),  ("toss",         "serve"),
        ("backhand",     "backhand"),
        ("forehand",     "forehand"),
        ("footwork",     "footwork"), ("movement",   "footwork"),
        ("volley",       "volley"),  ("net",         "volley"),
    ],
}

# Injury keywords for backend safety detection
_INJURY_KEYWORDS = [
    "hurt", "hurts", "pain", "painful", "sore", "soreness",
    "injury", "injured", "ache", "aching",
    "sprain", "sprained", "strain", "strained", "pulled", "pull",
    "tear", "torn", "swollen", "swelling", "bruised", "bruise",
    "fracture", "fractured", "knee", "ankle", "shoulder", "wrist",
    "elbow", "hip", "lower back", "back pain", "neck pain",
    "hamstring", "quad", "quadricep", "calf", "shin splint",
    "plantar", "tendon", "ligament", "tendinitis",
    "tweak", "tweaked", "popped", "snap", "snapped",
    "can't run", "can't play", "limping",
    "concussion", "dizzy", "dizziness",
    "hit in the head", "hit my head", "head impact",
]


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

        # Make OpenAI client optional - gracefully degrade if no API key.
        # Valid OpenAI keys start with "sk-" (both legacy sk-... and project sk-proj-... formats).
        # Reject empty strings and placeholder values that don't have the sk- prefix.
        try:
            key = self.settings.openai_api_key or ""
            if key.startswith("sk-"):
                self.client = OpenAI(api_key=key)
                self.has_openai = True
                print(f"[AI Orchestrator] OpenAI initialized ({self.settings.openai_model})")
            else:
                self.client = None
                self.has_openai = False
                print("[AI Orchestrator] No valid OpenAI API key — using template-based coaching")
        except Exception as e:
            self.client = None
            self.has_openai = False
            print(f"[AI Orchestrator] OpenAI initialization failed: {e} — using template-based coaching")

    # MARK: - Conversational AI Coach (Premium)

    async def generate_coach_response(
        self,
        user_id: UUID,
        sport: models.Sport,
        user_message: str,
        conversation_history: List[Dict[str, str]] = None,
        ios_context: Optional[Dict] = None
    ) -> Dict[str, str]:
        """
        Generate conversational AI Coach response (Premium feature).

        This is the main Premium AI feature - a conversational sports coach
        that feels like texting with a real mentor.

        Args:
            user_id: User UUID
            sport: Current sport context
            user_message: User's message to the coach
            conversation_history: Previous messages in conversation (from iOS)
            ios_context: Context dict sent from iOS (weak points, wearable, available time)

        Returns:
            {
                "response": "Coach's response text",
                "suggested_actions": ["action1", "action2"],
                "tone": "supportive|motivating|concerned",
                "follow_up_questions": ["question1"]
            }
        """
        # Update persistent coaching context from user message
        self._update_coach_context(user_id, sport, user_message)

        # Aggregate all context (sport profile, wearable, goals, matches)
        context = self._aggregate_user_context(user_id, sport)

        # Load saved coaching context (weak points, goals, recommendations history)
        saved_context = self._load_coach_context_into_dict(user_id, sport)
        context.update(saved_context)

        # Merge iOS-sent context (weak points, wearable data, available time, etc.)
        if ios_context:
            self._merge_ios_context(context, ios_context)

        # Build conversational prompt
        system_prompt = self._build_coach_system_prompt(sport)

        # ── Backend safety injection ──────────────────────────────────────────────────
        # If the user message contains injury language, append the safety constraint block
        # to the system prompt so GPT-4 prioritizes athlete safety over training goals.
        if self._detect_injury_context(user_message):
            system_prompt += (
                "\n\n⚠️ SAFETY ALERT — INJURY LANGUAGE DETECTED:\n"
                "The athlete has mentioned pain, soreness, or an injury in their message. MANDATORY:\n"
                "1. Acknowledge the pain with empathy BEFORE any training content.\n"
                "2. Do NOT prescribe high-intensity drills involving the affected body part.\n"
                "3. Offer a modified low-impact alternative: mobility work, body-part split, or light technical work.\n"
                "4. Recommend consulting a sports medicine professional before returning to full training.\n"
                "5. If pain sounds acute, recommend stopping training today.\n"
                "SAFETY TAKES ABSOLUTE PRIORITY OVER ANY TRAINING GOAL."
            )

        # ── Constrained mode injection ────────────────────────────────────────────────
        # Triggered by iOS when the first GPT response failed post-response contract validation.
        # Adds strict per-rule requirements to the system prompt before the second (final) attempt.
        if ios_context and ios_context.get("constrained_mode", False):
            sport_label = sport.value.title()
            football_note = (
                "All activities MUST be team-based — never suggest 1v1, solo-match, or individual-opponent drills. "
            ) if sport == models.Sport.FOOTBALL else ""
            system_prompt += (
                f"\n\n=== CONSTRAINED RESPONSE MODE — SECOND AND FINAL ATTEMPT ===\n"
                f"Your previous response violated the coaching contract. This is your FINAL attempt.\n"
                f"You MUST comply with ALL rules below or the response will be overridden by a local system:\n"
                f"1. ONLY discuss {sport_label}. Do NOT reference any other sport.\n"
                f"2. Include at least ONE specific, named drill or exercise for {sport_label}.\n"
                f"3. {football_note}Minimum 100 characters in the 'response' field.\n"
                f"4. Include at least 2 concrete 'suggested_actions'.\n"
                f"5. Return valid JSON matching the required schema.\n"
                f"=== END CONSTRAINED MODE ==="
            )
            print(f"[AI Coach] 🔒 Constrained mode active for {sport.value} — strict contract injected into system prompt")

        messages = self._build_conversation_messages(
            system_prompt=system_prompt,
            context=context,
            user_message=user_message,
            history=conversation_history
        )

        # Use OpenAI if available, otherwise use intelligent templates
        if self.has_openai and self.client:
            try:
                # Call GPT-4 — 30s timeout prevents indefinite hang on slow API
                response = self.client.chat.completions.create(
                    model=self.settings.openai_model,
                    messages=messages,
                    max_tokens=self.settings.openai_max_tokens,
                    temperature=self.settings.openai_temperature,
                    timeout=30
                )

                coach_response = response.choices[0].message.content

                # Parse structured response
                parsed = self._parse_coach_response(coach_response)

                # Normalize to guarantee structural completeness (actions, follow-up, tone)
                parsed = self._normalize_gpt_response(parsed, sport=sport, user_message=user_message)

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

        # Build a context-rich proactive message — reference their actual baseline if available
        critical_gaps = context.get('survey_critical_skills', [])
        top_gap = critical_gaps[0][0] if critical_gaps else None
        survey_weaknesses = context.get('survey_weaknesses', [])
        top_weakness = survey_weaknesses[0] if survey_weaknesses else None

        athlete_note = ""
        if top_gap:
            athlete_note = f"- Known top priority: {top_gap} (rated {critical_gaps[0][1]}/10 in baseline)"
        elif top_weakness:
            athlete_note = f"- Self-identified weakness: {top_weakness}"

        prompt = f"""You are a sharp, direct sports coach checking in with your athlete. Trigger: {trigger}

Athlete context:
- Sport: {sport.value}
- Recovery score: {context.get('recovery_score', 'unknown')}
- Matches this week: {context.get('recent_match_count', 0)}
- Last match result: {context.get('last_match_result', 'unknown')}
{athlete_note}

Write ONE short, natural check-in message (1-2 sentences max).
Rules:
- Sound like a real coach texting their athlete, not a bot
- If you know their gap, acknowledge it naturally (don't be clinical)
- Do NOT use emojis or exclamation marks excessively
- Do NOT ask multiple questions — one natural opener is enough
- Vary the opening — not always "Hey"

Examples of the RIGHT tone:
- "How's the body after yesterday? Feeling ready to work?"
- "You've got {top_gap or 'conditioning'} on the agenda today — what does your energy look like?"
- "Saw you've been putting in the work. How's the {top_weakness or 'training'} feel coming along?"
"""

        try:
            if not self.has_openai or not self.client:
                raise RuntimeError("OpenAI not available")
            response = self.client.chat.completions.create(
                model=self.settings.openai_model,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=80,
                temperature=0.85,
                timeout=15
            )
            return response.choices[0].message.content.strip()

        except Exception as e:
            print(f"[AI Orchestrator] Proactive check-in failed: {e}")
            # Fallback — use athlete's known gap if available, not generic
            if top_gap:
                return f"How's the body feeling today? You've had {top_gap} on the agenda — where are you at with it?"
            elif top_weakness:
                return f"How's the training going? I want to talk about your {top_weakness} when you're ready."
            if trigger == "low_recovery":
                return "Recovery score is looking low — how's the body feeling? Be honest with me."
            elif trigger == "recent_match":
                return "How did that last match go? Walk me through it."
            return "How's the training going? What did you work on last?"

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

        except Exception as e:
            print(f"[AI Orchestrator] Training analysis failed: {e}")
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

        # Extract weak points via explicit keywords
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

        # Semantic phrase mapping: translate natural-language expressions into athletic concepts.
        # Runs unconditionally — "I feel slow" doesn't contain weak/struggle but IS a weakness signal.
        semantic_phrase_map = [
            ('feel slow',          ['speed', 'agility']),
            ('feeling slow',       ['speed', 'agility']),
            ('too slow',           ['speed', 'quickness']),
            ('get tired quickly',  ['conditioning', 'stamina']),
            ('gets tired',         ['conditioning', 'endurance']),
            ('run out of gas',     ['conditioning', 'endurance']),
            ('out of gas',         ['conditioning', 'endurance']),
            ('not explosive',      ['explosiveness', 'power']),
            ("can't explode",      ['explosiveness', 'power']),
            ('struggle late',      ['endurance', 'conditioning']),
            ('late in game',       ['endurance', 'conditioning']),
            ("can't keep up",      ['speed', 'conditioning']),
            ('slow feet',          ['footwork', 'agility']),
            ('not strong enough',  ['strength', 'power']),
            ('getting pushed',     ['strength', 'physicality']),
            ('lose balance',       ['balance', 'stability', 'core']),
            ('losing balance',     ['balance', 'stability']),
            ('feel heavy',         ['conditioning', 'recovery']),
            ('timing is off',      ['timing', 'footwork']),
            ('lack confidence',    ['confidence', 'mental game']),
            ('nervous before',     ['mental', 'confidence']),
            ('not consistent',     ['consistency', 'fundamentals']),
            ('miss under pressure', ['composure', 'clutch']),
        ]
        semantic_concepts_found = []
        for phrase, concepts in semantic_phrase_map:
            if phrase in msg_lower:
                weak_points = json.loads(context.weak_points) if isinstance(context.weak_points, str) else context.weak_points
                for concept in concepts:
                    if concept not in [wp.lower() for wp in weak_points]:
                        weak_points.append(concept)
                        semantic_concepts_found.append(concept)
                context.weak_points = json.dumps(weak_points[-10:])
        if semantic_concepts_found:
            print(f"[AI Orchestrator] Semantic mapping added: {semantic_concepts_found}")

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

        # 5. Recent Training Sessions
        try:
            recent_sessions = self.db.query(models.TrainingSession).filter(
                models.TrainingSession.user_id == user_id,
                models.TrainingSession.sport == sport,
                models.TrainingSession.created_at >= week_ago
            ).order_by(models.TrainingSession.created_at.desc()).limit(5).all()

            if recent_sessions:
                session_summaries = []
                for session in recent_sessions[:3]:
                    drill_name = getattr(session, 'drill_name', None) or getattr(session, 'session_type', 'Training')
                    duration = getattr(session, 'duration_minutes', None) or getattr(session, 'duration', '?')
                    difficulty = getattr(session, 'perceived_difficulty', None)
                    summary = f"{drill_name} ({duration}min"
                    if difficulty:
                        summary += f", {difficulty}"
                    summary += ")"
                    session_summaries.append(summary)
                context['recent_training_sessions'] = session_summaries
        except Exception:
            pass  # Training sessions optional — don't break if model doesn't exist

        # 6. Premium Status
        subscription = self.db.query(Subscription).filter(
            Subscription.user_id == user_id,
            Subscription.status == "active"
        ).first()

        context['is_premium'] = subscription is not None

        # 7. Onboarding Survey — day-one skill baseline
        # This is the foundational athlete profile: what they rated themselves at signup.
        # Used by the AI to prioritize coaching without needing the user to re-state their gaps.
        try:
            survey = self.db.query(models.OnboardingSurvey).filter(
                models.OnboardingSurvey.user_id == user_id
            ).first()

            if survey:
                context['survey_main_sport'] = survey.main_sport.value if survey.main_sport else None
                skill_ratings = survey.skill_ratings or {}
                context['survey_skill_ratings'] = skill_ratings
                context['survey_strengths'] = survey.strengths or []
                context['survey_weaknesses'] = survey.weaknesses or []

                # Pre-classify skills by rating tier for the prompt formatter
                critical_skills = sorted(
                    [(k, v) for k, v in skill_ratings.items() if v <= 3],
                    key=lambda x: x[1]  # Lowest first = highest priority
                )
                developing_skills = [(k, v) for k, v in skill_ratings.items() if 4 <= v <= 6]
                strong_skills = [(k, v) for k, v in skill_ratings.items() if v >= 7]

                context['survey_critical_skills'] = critical_skills    # (name, rating) tuples
                context['survey_developing_skills'] = developing_skills
                context['survey_strong_skills'] = strong_skills

                # Seed weak_points from survey weaknesses + critical skills
                # so they're available even before the user has said anything
                survey_weak_signals = list(survey.weaknesses or [])
                for skill_name, _ in critical_skills:
                    normalized = skill_name.lower()
                    if normalized not in [w.lower() for w in survey_weak_signals]:
                        survey_weak_signals.append(normalized)

                existing_weak_points = context.get('saved_weak_points', []) or []
                seen = set(w.lower() for w in existing_weak_points)
                for signal in survey_weak_signals:
                    key = signal.lower()
                    if key not in seen:
                        existing_weak_points.append(key)
                        seen.add(key)
                context['saved_weak_points'] = existing_weak_points[:10]
        except Exception as e:
            print(f"[AI Orchestrator] Failed to load onboarding survey: {e}")

        return context

    def _merge_ios_context(self, context: Dict, ios_context: Dict):
        """Merge iOS-sent context into backend context dict.

        Priority order: iOS-supplied values are the most recent user signals, so they
        take precedence over older DB-saved values when there is a conflict.
        """
        # Weak points: iOS first (user just expressed them), then DB-saved.
        # Use ordered deduplication — Set() randomises order and loses priority signal.
        if ios_context.get('weak_points'):
            existing_wps = context.get('saved_weak_points', []) or []
            ios_wps = ios_context['weak_points']
            seen = set()
            combined = []
            for wp in ios_wps + existing_wps:   # iOS first = higher priority
                key = wp.lower()
                if key not in seen:
                    seen.add(key)
                    combined.append(key)
            context['combined_weak_points'] = combined[:10]

        # Latest concern: the single most-recent thing the user expressed.
        # This becomes the CURRENT FOCUS in the prompt — highest-priority coaching signal.
        if ios_context.get('latest_concern'):
            context['latest_concern'] = ios_context['latest_concern'].lower()
            print(f"[AI Orchestrator] Latest concern from iOS: {context['latest_concern']}")

        # Semantic concepts inferred from the user's most recent message.
        if ios_context.get('semantic_concepts'):
            context['semantic_concepts'] = [c.lower() for c in ios_context['semantic_concepts']]
            print(f"[AI Orchestrator] Semantic concepts from iOS: {context['semantic_concepts']}")

        # Inferred intent — tells GPT-4 what kind of response is expected.
        if ios_context.get('inferred_intent'):
            context['inferred_intent'] = ios_context['inferred_intent']

        if ios_context.get('available_time') is not None:
            context['available_time_minutes'] = ios_context['available_time']

        if ios_context.get('readiness_level'):
            context['ios_readiness'] = ios_context['readiness_level']

        if ios_context.get('recent_training'):
            context['ios_recent_training'] = ios_context['recent_training']

        wearable = ios_context.get('wearable_data') or {}
        if wearable:
            if wearable.get('resting_heart_rate'):
                context['ios_resting_hr'] = wearable['resting_heart_rate']
            if wearable.get('hrv'):
                context['ios_hrv'] = wearable['hrv']
            if wearable.get('sleep_hours'):
                context['ios_sleep_hours'] = wearable['sleep_hours']
            if wearable.get('steps_today'):
                context['ios_steps'] = wearable['steps_today']

        if ios_context.get('goals'):
            context['ios_goals'] = ios_context['goals']

        # Pre-analyzed coaching brief from iOS reasoning layer.
        # This is the highest-priority planning signal — synthesises weakness type, sport impact,
        # session structure, time constraints, biometrics, and recurring patterns into one block.
        # When present, GPT-4 should plan from this rather than re-derive signals from scratch.
        if ios_context.get('coaching_brief'):
            context['coaching_brief'] = ios_context['coaching_brief']
            print(f"[AI Orchestrator] Coaching brief received from iOS ({len(ios_context['coaching_brief'])} chars)")

        # Survey data forwarded by iOS — merge if the DB survey load didn't populate the fields.
        # This handles new devices, fresh installs, or when the DB query ran before the survey model existed.
        if ios_context.get('survey_skill_ratings') and not context.get('survey_skill_ratings'):
            skill_ratings = ios_context['survey_skill_ratings']
            if isinstance(skill_ratings, dict):
                context['survey_skill_ratings'] = skill_ratings
                context['survey_critical_skills'] = sorted(
                    [(k, v) for k, v in skill_ratings.items() if isinstance(v, (int, float)) and v <= 3],
                    key=lambda x: x[1]  # Lowest first = highest priority
                )
                context['survey_developing_skills'] = [
                    (k, v) for k, v in skill_ratings.items() if isinstance(v, (int, float)) and 4 <= v <= 6
                ]
                context['survey_strong_skills'] = [
                    (k, v) for k, v in skill_ratings.items() if isinstance(v, (int, float)) and v >= 7
                ]

        if ios_context.get('survey_weaknesses') and not context.get('survey_weaknesses'):
            context['survey_weaknesses'] = ios_context['survey_weaknesses']

        if ios_context.get('survey_strengths') and not context.get('survey_strengths'):
            context['survey_strengths'] = ios_context['survey_strengths']

    def _build_coach_system_prompt(self, sport: models.Sport) -> str:
        """Build comprehensive system prompt for conversational AI Coach"""

        sport_expertise = {
            models.Sport.BASKETBALL: """
- Shooting: form mechanics, arc, release point, shot selection, catch-and-shoot vs. off-dribble, free throws, three-point shooting
- Ball handling: crossover, through-legs, behind-back, hesitation moves, dribbling under pressure, weak-hand development
- Finishing: layups, floaters, Euro step, contact finishing, reverse layup, shot-fakes at the rim
- Defense: on-ball stance and positioning, help defense rotations, closeouts, box-outs, reading screens
- Passing: decision-making timing, chest/bounce/skip/lob, reading defenses, avoiding turnovers
- Basketball IQ: spacing, pick-and-roll offense/defense, transition, shot clock awareness, reading coverages""",

            models.Sport.TENNIS: """
- Serve: toss consistency, pronation mechanics, spin types (flat/kick/slice), placement targeting
- Forehand: grip, unit turn, swing path, topspin generation, inside-out, inside-in patterns
- Backhand: two-handed mechanics, loading and contact point, one-handed slice use, cross-court rally
- Net game: volley punch technique, overhead mechanics, net positioning, approach shot selection
- Footwork: split step timing, recovery steps after shots, court positioning, movement efficiency
- Mental game: between-point routine, handling pressure, break point conversion, consistency mindset
- Tactics: rally patterns, serve-plus-one planning, exploiting opponent weaknesses, court geometry""",

            models.Sport.SOCCER: """
- First touch: controlling lofted/driven/bouncing balls with foot, thigh, chest; turning on first touch
- Dribbling: close control in tight spaces, direction changes, body feints, 1v1 moves (cruyff, stepover, elastico, scissors)
- Passing: accuracy, weight and timing, through balls, switches of play, one-touch combinations
- Shooting: placement vs. power, volley technique, finishing from crosses, near-post and far-post runs
- Defending: positioning, tracking runs off the ball, press triggers, tackle timing, 1v1 defending
- Fitness: speed endurance, explosive acceleration, repeated sprint ability, agility
- Tactics: positional play, pressing triggers, transition moments, wide play and crossing""",

            models.Sport.FOOTBALL: """
- Throwing: grip, stance, three-step and five-step drops, release mechanics, spiral and velocity, accuracy on routes
- Route running: stem, break sharpness, sell routes vs. coverage, creating separation, run after catch
- Receiving: hand placement, concentration catches, contested-ball technique, body control, YAC
- Blocking: angles of attack, leverage and hand fighting, pass protection footwork and set
- Conditioning: explosive power, first-step quickness, speed off the line, football-specific agility
- Coverage reading: pre-snap recognition, route adjustments based on coverage, identifying open areas"""
        }

        # Use the exact sport key — no silent basketball default.
        # If a new sport is added and missing from the map, it fails loudly rather than coaching basketball.
        expertise_text = sport_expertise.get(sport) or "\n".join(
            f"- {k}: expert knowledge in technique, conditioning, and competition strategy"
            for k in ["Technical skills", "Physical conditioning", "Mental game", "Match preparation"]
        )

        return f"""You are a premium AI sports coach specializing in {sport.value}. You have deep expertise in technique, training science, sports psychology, and athletic development for young athletes.

## Your Identity
You know this athlete — their weak points, goals, recent performance, wearable metrics, and training history are in the context provided. You are NOT a generic chatbot. Reference their actual data naturally in your responses.

## {sport.value.title()} Expertise
{expertise_text}

## Coaching Identity

You are a coach, not an assistant. Coaches have a point of view. They decide what the athlete works on and why. They prescribe — they do not suggest.

**When this athlete tells you a problem, your job is to:**
1. Identify the root cause immediately (do not ask clarifying questions when you have enough signal)
2. State what they are working on today and why it was chosen
3. Prescribe the specific session — exact drills, sets, reps, rest periods
4. Move the conversation forward with one sharp follow-up

**Calibrate depth to the situation — not to what sounds comprehensive:**
- Conversational question → 2–4 sentence direct answer
- "Give me a workout" or "what should I do" → full structured plan, no preamble
- "Make that shorter" → immediately compress, skip re-explanation
- Emotional message ("I'm struggling", "I'm exhausted") → one sentence of acknowledgment, then get practical
- Follow-up ("what about defence?") → build on your prior response, do not restart from scratch

**Prescribe, do not suggest:**
- Wrong: "You could try working on your ball handling"
- Right: "Do 3 sets of figure-8 dribbles through your legs, 2 minutes each, then 5-10-5 shuttle runs, 4 reps full recovery"
- Every drill gets: a name, a rep/time count, and a rest period
- Every plan fits within the TIME CONSTRAINT if one is given

**Reference what you know:**
- Use their actual weak points, not generic placeholders
- Use their wearable data when present ("Your resting HR is 74 today — we dial back 20%")
- Reference recurring patterns when present ("You've brought up conditioning three times now — let's commit to this properly")
- Reference prior messages naturally, not mechanically

**Recovery-adaptive intensity:**
- Recovery score < 40: Active recovery only — light movement, stretching, mobility work. No intense training whatsoever.
- Recovery score 40–65: Moderate intensity. Reduce volume ~30%. Prioritize technique over conditioning load.
- Recovery score 65+: Full training intensity appropriate to their skill level.

**Coaching Analysis Brief (PRIMARY PLANNING INPUT when present):**
- When a COACHING ANALYSIS BRIEF block appears in the context, treat it as the pre-computed situation diagnosis. It contains: weakness type, sport-specific impact, session structure, time/recovery adjustments, biometric modifiers, recurring patterns, and a COACHING DIRECTIVE.
- PRIMARY FOCUS is what matters most today — address it directly. SECONDARY FOCUS is explicitly deprioritised — do not lead with it or spend equal time on it.
- PROGRESSION STAGE tells you HOW to design the session, not just WHAT:
  - Foundation (Stage 1): form before intensity — slow deliberate reps, no competitive pressure
  - Development (Stage 2): add load/speed/constraint — athlete is past basics, push the last set
  - Stress-Test (Stage 3): game conditions — scored reps, decision-making pressure, live competition format
- Use SESSION STRUCTURE as your skeleton. Fill it with exact sport-specific drill names, reps, rest, and coaching cues.
- Follow COACHING DIRECTIVE exactly — it is a direct instruction, not a suggestion.
- PROGRESSION DIRECTIVE overrides your default session design for this weakness type.
- When RECURRING PATTERNS appear, acknowledge the pattern as a coach would: "You've brought up your conditioning three times now — we're going to commit to this properly and move past Foundation today." Then apply the appropriate Progression Stage design.

**Latest-input priority (CRITICAL):**
- The ⚡ CURRENT FOCUS in the context is what the user expressed most recently. It outranks everything else — historical weak points, goals, prior recommendations. Address it explicitly and specifically.
- INFERRED CONCEPTS reveal what the user meant even when phrased vaguely ("I feel slow" → speed/agility, "I get tired" → conditioning). Use these concepts to drive your response when the user's language is imprecise.
- USER INTENT tells you what kind of response they're looking for. Honour it: "weakness_help" → targeted fix plan; "elaboration" → deepen the prior response; "constraint_adjustment" → adapt immediately to the new time/resource constraint.
- When the user says something vague like "I need to improve" or "help me", do NOT give a generic intro. Look at CURRENT FOCUS and INFERRED CONCEPTS first, then respond to THOSE.

**Weak point and goal integration:**
- When you know their weak points, organically weave improvement there into your recommendations.
- When you know their goals, align your advice toward those goals.
- If you've recently recommended something (shown in AVOID REPEATING), suggest something different.

**Athlete Skill Baseline — when ATHLETE BASELINE section is in context:**
- The 1–10 ratings are the athlete's own onboarding self-assessment. They are the starting ground truth for coaching until real performance data overrides them.
- CRITICAL GAPS (rated 1–3): Severe limitations. Prioritize these in every session unless recovery prevents intensity. A skill rated 2/10 is not "something to work on someday" — it is a coaching priority. Prescribe targeted drills for it specifically.
- DEVELOPING skills (rated 4–6): Ready for targeted progression. Route drill prescriptions here second, after critical gaps.
- STRONG skills (rated 7–10): These are the athlete's weapons. Acknowledge and build strategy around them. Do NOT spend session time hammering what's already working.
- When the athlete says something vague like "I need to improve" or "help me get better" — look at ATHLETE BASELINE FIRST. Coach their critical gaps directly without asking them to re-state their weaknesses.
- Never ask "what do you want to work on?" when ATHLETE BASELINE reveals clear critical gaps — you already know the answer.
- When ATHLETE BASELINE and CURRENT FOCUS conflict (athlete mentions a strong skill today), honor their current message — but weave in a critical gap from ATHLETE BASELINE naturally before closing the response.
- Self-stated weaknesses in ATHLETE BASELINE reinforce the skill ratings. If both the skill rating AND the self-stated weakness point to the same area, treat it as a confirmed high-priority focus.

**Do NOT:**
- Give generic advice that ignores their actual context or the coaching brief
- Start with hollow affirmations ("Great question!", "Awesome!", "That's a great goal!")
- List drill categories without naming specific drills ("work on your conditioning" is not a prescription)
- Repeat the same recommendation across consecutive messages — check AVOID REPEATING
- Ask clarifying questions when you already have enough signal to act
- Give a Foundation-stage session to an athlete in the Development or Stress-Test stage
- Ignore TIME CONSTRAINT or RECOVERY STATE adjustments — these are directives, not suggestions
- Dump every possible app feature — only mention what is genuinely relevant to what was just discussed
- Ask "what do you want to work on?" when ATHLETE BASELINE already tells you

## Structured Output (REQUIRED)
Every single response MUST end with exactly these two lines:
[ACTIONS: action1, action2]
[FOLLOWUP: one natural follow-up question]

ACTIONS (2–3 max): specific in-app actions like "Log training session", "View drill library", "Check recovery score", "Set a goal", "Browse challenges", "Open train tab". Only include actions relevant to what you just discussed.
FOLLOWUP: ONE natural follow-up question that moves the conversation forward. Make it sound like a real coach, not a quiz.

## Coaching Philosophy
{COACHING_PHILOSOPHY}

## Sport Team-Context Constraint
{SPORT_CONSTRAINTS.get(sport, "")}"""

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
        """Format context into comprehensive, AI-readable sections"""
        sections = []

        # ── COACHING ANALYSIS BRIEF — pre-computed by iOS reasoning layer ──────────────────
        # When present this is the single most authoritative planning input.
        # It contains: weakness classification, sport-specific impact, session structure,
        # constraint adjustments, biometric modifiers, and recurring pattern data.
        # GPT-4 should use this as its primary planning scaffold; individual fields below
        # provide supporting detail for any gaps not covered by the brief.
        if context.get('coaching_brief'):
            sections.append(
                "━━━ COACHING ANALYSIS BRIEF (use this as your primary training plan scaffold) ━━━\n"
                + context['coaching_brief']
                + "\n━━━ END BRIEF ━━━"
            )

        # ── CURRENT FOCUS — highest priority, always shown first ──────────────────────────
        # This is the most recent thing the user expressed. GPT-4 MUST address it directly.
        # Do not bury this after performance stats — it belongs at the top.
        if context.get('latest_concern'):
            sections.append(
                f"⚡ CURRENT FOCUS (address this first — most recent user signal): "
                f"{context['latest_concern']}"
            )

        # Semantic concepts inferred from latest message phrasing
        if context.get('semantic_concepts'):
            concepts = context['semantic_concepts']
            if concepts:
                sections.append(f"INFERRED CONCEPTS (from user's phrasing): {', '.join(concepts)}")

        # Inferred intent — what kind of response the user is looking for
        if context.get('inferred_intent') and context['inferred_intent'] not in ('general', 'unknown'):
            sections.append(f"USER INTENT: {context['inferred_intent'].replace('_', ' ')}")

        # Performance Profile
        perf_parts = []
        if 'elo_rating' in context:
            perf_parts.append(f"ELO {context['elo_rating']}")
        if 'games_played' in context:
            perf_parts.append(f"{context['games_played']} games played")
        if 'win_rate' in context:
            perf_parts.append(f"{context['win_rate'] * 100:.0f}% win rate")
        if 'skill_level' in context:
            perf_parts.append(f"{context['skill_level']} level")
        if perf_parts:
            sections.append("PERFORMANCE: " + " | ".join(perf_parts))

        # Physical & Recovery Status
        phys_parts = []
        recovery = context.get('recovery_score')
        hrv = context.get('hrv') or context.get('ios_hrv')
        sleep = context.get('sleep_duration') or context.get('ios_sleep_hours')
        resting_hr = context.get('ios_resting_hr')
        steps = context.get('ios_steps')
        fatigue = context.get('fatigue_level')
        ios_readiness = context.get('ios_readiness')

        if recovery is not None:
            phys_parts.append(f"Recovery {recovery:.0f}/100")
        if hrv is not None:
            phys_parts.append(f"HRV {hrv:.0f}ms")
        if sleep is not None:
            phys_parts.append(f"Sleep {sleep:.1f}h")
        if resting_hr is not None:
            phys_parts.append(f"Resting HR {resting_hr:.0f}bpm")
        if steps is not None:
            phys_parts.append(f"Steps {steps:,}")
        if fatigue is not None:
            phys_parts.append(f"Fatigue {fatigue}")
        if ios_readiness:
            phys_parts.append(f"Self-reported readiness: {ios_readiness}")
        if phys_parts:
            sections.append("PHYSICAL STATUS: " + " | ".join(phys_parts))

        # Weak Points / Focus Areas
        weak_points = context.get('combined_weak_points') or context.get('saved_weak_points') or []
        if weak_points:
            sections.append(f"KNOWN WEAK POINTS: {', '.join(weak_points)}")

        # Athlete Skill Baseline (onboarding survey 1-10 self-ratings)
        # Only shown when skill ratings exist — gives GPT-4 ground truth to prioritize from.
        if context.get('survey_skill_ratings'):
            baseline_lines = []
            critical = context.get('survey_critical_skills', [])
            developing = context.get('survey_developing_skills', [])
            strong = context.get('survey_strong_skills', [])

            if critical:
                labels = [f"{name} ({rating}/10)" for name, rating in critical]
                baseline_lines.append(f"  CRITICAL GAPS (1–3): {', '.join(labels)} — highest-priority coaching targets")
            if developing:
                labels = [f"{name} ({rating}/10)" for name, rating in developing]
                baseline_lines.append(f"  DEVELOPING (4–6): {', '.join(labels)} — improvable with focused work")
            if strong:
                labels = [f"{name} ({rating}/10)" for name, rating in strong]
                baseline_lines.append(f"  STRONG (7–10): {', '.join(labels)} — use as offensive weapons")

            survey_weaknesses = context.get('survey_weaknesses', [])
            survey_strengths = context.get('survey_strengths', [])
            if survey_weaknesses:
                baseline_lines.append(f"  Self-stated weaknesses: {', '.join(survey_weaknesses)}")
            if survey_strengths:
                baseline_lines.append(f"  Self-stated strengths: {', '.join(survey_strengths)}")

            if baseline_lines:
                sections.append(
                    "ATHLETE BASELINE (onboarding self-assessment — treat as ground truth until real performance data overrides):\n"
                    + "\n".join(baseline_lines)
                )

        # Goals
        all_goals = []
        if context.get('goals_summary'):
            all_goals.append(context['goals_summary'])
        if context.get('saved_goals'):
            all_goals.extend(context['saved_goals'])
        if context.get('ios_goals'):
            all_goals.extend(context['ios_goals'])
        if context.get('skill_focus'):
            all_goals.append(f"Skill focus: {context['skill_focus']}")
        if all_goals:
            sections.append(f"GOALS: {' | '.join(all_goals[:3])}")

        # Time Available
        if context.get('available_time_minutes') is not None:
            sections.append(f"TIME AVAILABLE: {context['available_time_minutes']} minutes")
        elif context.get('preferred_duration'):
            sections.append(f"PREFERRED DURATION: {context['preferred_duration']} minutes")

        # Recent Activity
        activity_parts = []
        if context.get('recent_match_count') is not None:
            activity_parts.append(f"{context['recent_match_count']} matches this week")
        if context.get('last_match_result'):
            activity_parts.append(f"Last match: {context['last_match_result']}")
        if context.get('ios_recent_training'):
            activity_parts.append(f"Recent session: {context['ios_recent_training']}")
        if context.get('recent_training_sessions'):
            recent = context['recent_training_sessions']
            if recent:
                activity_parts.append(f"Last training: {recent[0]}")
        if activity_parts:
            sections.append("RECENT ACTIVITY: " + " | ".join(activity_parts))

        # Things NOT to repeat (avoid stale recommendations)
        if context.get('recent_recommendations'):
            recent_recs = context['recent_recommendations']
            if recent_recs:
                rec_texts = [r.get('recommendation', '') for r in recent_recs[-3:] if isinstance(r, dict) and r.get('recommendation')]
                if rec_texts:
                    sections.append(f"AVOID REPEATING: {' | '.join(rec_texts)}")

        return "\n".join(sections) if sections else "New athlete — no context yet. Ask about their goals and what they want to work on."

    def _parse_coach_response(self, response: str) -> Dict[str, any]:
        """Parse AI response extracting [ACTIONS] and [FOLLOWUP] structured tags"""
        clean_response = response
        suggested_actions = []
        follow_up_questions = []

        # Extract [ACTIONS: action1, action2, action3]
        actions_match = re.search(r'\[ACTIONS?:\s*(.*?)\]', response, re.IGNORECASE | re.DOTALL)
        if actions_match:
            actions_text = actions_match.group(1)
            suggested_actions = [a.strip() for a in actions_text.split(',') if a.strip()][:3]
            clean_response = clean_response.replace(actions_match.group(0), '').strip()

        # Extract [FOLLOWUP: question] or [FOLLOWUPS: question]
        followup_match = re.search(r'\[FOLLOWUPS?:\s*(.*?)\]', response, re.IGNORECASE | re.DOTALL)
        if followup_match:
            followup_text = followup_match.group(1).strip()
            if followup_text:
                follow_up_questions = [followup_text]
            clean_response = clean_response.replace(followup_match.group(0), '').strip()

        # Clean up trailing whitespace/newlines left by removed tags
        clean_response = re.sub(r'\n{3,}', '\n\n', clean_response).strip()

        # Infer tone from response content
        response_lower = response.lower()
        if any(w in response_lower for w in ['recovery', 'rest', 'tired', 'fatigue', 'sleep', 'take it easy']):
            tone = 'concerned'
        elif any(w in response_lower for w in ['incredible', 'crushing it', 'amazing', 'win', 'great match', 'knocked it out']):
            tone = 'celebratory'
        elif any(w in response_lower for w in ["let's go", "push", "grind", "fire up", "intensity", "attack"]):
            tone = 'motivating'
        else:
            tone = 'supportive'

        return {
            "response": clean_response,
            "suggested_actions": suggested_actions,
            "tone": tone,
            "follow_up_questions": follow_up_questions
        }

    def _detect_injury_context(self, user_message: str) -> bool:
        """Returns True if the user message contains injury or pain language."""
        lowered = user_message.lower()
        return any(kw in lowered for kw in _INJURY_KEYWORDS)

    def _normalize_gpt_response(self, parsed: Dict, sport: models.Sport, user_message: str) -> Dict:
        """
        Post-processing layer that guarantees structural completeness of every GPT response.

        Ensures:
        - suggested_actions is always a non-empty list (2-3 sport-relevant defaults if absent)
        - follow_up_questions always has at least one question
        - tone is one of the expected values
        - response does not end abruptly (adds a coaching sign-off if too short)
        - logs divergence in DEBUG mode for monitoring

        This runs AFTER _parse_coach_response() and BEFORE returning to the caller.
        """
        sport_name = sport.value

        # ── suggested_actions fallback ─────────────────────────────────────────────────
        if not parsed.get("suggested_actions"):
            parsed["suggested_actions"] = [
                "Log training session",
                f"View {sport_name} drill library",
                "Check recovery score",
            ]
            print(f"[AI Normalize] ⚠️ GPT returned no actions for sport={sport_name} — injected defaults")

        # ── follow_up_questions fallback ───────────────────────────────────────────────
        if not parsed.get("follow_up_questions"):
            # Use injury-aware follow-up if safety was triggered
            if self._detect_injury_context(user_message):
                fallback_q = "How are you feeling — has the discomfort gotten better or worse today?"
            else:
                fallback_q = f"What aspect of your {sport_name} game do you most want to focus on this week?"
            parsed["follow_up_questions"] = [fallback_q]
            print(f"[AI Normalize] ⚠️ GPT returned no follow-up — injected fallback")

        # ── tone validation ────────────────────────────────────────────────────────────
        valid_tones = {"supportive", "motivating", "concerned", "celebratory"}
        if parsed.get("tone") not in valid_tones:
            parsed["tone"] = "supportive"

        # ── injury safety override ─────────────────────────────────────────────────────
        # If the user mentioned injury but the tone wasn't already set to "concerned",
        # override it so the iOS UI shows the correct coaching tone badge.
        if self._detect_injury_context(user_message) and parsed.get("tone") not in {"concerned"}:
            parsed["tone"] = "concerned"

        # ── response length guard ──────────────────────────────────────────────────────
        # A response under 80 chars is almost certainly truncated or empty.
        if len(parsed.get("response", "")) < 80:
            print(f"[AI Normalize] ⚠️ GPT response suspiciously short ({len(parsed.get('response', ''))} chars) — flagging")

        # ── football 1v1 / solo-match constraint enforcement ───────────────────────
        # Football is a team sport. If GPT generated a 1v1 or solo-match framing,
        # attempt an inline repair. If repair is not possible, log clearly for
        # debugging — the response still returns so the user doesn't hit a dead end.
        if sport == models.Sport.FOOTBALL:
            response_text = parsed.get("response", "")
            football_violation = self._detect_football_violation(response_text)
            if football_violation:
                repaired = self._repair_football_response(response_text)
                if repaired:
                    parsed["response"] = repaired
                    print(f"[AI Normalize] ⚠️ Football 1v1 violation repaired inline (sport=football)")
                else:
                    # HARD STOP: Never return an unrepaired football 1v1 response to the client.
                    # The backend must be safe independently of any iOS-side second defense layer.
                    print(f"[AI Normalize] 🚨 Football 1v1 HARD STOP — "
                          f"replacing unsafe response with safe team-context fallback; pattern='{football_violation}'")
                    parsed["response"] = (
                        "Football is a team sport — growth happens in a team environment. "
                        "Let's focus on your role in the team scheme. "
                        "What position do you play, and which aspect of team play do you want to improve?"
                    )
                    parsed["suggested_actions"] = [
                        "Review my position responsibilities",
                        "Work on team footwork and route running",
                        "Ask my coach about my development plan",
                    ]
                    parsed["tone"] = "supportive"
                    parsed["follow_up_questions"] = [
                        "What does your coach say is your biggest area for improvement?",
                        "Which team-play skill feels hardest right now?",
                    ]
                    parsed["constraint_enforced"] = True
                    return parsed  # Hard stop — return safe fallback immediately; do not fall through
                # Repair succeeded — reinforce team context in suggested actions
                team_action = "Ask your coach about team drill opportunities"
                if team_action not in parsed.get("suggested_actions", []):
                    parsed["suggested_actions"] = [team_action] + parsed.get("suggested_actions", [])[:2]

        return parsed

    # ── Football constraint helpers ─────────────────────────────────────────────

    _FOOTBALL_1V1_PATTERNS = [
        r"\b1\s*v\s*1\b",
        r"\bone[\s-]on[\s-]one\b",
        r"\bone\s*vs\.?\s*one\b",
        r"\bvs\.?\s+(?:an?\s+)?opponent\b",
        r"\bsolely you vs\b",
        r"\bplay against one player\b",
        r"\bindividual competition\b",
        r"\bsingle opponent\b",
        r"\bisolation match\b",
        r"\bgo up against one person\b",
    ]

    def _detect_football_violation(self, text: str) -> Optional[str]:
        """Returns the first matched 1v1/solo-match violation pattern string, or None."""
        lowered = text.lower()
        for pattern in self._FOOTBALL_1V1_PATTERNS:
            match = re.search(pattern, lowered)
            if match:
                return match.group(0)
        return None

    def _repair_football_response(self, text: str) -> Optional[str]:
        """
        Replaces 1v1/solo-match language with team-context equivalents.
        Returns None if the text still contains a violation after all replacements
        (repair failed — caller should log and pass through as-is).
        """
        replacements = [
            (r"\b1\s*v\s*1\b",                  "route-running drill with QB timing"),
            (r"\bone[\s-]on[\s-]one\b",          "team-based drill with position assignments"),
            (r"\bone\s*vs\.?\s*one\b",            "team-based position matchup drill"),
            (r"\bvs\.?\s+(?:an?\s+)?opponent\b",  "vs. the scout-team defense in formation"),
            (r"\bsolely you vs\b",                "you and your unit vs"),
            (r"\bplay against one player\b",      "run team drills against your position group"),
            (r"\bindividual competition\b",       "team competition drill"),
            (r"\bsingle opponent\b",              "position-group opponent in scheme"),
            (r"\bisolation match\b",              "team position-group drill"),
            (r"\bgo up against one person\b",     "compete in a team-drill setting"),
        ]
        result = text
        for pattern, replacement in replacements:
            result = re.sub(pattern, replacement, result, flags=re.IGNORECASE)
        # If the violation is still detectable, return None to signal repair failure
        return None if self._detect_football_violation(result) else result

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

        # SAFETY-CRITICAL: Injury check must be FIRST — before workout/practice/drill keywords.
        # "I twisted my ankle during practice" contains "practice" which would otherwise
        # trigger the workout path and return a training plan instead of a safety warning.
        if any(kw in msg_lower for kw in _INJURY_KEYWORDS):
            return {
                "response": (
                    "That sounds uncomfortable — please stop any activity that causes pain.\n\n"
                    "Here's what I'd suggest:\n"
                    "• Rest the affected area and avoid movements that reproduce the pain\n"
                    "• Apply ice (15–20 min) to reduce swelling if there is any\n"
                    "• For mild soreness: light mobility work and stretching are usually fine\n\n"
                    "If the pain is sharp, persistent, or gets worse with any movement, please consult "
                    "a sports medicine professional or physiotherapist before returning to training. "
                    "I'm a coaching tool, not a medical resource — your safety comes first."
                ),
                "suggested_actions": ["Rest today", "Schedule a check-up if pain persists"],
                "tone": "concerned",
                "follow_up_questions": ["How long have you been feeling this?"]
            }

        # Schedule / multi-day plan request (check BEFORE single-workout check)
        schedule_keywords = ['schedule', 'weekly', 'week plan', 'training plan',
                             'program', 'days a week', 'multi-day', 'day 1', 'day 2',
                             'make a plan', 'build a plan', 'this week', 'week of']
        if any(kw in msg_lower for kw in schedule_keywords):
            duration_per_session = context.get('available_time_minutes', 45)
            schedule_text = self._generate_multiday_schedule(
                sport=sport,
                duration_per_session=duration_per_session,
                skill_level=context.get('skill_level', 'intermediate'),
                recovery_score=context.get('recovery_score', 75)
            )
            return {
                "response": f"Here's your {sport.value} training schedule:\n\n{schedule_text}",
                "suggested_actions": ["Open Train section", "Log each session when done"],
                "tone": "motivating",
                "follow_up_questions": ["Which day do you want to start with?"]
            }

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
        if any(word in msg_lower for word in ['improve', 'better', 'weak', 'struggle', 'help with', 'help me', 'require', 'need to work', 'i need help']):
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

    def _generate_multiday_schedule(
        self,
        sport: models.Sport,
        duration_per_session: int = 45,
        skill_level: str = "intermediate",
        recovery_score: int = 75
    ) -> str:
        """Generate a 4-day sport-specific training schedule with varied daily focus."""

        warmup_mins = max(5, duration_per_session // 10)
        cooldown_mins = 5
        work_mins = duration_per_session - warmup_mins - cooldown_mins

        sport_configs = {
            models.Sport.BASKETBALL: {
                "day_focuses": [
                    ("Shooting & Scoring", ["3-point shooting: 10 shots from 5 spots", "Free throws: 30 makes", "Mid-range pull-up: 20 reps"]),
                    ("Ball Handling & Playmaking", ["Figure-8s through legs: 3×1 min", "Crossover combo: 3×30 reps", "Full-court dribble series: 5 runs"]),
                    ("Defense & Conditioning", ["Defensive slides: 3×45 sec", "Closeout drills: 3×10 reps", "Suicide runs: 6 reps"]),
                    ("Footwork & Finishing", ["Mikan drill: 3×20 layups", "Euro-step layup: 3×10 each side", "Pivot series: 3×15 reps"]),
                ],
                "warmup": "Dynamic stretch + 5-min dribble warm-up",
                "cooldown": "Static quad/hip stretch + deep breathing",
            },
            models.Sport.FOOTBALL: {
                "day_focuses": [
                    ("Route Running & Release", ["Stem routes: 4 routes × 5 reps each", "Release off the line: 3×10 burst reps", "Dig/slant route precision: 3×8 reps"]),
                    ("Catching & Hands", ["Tennis-ball drops: 3×20 catches", "High/low catch ladder: 3×10", "One-hand concentration catches: 3×15 each hand"]),
                    ("Speed & First-Step Explosion", ["40-yard accelerations: 6 reps", "Resistance band drives: 3×10", "Pro-agility shuttle: 5 reps"]),
                    ("Blocking & Strength Angles", ["Pad-level stance holds: 3×30 sec", "Drive-block steps: 3×10 each side", "Pass-pro footwork mirror: 3×30 sec"]),
                ],
                "warmup": "High knees, butt kicks, hip openers — 5 min",
                "cooldown": "Hamstring/hip flexor stretch + shoulder rolls",
            },
            models.Sport.SOCCER: {
                "day_focuses": [
                    ("First Touch & Dribbling", ["Cone weave: 3×1 min each foot", "First-touch chest/thigh control: 3×20", "1v1 dribbling box: 4×2 min"]),
                    ("Passing & Vision", ["Wall-pass accuracy: 50 reps each foot", "Triangle passing drill: 3×5 min", "Switch-field long ball: 3×10 each foot"]),
                    ("Shooting & Finishing", ["Shots from edge of box: 25 reps", "One-touch finish in box: 3×10", "Volley practice: 3×10"]),
                    ("Defending & Conditioning", ["Jockeying drill: 3×1 min", "Tackle timing: 3×10", "10×40m sprint intervals"]),
                ],
                "warmup": "Jogging, dynamic leg swings, ball juggling",
                "cooldown": "Hip flexor, quad, and calf stretch",
            },
            models.Sport.TENNIS: {
                "day_focuses": [
                    ("Serve & Return", ["First-serve placement: 30 serves", "Second-serve kick spin: 20 serves", "Return of serve drives: 3×15"]),
                    ("Forehand Consistency", ["Cross-court topspin rally: 3×5 min", "Inside-out forehand: 3×15", "Running forehand finish: 3×10"]),
                    ("Backhand & Net Play", ["Backhand cross-court rally: 3×5 min", "Approach + volley combo: 3×10", "Overhead smash: 3×15"]),
                    ("Footwork & Match Play", ["Ladder drills: 3×1 min", "Cone split-step reaction: 3×10", "Full point play-out rally: 3×10 min"]),
                ],
                "warmup": "Mini-tennis warm-up + light footwork ladder",
                "cooldown": "Shoulder, forearm, and wrist mobility stretch",
            },
        }

        cfg = sport_configs.get(sport, sport_configs[models.Sport.BASKETBALL])
        days = ["Day 1", "Day 2", "Day 3", "Day 4"]

        lines: List[str] = []
        for i, day_label in enumerate(days):
            focus_name, drills = cfg["day_focuses"][i % len(cfg["day_focuses"])]
            lines.append(f"**{day_label} — {focus_name}** ({duration_per_session} min)")
            lines.append(f"  Warmup ({warmup_mins} min): {cfg['warmup']}")
            for drill in drills:
                lines.append(f"  • {drill}")
            lines.append(f"  Cooldown ({cooldown_mins} min): {cfg['cooldown']}")
            lines.append("")

        if recovery_score < 50:
            lines.append("⚠️ Recovery note: Your recovery score is low — keep intensities moderate and prioritize sleep each night.")

        lines.append(f"Log each session in the Train tab to track your progress this week!")
        return "\n".join(lines)

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
            models.Sport.SOCCER: ["Dribbling", "Passing", "Finishing", "First touch"],
            models.Sport.TENNIS: ["Serve", "Forehand", "Backhand", "Footwork"],
            models.Sport.FOOTBALL: ["Throwing", "Catching", "Route running", "Blocking"]
        }
        return skills.get(sport, skills[models.Sport.BASKETBALL])

    def _extract_skill(self, message: str, sport: models.Sport) -> Optional[str]:
        """Extract mentioned skill from message, using sport-specific keyword aliases first."""
        # Alias map checked first; entries are ordered longest-phrase-first to avoid
        # "throw" matching before "throwing mechanics" in the same message.
        for keyword, canonical in _SPORT_SKILL_ALIASES.get(sport.value, []):
            if keyword in message:
                return canonical
        # Fall back to direct skill name match
        for skill in self._get_sport_skills(sport):
            if skill.lower() in message:
                return skill.lower()
        return None

    def _get_skill_drills(self, sport: models.Sport, skill: str) -> List[str]:
        """Get drills for specific skill — returns sport-correct drills only."""
        basketball_drills = {
            "shooting": [
                "Form shooting from 5 feet — 3×15 reps, focus on follow-through",
                "Catch-and-shoot from 5 spots (10 each = 50 makes)",
                "Free throws under fatigue — 50 makes, jog in place between sets",
                "Off-dribble pull-ups from mid-range — 3×10"
            ],
            "ball handling": [
                "Two-ball stationary dribbling — 3×2 min",
                "Figure-8 dribbles through legs — 3×90s",
                "Full-court combo moves (crossover → behind-back) — 5 trips",
                "Change-of-pace speed dribble — 4×full-court"
            ],
            "defense": [
                "Defensive slides across the lane — 6×full width",
                "Closeout-and-contest drill — 3×12 reps",
                "Shell drill positioning — 10 min with partner",
                "Help-and-recover rotations — 3×8 sequences"
            ],
            "finishing": [
                "Mikan Drill (alternating layups) — 3×30s",
                "Euro-step layup — 3×10 each side",
                "Contact finishing against pad — 3×8",
                "Weak-hand layup progression — 3×12"
            ]
        }

        soccer_drills = {
            "dribbling": [
                "Cone slalom — both feet, 4×full length",
                "Speed dribble with direction change every 5m — 5 trips",
                "1v1 move (elastico/cruyff) against stationary cone — 3×15",
                "Tight space ball retention (5×5 yard box) — 4×90s"
            ],
            "passing": [
                "Wall passes for accuracy — 3×30 each foot",
                "Long diagonal switching — 4×10 each foot",
                "Through-ball to target zone — 3×15",
                "One-touch combination passing — 10 min continuous"
            ],
            "finishing": [
                "Volley finish from cross — 3×10",
                "Near-post run and finish — 3×8",
                "Shooting from edge of box — 4×8, placement focus",
                "1v1 vs. goalkeeper simulation — 15 reps"
            ],
            "first touch": [
                "Lofted ball control with instep — 3×15",
                "Turn on first touch from wall pass — 3×12 each side",
                "Chest control and volley — 3×10",
                "Bouncing ball first touch — 3×12"
            ]
        }

        football_drills = {
            "throwing": [
                "3-step drop, feet set before release — 10 reps to short zones each side",
                "5-step drop with hitch, throw intermediate — 8 reps per target zone",
                "Seated throw drill — isolate hip/shoulder rotation, 3×10 each side",
                "Towel drill on wall — 20 reps, same release point and follow-through every time"
            ],
            "route running": [
                "5-yard out route with sharp break — 3×15 each side",
                "Slant from the slot — full speed, 3×12",
                "Post route vs. air — back-shoulder timing — 3×10",
                "Option route reading coverage — 15 reps with coverage call at line"
            ],
            "catching": [
                "Tennis ball reaction drill (drop-and-catch) — 3×10",
                "Back-shoulder catch on sideline — 3×12 each side",
                "High-point contested catch — 3×8 jump balls",
                "Jugs machine or thrown balls — 30 consecutive catches"
            ],
            "blocking": [
                "Stalk block footwork — 3×8 on stationary pad",
                "Run-after-catch screen block — 3×10 reps",
                "Reach block footwork vs. shade — 3×6",
                "Sustain block for 3-second count — 3×8"
            ],
            "speed": [
                "10-yard burst from receiver stance — 8× full recovery",
                "Pro-agility 5-10-5 shuttle — 6× full recovery",
                "Flying 20s (20m build-up + 20m full speed) — 6 reps",
                "Resisted sprint with band release — 4×20m"
            ],
            "footwork": [
                "5-cone release drill — 3×15 each direction",
                "Ladder: high-knees, lateral shuffle, crossover — 4 sets",
                "Stem-and-break at full speed — 3×20 reps",
                "3-step release off press coverage — 3×12 each side"
            ],
            "conditioning": [
                "110-yard sprint series — 8× at 90% effort (60s rest)",
                "Route-tree conditioning run — full tree without stopping, 3 rounds",
                "Position-specific interval: 4×3min on / 90s off",
                "Cone agility run — 10 consecutive reps at game speed"
            ]
        }

        tennis_drills = {
            "serve": [
                "Toss-only drill — 20 reps, focus on consistency",
                "Flat serve placement (T, body, wide) — 10 each location",
                "Kick serve at 60% — 20 reps, feel the topspin",
                "Full serve-plus-one combination — 15 reps to deuce and ad court"
            ],
            "forehand": [
                "Inside-out forehand from center — 3×10 fed balls",
                "Cross-court forehand sustained rally — 3×6 min",
                "Open-stance forehand on the run — 3×15",
                "Forehand approach shot + putaway — 20 combinations"
            ],
            "backhand": [
                "Two-handed loading and contact point drill — 3×10",
                "Cross-court backhand rally — 3×6 min",
                "Backhand slice approach — 3×15",
                "Backhand down-the-line under pressure — 3×12"
            ],
            "footwork": [
                "Split-step timing drill — 3×15 reps each side",
                "Sideline-to-sideline shuffle recovery — 4×90s",
                "Figure-8 cone pattern — 4×30s",
                "Approach-shot footwork sequence — 3×15 each direction"
            ],
            "volley": [
                "Stationary punch volley at net — 3×15 each side",
                "Approach-and-first-volley combination — 20 reps",
                "Rapid-fire reflex volley — 3×12",
                "Half-volley pickup drill — 3×15"
            ]
        }

        # Route to the correct sport's drill dictionary.
        # NO silent cross-sport fallbacks — each sport has its own default.
        if sport == models.Sport.BASKETBALL:
            default_drills = basketball_drills["shooting"]
            return basketball_drills.get(skill, default_drills)
        elif sport == models.Sport.SOCCER:
            default_drills = soccer_drills["dribbling"]
            return soccer_drills.get(skill, default_drills)
        elif sport == models.Sport.FOOTBALL:
            default_drills = football_drills["footwork"]
            return football_drills.get(skill, default_drills)
        elif sport == models.Sport.TENNIS:
            default_drills = tennis_drills["footwork"]
            return tennis_drills.get(skill, default_drills)
        else:
            # Unknown sport — return sport-labeled generic drills rather than wrong-sport drills
            return [
                f"Practice {skill} fundamentals for {sport.value}",
                f"Focus on technique and form in {skill}",
                f"Work with a {sport.value} coach on {skill} improvement"
            ]

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
