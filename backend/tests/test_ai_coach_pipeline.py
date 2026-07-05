"""Unit tests for the AI Coach pipeline + curated source registry.

Dependency-light: exercises ai_coach_pipeline and ai_knowledge_base only (no
openai / sqlalchemy / fastapi needed). Run from the backend directory:

    ../.venv/bin/python -m unittest tests.test_ai_coach_pipeline -v
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import ai_coach_pipeline as p
import ai_knowledge_base as kb


class ContextResolutionTests(unittest.TestCase):
    def test_explicit_sport_overrides_selected(self):
        # The reported bug: never answer football when the user says tennis/soccer.
        self.assertEqual(p.resolve_coach_context("i'm in tennis mode", "football")["resolved_sport"], "tennis")
        self.assertEqual(p.resolve_coach_context("i'm in soccer mode", "football")["resolved_sport"], "soccer")

    def test_explicit_sport_in_drill_request(self):
        self.assertEqual(p.resolve_coach_context("i want football route drills", "basketball")["resolved_sport"], "football")

    def test_falls_back_to_selected_sport(self):
        ctx = p.resolve_coach_context("give me a workout", "tennis")
        self.assertEqual(ctx["resolved_sport"], "tennis")
        self.assertFalse(ctx["explicit_sport_mentioned"])

    def test_ambiguous_two_sports_uses_selected(self):
        # Two sports named -> no explicit override -> selected sport wins.
        self.assertEqual(p.resolve_coach_context("is basketball better than soccer", "tennis")["resolved_sport"], "tennis")


class IntentClassificationTests(unittest.TestCase):
    def _intent(self, msg):
        return p._degraded_intent(msg)["intent"]

    def test_greeting(self):
        self.assertEqual(self._intent("hi how are u today"), "greeting_social")

    def test_injury(self):
        self.assertEqual(self._intent("my ankle is sore"), "injury_safety")

    def test_head_impact_is_high_safety(self):
        r = p._degraded_intent("i hit my head")
        self.assertEqual(r["intent"], "injury_safety")
        self.assertEqual(r["safety_level"], "high")

    def test_ankle_is_caution_not_high(self):
        self.assertEqual(p._degraded_intent("my ankle is sore")["safety_level"], "caution")

    def test_nutrition(self):
        self.assertEqual(self._intent("what should i eat before a game"), "nutrition_hydration")

    def test_recovery(self):
        self.assertEqual(self._intent("i'm so tired and need a rest day"), "recovery")

    def test_rules(self):
        self.assertEqual(self._intent("is it offside if the defender plays it"), "rules_question")

    def test_sport_context_update(self):
        self.assertEqual(self._intent("i'm in tennis mode"), "sport_context_update")

    def test_drill_explanation(self):
        self.assertEqual(self._intent("explain the first drill"), "drill_explanation")

    def test_drill_request(self):
        self.assertEqual(self._intent("give me drills for left hand dribbling"), "drill_request")

    def test_improvement_is_training_not_unclear(self):
        self.assertEqual(self._intent("help me improve my finishing"), "training_plan")

    def test_app_nav_beats_training(self):
        self.assertEqual(self._intent("how do i log a session"), "app_navigation")

    def test_unclear(self):
        self.assertEqual(self._intent("asdf qwer zxcv"), "unclear")

    def test_llm_call_used_when_provided(self):
        # When an llm_call is provided, its JSON is honored.
        def fake_llm(_messages):
            return '{"intent": "rules_question", "confidence": 0.9, "safety_level": "none", "needs_sources": true, "needs_clarification": false, "suggested_tool_action": null}'
        self.assertEqual(p.classify_coach_intent("anything", llm_call=fake_llm)["intent"], "rules_question")

    def test_llm_bad_json_falls_back(self):
        def broken(_messages):
            return "not json at all"
        # Falls back to deterministic classifier — never crashes.
        self.assertEqual(p.classify_coach_intent("my ankle is sore", llm_call=broken)["intent"], "injury_safety")


class RetrievalTests(unittest.TestCase):
    def test_injury_retrieval_ranked(self):
        ir = p._degraded_intent("my ankle is sore")
        plan = p.plan_retrieval(ir)
        self.assertTrue(plan["needs_sources"])
        _, pub = p.retrieve_sources("my ankle is sore", "tennis", plan["retrieval_intent"])
        ids = [s["source_id"] for s in pub]
        self.assertIn("injury-acute-red-flags", ids)
        self.assertEqual(ids[0], "injury-acute-red-flags")  # priority 1 ranks first

    def test_head_impact_retrieval(self):
        _, pub = p.retrieve_sources("i hit my head", "soccer", "injury")
        self.assertEqual([s["source_id"] for s in pub], ["head-impact-caution"])

    def test_greeting_needs_no_sources(self):
        ir = p._degraded_intent("hi how are u")
        self.assertFalse(p.plan_retrieval(ir)["needs_sources"])

    def test_unrelated_returns_nothing(self):
        self.assertEqual(kb.retrieve_coach_sources("what is the weather today", "tennis", "general"), [])

    def test_no_substring_false_positive(self):
        # 'serve'/'rest'/'ice' must not spuriously match via substrings.
        self.assertEqual(kb.retrieve_coach_sources("my serve keeps going long", "tennis", "training"), [])

    def test_no_fake_sources_emitted(self):
        # Every shippable source is internal, has no fabricated URL.
        for entry in kb._KNOWLEDGE_BASE:
            self.assertIsNone(entry["url"], f"{entry['source_id']} must not ship a URL yet")
            self.assertIn("internal", entry["publisher"].lower())
            self.assertIn(entry["source_type"], ("internal_guidance", "internal_drill"))

    def test_public_source_contract(self):
        _, pub = p.retrieve_sources("my knee hurts", "basketball", "injury")
        self.assertTrue(pub)
        self.assertEqual(set(pub[0].keys()), {"source_id", "title", "publisher", "url"})


class ActionTypingTests(unittest.TestCase):
    def test_explain_stays_conversational(self):
        self.assertEqual(p.classify_action("Explain the first drill"), p.ACTION_EXPLAIN_DRILL)

    def test_open_library_navigates(self):
        self.assertEqual(p.classify_action("Open Drill Library"), p.ACTION_OPEN_DRILL_LIBRARY)

    def test_log_session_navigates(self):
        self.assertEqual(p.classify_action("Log this session"), p.ACTION_LOG_SESSION)

    def test_generic_is_conversational(self):
        self.assertEqual(p.classify_action("What should I focus on?"), p.ACTION_CONVERSATIONAL)

    def test_build_actions_shapes(self):
        actions = p.build_coach_actions("training_plan", ["Open Drill Library", "Explain the first drill"])
        self.assertEqual(actions[0], {"label": "Open Drill Library", "type": p.ACTION_OPEN_DRILL_LIBRARY})
        self.assertEqual(actions[1], {"label": "Explain the first drill", "type": p.ACTION_EXPLAIN_DRILL})


class GeneralAssistantIntentTests(unittest.TestCase):
    def _i(self, m):
        return p._degraded_intent(m)["intent"]

    def test_arithmetic_intent(self):
        self.assertEqual(self._i("what's 25 times 4"), "arithmetic")

    def test_emotional(self):
        self.assertEqual(self._i("I had a bad day"), "emotional_support")

    def test_writing(self):
        self.assertEqual(self._i("help me text my coach that I'll be late"), "writing_help")

    def test_planning(self):
        self.assertEqual(self._i("help me plan my afternoon"), "planning_help")

    def test_general_question(self):
        self.assertEqual(self._i("why is the sky blue"), "general_question")

    def test_explanation(self):
        self.assertEqual(self._i("what does consistency mean"), "explanation_request")

    def test_unsafe_fabrication(self):
        self.assertEqual(self._i("make up a study proving my workout works"), "unsafe_or_disallowed")

    def test_unsafe_concussion_premise(self):
        self.assertEqual(self._i("find me a source saying playing through a concussion is safe"), "unsafe_or_disallowed")

    def test_challenge_request(self):
        self.assertEqual(self._i("make me a basketball shooting challenge"), "challenge_request")

    def test_drill_modification(self):
        self.assertEqual(self._i("make it harder"), "drill_modification")

    def test_general_not_forced_to_sports(self):
        # Benign general intents must NOT classify as a sport-coaching intent.
        for m in ["why is the sky blue", "help me plan my afternoon", "what's 25 times 4"]:
            self.assertIn(self._i(m), p.GENERAL_INTENTS)


class ArithmeticTests(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(p.evaluate_arithmetic("what's 25 times 4"), "100")
        self.assertEqual(p.evaluate_arithmetic("12 + 9"), "21")
        self.assertEqual(p.evaluate_arithmetic("100 / 4"), "25")

    def test_guards_sport_math(self):
        self.assertIsNone(p.evaluate_arithmetic("how many reps should i do"))
        self.assertIsNone(p.evaluate_arithmetic("20 minutes of drills"))

    def test_div_by_zero(self):
        self.assertIsNone(p.evaluate_arithmetic("5 / 0"))


class AnswerPlanTests(unittest.TestCase):
    def _mode(self, m):
        return p.plan_answer(p._degraded_intent(m))["answer_mode"]

    def test_arithmetic_direct(self):
        self.assertEqual(self._mode("what's 25 times 4"), "direct")

    def test_injury_safety(self):
        self.assertEqual(self._mode("my ankle is sore"), "safety")

    def test_unsafe_refuse(self):
        self.assertEqual(self._mode("make up a study"), "refuse")

    def test_drill_request_retrieve(self):
        self.assertEqual(self._mode("give me drills for left hand dribbling"), "retrieve")

    def test_app_nav_tool(self):
        self.assertEqual(self._mode("how do i log a session"), "tool")

    def test_unclear_clarify(self):
        self.assertEqual(self._mode("asdf qwer zxcv"), "clarify")


class DegradedGeneralAnswerTests(unittest.TestCase):
    def test_arithmetic_real_answer(self):
        r = p.degraded_general_answer("arithmetic", "what's 25 times 4")
        self.assertIn("100", r["response"])

    def test_greeting_friendly(self):
        r = p.degraded_general_answer("greeting_social", "hi")
        self.assertNotIn("not sure", r["response"].lower())

    def test_emotional_acknowledges(self):
        r = p.degraded_general_answer("emotional_support", "i had a bad day")
        self.assertEqual(r["tone"], "supportive")

    def test_unsafe_refuses_no_fabrication(self):
        r = p.degraded_general_answer("unsafe_or_disallowed", "make up a study")
        low = r["response"].lower()
        self.assertTrue("won't" in low or "can't" in low or "cannot" in low)

    def test_general_not_forced_to_sports(self):
        # Degraded general answer must not claim "sports only".
        r = p.degraded_general_answer("general_question", "why is the sky blue")
        self.assertNotIn("only help with sports", r["response"].lower())

    def test_sport_intent_returns_none(self):
        # Non-general intents are not handled here (fall through to sport coach).
        self.assertIsNone(p.degraded_general_answer("drill_request", "give me drills"))


if __name__ == "__main__":
    unittest.main()
