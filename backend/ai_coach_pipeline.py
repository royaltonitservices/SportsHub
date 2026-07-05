"""AI Coach pipeline — staged, assistant-style request flow.

This module makes the AI Coach behave like a real assistant pipeline rather than
a single keyword router:

    user message
      -> resolve_coach_context   (sport priority, explicit-mention override)
      -> classify_coach_intent   (LLM JSON when a key exists; degraded otherwise)
      -> plan_retrieval          (does this intent need source material?)
      -> retrieve (ai_knowledge_base)   (ranked curated sources)
      -> generate (in ai_orchestrator)  (GPT with snippets, or safe fallback)
      -> build_coach_actions     (TYPED chips, default conversational)

Design notes / honesty contract:
  • Dependency-light on purpose: imports only `ai_knowledge_base` + stdlib, so it
    is unit-testable in isolation (no openai / sqlalchemy needed).
  • The LLM branch of `classify_coach_intent` is implemented and ready, but is only
    taken when the orchestrator passes a working `llm_call`. With no OPENAI_API_KEY
    it is never reached locally — we do NOT fake GPT behavior.
  • Sport priority guarantees the coach never answers in football when the user
    explicitly says tennis or soccer.
  • Retrieval is delegated to the curated registry; an empty result means NO
    source-backed claim is allowed (the caller must not invent citations).
"""

import json
import re
from typing import Callable, Dict, List, Optional

from ai_knowledge_base import retrieve_coach_source_entries, public_source

SUPPORTED_SPORTS = ["basketball", "football", "soccer", "tennis"]

# Canonical intents the coach understands. The assistant is a general assistant
# with deep sports specialization — general intents are first-class, NOT redirected
# back to sports.
INTENTS = [
    # General assistant
    "greeting_social",
    "general_conversation",
    "general_question",
    "arithmetic",
    "explanation_request",
    "writing_help",
    "planning_help",
    "emotional_support",
    "current_or_source_needed",
    # Sport coaching
    "training_plan",
    "drill_request",
    "drill_explanation",
    "drill_modification",
    "recovery",
    "nutrition_hydration",
    "rules_question",
    "sport_context_update",
    "progress_readiness",
    "challenge_request",
    # Safety / app / other
    "injury_safety",
    "app_navigation",
    "unsafe_or_disallowed",
    "unclear",
]

# Intents that are general-assistant (not sport coaching). Used by the orchestrator
# so benign questions are NOT answered with workout templates in degraded mode.
GENERAL_INTENTS = {
    "greeting_social", "general_conversation", "general_question", "arithmetic",
    "explanation_request", "writing_help", "planning_help", "emotional_support",
    "current_or_source_needed", "unsafe_or_disallowed",
}

# Typed actions the iOS client can honor today. We deliberately only emit types
# that have a real destination/behavior — no dead navigation.
ACTION_CONVERSATIONAL = "conversational_reply"
ACTION_EXPLAIN_DRILL = "explain_drill"
ACTION_OPEN_DRILL_LIBRARY = "open_drill_library"
ACTION_LOG_SESSION = "log_session"

# ── Keyword sets (single source of truth, imported by ai_orchestrator) ──────────

INJURY_KEYWORDS = [
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
    # Inability to bear weight is a red flag — must not depend on the model alone.
    "can't put weight", "cant put weight", "can't bear weight", "cant bear weight",
    "can't stand on", "cant stand on", "can't walk", "cant walk", "put weight on",
    "concussion", "dizzy", "dizziness",
    "hit in the head", "hit my head", "head impact",
]

HEAD_IMPACT_KEYWORDS = [
    "concussion", "dizzy", "dizziness", "hit in the head", "hit my head",
    "head impact", "headache", "blurry", "blurred vision", "knocked out",
    "blacked out", "nausea",
]

RECOVERY_KEYWORDS = [
    "tired", "exhausted", "fatigue", "fatigued", "burnout", "burned out",
    "overtraining", "overtrained", "rest day", "drained", "worn out",
    "need rest", "need a rest", "recover", "recovery",
]

_NUTRITION_KEYWORDS = [
    "eat", "eating", "food", "meal", "snack", "diet",
    "hydrate", "hydration", "water", "drink", "nutrition", "fuel", "fueling",
    "carbs", "protein", "cramp", "cramping", "dehydrated",
    "before a game", "before practice", "what should i eat",
]

