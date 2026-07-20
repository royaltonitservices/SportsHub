"""Unit tests for the modernized AI architecture pieces added in the completion pass:

  - central per-user rate limiting (ai_rate_limit)
  - Structured Outputs schema + product-contract validation (ai_orchestrator)
  - provider model selection (ai_provider)

Dependency-light: no live OpenAI calls. The orchestrator is constructed with a
real DB session but only its PURE helpers (schema/map/validate/model-select) are
exercised, so these tests are offline and fast.

Run from the backend directory:
    ../.venv/bin/python -m unittest tests.test_ai_architecture -v
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ai_rate_limit import InMemoryDailyLimiter, DEFAULT_DAILY_MESSAGE_LIMIT
from ai_provider import OpenAIProvider
from config import get_settings
import models


# ── AI Coach daily allowance (the ONLY quota: 200/day, no other limits) ─────────

class DailyLimitTests(unittest.TestCase):
    def setUp(self):
        self.limiter = InMemoryDailyLimiter()

    def test_first_200_allowed_201_rejected(self):
        u = "user-200"
        for i in range(200):
            d = self.limiter.reserve(u, 200)
            self.assertTrue(d.allowed, f"message {i+1} should be allowed")
        d201 = self.limiter.reserve(u, 200)
        self.assertFalse(d201.allowed)
        self.assertEqual(d201.reason, "daily_limit")
        self.assertEqual(d201.remaining, 0)
        self.assertIsNotNone(d201.retry_after_s)

    def test_boundary_199_200(self):
        u = "user-boundary"
        for _ in range(199):
            self.assertTrue(self.limiter.reserve(u, 200).allowed)
        self.assertTrue(self.limiter.reserve(u, 200).allowed)   # 200th
        self.assertFalse(self.limiter.reserve(u, 200).allowed)  # 201st

    def test_release_returns_slot(self):
        # A failed turn with no user-visible reply releases its reserved slot.
        u = "user-release"
        for _ in range(200):
            self.limiter.reserve(u, 200)
        self.assertFalse(self.limiter.reserve(u, 200).allowed)  # at limit
        self.limiter.release(u)                                 # a failure freed one
        self.assertTrue(self.limiter.reserve(u, 200).allowed)   # now allowed again

    def test_release_never_below_zero(self):
        u = "user-underflow"
        self.limiter.release(u)  # nothing reserved
        d = self.limiter.reserve(u, 200)
        self.assertTrue(d.allowed)
        self.assertEqual(d.remaining, 199)

    def test_users_isolated(self):
        for _ in range(200):
            self.limiter.reserve("a", 200)
        self.assertFalse(self.limiter.reserve("a", 200).allowed)
        self.assertTrue(self.limiter.reserve("b", 200).allowed)  # b unaffected

    def test_peek_does_not_consume(self):
        u = "user-peek"
        self.limiter.reserve(u, 200)
        p1 = self.limiter.peek(u, 200)
        p2 = self.limiter.peek(u, 200)
        self.assertEqual(p1.remaining, p2.remaining)  # peek is read-only

    def test_default_limit_is_200(self):
        self.assertEqual(DEFAULT_DAILY_MESSAGE_LIMIT, 200)
        self.assertEqual(get_settings().ai_daily_message_limit, 200)


# ── Provider model selection ────────────────────────────────────────────────────

class ModelSelectionTests(unittest.TestCase):
    def setUp(self):
        self.p = OpenAIProvider(get_settings())
        self.s = get_settings()

    def test_routine_uses_default(self):
        self.assertEqual(self.p.select_model("coach_response"), self.s.ai_default_model)

    def test_checkin_uses_checkin_model(self):
        self.assertEqual(self.p.select_model("checkin"), self.s.ai_checkin_model)

    def test_prior_failure_escalates(self):
        self.assertEqual(self.p.select_model("coach_response", prior_failure=True),
                         self.s.ai_escalation_model)

    def test_high_safety_escalates(self):
        self.assertEqual(self.p.select_model("coach_response", safety_level="high"),
                         self.s.ai_escalation_model)

    def test_arithmetic_never_escalates(self):
        # Routine, low-severity → default, never the expensive escalation model.
        self.assertEqual(self.p.select_model("coach_response", safety_level="none",
                                             complexity="normal"),
                         self.s.ai_default_model)


# ── Structured Outputs schema + contract validation ─────────────────────────────

class _OrchHelper:
    """Lazily build a real orchestrator once (no network at construction)."""
    _o = None

    @classmethod
    def get(cls):
        if cls._o is None:
            from database import SessionLocal
            from ai_orchestrator import AIOrchestrator
            cls._o = AIOrchestrator(SessionLocal())
        return cls._o


class StructuredSchemaTests(unittest.TestCase):
    def setUp(self):
        self.o = _OrchHelper.get()

    def test_schema_constrains_sources_to_retrieved_ids(self):
        schema = self.o._coach_response_schema(["src-1", "src-2"])
        enum = schema["properties"]["sources_used"]["items"]["enum"]
        self.assertEqual(enum, ["src-1", "src-2"])
        self.assertFalse(schema["additionalProperties"])
        for f in ["message", "tone", "suggested_actions", "follow_up_questions", "sources_used"]:
            self.assertIn(f, schema["required"])

    def test_schema_no_enum_when_no_sources(self):
        schema = self.o._coach_response_schema([])
        self.assertNotIn("enum", schema["properties"]["sources_used"]["items"])

    def test_map_structured_response(self):
        data = {"message": "  do work  ", "tone": "motivating",
                "suggested_actions": ["a", "", "b", "c", "d"],
                "follow_up_questions": ["q1", "q2", "q3"],
                "sources_used": ["src-1", "bogus"]}
        m = self.o._map_structured_response(data, ["src-1"])
        self.assertEqual(m["response"], "do work")
        self.assertEqual(m["suggested_actions"], ["a", "b", "c"])   # blanks dropped, capped 3
        self.assertEqual(len(m["follow_up_questions"]), 2)          # capped 2
        self.assertEqual(m["_sources_used"], ["src-1", "bogus"])    # raw kept for validation

    def test_contract_flags_short_message(self):
        v = self.o._validate_coach_contract({"response": "ok", "_sources_used": []},
                                            models.Sport.BASKETBALL, [])
        self.assertIn("message_empty_or_too_short", v)

    def test_contract_flags_invented_source(self):
        parsed = {"response": "x" * 40, "_sources_used": ["ghost-src"]}
        v = self.o._validate_coach_contract(parsed, models.Sport.BASKETBALL, ["real-src"])
        self.assertIn("invented_source_reference", v)

    def test_contract_flags_football_1v1(self):
        parsed = {"response": "Do a 1v1 drill against one opponent to win." + "x" * 20,
                  "_sources_used": []}
        v = self.o._validate_coach_contract(parsed, models.Sport.FOOTBALL, [])
        self.assertIn("football_solo_or_1v1_framing", v)

    def test_contract_passes_valid_response(self):
        parsed = {"response": "Do left-hand pound dribbles, 3 sets of 30 seconds, rest 15.",
                  "_sources_used": []}
        v = self.o._validate_coach_contract(parsed, models.Sport.BASKETBALL, [])
        self.assertEqual(v, [])


# ── Wearable relevance + formatting (pure, offline) ─────────────────────────────

from ai_wearable import wearable_relevant, format_wearable_block


class WearableRelevanceTests(unittest.TestCase):
    def test_relevant_prompts(self):
        for m in ["How hard should I train today?",
                  "Build today's workout around my recovery",
                  "I feel tired, check my recent activity",
                  "How has my training been this week?",
                  "am I recovered enough for a hard workout?",
                  "what did my smartwatch show after practice?"]:
            self.assertTrue(wearable_relevant(m, "training_plan"), m)

    def test_relevant_by_intent(self):
        self.assertTrue(wearable_relevant("anything", "recovery"))
        self.assertTrue(wearable_relevant("anything", "progress_readiness"))

    def test_fitness_tracker_and_synonyms_relevant(self):
        # Regression: "fitness tracker" / "tracker" / brand names / strat / HRV /
        # Apple Watch / smartwatch must all be treated as wearable-related.
        for m in ["Like my fitness tracker", "Can you use my fitness tracker?",
                  "do you know my tracker data?", "Use my Apple Watch data",
                  "what does my smartwatch say?", "do you have my HRV?",
                  "can you see my recovery score?", "what's my training strain?"]:
            self.assertTrue(wearable_relevant(m, "general_conversation"), m)

    def test_irrelevant_prompts(self):
        for m in ["Hi", "What's 25 times 4?", "Why is the sky blue?",
                  "Help me text my coach", "What does consistency mean?",
                  "Give me a left-hand dribbling drill"]:
            self.assertFalse(wearable_relevant(m, "drill_request"), m)


class WearableFormatTests(unittest.TestCase):
    def test_no_data_is_honest(self):
        block = format_wearable_block({"data_available": False, "recent_training": None,
                                       "unavailable_metrics": ["HRV"]})
        self.assertIn("No recent synced wearable", block)
        self.assertIn("Do NOT invent", block)

    def test_fresh_data_lists_only_present_metrics(self):
        ctx = {"data_available": True, "freshness": "fresh", "data_age_days": 0,
               "as_of": "2026-07-05", "metrics": {"recovery_score": 62.0, "sleep_hours": 7.5},
               "recent_training": {"sessions_last_7d": 4, "total_minutes_last_7d": 210},
               "unavailable_metrics": ["HRV", "resting heart rate"]}
        block = format_wearable_block(ctx)
        self.assertIn("62.0/100", block)
        self.assertIn("7.5 h", block)
        self.assertIn("4 sessions", block)
        self.assertIn("Unavailable", block)
        self.assertNotIn("bpm", block)          # resting HR absent → not shown
        self.assertIn("NEVER overrides", block)  # safety-priority rule present

    def test_stale_data_flagged(self):
        ctx = {"data_available": True, "freshness": "stale", "data_age_days": 5,
               "as_of": "2026-06-30", "metrics": {"recovery_score": 55.0},
               "recent_training": None, "unavailable_metrics": []}
        block = format_wearable_block(ctx)
        self.assertIn("STALE", block)


if __name__ == "__main__":
    unittest.main()
