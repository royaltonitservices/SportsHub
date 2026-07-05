"""
LLM provider boundary for SportsHub.

This module owns ONLY provider/infrastructure concerns:
  - OpenAI client creation (never logs or echoes the API key)
  - centralized model selection (routine / escalation / check-in)
  - request-specific output budgets and temperature policy
  - transport retries (429 / transient 5xx / timeout / connection) with backoff
  - defensive param compatibility (models that reject custom temperature)
  - usage / latency / request-id metadata

It intentionally knows NOTHING about SportsHub coaching behavior, sport context,
safety policy, retrieval, or typed actions — those belong to the orchestrator.

Honesty contract:
  - `available` is True only when a real client was constructed from an sk- key.
  - `ProviderResult.ok` is True only when a real model call returned content.
    The orchestrator uses this to set `is_degraded_fallback` truthfully.
"""
from __future__ import annotations

import json
import random
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

try:
    from openai import OpenAI
    from openai import (
        APIConnectionError,
        APITimeoutError,
        RateLimitError,
        APIStatusError,
        BadRequestError,
    )
except Exception:  # pragma: no cover - openai must be installed in the venv
    OpenAI = None  # type: ignore
    APIConnectionError = APITimeoutError = RateLimitError = APIStatusError = BadRequestError = Exception  # type: ignore


# ── Task taxonomy — one place that maps a coaching task to output budget/temp ────

# Output token budgets per request type (Section 26). The routed models are
# reasoning models: `max_completion_tokens` covers BOTH hidden reasoning tokens
# AND visible output, so budgets include reasoning headroom (a too-small budget
# truncates the JSON to empty). Reasoning effort is held low to keep cost down.
_OUTPUT_BUDGET: Dict[str, int] = {
    "intent":            800,
    "coach_response":    3000,
    "coach_response_detailed": 3500,
    "checkin":           700,
    "drill":             2500,
    "challenge":         2000,
    "analysis":          2000,
    "escalation":        4000,
}

# Low reasoning effort keeps hidden-reasoning token spend (and latency/cost) down
# while leaving room for the actual answer. Dropped defensively for any model that
# rejects the parameter.
_DEFAULT_REASONING_EFFORT = "low"

# Temperature policy (Section 27). Low for structured/safety/classification,
# moderate for conversational wording. Providers that reject custom temperature
# are handled defensively at call time.
_TEMPERATURE: Dict[str, float] = {
    "intent":            0.0,
    "coach_response":    0.6,
    "coach_response_detailed": 0.6,
    "checkin":           0.8,
    "drill":             0.4,
    "challenge":         0.6,
    "analysis":          0.3,
    "escalation":        0.5,
}


@dataclass
class ProviderResult:
    """Outcome of a single provider call. `ok=False` means NO model text was
    produced — the caller must fall back and report is_degraded_fallback=True."""
    ok: bool
    text: str = ""
    model: str = ""
    prompt_tokens: int = 0
    completion_tokens: int = 0
    latency_s: float = 0.0
    request_id: Optional[str] = None
    attempts: int = 1
    error: Optional[str] = None  # short, key-safe error class/summary