_RULES_KEYWORDS = [
    "rule", "rules", "is it legal", "legal", "offside", "double dribble",
    "foul", "out of bounds", "how many players", "allowed to", "regulation",
    "fault", "let", "handball",
]

_DRILL_EXPLAIN_PHRASES = [
    "explain", "how do i do", "how to do", "what is the", "another drill",
    "break it down", "walk me through", "show me how",
]

_DRILL_REQUEST_PHRASES = [
    "drill", "drills", "give me drills", "drills for",
]

_TRAINING_PLAN_PHRASES = [
    "workout", "session", "training plan", "routine", "schedule",
    "train", "practice plan", "conditioning", "warm up", "warmup",
]

# Skill-improvement phrasing — athletes state a focus as a need ("help my serve",
# "I want to improve my left hand"). Routes to coaching/training, not unclear.
_IMPROVEMENT_PHRASES = [
    "improve", "get better", "getting better", "work on", "working on",
    "help me with", "help my", "focus on", "struggle with", "i struggle",
    "weak", "i want to", "i need to", "how do i get better",
]

_PROGRESS_PHRASES = [
    "how am i doing", "am i improving", "my progress", "my stats",
    "my streak", "readiness", "how ready", "am i ready",
]

_APP_NAV_PHRASES = [
    "how do i log", "where is", "open the", "how do i find",
    "how do i save", "which tab", "how does premium",
]

_GREETING_PREFIXES = ["hi", "hey", "hello", "yo ", "sup", "good morning",
                      "good afternoon", "good evening", "morning", "howdy"]
_GREETING_SOCIAL = ["how are you", "how are u", "how r u", "how's it going",
                    "hows it going", "what's up", "whats up", "how ya doing",
                    "thanks", "thank you", "appreciate it"]

_SPORT_CONTEXT_MARKERS = ["mode", "switch to", "switch me to", "change to",
                          "let's do", "lets do", "play "]

# General-assistant phrasing (first-class — NOT redirected to sports).
_EMOTIONAL_PHRASES = [
    "bad day", "rough day", "tough day", "nervous", "anxious", "anxiety",
    "stressed", "stressful", "i'm sad", "im sad", "feeling down", "upset",
    "frustrated", "worried", "scared", "overwhelmed", "i feel bad",
]
_WRITING_PHRASES = [
    "help me text", "help me write", "help me message", "write a message",
    "rephrase", "reword", "make this more", "make it more polite",
    "help me ask", "how do i say", "draft a", "help me tell",
]
_PLANNING_PHRASES = [
    "help me plan", "plan my", "what should i do first", "help me organize",
    "help me prioritize", "organize my", "what should i pack",
]
_EXPLANATION_PHRASES = [
    "what does", "what is", "what's the difference", "difference between",
    "explain", "define", "meaning of", "what do you mean by",
]
_GENERAL_QUESTION_PREFIXES = [
    "why is", "why does", "why do", "how does", "how do you", "what causes",
    "who is", "who was", "where is", "when did", "when was",
]
_CHALLENGE_PHRASES = [
    "make me a challenge", "create a challenge", "challenge idea",
    "give me a challenge", "shooting challenge", "make a challenge",
    "set up a challenge", "design a challenge",
]
_DRILL_MODIFY_PHRASES = [
    "make it harder", "make that harder", "make it easier", "make that easier",
    "harder version", "easier version", "make it easier on", "too hard",
    "too easy", "less intense", "more intense", "tougher",
]
# Requests to fabricate evidence or endorse an unsafe premise — refuse, never comply.
_UNSAFE_PHRASES = [
    "make up a", "make up a study", "make something up", "fabricate",
    "invent a source", "cite a source even", "cite something even",
    "even if you don't have", "even if you dont have", "prove my workout",
    "concussion is safe", "playing through a concussion is safe",
    "play through a concussion", "safe to play through a concussion",
]


# ── Helpers ─────────────────────────────────────────────────────────────────────


