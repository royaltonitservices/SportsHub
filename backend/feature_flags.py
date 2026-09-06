"""
Backend v1 shipping feature flags (Milestone 2 de-scope).

These gate whole shipping SURFACES independently of any per-user entitlement
(premium / subscription / admin / age). They are the server-side counterpart to the
iOS `enum V1` flags.

AI_COACH_ENABLED — the AI Coach (and every endpoint that can invoke the OpenAI/LLM
provider) is OFF in v1 until Gate 1.6 implements safe age routing (13-17
deterministic-only, 18+ OpenAI with consent). While OFF, NO shipping API endpoint may
reach the provider — regardless of premium status, an active Subscription row, or the
caller's age. This is a hard feature disable, NOT an age/premium gate. Default OFF;
overridable only by an explicit env var so a future gate can turn it on deliberately.
"""
import os


def _flag(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


# AI Coach / LLM provider surface — OFF until Gate 1.6.
AI_COACH_ENABLED = _flag("SPORTSHUB_AI_COACH_ENABLED", default=False)