class OpenAIProvider:
    """Thin, testable boundary around the OpenAI chat API."""

    # Transient errors worth retrying at the transport layer.
    _RETRYABLE = (RateLimitError, APITimeoutError, APIConnectionError)

    def __init__(self, settings, *, max_transport_attempts: int = 3, request_timeout_s: int = 30):
        self.settings = settings
        self.max_transport_attempts = max_transport_attempts
        self.request_timeout_s = request_timeout_s
        self.client = None
        self.available = False
        # Valid OpenAI keys start with "sk-" (legacy sk-..., project sk-proj-...,
        # and service-account sk-svcacct-... all qualify). Reject empty/placeholder.
        try:
            key = (settings.openai_api_key or "")
            if OpenAI is not None and key.startswith("sk-"):
                self.client = OpenAI(api_key=key, timeout=request_timeout_s)
                self.available = True
        except Exception:
            # Never surface the key in an error; degrade quietly.
            self.client = None
            self.available = False

    # ── Model selection (Section 9) ──────────────────────────────────────────────

    def select_model(
        self,
        task: str,
        *,
        safety_level: str = "none",
        complexity: str = "normal",
        prior_failure: bool = False,
    ) -> str:
        """Centralized model routing. Never scatter model IDs elsewhere.

        Routine work uses the default (cheap) model. The escalation model is
        reserved for a bounded set of hard cases: a prior contract failure
        (semantic repair), high-severity safety reasoning, or explicitly complex
        turns. Check-ins always use the cheap check-in model.
        """
        if task == "checkin":
            return self.settings.ai_checkin_model
        if prior_failure or safety_level == "high" or complexity == "high":
            return self.settings.ai_escalation_model
        return self.settings.ai_default_model

    # ── Core call ────────────────────────────────────────────────────────────────

    def chat(
        self,
        task: str,
        messages: List[Dict[str, str]],
        *,
        model: Optional[str] = None,
        safety_level: str = "none",
        complexity: str = "normal",
        prior_failure: bool = False,
        max_output_tokens: Optional[int] = None,
        temperature: Optional[float] = None,
        response_format: Optional[Dict] = None,
    ) -> ProviderResult:
        """Make one chat completion with transport retries and honest metadata.

        When `response_format` is a json_schema spec, the model output is
        schema-constrained (Structured Outputs). Returns a ProviderResult; on
        total failure returns ok=False (never raises for provider errors) so the
        orchestrator can fall back deterministically.
        """
        if not self.available or self.client is None:
            return ProviderResult(ok=False, error="provider_unavailable")

        chosen_model = model or self.select_model(
            task, safety_level=safety_level, complexity=complexity, prior_failure=prior_failure
        )
        budget = max_output_tokens or _OUTPUT_BUDGET.get(task, 700)
        temp = temperature if temperature is not None else _TEMPERATURE.get(task, 0.6)

        started = time.time()
        last_err = None
        for attempt in range(1, self.max_transport_attempts + 1):
            try:
                return self._do_call(chosen_model, messages, budget, temp, started, attempt, response_format)
            except self._RETRYABLE as e:  # transient — back off and retry
                last_err = type(e).__name__
                if attempt < self.max_transport_attempts:
                    time.sleep(min(8.0, (2 ** (attempt - 1)) * 0.5) + random.uniform(0, 0.4))
                    continue
            except APIStatusError as e:  # retry 5xx only; surface 4xx immediately
                last_err = f"APIStatusError:{getattr(e, 'status_code', '?')}"
                status = getattr(e, "status_code", 0) or 0
                if status >= 500 and attempt < self.max_transport_attempts:
                    time.sleep(min(8.0, (2 ** (attempt - 1)) * 0.5) + random.uniform(0, 0.4))
                    continue
                return ProviderResult(ok=False, model=chosen_model, attempts=attempt,
                                      latency_s=time.time() - started, error=last_err)
            except Exception as e:  # non-retryable (auth, bad request, etc.)
                return ProviderResult(ok=False, model=chosen_model, attempts=attempt,
                                      latency_s=time.time() - started, error=type(e).__name__)
        return ProviderResult(ok=False, model=chosen_model, attempts=self.max_transport_attempts,
                              latency_s=time.time() - started, error=last_err or "exhausted")

    def chat_structured(
        self,
        task: str,
        messages: List[Dict[str, str]],
        schema: Dict,
        *,
        schema_name: str = "coach_response",
        **kwargs,
    ) -> Tuple[Optional[Dict], ProviderResult]:
        """Schema-constrained chat call. Returns (parsed_dict_or_None, result).

        The dict is parsed from the guaranteed-schema JSON; None only if the
        provider failed or (rarely) returned unparseable content. The caller
        still validates product invariants and owns is_degraded_fallback.
        """
        rf = {"type": "json_schema",
              "json_schema": {"name": schema_name, "strict": True, "schema": schema}}
        res = self.chat(task, messages, response_format=rf, **kwargs)
        if not res.ok:
            return None, res
        try:
            # strict=False tolerates the literal control characters (newlines/tabs)
            # models sometimes emit inside long string values; the schema still
            # guarantees the shape and field types.
            return json.loads(res.text, strict=False), res
        except Exception:
            return None, ProviderResult(ok=False, text=res.text, model=res.model,
                                        prompt_tokens=res.prompt_tokens, completion_tokens=res.completion_tokens,
                                        latency_s=res.latency_s, attempts=res.attempts, error="json_parse_failed")

    def _do_call(self, model, messages, budget, temp, started, attempt, response_format=None) -> ProviderResult:
        """Single attempt. Defensively drops optional params (`temperature`,
        `reasoning_effort`) that a given model rejects rather than failing the turn
        (e.g. gpt-5.5 only supports the default temperature)."""
        kwargs = dict(model=model, messages=messages,
                      max_completion_tokens=budget, timeout=self.request_timeout_s)
        if response_format is not None:
            kwargs["response_format"] = response_format
        # gpt-5.x reasoning models only accept the default temperature; sending a
        # custom value forces a rejected first call + retry (and flakiness). Skip it
        # for those models. The defensive drop below still covers any other model.
        optional = {"reasoning_effort": _DEFAULT_REASONING_EFFORT}
        if not model.startswith("gpt-5"):
            optional["temperature"] = temp
        while True:
            try:
                resp = self.client.chat.completions.create(**kwargs, **optional)
                break
            except BadRequestError as e:
                msg = str(e).lower()
                dropped = [p for p in list(optional) if p in msg]
                for p in dropped:
                    optional.pop(p)
                if not dropped:  # unrelated bad request — surface it
                    raise
        text = (resp.choices[0].message.content or "") if resp.choices else ""
        usage = getattr(resp, "usage", None)
        return ProviderResult(
            ok=bool(text.strip()),
            text=text,
            model=model,
            prompt_tokens=getattr(usage, "prompt_tokens", 0) or 0,
            completion_tokens=getattr(usage, "completion_tokens", 0) or 0,
            latency_s=time.time() - started,
            request_id=getattr(resp, "_request_id", None) or getattr(resp, "id", None),
            attempts=attempt,
            error=None if text.strip() else "empty_completion",
        )