def evaluate_arithmetic(message: str) -> Optional[str]:
    """Deterministically evaluate a simple two-operand arithmetic expression.

    Honest: this is real computation, not model output. Returns the result as a
    string, or None when the message isn't a plain arithmetic expression or
    contains sport/coaching vocabulary (so "how many reps" is NOT math)."""
    low = message.lower()
    guard = ["rep", "set", "drill", "workout", "session", "minute", "point",
             "score", "basketball", "football", "soccer", "tennis", "mile"]
    if any(g in low for g in guard):
        return None
    if not any(c.isdigit() for c in low):
        return None
    expr = low
    for word, sym in [(" divided by ", "/"), (" multiplied by ", "*"),
                      (" times ", "*"), (" plus ", "+"), (" minus ", "-"),
                      ("×", "*"), ("÷", "/")]:
        expr = expr.replace(word, sym)
    for pre in ["what is ", "what's ", "whats ", "calculate ", "compute ", "solve "]:
        expr = expr.replace(pre, "")
    expr = expr.strip().strip("?!.,;:")
    m = re.match(r"^(-?\d+(?:\.\d+)?)\s*([+\-*/])\s*(-?\d+(?:\.\d+)?)$", expr)
    if not m:
        return None
    left, op, right = float(m.group(1)), m.group(2), float(m.group(3))
    if op == "+":
        val = left + right
    elif op == "-":
        val = left - right
    elif op == "*":
        val = left * right
    else:
        if right == 0:
            return None
        val = left / right
    return str(int(val)) if val == int(val) else f"{val:.4g}"

def _contains_any(low: str, items: List[str]) -> bool:
    return any(item in low for item in items)


def mentioned_sport(message: str) -> Optional[str]:
    """Return the single sport explicitly named, or None if zero/multiple
    (ambiguous). Word-boundary matched so 'foot' doesn't match 'football' etc."""
    low = message.lower()
    found = [s for s in SUPPORTED_SPORTS if re.search(r"\b" + s + r"\b", low)]
    return found[0] if len(found) == 1 else None


# ── Stage A: context resolution ─────────────────────────────────────────────────

def resolve_coach_context(
    user_message: str,
    selected_sport: Optional[str],
    profile_sport: Optional[str] = None,
) -> Dict:
    """Resolve the sport the coach should answer in.

    Priority: explicit sport in message > selected sport (app) > profile/default.
    The resolved sport NEVER becomes football when the user explicitly named
    tennis or soccer.
    """
    explicit = mentioned_sport(user_message)
    selected = (selected_sport or "").lower() or None
    profile = (profile_sport or "").lower() or None

    if explicit:
        resolved, confidence, note = explicit, 1.0, "explicit sport in message"
    elif selected:
        resolved, confidence, note = selected, 0.7, "app-selected sport"
    elif profile:
        resolved, confidence, note = profile, 0.5, "profile/default sport"
    else:
        resolved, confidence, note = None, 0.0, "no sport resolved — clarify"

    return {
        "resolved_sport": resolved,
        "explicit_sport_mentioned": explicit is not None,
        "confidence": confidence,
        "context_notes": note,
    }


# ── Stage B: intent classification ──────────────────────────────────────────────

def _degraded_intent(user_message: str) -> Dict:
    """Deterministic, structured intent classification used when no LLM is
    available. Ordered by safety/specificity — not a flat keyword bag."""
    low = user_message.lower().strip()

    def result(intent, *, safety="none", sources=False, clarify=False, tool=None, conf=0.6):
        return {
            "intent": intent,
            "confidence": conf,
            "safety_level": safety,
            "needs_sources": sources,
            "needs_clarification": clarify,
            "suggested_tool_action": tool,
        }

    # 0. Refuse fabrication / unsafe premises before anything else.
    if _contains_any(low, _UNSAFE_PHRASES):
        return result("unsafe_or_disallowed", safety="caution", conf=0.9)

    # 1. Safety first — injury, with head-impact escalation.
    if _contains_any(low, INJURY_KEYWORDS):
        if _contains_any(low, HEAD_IMPACT_KEYWORDS):
            return result("injury_safety", safety="high", sources=True, conf=0.9)
        return result("injury_safety", safety="caution", sources=True, conf=0.85)

    # 2. Plain arithmetic — a direct, deterministic answer (no sports redirect).
    if evaluate_arithmetic(user_message) is not None:
        return result("arithmetic", conf=0.9)

    # 3. Emotional statements — acknowledge, don't prescribe a workout.
    if _contains_any(low, _EMOTIONAL_PHRASES):
        return result("emotional_support", conf=0.7)

    # 4. Nutrition / hydration (before recovery so "eat before a game" wins).
    if _contains_any(low, _NUTRITION_KEYWORDS):
        return result("nutrition_hydration", sources=True, conf=0.7)

    # 5. Recovery / fatigue.
    if _contains_any(low, RECOVERY_KEYWORDS):
        return result("recovery", sources=True, conf=0.7)

    # 6. Writing / planning help (general assistant).
    if _contains_any(low, _WRITING_PHRASES):
        return result("writing_help", conf=0.7)
    if _contains_any(low, _PLANNING_PHRASES):
        return result("planning_help", conf=0.7)

    # 7. Rules questions.
    if _contains_any(low, _RULES_KEYWORDS):
        return result("rules_question", sources=True, conf=0.6)

    # 8. Explicit sport-context update ("I'm in tennis mode", "switch to soccer").
    if mentioned_sport(user_message) and _contains_any(low, _SPORT_CONTEXT_MARKERS):
        return result("sport_context_update", conf=0.75)

    # 9. App navigation / help — BEFORE drill/training so "how do I log a session"
    #    is help, not a training plan (the 'session' keyword would otherwise win).
    if _contains_any(low, _APP_NAV_PHRASES):
        return result("app_navigation", conf=0.6)

    # 10. Challenge requests.
    if _contains_any(low, _CHALLENGE_PHRASES):
        return result("challenge_request", conf=0.7)

    # 11. Drill modification (follow-up referencing a prior drill) then explain/request.
    if _contains_any(low, _DRILL_MODIFY_PHRASES):
        return result("drill_modification", conf=0.7)
    if _contains_any(low, _DRILL_EXPLAIN_PHRASES) and "drill" in low:
        return result("drill_explanation", sources=True, conf=0.7)
    if _contains_any(low, _DRILL_REQUEST_PHRASES):
        return result("drill_request", sources=True, conf=0.7)

    # 12. Training plans / sessions / skill-improvement requests.
    if _contains_any(low, _TRAINING_PLAN_PHRASES) or _contains_any(low, _IMPROVEMENT_PHRASES):
        return result("training_plan", sources=True, conf=0.65)

    # 13. Progress / readiness.
    if _contains_any(low, _PROGRESS_PHRASES):
        return result("progress_readiness", conf=0.6)

    # 14. General explanation / question (non-sport). Answered by the LLM when
    #     available; honestly degraded otherwise (see degraded_general_answer).
    if _contains_any(low, _EXPLANATION_PHRASES):
        return result("explanation_request", conf=0.6)
    if any(low.startswith(p) for p in _GENERAL_QUESTION_PREFIXES):
        return result("general_question", conf=0.6)

    # 15. Greeting / social.
    words = low.split()
    if (any(low.startswith(p) for p in _GREETING_PREFIXES) and len(words) <= 6) \
            or _contains_any(low, _GREETING_SOCIAL):
        return result("greeting_social", conf=0.7)

    # 16. Short first-person social statement -> general conversation (not "unclear").
    if words and low.startswith(("i ", "i'm", "im ", "my ", "we ", "it ")) and len(words) <= 12:
        return result("general_conversation", conf=0.45)

    return result("unclear", clarify=True, conf=0.4)


_LLM_INTENT_INSTRUCTION = (
    "You are an intent classifier for a youth sports coaching assistant. "
    "Classify the athlete's message into EXACTLY ONE intent from this list: "
    + ", ".join(INTENTS) + ". "
    "Return STRICT JSON only: {\"intent\": <one of the list>, "
    "\"confidence\": <0..1>, \"safety_level\": \"none\"|\"caution\"|\"high\", "
    "\"needs_sources\": <bool>, \"needs_clarification\": <bool>, "
    "\"suggested_tool_action\": <string or null>}. "
    "safety_level is 'high' for any head impact / concussion / neurological "
    "symptom, 'caution' for other injury/pain, else 'none'. Do not diagnose."
)


def classify_coach_intent(
    user_message: str,
    llm_call: Optional[Callable[[List[Dict]], str]] = None,
) -> Dict:
    """Classify intent. Uses the LLM (`llm_call`) for semantic understanding when
    one is provided by the orchestrator; otherwise falls back to the structured
    deterministic classifier.

    `llm_call(messages)` must return the model's raw text content. Any failure or
    malformed JSON falls back safely — we never crash the coach on classification.
    """
    if llm_call is not None:
        try:
            messages = [
                {"role": "system", "content": _LLM_INTENT_INSTRUCTION},
                {"role": "user", "content": user_message},
            ]
            raw = llm_call(messages)
            parsed = json.loads(_extract_json(raw))
            intent = parsed.get("intent")
            if intent in INTENTS:
                return {
                    "intent": intent,
                    "confidence": float(parsed.get("confidence", 0.7)),
                    "safety_level": parsed.get("safety_level", "none"),
                    "needs_sources": bool(parsed.get("needs_sources", False)),
                    "needs_clarification": bool(parsed.get("needs_clarification", False)),
                    "suggested_tool_action": parsed.get("suggested_tool_action"),
                }
        except Exception:
            pass  # Fall through to degraded — never fail the request on classification.
    return _degraded_intent(user_message)


def _extract_json(text: str) -> str:
    """Pull the first {...} JSON object out of a model response."""
    match = re.search(r"\{.*\}", text or "", re.DOTALL)
    return match.group(0) if match else "{}"


# ── Stage C: retrieval planning ─────────────────────────────────────────────────

# Intent -> (needs_sources, registry retrieval intent). Intents not listed here
# default to (False, "general") — general-assistant intents don't retrieve sources.
_INTENT_RETRIEVAL = {
    "injury_safety": (True, "injury"),
    "recovery": (True, "recovery"),
    "nutrition_hydration": (True, "training"),
    "rules_question": (True, "general"),       # no rules sources yet -> honest []
    "drill_explanation": (True, "training"),
    "drill_request": (True, "training"),
    "drill_modification": (True, "training"),
    "training_plan": (True, "training"),
    "challenge_request": (False, "general"),
    "current_or_source_needed": (True, "general"),
    "progress_readiness": (False, "general"),
    "sport_context_update": (False, "general"),
    "app_navigation": (False, "general"),
    "greeting_social": (False, "general"),
    "general_conversation": (False, "general"),
    "general_question": (False, "general"),
    "arithmetic": (False, "general"),
    "explanation_request": (False, "general"),
    "writing_help": (False, "general"),
    "planning_help": (False, "general"),
    "emotional_support": (False, "general"),
    "unsafe_or_disallowed": (False, "general"),
    "unclear": (False, "general"),
}


def plan_retrieval(intent_result: Dict) -> Dict:
    """Decide whether source retrieval is warranted and which registry intent
    to use. Honors an explicit `needs_sources` from the (LLM) classifier."""
    intent = intent_result.get("intent", "unclear")
    default_needs, retrieval_intent = _INTENT_RETRIEVAL.get(intent, (False, "general"))
    needs = intent_result.get("needs_sources", default_needs) or default_needs
    return {"needs_sources": needs, "retrieval_intent": retrieval_intent}


# ── Answer planner: direct answer vs investigation vs safety vs tool ────────────

def plan_answer(intent_result: Dict) -> Dict:
    """Decide HOW to answer: direct, retrieve, safety, clarify, or tool.

    Observable decision policy (no hidden chain-of-thought): the mode is a pure
    function of the classified intent + safety + retrieval needs."""
    intent = intent_result.get("intent", "unclear")
    safety = intent_result.get("safety_level", "none")
    retrieval = plan_retrieval(intent_result)

    if intent == "unsafe_or_disallowed":
        mode = "refuse"
    elif safety in ("caution", "high") or intent == "injury_safety":
        mode = "safety"
    elif intent in ("arithmetic", "greeting_social", "general_conversation",
                    "emotional_support", "writing_help", "planning_help",
                    "explanation_request", "sport_context_update"):
        mode = "direct"
    elif intent == "app_navigation":
        mode = "tool"
    elif retrieval["needs_sources"] or intent == "current_or_source_needed":
        mode = "retrieve"
    elif intent == "unclear":
        mode = "clarify"
    else:
        mode = "direct"

    return {
        "answer_mode": mode,
        "needs_sources": retrieval["needs_sources"],
        "needs_current_information": intent == "current_or_source_needed",
        "retrieval_intent": retrieval["retrieval_intent"],
    }


# ── Degraded general-assistant answers (no LLM) — honest, never sports-forcing ──

def degraded_general_answer(intent: str, user_message: str) -> Optional[Dict]:
    """Return a safe, HONEST degraded response for general-assistant intents when
    no model is available, or None if this intent isn't a general one.

    Rules: never force the topic into sports; never fabricate; be explicit that
    free-form help needs the online assistant. Arithmetic is answered for real."""
    base = {"suggested_actions": [], "tone": "supportive", "follow_up_questions": []}

    if intent == "arithmetic":
        ans = evaluate_arithmetic(user_message)
        if ans is not None:
            return {**base, "response": f"That's {ans}.", "tone": "supportive"}

    if intent == "greeting_social":
        return {**base, "response": "Hey! I'm doing well and ready to help. "
                "What's on your mind — training, a question, or just to talk?",
                "suggested_actions": ["Build me a session", "Ask me anything"]}

    if intent == "emotional_support":
        return {**base, "response": "I'm sorry it's been rough — that's completely "
                "understandable. I'm here. Want to talk about it, or would a "
                "light, low-pressure session help take your mind off it?",
                "tone": "supportive",
                "follow_up_questions": ["What's weighing on you most right now?"]}

    if intent in ("writing_help", "planning_help", "general_question",
                  "explanation_request", "general_conversation", "current_or_source_needed"):
        return {**base, "response": "Happy to help with that. Full free-form help "
                "(writing, general questions, planning) works best when my online "
                "assistant is available — right now I'm in offline mode, so I can't "
                "give that its best answer. I can still help with training, drills, "
                "recovery, and coaching. Want to try one of those, or ask again when "
                "I'm back online?",
                "tone": "supportive"}

    if intent == "unsafe_or_disallowed":
        return {**base, "response": "I can't do that — I won't make up studies, "
                "sources, or citations, and I won't tell you it's safe to play "
                "through a head injury. If you're hurt, the safe move is to stop and "
                "get checked by a medical professional. I'm happy to help with real "
                "training, drills, or recovery instead.",
                "tone": "concerned"}

    return None


# ── Stage D: retrieval (thin wrapper over the curated registry) ─────────────────

def retrieve_sources(query: str, sport: Optional[str], retrieval_intent: str, limit: int = 3):
    """Return (full_entries, public_sources). Empty => no source-backed claim."""
    entries = retrieve_coach_source_entries(query, sport, retrieval_intent, limit=limit)
    return entries, [public_source(e) for e in entries]


# ── Stage F: typed action building ──────────────────────────────────────────────

_DRILL_LIBRARY_PHRASES = ["open drill library", "open drills", "browse drills",
                          "show drills", "go to drills", "go to train"]
_SESSION_LOG_PHRASES = ["log session", "log a session", "log workout", "log this",
                        "add to session", "open session log", "track session"]
_EXPLAIN_PHRASES = ["explain", "how do i do", "another drill", "show me how", "walk me through"]


def classify_action(label: str) -> str:
    """Map a suggested-action label to a TYPED action the client can route by
    type instead of guessing from substrings. Default is conversational (stay in
    chat) — navigation only for explicit phrases."""
    a = label.lower()
    if _contains_any(a, _DRILL_LIBRARY_PHRASES):
        return ACTION_OPEN_DRILL_LIBRARY
    if _contains_any(a, _SESSION_LOG_PHRASES):
        return ACTION_LOG_SESSION
    if "drill" in a and _contains_any(a, _EXPLAIN_PHRASES):
        return ACTION_EXPLAIN_DRILL
    return ACTION_CONVERSATIONAL


def build_coach_actions(intent: str, suggested_actions: List[str]) -> List[Dict]:
    """Return typed {label, type} actions. Only types the client honors are
    emitted — no dead navigation."""
    return [{"label": label, "type": classify_action(label)} for label in (suggested_actions or [])]
